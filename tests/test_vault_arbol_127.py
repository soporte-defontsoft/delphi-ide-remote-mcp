# -*- coding: utf-8 -*-
"""El vault de un workspace dentro de su ReadOnlyRoot, alcanzado por un ENLACE que un RECORREDOR sigue
(revisor del paisaje de la 1.27, sobre el V192 de la 1.23.1).

V192 cerro la puerta de leer: un fichero del vault por un enlace se niega por su ruta REAL (JaulaDecide).
Pero la copia de un arbol (CopiaArbol: delphi_move copy=true, la etapa de delphi_test) sigue un enlace cuyo
destino se puede leer y, detras, solo preguntaba por el vault por el TEXTO de la ruta; y el listado
(WalkFiles: delphi_list) ni eso. Un enlace de la raiz a la referencia que CONTIENE el vault lo copiaba y lo
listaba.

  A1 (control) delphi_read del secreto por el enlace: negado (V192)
  A2 delphi_move copy=true de la carpeta con el enlace: la copia no lleva el secreto
  A3 delphi_list de la carpeta con el enlace: no lista el secreto

Uso:  python tests/test_vault_arbol_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('vault_arbol_127')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV, src=exe_src)
JAIL = os.path.join(BASE, 'jail')
REF = os.path.join(BASE, 'ref')
VAULT = os.path.join(REF, 'vault')
X = os.path.join(JAIL, 'x')
os.makedirs(X)
os.makedirs(VAULT)
for n in ('AGENTS-VAULT.md', 'MEMORY.md'):
    open(os.path.join(VAULT, n), 'w').write('# x\n')
open(os.path.join(VAULT, 'secreto.md'), 'w').write('SECRETO del vault\n')
open(os.path.join(REF, 'libre.txt'), 'w').write('se puede leer\n')
open(os.path.join(X, 'propio.txt'), 'w').write('mio\n')
check('el enlace se planta', mc.junction(os.path.join(X, 'lnk'), REF))
PUERTO = mc.puerto_libre()
TOKEN = 'vault-arbol-127-0123456789'
open(os.path.join(SRV, 'settings.ini'), 'w').write(
    '[Workspace.S]\nToken=%s\nRoots=%s\nReadOnlyRoots=%s\nVaultPath=%s\n' % (TOKEN, JAIL, REF, VAULT))
proc = mc.lanza_http(EXE, PUERTO, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
try:
    cli = mc.Http(PUERTO, TOKEN)
    cli.session('vault-arbol')
    r = cli.call('delphi_read', {'path': os.path.join(X, 'lnk', 'vault', 'secreto.md')})
    # por SU negativa (VAULT-002, V192): rechazado a secas pasaba con la de la jaula o la de un enlace
    # (revisor de baterias de la 1.27)
    check('A1 control: el secreto por el enlace, negado',
          mc.rechazado(r) and mc.es(r, 'SR_VAULT_NOT_CODE') and 'SECRETO' not in r, r[:200])

    Y = os.path.join(JAIL, 'y')
    r = cli.call('delphi_move', {'path': X, 'dest': Y, 'copy': True})
    # la fixture: la copia se hizo y siguio el enlace (lo legible de detras llego)
    check('A2 fixture: la copia existe y trae lo legible de detras del enlace',
          os.path.isfile(os.path.join(Y, 'propio.txt')) and os.path.isfile(os.path.join(Y, 'lnk', 'libre.txt')), r[:400])
    copiado = os.path.join(Y, 'lnk', 'vault', 'secreto.md')
    check('A2 delphi_move copy=true no copia el vault que hay detras del enlace', not os.path.exists(copiado), r[:400])

    r = cli.call('delphi_list', {'root': X, 'pattern': '*.md;*.txt'})
    check('A3 fixture: el listado entra por el enlace (lista libre.txt)', 'libre.txt' in r, r[:400])
    check('A3 delphi_list no lista el vault que hay detras del enlace', 'secreto.md' not in r, r[:600])
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('el vault detras de un enlace que sigue un recorredor 1.27')
