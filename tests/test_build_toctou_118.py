# -*- coding: utf-8 -*-
"""TOCTOU entre el escaneo compile-only del .dproj y msbuild (revisor 1.18.0: M1 / cobertura C2).

En f0557ab el escaneo (DprojBuildHazard) corria ANTES de GBuildLock y SIN
EnterFileEdit; msbuild re-lee el .dproj del disco dentro del cerrojo. Una edicion
del .dproj por una tool (delphi_upload, un git switch..., que toman GLock =
EnterFileEdit) entre el escaneo y msbuild colaba un <Exec>. El arreglo mueve el
escaneo DENTRO de GBuildLock + EnterFileEdit, sostenido hasta pasado msbuild:
msbuild compila los MISMOS bytes que se escanearon.

La carrera: un build A largo (NO confiado) retiene el turno de GBuildLock; un
build B de un proyecto victima se encola detras; durante la espera, delphi_upload
escribe el .dproj de B con un <Target BeforeTargets="Build"><Exec> que SOLO escribe
un marcador DENTRO de la carpeta de la bateria (bajo mc.RAIZ; nada real, nada fuera).
  - Arreglado: NINGUN marcador, en cualquiera de los dos ordenes posibles -la
    edicion gana el cerrojo y B la rechaza por el escaneo, o B compila limpio y la
    edicion espera a que acabe el build.
  - f0557ab: el marcador APARECE (B compila el .dproj envenenado).
Mide ademas que la edicion del .dproj ESPERA mientras A corre (serializacion por GLock):
con el arreglo espera; en f0557ab, no.

Margenes de tiempo amplios. Si la maquina no da la secuencia -sin RAD Studio, A
compila demasiado rapido para retener el turno, o B no se encola- la bateria no
mide nada y sale SIN_CHECKS (no en falso verde). Si salta por "A compilo en Xs",
sube UNIDADES_A / PROCS_POR_UNIDAD. Limpia su carpeta al acabar.

Uso:  python tests/test_build_toctou_118.py [ruta-al-exe]
"""
import atexit
import base64
import glob
import json
import os
import threading
import time
import mcp_cliente as mc
from mcp_cliente import check

TOKEN = 'toctou-token'
UNIDADES_A = 40            # unidades del proyecto largo A (sube si tu maquina salta)
PROCS_POR_UNIDAD = 3500    # procedimientos por unidad: compilar A tiene que costar segundos
                           # (20x600 compilo en 2.1 s y 40x1500 en 3.9 s en la maquina del autor,
                           # 10-oct-2026; con 3.9 s el check de la espera pasaba tambien en f0557ab)
B_DELAY = 1.0              # B entra tras A: su escaneo (limpio) corre y se encola detras
INJECT_DELAY = 2.5         # se inyecta cuando A lleva rato reteniendo el turno
# A tiene que durar al menos esto: la inyeccion cae en medio, y "la edicion espera"
# (acaba con A) se separa de "no espera" (acaba en INJECT_DELAY) mas que el margen del check
MIN_A = INJECT_DELAY + 4.0

WORK = mc.carpeta('build-toctou')
atexit.register(mc.borra, WORK)
EXE = mc.copia_exe(WORK)
JAIL = os.path.join(WORK, 'jaula')
os.makedirs(JAIL)
MARKER = os.path.join(WORK, 'marcador-pwned.txt')   # bajo mc.RAIZ: nada real, nada fuera de la bateria

# Sin AllowBuildScripts: los DOS builds son NO confiados -> corre el escaneo compile-only.
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))

PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
cli = mc.Http(PORT, TOKEN, t=600)   # seguro entre hilos: A, B y la inyeccion a la vez
call = cli.call

SKIP = None   # motivo si la maquina no da la secuencia -> fin(sin_checks=SKIP), sin medir


def falta_rad(txt):
    return mc.catalogo()['SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED'] in str(txt)


def compilo(txt):
    try:
        return json.loads(txt).get('success') is True
    except Exception:
        return False


