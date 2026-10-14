# -*- coding: utf-8 -*-
"""Punto 7 de la 1.18.2 (SiguienteTabOrder no cuenta los heredados): designer
insert (y set parent=) ponia TabOrder = el siguiente de los hijos que ESTAN en
el .dfm. En una form heredada los del ancestro no estan en el fichero: un
TButton nuevo en un panel heredado con dos botones salia con TabOrder = 0, y al
cargarlo el IDE lo pone el PRIMERO del tabulador y reescribe los del ancestro.
Ahora el TabOrder lo da el juez - el escritor del IDE cargando la propuesta,
con los ancestros -: el ultimo, como al soltar uno en el disenador.

  T1 insert de un TButton en el panel heredado: TabOrder = 2 (ROJO en
     produccion: 0)
  T2 control: en una form sin herencia, insert en un panel con un boton:
     TabOrder = 1

Y en FMX (D1 del revisor de cierre, MEDIDO: el centinela "al final" 32767
que se le daba al juez lo colocaba la VCL la ultima, pero el TabList de FMX
rellena hasta ese indice y su escritor lo guarda tal cual): ahora el juez ve
el bloque SIN TabOrder y el IDE le da el suyo.
  F1 insert en la raiz FMX (Button1 0, Panel1 1): TabOrder = 2 (ROJO en
     produccion: 32767)
  F2 un segundo insert: 3 (ROJO en produccion: 32768, fuera de TTabOrder)
  F3 insert de un TEdit en el TPanel: su escritor no le da TabOrder (no esta
     en el TabList de la form); queda la cuenta propia, 1 (ROJO: 32767)
  F4 set parent= de Button8 al panel: tabOrder 2 en la respuesta y en el
     fichero (ROJO: 32767)
  F5 insert con props TabOrder=0: se respeta y no dice previous 32767 (D2)
  F6 ningun 32767 ni nada mayor en el fichero

Uso:  python tests/test_taborder_heredado_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('taborder_heredado_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
USES = b'  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;\r\n'
open(os.path.join(JAIL, 'UBase.dfm'), 'wb').write(
    b"object FormBase: TFormBase\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Base'\r\n"
    b'  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Panel1: TPanel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 200\r\n    Height = 150\r\n'
    b'    TabOrder = 0\r\n'
    b'    object Button1: TButton\r\n      Left = 8\r\n      Top = 8\r\n      TabOrder = 0\r\n    end\r\n'
    b'    object Button2: TButton\r\n      Left = 8\r\n      Top = 40\r\n      TabOrder = 1\r\n    end\r\n'
    b'  end\r\nend\r\n')
open(os.path.join(JAIL, 'UBase.pas'), 'wb').write(
    b'unit UBase;\r\n\r\ninterface\r\n\r\nuses\r\n' + USES + b'\r\n'
    b'type\r\n  TFormBase = class(TForm)\r\n    Panel1: TPanel;\r\n    Button1: TButton;\r\n'
    b'    Button2: TButton;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
HIJA = os.path.join(JAIL, 'UHija.dfm')
open(HIJA, 'wb').write(
    b"inherited FormHija: TFormHija\r\n  Caption = 'Hija'\r\n"
    b'  inherited Panel1: TPanel\r\n  end\r\nend\r\n')
open(os.path.join(JAIL, 'UHija.pas'), 'wb').write(
    b'unit UHija;\r\n\r\ninterface\r\n\r\nuses\r\n' + USES.replace(b';\r\n', b', UBase;\r\n') + b'\r\n'
    b'type\r\n  TFormHija = class(TFormBase)\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
SOLA = os.path.join(JAIL, 'USola.dfm')
open(SOLA, 'wb').write(
    b"object FormSola: TFormSola\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Sola'\r\n"
    b'  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Panel1: TPanel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 200\r\n    Height = 150\r\n'
    b'    TabOrder = 0\r\n'
    b'    object Button1: TButton\r\n      Left = 8\r\n      Top = 8\r\n      TabOrder = 0\r\n    end\r\n'
    b'  end\r\nend\r\n')
open(os.path.join(JAIL, 'USola.pas'), 'wb').write(
    b'unit USola;\r\n\r\ninterface\r\n\r\nuses\r\n' + USES + b'\r\n'
    b'type\r\n  TFormSola = class(TForm)\r\n    Panel1: TPanel;\r\n    Button1: TButton;\r\n'
    b'  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')


UF = os.path.join(JAIL, 'UF.fmx')
open(UF, 'wb').write(
    b'object FormF: TFormF\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n  FormFactor.Devices = [Desktop]\r\n'
    b'  DesignerMasterStyle = 0\r\n'
    b'  object Button1: TButton\r\n    Position.X = 8.000000000000000000\r\n'
    b'    Position.Y = 8.000000000000000000\r\n    TabOrder = 0\r\n  end\r\n'
    b'  object Panel1: TPanel\r\n    Position.X = 8.000000000000000000\r\n'
    b'    Position.Y = 40.000000000000000000\r\n    TabOrder = 1\r\n'
    b'    object Edit1: TEdit\r\n      Touch.InteractiveGestures = [LongTap, DoubleTap]\r\n      TabOrder = 0\r\n'
    b'    end\r\n  end\r\nend\r\n')
open(os.path.join(JAIL, 'UF.pas'), 'wb').write(
    b'unit UF;\r\n\r\ninterface\r\n\r\nuses\r\n  System.Classes, FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls,'
    b' FMX.Edit;\r\n\r\ntype\r\n  TFormF = class(TForm)\r\n    Button1: TButton;\r\n    Panel1: TPanel;\r\n'
    b'    Edit1: TEdit;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n')


def taborder(path, nombre):
    t = open(path, encoding='utf-8').read()
    m = re.search(r'object ' + nombre + r': \w+\r?\n((?:\s+\w[^\n]*\n)*?)\s*end', t)
    if not m:
        return None
    n = re.search(r'TabOrder = (\d+)', m.group(1))
    return int(n.group(1)) if n else None


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='taborder-heredado', t=300)
try:
    r = srv.call('delphi_designer', {'command': 'insert', 'path': HIJA, 'classname': 'TButton',
                                     'component': 'Button3', 'parent': 'Panel1'}, t=240)
    check('T1 insert en un panel HEREDADO con dos botones: TabOrder = 2 (el ultimo, con los del ancestro)',
          not mc.rechazado(r) and taborder(HIJA, 'Button3') == 2, (r[:300], taborder(HIJA, 'Button3')))
    r = srv.call('delphi_designer', {'command': 'insert', 'path': SOLA, 'classname': 'TButton',
                                     'component': 'Button2', 'parent': 'Panel1'}, t=240)
    check('T2 control: sin herencia, en un panel con un boton: TabOrder = 1',
          not mc.rechazado(r) and taborder(SOLA, 'Button2') == 1, (r[:300], taborder(SOLA, 'Button2')))

    def ins(args):
        return srv.call('delphi_designer', dict({'command': 'insert', 'path': UF}, **args), t=240)

    r = ins({'classname': 'TButton', 'component': 'Button9'})
    check('F1 FMX: insert en la raiz (Button1 0, Panel1 1): TabOrder = 2, no 32767',
          not mc.rechazado(r) and taborder(UF, 'Button9') == 2, (r[:300], taborder(UF, 'Button9')))
    r = ins({'classname': 'TButton', 'component': 'Button8'})
    check('F2 FMX: un segundo insert: 3, no 32768 (fuera de TTabOrder)',
          not mc.rechazado(r) and taborder(UF, 'Button8') == 3, (r[:300], taborder(UF, 'Button8')))
    r = ins({'classname': 'TEdit', 'component': 'Edit9', 'parent': 'Panel1'})
    check('F3 FMX: un TEdit en el panel (su escritor no le da TabOrder): la cuenta propia, 1',
          not mc.rechazado(r) and taborder(UF, 'Edit9') == 1, (r[:300], taborder(UF, 'Edit9')))
    r = srv.call('delphi_designer', {'command': 'set', 'path': UF, 'component': 'Button8', 'parent': 'Panel1'},
                 t=240)
    check('F4 FMX: set parent= de Button8 al panel: tabOrder 2 en la respuesta y en el fichero',
          not mc.rechazado(r) and '"tabOrder":2' in r and taborder(UF, 'Button8') == 2,
          (r[:300], taborder(UF, 'Button8')))
    r = ins({'classname': 'TButton', 'component': 'Button7', 'props': 'TabOrder=0'})
    check('F5 FMX: insert con props TabOrder=0: se respeta y no dice previous 32767 (D2)',
          not mc.rechazado(r) and taborder(UF, 'Button7') == 0 and '32767' not in r,
          (r[:400], taborder(UF, 'Button7')))
    valores = [int(x) for x in re.findall(r'TabOrder = (\d+)', open(UF, encoding='utf-8').read())]
    check('F6 FMX: ningun TabOrder de 32767 o mas en el fichero', valores and max(valores) < 32767, valores)
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('designer: el TabOrder de lo nuevo cuenta los heredados 1182 (punto 7)')
