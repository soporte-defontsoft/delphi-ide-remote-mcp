# -*- coding: utf-8 -*-
"""1.29 (EH4 del revisor del paisaje): "esto no es texto" (LooksBinaryBytes, bytes NUL) lo negaban delphi_read,
delphi_edit old/new y delphi_textedit de uno en uno, pero no los otros caminos que reescriben un fichero:
adduses edito un .pas con bytes NUL que old/new negaba con TEXT-008 (medido en vivo el 7-nov-2026). La regla
vive ahora en la de ida y vuelta de TODO el que reescribe (Lsp.Puertas.ReescrituraDenegada).

  B1 adduses en un .pas con NUL: TEXT-008, y el fichero intacto
  B2 removeuses, igual
  B3 una tanda de delphi_edit (edits) en el .pas con NUL: TEXT-008
  B4 una tanda de delphi_textedit en un .txt con NUL: TEXT-008
  B5 control: old/new en el .pas con NUL ya lo negaba (TEXT-008)
  B6 control: adduses en un .pas limpio sigue funcionando

Uso:  python tests/test_binario_reescritura_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('binario_reescritura_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
UNIDAD = (b'unit u;\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils;\r\n\r\nimplementation\r\n\r\n'
          b'const X = 1;\x00\x00\x00\r\nend.\r\n')
PAS = os.path.join(JAIL, 'u.pas')
TXT = os.path.join(JAIL, 'n.txt')
LIMPIO = os.path.join(JAIL, 'limpio.pas')
open(PAS, 'wb').write(UNIDAD)
open(TXT, 'wb').write(b'uno\r\ndos\x00\x00\r\ntres\r\n')
open(LIMPIO, 'wb').write(UNIDAD.replace(b'\x00', b''))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='bin129', t=60)


def intacto(ruta, bytes_):
    return open(ruta, 'rb').read() == bytes_


try:
    r = srv.call('delphi_edit', {'path': PAS, 'adduses': 'System.Math'})
    check('B1 adduses en un .pas con NUL: TEXT-008 y el fichero intacto. ROJO contra 958be0fe: lo edita',
          mc.es(r, 'SR_TEXT_PARECE_BINARIO_FMT') and intacto(PAS, UNIDAD), r[:200])
    r = srv.call('delphi_edit', {'path': PAS, 'removeuses': 'System.SysUtils', 'section': 'interface'})
    check('B2 removeuses, igual', mc.es(r, 'SR_TEXT_PARECE_BINARIO_FMT') and intacto(PAS, UNIDAD), r[:200])
    r = srv.call('delphi_edit', {'path': PAS, 'edits': [{'old': 'const X = 1;', 'new': 'const X = 2;'}]})
    check('B3 una tanda de delphi_edit: TEXT-008', mc.es(r, 'SR_TEXT_PARECE_BINARIO_FMT') and intacto(PAS, UNIDAD),
          r[:200])
    TXT_ANTES = open(TXT, 'rb').read()
    r = srv.call('delphi_textedit', {'path': TXT, 'edits': [{'old': 'uno', 'new': 'UNO'}]})
    check('B4 una tanda de delphi_textedit en un .txt con NUL: TEXT-008',
          mc.es(r, 'SR_TEXT_PARECE_BINARIO_FMT') and intacto(TXT, TXT_ANTES), r[:200])
    r = srv.call('delphi_edit', {'path': PAS, 'old': 'const X = 1;', 'new': 'const X = 2;'})
    check('B5 control: old/new ya lo negaba', mc.es(r, 'SR_TEXT_PARECE_BINARIO_FMT'), r[:200])
    r = srv.call('delphi_edit', {'path': LIMPIO, 'adduses': 'System.Math'})
    check('B6 control: adduses en un .pas limpio sigue funcionando',
          not mc.fallo(r) and b'System.Math' in open(LIMPIO, 'rb').read(), r[:200])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('reescritura de un binario (1.29)')
