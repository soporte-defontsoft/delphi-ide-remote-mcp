# -*- coding: utf-8 -*-
"""H4 de Hermes (1.18.2, punto 9): las listas de nombres del disenador se
cortaban a 40 SIN decirlo (MAX_NOMBRES): en un form de 161 componentes la de
DSGN-078 parecia la entera. Ahora dicen cuantos faltan y donde verlos
(command=tree), en sus dos usos: los componentes del form y los que caben en
una referencia.

  M1 set sobre un componente que no existe: DSGN-078 lista 40 y dice
     "... and N more (command=tree ...)" con el N exacto (ROJO en produccion)
  M2 una referencia de otro tipo (FocusControl = una TLabel): la lista de los
     que caben dice tambien cuantos faltan (ROJO en produccion)
  M3 el control: un form con pocos componentes no lleva "more" (guarda)

Uso:  python tests/test_designer_nombres_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_nombres_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
N_EDITS = 45


def form(nombre, n):
    bloques = ''.join('  object Edit%d: TEdit\r\n    Left = 8\r\n    Top = %d\r\n    Width = 121\r\n'
                      '    Height = 23\r\n    TabOrder = %d\r\n  end\r\n' % (i, 8 + i * 4, i - 1)
                      for i in range(1, n + 1))
    dfm = ('object FormM: TFormM\r\n  Left = 0\r\n  Top = 0\r\n  Caption = \'M\'\r\n  ClientHeight = 400\r\n'
           '  ClientWidth = 400\r\n  object Label1: TLabel\r\n    Left = 200\r\n    Top = 8\r\n'
           '    Width = 30\r\n    Height = 15\r\n    Caption = \'L\'\r\n  end\r\n' + bloques + 'end\r\n')
    campos = '    Label1: TLabel;\r\n' + ''.join('    Edit%d: TEdit;\r\n' % i for i in range(1, n + 1))
    pas = ('unit %s;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, System.Classes;\r\n\r\n'
           'type\r\n  TFormM = class(TForm)\r\n%s  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n'
           % (nombre, campos))
    p = os.path.join(JAIL, nombre + '.dfm')
    open(p, 'w', newline='').write(dfm)
    open(os.path.join(JAIL, nombre + '.pas'), 'w', newline='').write(pas)
    return p


def faltan(r):
    m = re.search(r'and (\d+) more \(command=tree', r)
    return int(m.group(1)) if m else None


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-nombres', t=240)
try:
    p = form('UM1', N_EDITS)
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'NoExiste', 'prop': 'Caption',
                                     'value': 'x'}, t=240)
    total = 1 + 1 + N_EDITS  # el form, Label1 y los Edit
    check('M1 DSGN-078 en un form de %d: dice "and %d more (command=tree ...)"' % (total, total - 40),
          mc.abre(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and faltan(r) == total - 40, r[-300:])

    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Label1', 'prop': 'FocusControl',
                                     'value': 'Label1'}, t=240)
    check('M2 la lista de los que caben en la referencia dice tambien cuantos faltan',
          mc.rechazado(r) and (faltan(r) or 0) > 0, r[-300:])

    p = form('UM3', 3)
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'NoExiste', 'prop': 'Caption',
                                     'value': 'x'}, t=240)
    check('M3 el control: con pocos componentes la lista va entera y sin "more"',
          mc.abre(r, 'SR_DESIGNER_COMPONENTE_NO_ESTA_FMT') and faltan(r) is None and 'Edit3' in r, r[-300:])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('designer: listas de nombres sin tope callado 1182 (H4)')
