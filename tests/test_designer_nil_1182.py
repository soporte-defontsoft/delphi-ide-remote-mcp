# -*- coding: utf-8 -*-
"""H1 de Hermes (1.18.2, punto 9): designer set value=nil en una propiedad de
TEXTO escribia el literal 'nil' (StyleLookup = 'nil' en un FMX; Caption = 'nil'
aqui). nil, sin comillas, solo vacia una REFERENCIA a otro componente (el IDE
no escribe una referencia vacia: la linea se quita), y la descripcion decia
"nil to clear one", que se lee como "quitar la propiedad". Ahora se niega donde
la propiedad no es una referencia (DSGN-148), con los dos caminos: 'nil' entre
comillas si es el texto; quitar la linea de la propiedad, delphi_edit.

  N1 set Caption=nil (una cadena): DSGN-148 y el form intacto
     (ROJO en produccion: escribia Caption = 'nil')
  N2 ...lo mismo por props (Caption=nil;Left=8): DSGN-148, nada escrito
     (todo o nada; ROJO en produccion)
  N3 el remedio: Caption='nil' entre comillas escribe el texto (guarda)
  N4 el control: PopupMenu=nil (una referencia) quita la linea (guarda)

Uso:  python tests/test_designer_nil_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_nil_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

DFM = (b"object FormN: TFormN\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'N'\r\n"
       b"  ClientHeight = 100\r\n  ClientWidth = 200\r\n"
       b"  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    Width = 75\r\n    Height = 25\r\n"
       b"    Caption = 'x'\r\n    PopupMenu = PopupMenu1\r\n    TabOrder = 0\r\n  end\r\n"
       b"  object PopupMenu1: TPopupMenu\r\n    Left = 96\r\n    Top = 8\r\n  end\r\nend\r\n")
PAS = (b"unit UN;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Menus, "
       b"System.Classes;\r\n\r\ntype\r\n  TFormN = class(TForm)\r\n    Button1: TButton;\r\n"
       b"    PopupMenu1: TPopupMenu;\r\n  end;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")


def form(nombre):
    d = os.path.join(JAIL, nombre + '.dfm')
    open(d, 'wb').write(DFM)
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS.replace(b'unit UN;', ('unit %s;' % nombre).encode()))
    return d


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-nil', t=240)
try:
    d = form('UN1')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Button1', 'prop': 'Caption',
                                     'value': 'nil'}, t=240)
    check('N1 set Caption=nil en una cadena: DSGN-148 y el form intacto',
          mc.abre(r, 'SR_DESIGNER_SET_NIL_FMT') and open(d, 'rb').read() == DFM, (r[:300], open(d, 'rb').read()[-120:]))

    d = form('UN2')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Button1',
                                     'props': 'Caption=nil;Left=16'}, t=240)
    check('N2 lo mismo por props: DSGN-148 y nada escrito (todo o nada)',
          mc.es(r, 'SR_DESIGNER_SET_NIL_FMT') and mc.rechazado(r) and open(d, 'rb').read() == DFM, r[:300])

    d = form('UN3')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Button1', 'prop': 'Caption',
                                     'value': "'nil'"}, t=240)
    check("N3 el remedio: Caption='nil' entre comillas escribe ese texto",
          not mc.fallo(r) and b"    Caption = 'nil'\r\n" in open(d, 'rb').read(), r[:300])

    d = form('UN4')
    r = srv.call('delphi_designer', {'path': d, 'command': 'set', 'component': 'Button1', 'prop': 'PopupMenu',
                                     'value': 'nil'}, t=240)
    # (revisor de baterias, 18-oct-2026) la LINEA entera: un PopupMenu = nil
    # escrito seguia verde
    check('N4 el control: PopupMenu=nil (una referencia) quita su linea',
          not mc.fallo(r) and b'PopupMenu =' not in open(d, 'rb').read(), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('designer set nil 1182 (H1)')
