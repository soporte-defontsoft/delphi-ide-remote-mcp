# -*- coding: utf-8 -*-
r"""Los textos que dejaron luna y Qwen en la pasada de Hermes de la 1.27 (4-nov-2026), cada uno
contra lo que el texto afirma:

  K1 build target=Clean dice que limpio (BUILD-069, cleanNote): el agente lo averiguaba con
     delphi_list. ROJA contra c582da0 (sin la nota).
  K2 arbitro (msbuild): lo que BUILD-069 afirma es verdad - tras un set-output, Clean borra el exe de
     la carpeta declarada (Compiled\Win64\Debug) y deja el de la carpeta de antes (Win64\Debug).
  K3 STYLE-008 dice que un .style de texto se puede escribir (delphi_textedit create=true, object
     TStyleContainer): solo decia "exportalo del Bitmap Style Designer". ROJA contra c582da0.
  K4 RENAME-019 al renombrar la VARIABLE global del form: el texto no dice "published member" (no lo
     es) y dice que el form se ata por su Name. ROJA contra c582da0.
  K5 la cache del estilo por defecto lleva la huella del conversor que la produjo (R15 del revisor del
     paisaje): una cache vieja sin clave (win10-default.style) con un StyleName falso NO se cree - el
     lint dice que ese lookup no tiene estilo - y se borra; la nueva vive en estilos\defecto-*.style.
     ROJA contra c582da0 (se creia la plantada y el lookup falso salia como estandar). El nombre de
     la cache, del fuente (NombreDeCacheDelEstilo y su inversa en Lsp.Styles), no copiado aqui.
  K7 la purga de las caches viejas del estilo no depende de la jaula de quien llama: un servidor
     cuyas raices NO contienen su casa (su LOCALAPPDATA fuera) no purgaba nada - recorria su cache
     con WalkFiles, que empieza por la jaula del agente (ReadPathDenied) -; lo ajeno se queda.
     ROJA contra el build de las 20:03 del 4-nov (R15 sin el arreglo: la plantada seguia).
  K6 un clone fallido no deja su carpeta, NUNCA (V45 de test_capacidades_125, intermitente): quitar la
     carpeta vacia que creo la llamada rebotaba con 32 (algo la tiene abierta un instante) y se
     quedaba. Medido: de 1 a 10 de 40 se quedaban, todas se podian quitar un segundo despues. Aqui, 20
     clones fallidos y ninguna carpeta. ROJA contra c582da0 cuando rebota (intermitente: la tasa
     cambia de una tanda a otra).

TEST-037 nombrando el caracter va en test_capacidades_126 (A4b), junto a sus checks.

Uso:  python tests/test_cierre_127.py [ruta-a-DelphiLspMcp.exe]
"""
import functools
import glob
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('cierre-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='cierre', t=600)

# EL nombre de la cache del estilo por defecto, del fuente: su carpeta, su prefijo y su extension
# (NombreDeCacheDelEstilo / LeeNombreDeCacheDelEstilo) y la vieja sin clave, que solo se purga
ESTILOS_PAS = 'Server/Lsp.Styles.pas'
CACHE_SUB = mc.cadena_del_fuente(ESTILOS_PAS, 'CACHE_ESTILOS_SUB')
CACHE_PREFIJO = mc.cadena_del_fuente(ESTILOS_PAS, 'PREFIJO_CACHE_ESTILO')
CACHE_EXT = mc.cadena_del_fuente(ESTILOS_PAS, 'EXT_CACHE_ESTILO')
CACHE_SIN_CLAVE = mc.cadena_del_fuente(ESTILOS_PAS, 'CACHE_ESTILO_SIN_CLAVE')


def caches_del_estilo(lad):
    """Las caches del estilo por defecto en la casa de un LOCALAPPDATA: lo que LeeNombreDeCacheDelEstilo
    toma por suyo (el prefijo, una huella no vacia y la extension)."""
    d = mc.cache_servidor(CACHE_SUB, lad)
    p, e = CACHE_PREFIJO.lower(), CACHE_EXT.lower()
    return sorted(n for n in (os.listdir(d) if os.path.isdir(d) else [])
                  if n.lower().startswith(p) and n.lower().endswith(e) and len(n) > len(p) + len(e))


def compila(r):
    return mc.como_json(r).get('success') is True


try:
    # K1/K2: Clean, contra msbuild
    carpeta = os.path.join(BASE, 'limpia')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Limpia', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Limpia.dproj')
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Debug'}, 600)
    check('fixture: compila en la carpeta del IDE (Win64\\Debug)', compila(r), r[:300])
    viejo = os.path.join(carpeta, 'Win64', 'Debug', 'Limpia.exe')
    r = srv.call('delphi_config', {'project': proyecto, 'command': 'set-output', 'output': 'Compiled'})
    check('fixture: set-output Compiled', not mc.rechazado(r), r[:300])
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Debug'}, 600)
    nuevo = os.path.join(carpeta, 'Compiled', 'Win64', 'Debug', 'Limpia.exe')
    check('fixture: compila en la carpeta declarada (Compiled) y la de antes sigue',
          compila(r) and os.path.isfile(nuevo) and os.path.isfile(viejo), r[:300])
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Debug',
                                  'target': 'Clean'}, 600)
    check('K1 Clean dice que limpio y que no (BUILD-069, cleanNote)',
          compila(r) and mc.es(r, 'SN_BUILD_CLEAN_NOTE') and 'cleanNote' in mc.como_json(r), r[:400])
    check('K2 arbitro: Clean borro el exe de la carpeta declarada y dejo el de la carpeta de antes',
          not os.path.isfile(nuevo) and os.path.isfile(viejo), (os.path.isfile(nuevo), os.path.isfile(viejo)))

    # K3: STYLE-008 dice como escribir uno
    estilos = os.path.join(BASE, 'estilos')
    os.makedirs(estilos)
    open(os.path.join(estilos, 'a.rc'), 'w', encoding='utf-8').write('// a\r\n')
    r = srv.call('delphi_styles', {'command': 'lint', 'path': estilos})
    check('K3 STYLE-008 en una carpeta sin .style de texto, y dice que se puede escribir uno',
          mc.es(r, 'SR_STYLES_NO_TEXT_FMT') and 'delphi_textedit create=true' in r
          and 'TStyleContainer' in r, r[:400])

    # K5: la cache del estilo por defecto, con la huella del conversor (otro servidor, su LOCALAPPDATA)
    lad = os.path.join(BASE, 'lad')
    vieja = mc.cache_servidor(CACHE_SIN_CLAVE, lad)
    os.makedirs(os.path.dirname(vieja))
    open(vieja, 'w', encoding='utf-8').write(
        "object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'falsoestilo'\r\n  end\r\nend\r\n")
    k5 = os.path.join(BASE, 'k5')
    os.makedirs(os.path.join(k5, 'Est'))
    open(os.path.join(k5, 'Est', 'Bat.style'), 'w', encoding='utf-8').write(
        "object TStyleContainer\r\n  object TLayout\r\n    StyleName = 'cardstyle'\r\n  end\r\nend\r\n")
    open(os.path.join(k5, 'Form1.fmx'), 'w', encoding='utf-8').write(
        "object Form1: TForm1\r\n  Left = 0\r\n  Top = 0\r\n  object Button1: TButton\r\n"
        "    StyleLookup = 'falsoestilo'\r\n  end\r\nend\r\n")
    # con el conversor al lado: sin el no hay estilo por defecto (ni juez), y K5 pasaba por eso
    exe5 = mc.copia_exe(os.path.join(BASE, 'srv5'), src=exe_src, con_conversor=True)
    otro = mc.Stdio(exe5, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': lad}), nombre='cierre5', t=600)
    try:
        r = otro.call('delphi_styles', {'command': 'lint', 'path': os.path.join(k5, 'Est'), 'project': k5}, 300)
    finally:
        otro.cierra()
    check('K5 control: el lint tiene el estilo por defecto de la plataforma (hay juez)',
          not mc.fallo(r) and not mc.es(r, 'SN_STYLES_NO_DEFAULTS'), r[:400])
    sin_estilo = json.dumps(mc.como_json(r).get('lookupsWithoutStyle', ''))
    check('K5 la cache vieja sin clave no se cree: falsoestilo sale sin estilo en el lint',
          'falsoestilo' in sin_estilo, r[:500])
    nuevas = caches_del_estilo(lad)
    check('K5 ...la vieja se borra y la nueva lleva la huella del conversor (estilos\\defecto-*.style)',
          not os.path.exists(vieja) and len(nuevas) == 1, (os.path.exists(vieja), nuevas))

    # K7: la purga, con raices que NO contienen la casa del servidor (su LOCALAPPDATA fuera de ellas)
    lad7 = os.path.join(BASE, 'lad7')
    k7 = os.path.join(BASE, 'k7')
    estilos7 = mc.cache_servidor(CACHE_SUB, lad7)
    os.makedirs(estilos7)
    plantada = os.path.join(estilos7, CACHE_PREFIJO + '0-0' + CACHE_EXT)
    ajena = os.path.join(estilos7, 'ajena' + CACHE_EXT)
    for f in (plantada, ajena):
        open(f, 'w', encoding='utf-8').write("object TStyleContainer\r\nend\r\n")
    shutil.copytree(k5, k7)
    exe7 = mc.copia_exe(os.path.join(BASE, 'srv7'), src=exe_src, con_conversor=True)
    otro = mc.Stdio(exe7, mc.entorno({'DELPHI_MCP_ROOTS': k7, 'LOCALAPPDATA': lad7}), nombre='cierre7', t=600)
    try:
        r = otro.call('delphi_styles', {'command': 'lint', 'path': os.path.join(k7, 'Est'), 'project': k7}, 300)
    finally:
        otro.cierra()
    check('K7 control: con raices que no contienen su casa, el lint tiene el estilo por defecto (hay juez)',
          not mc.fallo(r) and not mc.es(r, 'SN_STYLES_NO_DEFAULTS'), r[:400])
    quedan7 = caches_del_estilo(lad7)
    check('K7 la cache vieja se purga aunque la casa no este en las raices; lo ajeno se queda',
          not os.path.exists(plantada) and os.path.exists(ajena) and len(quedan7) == 1,
          (os.path.exists(plantada), os.path.exists(ajena), quedan7))

    # K6: un clone fallido no deja su carpeta (otro servidor: los remotos de 127.0.0.1)
    git_base = os.path.join(BASE, 'git')
    origen = os.path.join(git_base, 'g')
    os.makedirs(origen)

    def crudo(*a, cwd=origen):
        return subprocess.run(['git'] + list(a), cwd=cwd, capture_output=True, text=True)
    crudo('init', '-q', '-b', 'principal')
    open(os.path.join(origen, 'a.txt'), 'w').write('uno\n')
    crudo('add', '.')
    crudo('-c', 'user.name=x', '-c', 'user.email=x@x', 'commit', '-q', '-m', 'uno')
    bare = os.path.join(git_base, 'rem.git')
    crudo('init', '-q', '--bare', bare)
    crudo('push', '-q', bare, 'HEAD:refs/heads/principal')
    crudo('update-server-info', cwd=bare)
    web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(
        type('Callado', (http.server.SimpleHTTPRequestHandler,), {'log_message': lambda *a: None}),
        directory=git_base))
    threading.Thread(target=web.serve_forever, daemon=True).start()
    url = 'http://127.0.0.1:%d/rem.git' % web.server_port
    gsrv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_GIT_REMOTES': '127.0.0.1'}),
                    nombre='cierre6', t=600)
    quedan, respuestas = [], []
    try:
        for i in range(20):
            destino = os.path.join(git_base, 'cl%d' % i)
            t = gsrv.call('delphi_git', {'repo': destino, 'command': 'clone', 'message': url,
                                         'branch': 'noexiste'})
            respuestas.append('noexiste' in t)
            if os.path.exists(destino):
                quedan.append(i)
    finally:
        gsrv.cierra()
        web.shutdown()
    check('K6 fixture: los 20 clones los niega git (rama que no esta)', all(respuestas), respuestas)
    check('K6 un clone fallido no deja su carpeta: ninguna de 20 (V45)', not quedan, quedan)

    # K4: RENAME-019 de la variable global del form
    vcl = os.path.join(BASE, 'vcl')
    salida = srv.call('delphi_create', {'kind': 'project-vcl', 'name': 'Forma', 'dir': vcl})
    check('fixture: proyecto VCL creado', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    unidad, linea0, col0 = None, None, None
    for pas in glob.glob(os.path.join(vcl, '*.pas')):
        with open(pas, encoding='utf-8-sig') as f:
            for i, texto in enumerate(f.read().splitlines()):
                m = re.match(r'^(\s+)(\w+): T\w+;$', texto)
                if m and os.path.isfile(pas[:-4] + '.dfm'):
                    unidad, linea0, col0 = pas, i, len(m.group(1))
    check('fixture: la variable global del form, en su unidad', unidad is not None, os.listdir(vcl))
    if unidad:
        r = srv.call('delphi_rename_symbol', {'path': unidad, 'line': linea0, 'character': col0,
                                              'newname': 'Principal'}, 300)
        check('K4 RENAME-019 de la variable del form: el form se ata por su Name, no "published member"',
              mc.es(r, 'SR_RENAME_DESIGNER_FMT') and 'its own Name' in r and 'published member' not in r,
              r[:600])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('cierre de la 1.27: textos de la pasada de Hermes')
