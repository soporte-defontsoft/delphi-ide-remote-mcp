# -*- coding: utf-8 -*-
"""El vault de un workspace dentro de su ReadOnlyRoot, alcanzado por un ENLACE (V192 de la 1.23.1, revisor
del paisaje del 29-oct, medido).

Las tools de codigo no tocan el vault, y por su texto ya se negaba (VAULT-002). Por la ruta REAL lo
preguntaba solo la rama de las RAICES de la jaula (JaulaDecide); la de las referencias (ReadOnlyRoots) y
la de la biblioteca contestaban "se lee" antes: con el vault dentro de una referencia, un enlace en la
raiz o en la referencia que apuntase dentro dejaba leer sus notas con delphi_read y buscarlas con
delphi_search.

  E1 (control) delphi_read del secreto por su ruta: VAULT-002
  E2 delphi_read por un enlace de la RAIZ que apunta al vault: negado, sin el secreto (ROJA contra b6c7ff9)
  E3 delphi_read por un enlace de la REFERENCIA que apunta al vault: negado (ROJA)
  E4 delphi_search en la referencia: el secreto no sale (ROJA: lo encontraba por el enlace)

Uso:  python tests/test_vault_enlace_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('vault_enlace_1231')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV, src=exe_src)
JAIL = os.path.join(BASE, 'jail')
REF = os.path.join(BASE, 'ref')
VAULT = os.path.join(REF, 'vault')
os.makedirs(JAIL)
os.makedirs(VAULT)
os.makedirs(os.path.join(REF, 'otra'))
for n in ('AGENTS-VAULT.md', 'MEMORY.md'):
    open(os.path.join(VAULT, n), 'w').write('# x\n')
open(os.path.join(VAULT, 'secreto.md'), 'w').write('SECRETO del vault\n')
ok = mc.junction(os.path.join(JAIL, 'lnk'), VAULT) and mc.junction(os.path.join(REF, 'otra', 'lnk2'), VAULT)
check('los enlaces se plantan', ok)
PUERTO = mc.puerto_libre()
TOKEN = 'vault-enlace-1231-0123456789'
open(os.path.join(SRV, 'settings.ini'), 'w').write(
    '[Workspace.S]\nToken=%s\nRoots=%s\nReadOnlyRoots=%s\nVaultPath=%s\n' % (TOKEN, JAIL, REF, VAULT))
proc = mc.lanza_http(EXE, PUERTO, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
try:
    cli = mc.Http(PUERTO, TOKEN)
    cli.session('vault-enlace')
    r = cli.call('delphi_read', {'path': os.path.join(VAULT, 'secreto.md')})
    check('E1 control: el secreto por su ruta, VAULT-002', mc.rechazado(r) and 'SECRETO' not in r, r[:200])
    r = cli.call('delphi_read', {'path': os.path.join(JAIL, 'lnk', 'secreto.md')})
    check('E2 por un enlace de la raiz que apunta al vault: negado', mc.rechazado(r) and 'SECRETO' not in r, r[:200])
    r = cli.call('delphi_read', {'path': os.path.join(REF, 'otra', 'lnk2', 'secreto.md')})
    check('E3 por un enlace de la referencia que apunta al vault: negado',
          mc.rechazado(r) and 'SECRETO' not in r, r[:200])
    r = cli.call('delphi_search', {'root': REF, 'query': 'SECRETO', 'pattern': '*.md'})
    check('E4 delphi_search en la referencia no encuentra el secreto por el enlace', 'SECRETO' not in r, r[:300])
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('el vault alcanzado por un enlace 1231 (V192)')
