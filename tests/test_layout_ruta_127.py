# -*- coding: utf-8 -*-
r"""layout VCL nombra cada caja por su RUTA, la del renderizador (revisor del paisaje de la 1.27, R1).

El recorrido del texto nombraba cada caja por su nombre a secas y el renderizador por su ruta
(FrameX1.PanelFrame), y se cruzaban por el nombre: lo sobrescrito dentro de un frame en linea salia dos
veces, y con un homonimo en el form tomaba SU rectangulo. Medido el 3-nov-2026: el PanelFrame de dentro
de FrameX1 salia con x=20 y=300, las del PanelFrame del form; boxes es lo que el contrato da para colocar
el siguiente control.

  L1 lo sobrescrito en el frame sale UNA vez, por su ruta, con el rectangulo del renderizador
  L2 el homonimo del form conserva el suyo
  L3 ninguna caja PanelFrame con padre FrameX1 (la del texto, con el nombre a secas)

Uso:  python tests/test_layout_ruta_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('layout-ruta-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src, con_render=True)
J = os.path.join(BASE, 'jail')
os.makedirs(J)
FONT = ("  Font.Charset = DEFAULT_CHARSET\n  Font.Color = clWindowText\n  Font.Height = -12\n  Font.Name = 'Segoe UI'\n"
        "  Font.Style = []\n  TextHeight = 15\n")


def escribe(n, t):
    with open(os.path.join(J, n), 'w', newline='\r\n') as f:
        f.write(t)
    return os.path.join(J, n)


escribe('UFrameX.pas', "unit UFrameX;\ninterface\nuses Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, System.Classes, Vcl.Controls;\n"
        "type\n  TFrameX = class(TFrame)\n    EditFrame: TEdit;\n    PanelFrame: TPanel;\n  end;\nimplementation\n"
        "{$R *.dfm}\nend.\n")
escribe('UFrameX.dfm', "object FrameX: TFrameX\n  Left = 0\n  Top = 0\n  Width = 300\n  Height = 120\n  TabOrder = 0\n"
        "  object EditFrame: TEdit\n    Left = 8\n    Top = 32\n    Width = 200\n    Height = 23\n    TabOrder = 0\n  end\n"
        "  object PanelFrame: TPanel\n    Left = 8\n    Top = 64\n    Width = 280\n    Height = 41\n    TabOrder = 1\n  end\n"
        "end\n")
escribe('UConFrame.pas', "unit UConFrame;\ninterface\nuses UFrameX, Vcl.Forms, Vcl.ExtCtrls, System.Classes, Vcl.Controls;\n"
        "type\n  TFormConFrame = class(TForm)\n    FrameX1: TFrameX;\n    PanelFrame: TPanel;\n  end;\nimplementation\n"
        "{$R *.dfm}\nend.\n")
F = escribe('UConFrame.dfm', "object FormConFrame: TFormConFrame\n  Left = 0\n  Top = 0\n  Caption = 'Con frames'\n"
            "  ClientHeight = 400\n  ClientWidth = 340\n" + FONT +
            "  inline FrameX1: TFrameX\n    Left = 16\n    Top = 32\n    Width = 300\n    Height = 120\n    TabOrder = 0\n"
            "    inherited PanelFrame: TPanel\n      Top = 70\n    end\n  end\n"
            "  object PanelFrame: TPanel\n    Left = 20\n    Top = 300\n    Width = 100\n    Height = 50\n    TabOrder = 1\n"
            "  end\nend\n")
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': J}), nombre='layout-ruta-127', t=300)
try:
    r = srv.call('delphi_designer', {'command': 'layout', 'path': F}, t=240)
    j = mc.como_json(r) or {}
    cajas = j.get('boxes') or []
    check('fixture: las cajas las da el renderizador', j.get('boxesFrom') == 'renderer', r[:300])
    en_frame = [b for b in cajas if b.get('name') == 'FrameX1.PanelFrame']
    check('L1 lo sobrescrito en el frame, UNA vez y por su ruta, con el rectangulo del renderizador (dentro del frame)',
          len(en_frame) == 1 and en_frame[0].get('y', 0) > 32 and en_frame[0].get('y', 0) < 152, str(cajas))
    del_form = [b for b in cajas if b.get('name') == 'PanelFrame']
    check('L2 el homonimo del form conserva el suyo', len(del_form) == 1 and del_form[0].get('y') == 300, str(del_form))
    check('L3 ninguna caja PanelFrame con padre FrameX1 (el nombre a secas del texto)',
          not [b for b in cajas if b.get('name') == 'PanelFrame' and b.get('parent') == 'FrameX1'], str(cajas))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('layout VCL nombra cada caja por su ruta 1.27 (R1)')
