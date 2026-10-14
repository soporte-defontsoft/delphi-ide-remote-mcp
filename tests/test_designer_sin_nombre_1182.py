# -*- coding: utf-8 -*-
"""B3 rev6 del punto 7 de la 1.18.2: el juez del orden (designer set index= /
before= / after=) con componentes SIN nombre ('object TTimer'). Comparaba
solo los hijos CON nombre: un hermano sin nombre no contaba, y un orden que el
IDE no guarda respecto a el se escribia diciendo "Placed where the IDE's own
writer keeps it". Un padre sin nombre se buscaba por su CLASE y salia DSGN-143
"loaded the form without TPanel", que no es lo que pasa.

  N1 un padre sin nombre: DSGN-150 (lo dice) y nada escrito (ROJO en produccion:
     DSGN-143 "without TPanel")
  N2 Button2 detras de un TTimer SIN nombre (index= el ultimo): el IDE escribe
     los controles antes; se niega con SU orden (DSGN-136), nada escrito (ROJO en
     produccion: se escribia)
  N3 control: Button2 delante de Button1 con el TTimer sin nombre al lado: se
     escribe (el IDE lo guarda)

Uso:  python tests/test_designer_sin_nombre_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_sin_nombre_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
PAS = (b'unit U%s;\r\n\r\ninterface\r\n\r\nuses\r\n'
       b'  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;\r\n\r\n'
       b'type\r\n  TForm1 = class(TForm)\r\n    Button1: TButton;\r\n    Button2: TButton;\r\n  end;\r\n\r\n'
       b'var\r\n  Form1: TForm1;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
HDR = (b"object Form1: TForm1\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Form1'\r\n"
       b'  ClientHeight = 200\r\n  ClientWidth = 300\r\n')
BOT1 = b'  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    TabOrder = 0\r\n  end\r\n'
BOT2 = b'  object Button2: TButton\r\n    Left = 8\r\n    Top = 80\r\n    TabOrder = 1\r\n  end\r\n'
TIMER = b'  object TTimer\r\n    Left = 200\r\n    Top = 8\r\n  end\r\n'

PADRE = os.path.join(JAIL, 'UPadre.dfm')
T_PADRE = (HDR + b'  object TPanel\r\n    Left = 8\r\n    Top = 8\r\n    TabOrder = 0\r\n'
           b'    object Button1: TButton\r\n      Left = 8\r\n      Top = 8\r\n      TabOrder = 0\r\n    end\r\n'
           b'    object Button2: TButton\r\n      Left = 8\r\n      Top = 40\r\n      TabOrder = 1\r\n    end\r\n'
           b'  end\r\nend\r\n')
open(PADRE, 'wb').write(T_PADRE)
open(os.path.join(JAIL, 'UPadre.pas'), 'wb').write(PAS % b'Padre')
HERM = os.path.join(JAIL, 'UHerm.dfm')
T_HERM = HDR + BOT1 + BOT2 + TIMER + b'end\r\n'
open(HERM, 'wb').write(T_HERM)
open(os.path.join(JAIL, 'UHerm.pas'), 'wb').write(PAS % b'Herm')


def orden(path):
    return [l.strip() for l in open(path, encoding='utf-8').read().splitlines()
            if l.startswith('  object ')]


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-sin-nombre', t=300)
try:
    def dsg(path, args):
        return srv.call('delphi_designer', dict({'command': 'set', 'path': path}, **args), t=240)

    r = dsg(PADRE, {'component': 'Button2', 'before': 'Button1'})
    check('N1 un padre SIN nombre: DSGN-150 y nada escrito (no "without TPanel")',
          mc.rechazado(r) and 'DSGN-150' in r and open(PADRE, 'rb').read() == T_PADRE, r[:300])
    r = dsg(HERM, {'component': 'Button2', 'index': 3})
    check('N2 Button2 detras de un TTimer SIN nombre: el IDE no lo guarda (DSGN-136, su orden), nada escrito',
          mc.rechazado(r) and 'DSGN-136' in r and 'TTimer' in r and open(HERM, 'rb').read() == T_HERM,
          (r[:300], orden(HERM)))
    open(HERM, 'wb').write(T_HERM)
    r = dsg(HERM, {'component': 'Button2', 'before': 'Button1'})
    check('N3 control: Button2 delante de Button1 con el TTimer sin nombre al lado: se escribe',
          not mc.rechazado(r) and orden(HERM) == ['object Button2: TButton', 'object Button1: TButton',
                                                  'object TTimer'], (r[:300], orden(HERM)))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('designer: el orden con componentes sin nombre 1182 (B3 rev6)')
