# -*- coding: utf-8 -*-
"""Un ALIAS de parametro y su nombre real a la vez, con valores DISTINTOS (V93,
1.23.1). ApplyArgAliases (Lsp.Guard) descartaba el alias en silencio: medido en
produccion, delphi_search root=A path=B buscaba en A y no decia nada de B. Un
parametro ignorado en silencio es un fallo nuestro: con valores distintos se
niega nombrando los dos; con el MISMO valor (el caso de Hermes, path=root) sigue
siendo inocuo.

  A1 delphi_search root=A path=B: negado (GUARD-045) con los dos nombres, nada buscado
  A2 delphi_search root=A path=A: busca, como siempre
  A3 delphi_list root=A dir=B: negado igual (otra tool, otro alias)
  A4 delphi_search root=A path=null: busca en A (null es "no viene" para la puerta
     y el binder; la comparacion miraba el texto 'null' y lo negaba: V100, de la
     pasada del paisaje del diff)

Uso:  python tests/test_alias_valor_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('alias_valor_1231')
JAIL = os.path.join(BASE, 'jail')
A = os.path.join(JAIL, 'A')
B = os.path.join(JAIL, 'B')
os.makedirs(A)
os.makedirs(B)
open(os.path.join(A, 'UA.pas'), 'w').write('unit UA;\ninterface\nconst MARCA_A = 1;\nimplementation\nend.\n')
open(os.path.join(B, 'UB.pas'), 'w').write('unit UB;\ninterface\nconst MARCA_B = 1;\nimplementation\nend.\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='alias-valor', t=120)
try:
    r = srv.call('delphi_search', {'root': A, 'path': B, 'query': 'MARCA_'})
    check('A1 delphi_search root=A path=B: negado nombrando root y path (antes buscaba en A y callaba)',
          mc.abre(r, 'SR_ARG_ALIAS_OTRO_VALOR_FMT') and 'root' in r and 'path' in r and 'UA.pas' not in r, r[:400])
    r = srv.call('delphi_search', {'root': A, 'path': A, 'query': 'MARCA_'})
    check('A2 delphi_search root=A path=A (el mismo valor): busca, como siempre',
          not mc.fallo(r) and 'UA.pas' in r and 'UB.pas' not in r, r[:400])
    r = srv.call('delphi_list', {'root': A, 'dir': B})
    check('A3 delphi_list root=A dir=B: negado igual (otra tool, otro alias)',
          mc.abre(r, 'SR_ARG_ALIAS_OTRO_VALOR_FMT') and 'dir' in r, r[:400])
    r = srv.call('delphi_search', {'root': A, 'path': None, 'query': 'MARCA_'})
    check('A4 delphi_search root=A path=null: busca en A, null no es otro valor (ROJO contra V93 sin V100)',
          not mc.fallo(r) and 'UA.pas' in r, r[:400])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('alias con otro valor 1.23.1 (V93)')
