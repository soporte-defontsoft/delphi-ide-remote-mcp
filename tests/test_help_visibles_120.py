# -*- coding: utf-8 -*-
"""delphi_help command=tool y lo que tools/list NO anuncia (1.20, Hermes en la VM, validacion
previa del 16-oct): las negativas HELP-007 (sin name) y HELP-002 (un nombre que no existe)
listaban el REGISTRO entero como "the ones there are", y en un workspace sin vault ofrecian
vault_append/vault_patch/... que tools/list no le anuncia - una invitacion a llamar una tool
que no esta. Ahora listan lo que tools/list anuncia a esa sesion (el mismo filtro,
ToolHiddenFromList). Se reproduce con un vault de SOLO LECTURA: las de escritura del vault
estan registradas y tools/list las calla.

  V0 control: tools/list trae vault_read y no vault_append
  V1 HELP-007 (command=tool sin name): vault_read si, vault_append no (ROJO en 3cc31fc)
  V2 HELP-002 (un nombre sin parecido): lo mismo (ROJO en 3cc31fc)

Uso:  python tests/test_help_visibles_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('help_visibles_120')
JAIL = os.path.join(BASE, 'jail')
VAULT = os.path.join(BASE, 'vault')
for d in (JAIL, VAULT):
    os.makedirs(d)
open(os.path.join(VAULT, 'AGENTS-VAULT.md'), 'w').write('# reglas\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                                'DELPHI_MCP_VAULT_READONLY': '1'}), nombre='help-visibles', t=120)
try:
    lista = srv.request('tools/list') or {}
    nombres = [t.get('name') for t in lista.get('result', {}).get('tools', [])]
    check('V0 control: tools/list trae vault_read y no vault_append',
          'vault_read' in nombres and 'vault_append' not in nombres, nombres)

    r = srv.call('delphi_help', {'command': 'tool'})
    check('V1 HELP-007 lista lo que tools/list anuncia: vault_read si, vault_append no',
          mc.tiene(r, 'HELP-007') and 'vault_read' in r and 'vault_append' not in r, r[:600])

    r = srv.call('delphi_help', {'command': 'tool', 'name': 'zzqqxx120'})
    check('V2 HELP-002 lista lo que tools/list anuncia: vault_read si, vault_append no',
          mc.tiene(r, 'HELP-002') and 'vault_read' in r and 'vault_append' not in r, r[:600])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('help nombra solo las tools que tools/list anuncia 120')