try:
    # ---- fixtures: proyecto victima B (limpio) y proyecto largo A (NO confiado) ----
    B_DIR = os.path.join(JAIL, 'victima')
    rb = call('delphi_create', {'kind': 'project-console', 'dir': B_DIR, 'name': 'BuildB'})
    A_DIR = os.path.join(JAIL, 'larga')
    ra = call('delphi_create', {'kind': 'project-console', 'dir': A_DIR, 'name': 'BuildA'})
    b_dpr = glob.glob(os.path.join(B_DIR, '**', 'BuildB.dpr'), recursive=True)
    a_dpr = glob.glob(os.path.join(A_DIR, '**', 'BuildA.dpr'), recursive=True)
    if not a_dpr or not b_dpr:
        SKIP = 'delphi_create no dejo los proyectos: A=%s B=%s' % (str(ra)[:120], str(rb)[:120])
    else:
        B_PROJ = b_dpr[0][:-4] + '.dproj'
        A_PROJ = a_dpr[0][:-4] + '.dproj'
        A_SRC = os.path.dirname(a_dpr[0])

        # Engordar A: unidades triviales VALIDAS, todas en el uses del .dpr, para que
        # compilar A tarde segundos y retenga el turno de GBuildLock. El .dpr lo escribe
        # la bateria (es su carpeta); no se mide ninguna tool al prepararlo.
        usos = ['System.SysUtils']
        for u in range(UNIDADES_A):
            nombre = 'ULarga%02d' % u
            cab = ['unit %s;' % nombre, 'interface']
            cuerpo = ['implementation']
            for p in range(PROCS_POR_UNIDAD):
                cab.append('function F%02d_%03d(X: Integer): Integer;' % (u, p))
                cuerpo.append('function F%02d_%03d(X: Integer): Integer;' % (u, p))
                cuerpo.append('begin')
                cuerpo.append('  Result := X + %d;' % p)
                for k in range(6):
                    cuerpo.append('  Result := Result * 2 - %d + (Result div %d);' % (k + 1, k + 2))
                cuerpo.append('end;')
            lineas = cab + cuerpo + ['end.']
            with open(os.path.join(A_SRC, nombre + '.pas'), 'w', encoding='utf-8', newline='\r\n') as f:
                f.write('\r\n'.join(lineas) + '\r\n')
            usos.append("%s in '%s.pas'" % (nombre, nombre))
        with open(a_dpr[0], 'w', encoding='utf-8', newline='\r\n') as f:
            f.write('program BuildA;\r\n{$APPTYPE CONSOLE}\r\nuses\r\n  '
                    + ',\r\n  '.join(usos) + ';\r\nbegin\r\n  Writeln(\'A\');\r\nend.\r\n')

        # El veneno: un Target que msbuild ejecuta ANTES de Build; SOLO escribe el
        # marcador DENTRO de la carpeta de la bateria (nada real, nada fuera de mc.RAIZ).
        # Va por XML (&gt; &quot;) y lo detecta DprojBuildHazard: con el arreglo, si B
        # llega a escanearlo envenenado, lo rechaza.
        POISON = ('  <Target Name="Toctou118" BeforeTargets="Build">\r\n'
                  '    <Exec Command="cmd /c echo pwned&gt; &quot;%s&quot;" />\r\n'
                  '  </Target>\r\n' % MARKER)

        res = {}

        def construye(clave, proyecto, espera=0.0):
            if espera:
                time.sleep(espera)
            t0 = time.monotonic()
            r = call('delphi_build', {'project': proyecto, 'config': 'Debug'}, t=600)
            res[clave] = (t0, time.monotonic(), r)

        ta = threading.Thread(target=construye, args=('a', A_PROJ))
        tb = threading.Thread(target=construye, args=('b', B_PROJ, B_DELAY))
        ta.start()
        tb.start()
        time.sleep(INJECT_DELAY)   # A retiene el turno; B (su escaneo limpio ya corrio) espera en la cola
        iny0 = time.monotonic()
        # Por delphi_upload: delphi_textedit no escribe un .dproj (lo niega) y upload
        # si, entero y con el cerrojo de escritura, como cualquier escritor.
        envenenado = open(B_PROJ, 'rb').read().replace(b'</Project>', POISON.encode() + b'</Project>')
        r_iny = call('delphi_upload', {'path': B_PROJ, 'offset': 0,
                                       'chunkbase64': base64.b64encode(envenenado).decode()})
        iny1 = time.monotonic()
        ta.join()
        tb.join()

        a0, a1, ar = res.get('a', (0.0, 0.0, ''))
        b0, b1, br = res.get('b', (0.0, 0.0, ''))
        a_dur = a1 - a0
        poison_en_disco = (os.path.isfile(B_PROJ)
                           and 'Toctou118' in open(B_PROJ, encoding='utf-8', errors='replace').read())

        # ---- validez de la secuencia (si no se dio, SIN_CHECKS, nunca falso verde) ----
        if falta_rad(ar) or falta_rad(br):
            SKIP = 'no hay RAD Studio en esta maquina'
        elif not compilo(ar):
            SKIP = 'el build largo A no compilo (fixture): %s' % str(ar)[:200]
        elif not poison_en_disco:
            SKIP = 'la inyeccion no entro en el .dproj de B (delphi_upload): %s' % str(r_iny)[:160]
        elif a_dur < MIN_A:
            SKIP = ('A compilo en %.1fs (< %.1fs): no retuvo el turno el tiempo necesario; '
                    'sube UNIDADES_A/PROCS_POR_UNIDAD' % (a_dur, MIN_A))
        elif iny0 > a1:
            SKIP = 'la inyeccion (a +%.1fs) cayo despues de que A acabara (+%.1fs)' % (iny0 - a0, a_dur)
        elif b1 < a1 - 1.0:
            SKIP = 'B no se encolo detras de A (B acabo %.1fs antes que A)' % (a1 - b1)
        else:
            # La secuencia se dio: A retuvo el turno, B se encolo, se inyecto en medio.
            hay_marcador = os.path.exists(MARKER)
            check('TOCTOU build: msbuild NO compila el <Exec> inyectado entre el escaneo y el build',
                  not hay_marcador,
                  'marcador presente = el .dproj envenenado se compilo (vulnerable, f0557ab). '
                  'A=%.1fs B=%.1fs inyeccion=[+%.1f,+%.1f]s' % (a_dur, b1 - b0, iny0 - a0, iny1 - a0))
            # Serializacion: con el arreglo, la edicion del .dproj ESPERA a que A suelte
            # el cerrojo de escritura (GLock); en f0557ab no espera y acaba enseguida.
            check('TOCTOU build: la edicion del .dproj espera a que A suelte el cerrojo',
                  iny1 >= a1 - 1.5,
                  'la edicion acabo a +%.1fs y A a +%.1fs (duro %.1fs)' % (iny1 - a0, a_dur, iny1 - iny0))
finally:
    proc.kill()

mc.fin('build toctou (M1 / C2)', sin_checks=SKIP)
