# -*- coding: utf-8 -*-
"""V166 (1.23.1): the vault walker (CollectNotes) does not cross links.

vault_search / its "files" listing walked the vault with a recursive
TDirectory.GetFiles/GetDirectories of its own, with no link check and no cycle
cut: a junction inside the vault pointing OUTSIDE listed and read the .md behind
it (outside the vault jail), and a junction to an ancestor looped until the path
blew up. The vault is a separate jail, so WalkFiles (the workspace walker) does
not apply; CollectNotes now skips reparse points (EsEnlace), like WalkFiles.

  M1 a junction inside the vault -> an outside folder with secreto.md:
     vault_search target=files does NOT list it (RED against 06f59ce: it did)
  M2 (control) a real nested note IS listed

Usage:  python tests/test_vault_enlace_v166.py [path-to-DelphiLspMcp.exe]
"""
import os, sys, _winapi
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('vault_enlace_v166')
VAULT = os.path.join(BASE, 'vault')
FUERA = os.path.join(BASE, 'fuera')     # FUERA del vault
WORK = os.path.join(BASE, 'work')
for d in (VAULT, os.path.join(VAULT, 'sub'), FUERA, WORK):
    os.makedirs(d)
open(os.path.join(VAULT, 'MEMORY.md'), 'w', encoding='utf-8').write('# MEMORY\n\n- indice\n')
open(os.path.join(VAULT, 'sub', 'anidada.md'), 'w', encoding='utf-8').write('# Anidada\n\ndentro del vault\n')
open(os.path.join(FUERA, 'secreto.md'), 'w', encoding='utf-8').write('# Secreto\n\nfuera del vault\n')
_winapi.CreateJunction(FUERA, os.path.join(VAULT, 'lnk'))  # una union dentro del vault -> fuera

S = mc.Stdio(mc.copia_exe(os.path.join(BASE, 's'), src=exe_src),
             mc.entorno({'DELPHI_MCP_ROOTS': WORK, 'DELPHI_MCP_VAULT_PATH': VAULT,
                         'DELPHI_MCP_VAULT_READONLY': '1'}), nombre='v166', t=300)
try:
    r = S.call('vault_search', {'target': 'files', 'pattern': '*.md'})
    check('M1 vault_search target=files NO lista el .md de detras de una union a fuera del vault',
          'secreto' not in r, r[:300])
    check('M2 control: una nota anidada REAL del vault si se lista',
          'anidada.md' in r, r[:300])
finally:
    S.cierra()
    lnk = os.path.join(VAULT, 'lnk')
    if os.path.isdir(lnk):
        os.rmdir(lnk)  # quita el ENLACE, no FUERA
    mc.borra(BASE)

mc.fin('V166 vault link walker battery')
