# -*- coding: utf-8 -*-
"""Un enlace Linux que pide una biblioteca que el sysroot NO tiene (C10 del cierre de la 1.28: "ninguna
bateria provoca un 'cannot find -l'", el C8 de la 1.26). delphi_build mira la salida del enlazador
(CompletaEnlacesDev, Lsp.BuildRunner): un 'cannot find -lX' cuyo libX.so falta pero cuya version con numero
SI esta se completa en el SDK y el build se repite; si NO hay ninguna version, lo dice (BUILD-035) y no
escribe nada en el SDK. Aqui el segundo camino, que no toca el SDK de la maquina: una funcion external de
'libc10noexiste.so', que ld pide como -lc10noexiste (con 'c10noexiste' a secas dice 'cannot open', medido).
Necesita un SDK de Linux64 en el IDE (el de por defecto); sin el, NOTA.

  E1 el build falla con el 'cannot find -lc10noexiste' del enlazador
  E2 ...y sdkLinkNote es BUILD-035, que nombra libc10noexiste.so: a esa maquina le falta la libreria
  E3 ...y en el sysroot no nacio ningun libc10noexiste*: este camino no escribe en el SDK

Uso:  python tests/test_enlace_falta_128.py [ruta-a-DelphiLspMcp.exe]
"""
import glob, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('enlace_falta_128')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='enlace-falta', t=900)
try:
    SDK = mc.sdk_por_defecto(srv.call, 'Linux64')
    if not SDK:
        print('NOTA E1-E3 no se miden: el IDE de esta maquina no tiene SDK por defecto para Linux64')
    else:
        r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Falta', 'dir': os.path.join(JAIL, 'Falta')})
        DPR = os.path.join(JAIL, 'Falta', 'Falta.dpr')
        DPROJ = os.path.join(JAIL, 'Falta', 'Falta.dproj')
        check('preparacion: el proyecto nace', os.path.isfile(DPR) and os.path.isfile(DPROJ), r[:200])
        texto = open(DPR, encoding='utf-8-sig').read()
        texto = texto.replace('  System.SysUtils;',
                              "  System.SysUtils;\n\nfunction NoExiste(X: Integer): Integer; cdecl; "
                              "external 'libc10noexiste.so' name 'c10_no_existe';", 1)
        texto = texto.replace("Writeln('Falta running');", "Writeln('Falta running ', NoExiste(1));", 1)
        with open(DPR, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(texto)
        srv.call('delphi_config', {'command': 'add-platform', 'project': DPROJ, 'platform': 'Linux64'})
        r = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64', 'sdk': SDK}, 900)
        j = mc.como_json(r) or {}
        errores = '\n'.join(j.get('errors') or [])
        check('E1 el build falla con el "cannot find -lc10noexiste" del enlazador',
              j.get('success') is False and 'cannot find -lc10noexiste' in errores, r[:500])
        nota = j.get('sdkLinkNote', '')
        check('E2 ...y sdkLinkNote es BUILD-035, que nombra libc10noexiste.so (falta la libreria en esa maquina)',
              mc.abre(nota, 'SN_BUILD_DEVLINK_MISSING_FMT') and 'libc10noexiste.so' in nota, (nota[:300], r[:300]))
        # la carpeta tiene que estar: sin ella el glob no veria nada y E3 pasaria sin medir
        SYSROOT = os.path.join(mc.carpeta_sdks(), SDK + '.sdk')
        nacidos = glob.glob(os.path.join(SYSROOT, '**', 'libc10noexiste*'), recursive=True)
        check('E3 ...y en el sysroot (%s.sdk) no nacio ningun libc10noexiste*' % SDK,
              os.path.isdir(SYSROOT) and not nacidos, (SYSROOT, nacidos[:3]))
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('enlace Linux con una libreria que no esta 1.28 (C10)')
