# -*- coding: utf-8 -*-
"""1.29 (EH1 del revisor del paisaje): el commit de un changeset recoloca el atline de cada paso por lo que los
de antes cambiaron por encima en SU fichero. Dos huecos medidos el 7-nov-2026 en vivo:

  C1 un create del mismo lote se tomaba por lineas metidas delante: delete-line atline=2 de un fichero que el
     lote crea iba a la linea 5 ("x.txt has 3") y el lote entero se deshacia
  C2 el atline no seguia a un move: lo apilado sobre el destino de un move no se recolocaba por las ediciones
     de antes del move sobre el origen, y el ancla caia en otra linea

Uso:  python tests/test_changeset_atline_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('changeset_atline_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='cs129', t=60)


def lote(ops):
    r = srv.call('delphi_changeset', {'command': 'begin'})
    cid = r.split('CHANGESET ')[1].split(' ')[0] if 'CHANGESET ' in r else ''
    srv.call('delphi_changeset', {'command': 'stage', 'id': cid, 'ops': ops})
    srv.call('delphi_changeset', {'command': 'preview', 'id': cid})
    return srv.call('delphi_changeset', {'command': 'commit', 'id': cid})


try:
    X = os.path.join(JAIL, 'x.txt')
    r = lote([{'kind': 'create', 'path': X, 'content': 'uno\r\n\r\ntres\r\n'},
              {'kind': 'delete-line', 'path': X, 'atline': 2}])
    hay = open(X, 'rb').read() if os.path.exists(X) else None
    check('C1 create + delete-line atline=2 del mismo fichero: se aplica en la linea 2 de lo creado. ROJO contra '
          '958be0fe: iba a la 5 y el lote se deshacia', mc.abre(r, 'SN_CHANGESET_COMMITTED_FMT')
          and hay == b'uno\r\ntres\r\n', (r[:240], hay))
    A = os.path.join(JAIL, 'a.txt')
    B = os.path.join(JAIL, 'b.txt')
    open(A, 'wb').write(b'l1\r\nl2\r\nl3\r\nl4\r\n')
    r = lote([{'kind': 'edit', 'path': A, 'old': 'l1', 'new': 'l1\r\nextra'},
              {'kind': 'move', 'path': A, 'dest': B},
              {'kind': 'edit', 'path': B, 'old': 'l3', 'new': 'L3', 'atline': 3}])
    hay = open(B, 'rb').read() if os.path.exists(B) else None
    check('C2 lo apilado sobre el destino de un move se recoloca por lo de antes del move. ROJO contra 958be0fe',
          mc.abre(r, 'SN_CHANGESET_COMMITTED_FMT') and hay == b'l1\r\nextra\r\nl2\r\nL3\r\nl4\r\n', (r[:240], hay))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('changeset: atline tras create y move (1.29)')
