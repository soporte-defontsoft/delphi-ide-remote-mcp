# -*- coding: utf-8 -*-
"""V120 de la 1.24: el renderizador busca ancestros y frames por la clase raiz de
los forms de la carpeta, y con dos forms de la misma clase cargaba el primero
listado. Es lo que deja copiar un form en el Explorador: "UBase - copia.dfm" lleva
TFormBase y se lista antes que UBase.dfm. Medido contra la 1.23.1: el preview
dibujaba la copia mientras el exe enlazaba UBase.

La copia y el original se distinguen por DONDE ponen su control (componentRect):

  A1 un ancestro en dos forms: se lee el que dice el uses (ROJO en la 1.23.1)
  A2 un frame inline en dos forms: lo mismo (ROJO en la 1.23.1)
  A3 ...y un uses que no nombra a ninguno: se lee uno y RENDER-025 dice cual
  A4 control: sin copia, sin aviso
  A5 control: la copia pedida por su nombre sigue siendo ella

Uso:  python tests/test_render_ancestro_124.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('render_ancestro_124')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
JAIL = os.path.join(BASE, 'jail')


def escribe(carpeta, nombre, texto):
    os.makedirs(carpeta, exist_ok=True)
    ruta = os.path.join(carpeta, nombre)
    open(ruta, 'wb').write(texto.replace('\n', '\r\n').encode('ascii'))
    return ruta


def base_dfm(left):
    return ('object FormBase: TFormBase\n  Left = 0\n  Top = 0\n  Caption = \'B\'\n  ClientHeight = 200\n'
            '  ClientWidth = 400\n  object LabelBase: TLabel\n    Left = %d\n    Top = 8\n    Width = 24\n'
            '    Height = 15\n    Caption = \'B\'\n  end\nend\n' % left)


def base_pas(unidad='UBase'):
    return ('unit %s;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls;\n\ntype\n  TFormBase = class(TForm)\n'
            '    LabelBase: TLabel;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % unidad)


def hija(carpeta, usos):
    escribe(carpeta, 'UHija.pas', 'unit UHija;\n\ninterface\n\nuses\n  Vcl.Forms, %s;\n\ntype\n'
            '  TFormHija = class(TFormBase)\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % usos)
    return escribe(carpeta, 'UHija.dfm', 'inherited FormHija: TFormHija\n  Caption = \'H\'\nend\n')


def rect(srv, form, componente):
    r = srv.call('delphi_designer', {'command': 'preview', 'path': form, 'component': componente,
                                     'out': os.path.join(JAIL, 'o.png')}, t=120)
    try:
        j = json.loads(r)
    except ValueError:
        return None, [], r[:300]
    return j.get('componentRect', '').split(',')[0], j.get('warnings', []), r[:300]


D_A = os.path.join(JAIL, 'ancestro')
D_F = os.path.join(JAIL, 'frame')
D_N = os.path.join(JAIL, 'ninguno')
D_C = os.path.join(JAIL, 'control')
for d in (D_A, D_N):
    escribe(d, 'UBase.dfm', base_dfm(20))
    escribe(d, 'UBase.pas', base_pas())
    escribe(d, 'UBase - copia.dfm', base_dfm(200))
    escribe(d, 'UBase - copia.pas', base_pas())
HIJA = hija(D_A, 'UBase')
COPIA = os.path.join(D_A, 'UBase - copia.dfm')
# un uses que no la nombra: la clase llega por otra unidad, y en la carpeta nadie dice cual
escribe(D_N, 'UOtra.pas', 'unit UOtra;\n\ninterface\n\nuses\n  UBase;\n\nimplementation\n\nend.\n')
HIJA_N = hija(D_N, 'UOtra')
escribe(D_C, 'UBase.dfm', base_dfm(20))
escribe(D_C, 'UBase.pas', base_pas())
HIJA_C = hija(D_C, 'UBase')


def marco_dfm(left):
    return ('object Marco: TMarco\n  Left = 0\n  Top = 0\n  Width = 300\n  Height = 60\n  TabOrder = 0\n'
            '  object LabelM: TLabel\n    Left = %d\n    Top = 4\n    Width = 24\n    Height = 15\n'
            '    Caption = \'M\'\n  end\nend\n' % left)


MARCO_PAS = ('unit UMarco;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls;\n\ntype\n  TMarco = class(TFrame)\n'
             '    LabelM: TLabel;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
escribe(D_F, 'UMarco.dfm', marco_dfm(30))
escribe(D_F, 'UMarco.pas', MARCO_PAS)
escribe(D_F, 'UMarco - copia.dfm', marco_dfm(150))
escribe(D_F, 'UMarco - copia.pas', MARCO_PAS)
escribe(D_F, 'UForm.pas', 'unit UForm;\n\ninterface\n\nuses\n  Vcl.Forms, UMarco;\n\ntype\n'
        '  TFormF = class(TForm)\n    Marco1: TMarco;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
FORM_F = escribe(D_F, 'UForm.dfm', 'object FormF: TFormF\n  Left = 0\n  Top = 0\n  Caption = \'F\'\n'
                 '  ClientHeight = 200\n  ClientWidth = 400\n  inline Marco1: TMarco\n    Left = 0\n    Top = 0\n'
                 '    Width = 300\n    Height = 60\n    TabOrder = 0\n  end\nend\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='render-ancestro', t=300)
try:
    x, avisos, r = rect(srv, HIJA, 'LabelBase')
    check('A1 un ancestro en dos forms: se lee el que dice el uses, sin aviso', x == '20' and not avisos, (x, avisos, r))
    x, avisos, r = rect(srv, FORM_F, 'Marco1.LabelM')
    check('A2 un frame inline en dos forms: se lee el que dice el uses', x == '30' and not avisos, (x, avisos, r))
    x, avisos, r = rect(srv, HIJA_N, 'LabelBase')
    check('A3 un uses que no nombra a ninguno: uno de los dos, y RENDER-025 dice cual',
          x in ('20', '200') and any(mc.es(a, 'SN_RENDER_CLASE_EN_VARIOS_FMT') and 'UBase - copia.dfm' in a
                                     for a in avisos), (x, avisos, r))
    x, avisos, r = rect(srv, HIJA_C, 'LabelBase')
    check('A4 control: sin copia, su ancestro y sin aviso', x == '20' and not avisos, (x, avisos, r))
    x, avisos, r = rect(srv, COPIA, 'LabelBase')
    check('A5 control: la copia pedida por su nombre sigue siendo ella', x == '200', (x, avisos, r))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el ancestro de una form con su copia al lado (V120)')
