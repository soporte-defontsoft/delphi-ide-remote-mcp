# -*- coding: utf-8 -*-
"""Un .dfm en UTF-8 SIN BOM con letras altas (medido el 13-oct con dcc en
testsserver\\mide-dfm: Configuracion con la o en C3 B3 -> el exe lleva la o
partida en dos letras). El IDE, dcc y este servidor leen un form sin BOM en la
ANSI de la maquina, asi que lo que el agente ve (la o partida) es lo que tendra
el programa, pero nadie se lo decia: lint daba CLEAN. Ahora delphi_read y
designer lint lo dicen (READ-009) cuando EL detector, sin la regla de los
forms, diria que sus bytes son UTF-8. Convertirlo es cambiar la codificacion:
del usuario.

  F1 delphi_read del form UTF-8 sin BOM: READ-009 (ROJO en produccion)
  F2 designer lint del mismo: READ-009 (ROJO en produccion)
  F3 control: el mismo form CON BOM: sin nota
  F4 control: el form en ANSI de verdad (la o en un byte): sin nota

Uso:  python tests/test_form_utf8_sin_bom_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('form_utf8_sin_bom_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
TXT = ("object Form1: TForm1\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Configuración'\r\n"
       "  ClientHeight = 100\r\n  ClientWidth = 200\r\nend\r\n")
PAS = (b'unit U%s;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms;\r\n\r\ntype\r\n  TForm1 = class(TForm)\r\n'
       b'  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')


def form(nombre, contenido):
    p = os.path.join(JAIL, 'U%s.dfm' % nombre)
    open(p, 'wb').write(contenido)
    open(os.path.join(JAIL, 'U%s.pas' % nombre), 'wb').write(PAS % nombre.encode())
    return p


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='form-utf8-sin-bom', t=240)
try:
    p = form('A', TXT.encode('utf-8'))
    r = srv.call('delphi_read', {'path': p})
    check('F1 delphi_read de un form UTF-8 sin BOM: READ-009', 'READ-009' in r, r[:400])
    r = srv.call('delphi_designer', {'command': 'lint', 'path': p}, t=240)
    check('F2 designer lint del mismo: READ-009', 'READ-009' in r, r[:400])
    p = form('B', b'\xef\xbb\xbf' + TXT.encode('utf-8'))
    r1 = srv.call('delphi_read', {'path': p})
    r2 = srv.call('delphi_designer', {'command': 'lint', 'path': p}, t=240)
    check('F3 control: con BOM, sin nota', 'READ-009' not in r1 and 'READ-009' not in r2, (r1[:200], r2[:200]))
    p = form('C', TXT.encode('cp1252'))
    r1 = srv.call('delphi_read', {'path': p})
    r2 = srv.call('delphi_designer', {'command': 'lint', 'path': p}, t=240)
    check('F4 control: ANSI de verdad, sin nota', 'READ-009' not in r1 and 'READ-009' not in r2, (r1[:200], r2[:200]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('form UTF-8 sin BOM 1182')
