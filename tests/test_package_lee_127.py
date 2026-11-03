# -*- coding: utf-8 -*-
r"""delphi_package juzga la carpeta que empaqueta con la puerta de LEER (revisor del paisaje de la 1.27).

La carpeta solo se lee; lo que se escribe es el zip, que juzga la puerta de destino. Se juzgaba con la de
escribir (PathDenied), que niega una ReadOnlyRoot: empaquetar una carpeta de referencia con el zip dentro
de la jaula se negaba, mientras su gemela delphi_move copy=true lee el origen con la de leer.

  K1 delphi_package de una carpeta de una ReadOnlyRoot, con outfile en la jaula: el zip se hace (ROJA: GUARD)
  K2 (guarda) el mismo con outfile en la referencia: negado (alli no se escribe) y sin zip

Uso:  python tests/test_package_lee_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('package-lee-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
REF = os.path.join(BASE, 'ref')
DIST = os.path.join(REF, 'dist')
os.makedirs(JAIL)
os.makedirs(DIST)
open(os.path.join(DIST, 'App.exe'), 'wb').write(b'MZ fixture')
open(os.path.join(DIST, 'leeme.txt'), 'w').write('x\n')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_READONLY_ROOTS': REF}), nombre='package-lee', t=120)
try:
    ZIP = os.path.join(JAIL, 'dist.zip')
    r = srv.call('delphi_package', {'dir': DIST, 'outfile': ZIP})
    check('K1 una carpeta de la referencia empaquetada en un zip de la jaula: el zip se hace',
          not mc.rechazado(r) and os.path.isfile(ZIP), r[:300])
    ZIP2 = os.path.join(REF, 'dist.zip')
    r = srv.call('delphi_package', {'dir': DIST, 'outfile': ZIP2})
    check('K2 (guarda) el zip en la referencia: negado y sin zip', mc.rechazado(r) and not os.path.exists(ZIP2), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_package lee con la puerta de leer 1.27')
