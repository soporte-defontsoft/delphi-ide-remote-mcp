# -*- coding: utf-8 -*-
"""DSGN-093 de la 1.20 (Hermes, hermes-120 del 16-oct, paso A5): un color ARGB escrito
a mano, TextSettings.FontColor = $FF00A152, no cabe en los 32 bits CON SIGNO que lee
el cargador (ReadInteger), y el mensaje solo decia el tope: Hermes tardo 6 llamadas
en salir (optimo 3) y acabo escribiendo -16735918. Los mismos 32 bits caben de otra
forma, CALCULADA: con su signo, y en la forma x+hexadecimal que el IdentTo de su tipo
lee (FormasAbiertas de la tabla; es como escriben los forms del IDE: xFF414141).

  T1 set $FF00A152 en un TAlphaColor: DSGN-093 con xFF00A152 y -16735918
     (ROJO en produccion: solo el tope)
  T2 lo que propone entra: set xFF00A152 se escribe
  T3 un Integer sin forma x (Width de un TLabel VCL): solo con su signo, -16
  T4 el lint de un FMX escrito a mano con $FF00A152 dice lo mismo
  T5 control: lo que no cabe ni en 32 bits sin signo no propone nada

Uso:  python tests/test_valor_32_bits_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('valor_32_bits_120')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

FMX = ("object FormF: TFormF\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 480\r\n"
       "  ClientWidth = 640\r\n  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n"
       "  FormFactor.Devices = [Desktop]\r\n  DesignerMasterStyle = 0\r\n"
       "  object Edit1: TEdit\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 40.000000000000000000\r\n{edit}    TabOrder = 0\r\n  end\r\nend\r\n")
PAS_FMX = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Types, System.UITypes, "
           "System.Classes, System.Variants,\r\n  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, "
           "FMX.Edit, FMX.Controls.Presentation;\r\n\r\ntype\r\n  TFormF = class(TForm)\r\n    Edit1: TEdit;\r\n"
           "  end;\r\n\r\nvar\r\n  FormF: TFormF;\r\n\r\nimplementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n")
VCL = ("object FormV: TFormV\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'V'\r\n  ClientHeight = 200\r\n"
       "  ClientWidth = 300\r\n  object Label1: TLabel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 30\r\n"
       "    Height = 15\r\n    Caption = 'Label1'\r\n  end\r\nend\r\n")
PAS_VCL = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Classes, Vcl.Controls, "
           "Vcl.Forms, Vcl.StdCtrls;\r\n\r\ntype\r\n  TFormV = class(TForm)\r\n    Label1: TLabel;\r\n"
           "  end;\r\n\r\nvar\r\n  FormV: TFormV;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")


def fmx(nombre, edit=''):
    p = os.path.join(JAIL, nombre + '.fmx')
    open(p, 'wb').write(b'\xef\xbb\xbf' + FMX.replace('{edit}', edit).encode('utf-8'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS_FMX.replace('{u}', nombre).encode('utf-8'))
    return p


def vcl(nombre):
    p = os.path.join(JAIL, nombre + '.dfm')
    open(p, 'wb').write(VCL.encode('ascii'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS_VCL.replace('{u}', nombre).encode('ascii'))
    return p


def plano(r):
    return (r or '').replace('\\"', '"')


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='valor-32-bits', t=240)
try:
    for fw, r in mc.espera_tablas(srv.call):
        check('T0 la tabla %s esta lista' % fw, mc.tabla_lista(r), r[:200])

    pf = fmx('UF')
    pv = vcl('UV')

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Edit1',
                                           'prop': 'TextSettings.FontColor', 'value': '$FF00A152'}))
    check('T1 $FF00A152 en un TAlphaColor: DSGN-093 con xFF00A152 y -16735918',
          mc.tiene(r, 'DSGN-093') and 'the same 32 bits go as xFF00A152, which its reader takes, or as -16735918' in r,
          r[:600])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Edit1',
                                           'prop': 'TextSettings.FontColor', 'value': 'xFF00A152'}))
    check('T2 lo que propone entra: xFF00A152 se escribe',
          not mc.rechazado(r) and 'TextSettings.FontColor = xFF00A152' in open(pf, 'rb').read().decode('utf-8-sig'),
          r[:600])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Width', 'value': '$FFFFFFF0'}))
    check('T3 un Integer sin forma x: solo con su signo, -16',
          mc.tiene(r, 'DSGN-093') and 'the same 32 bits go as -16' in r and 'which its reader takes' not in r,
          r[:600])

    p4 = fmx('UF4', edit='    TextSettings.FontColor = $FF00A152\r\n')
    r = plano(srv.call('delphi_designer', {'path': p4, 'command': 'lint'}, t=240))
    check('T4 el lint de un FMX a mano con $FF00A152 propone xFF00A152 y -16735918',
          'xFF00A152' in r and '-16735918' in r, r[:900])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Width', 'value': '-2147483649'}))
    check('T5 control: lo que no cabe ni sin signo no propone nada',
          mc.tiene(r, 'DSGN-093') and 'the same 32 bits' not in r, r[:600])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('los mismos 32 bits de un valor que no cabe con signo 120 (DSGN-093)')
