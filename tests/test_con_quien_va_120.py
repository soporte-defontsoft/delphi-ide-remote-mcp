# -*- coding: utf-8 -*-
"""DSGN-047 y DSGN-087 de la 1.20, medidos en el historial de Hermes el 16-oct
(lo de Hermes aparte: sus pruebas de borde, las pausas de su puente).

DSGN-047, un parametro que no va con el comando: de 10 casos, 4 eran un
command OLVIDADO ({path, maxdepth} sin command) y el mensaje decia "path no va
con command=info", que el modelo no habia pedido. Ahora ParametroQueNoVa, la
regla de las 13 tools de varios modos, dice tambien con que modos SI va,
sacado de la MISMA tabla (sin lista propia).

DSGN-087, una propiedad que la clase no publica: la mayoria de los casos de
verdad (set, insert y los avisos del lint tras delphi_edit) eran la propiedad
de la OTRA plataforma (Alignment en un TLabel FMX, Caption en un TButton FMX,
Position.X en un TLabel VCL), y la parecida por distancia mentia: "Did you
mean Action?" por Caption y "Hint.Color" por Font.Color (Hint es una cadena).
Ahora el juez lo dice con la tabla del otro marco, y la parecida solo propone
una ruta que existe entera.

  V1  designer sin command con path y maxdepth: "What you sent (path,
      maxdepth) goes with: tree." (ROJO en produccion: solo "info takes...")
  V2  to-text con path y out: "What you sent (path, out) goes with: preview."
  V3  delphi_edit old/new con code: '"code" goes with: insert=rutina-global,
      insert=metodo.'
  V4  set Alignment en un TLabel FMX: es la del TLabel de la VCL
  V5  set Font.Color en un TEdit FMX: la del TEdit de la VCL, y no Hint.Color
  V6  insert de un TButton FMX con Caption: la del TButton de la VCL, y no
      "Did you mean Action?"
  V7  set Position.X en un TLabel VCL: la del TLabel de FMX
  V8  control: AlignTo en un TLayout FMX sigue diciendo "Did you mean Align?"
      (la VCL no tiene TLayout: sin pista)
  V9  control: una propiedad que no existe en ningun marco: ni pista ni parecida
  V10 lint de un FMX escrito a mano: Alignment en el TLabel y
      TextSettings.Font.Color (la pista en el trozo que falla: el TFont de la VCL)
  V11 Hent.Color en un TLabel VCL: ni "Did you mean Hint.Color?" (no existe)
  V12 control de V11: Fant.Size sigue proponiendo Font.Size (existe)
  V13 otra tool por la misma regla: delphi_textedit old/new con content:
      '"content" goes with: create.'

Uso:  python tests/test_con_quien_va_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('con_quien_va_120')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

FMX = ("object FormF: TFormF\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 480\r\n"
       "  ClientWidth = 640\r\n  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n"
       "  FormFactor.Devices = [Desktop]\r\n  DesignerMasterStyle = 0\r\n"
       "  object Label1: TLabel\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    Text = 'Label1'\r\n{label}  end\r\n"
       "  object Edit1: TEdit\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 40.000000000000000000\r\n    TabOrder = 0\r\n  end\r\n"
       "  object Layout1: TLayout\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 80.000000000000000000\r\n    TabOrder = 1\r\n  end\r\nend\r\n")
PAS_FMX = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Types, System.UITypes, "
           "System.Classes, System.Variants,\r\n  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, "
           "FMX.StdCtrls, FMX.Edit, FMX.Layouts, FMX.Controls.Presentation;\r\n\r\ntype\r\n"
           "  TFormF = class(TForm)\r\n    Label1: TLabel;\r\n    Edit1: TEdit;\r\n    Layout1: TLayout;\r\n"
           "  end;\r\n\r\nvar\r\n  FormF: TFormF;\r\n\r\nimplementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n")
VCL = ("object FormV: TFormV\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'V'\r\n  ClientHeight = 200\r\n"
       "  ClientWidth = 300\r\n  object Label1: TLabel\r\n    Left = 8\r\n    Top = 8\r\n    Width = 30\r\n"
       "    Height = 15\r\n    Caption = 'Label1'\r\n  end\r\nend\r\n")
PAS_VCL = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Classes, Vcl.Controls, "
           "Vcl.Forms, Vcl.StdCtrls;\r\n\r\ntype\r\n  TFormV = class(TForm)\r\n    Label1: TLabel;\r\n"
           "  end;\r\n\r\nvar\r\n  FormV: TFormV;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")


def fmx(nombre, label=''):
    p = os.path.join(JAIL, nombre + '.fmx')
    open(p, 'wb').write(b'\xef\xbb\xbf' + FMX.replace('{label}', label).encode('utf-8'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS_FMX.replace('{u}', nombre).encode('utf-8'))
    return p


def vcl(nombre):
    p = os.path.join(JAIL, nombre + '.dfm')
    open(p, 'wb').write(VCL.encode('ascii'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(PAS_VCL.replace('{u}', nombre).encode('ascii'))
    return p


def plano(r):
    """La respuesta con las comillas como las escribe el servidor (en una
    respuesta JSON van escapadas)."""
    return (r or '').replace('\\"', '"')


def pista(propiedad, marco, clase, este):
    return '"%s" is what the %s %s publishes; this form is %s' % (propiedad, marco, clase, este)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='con-quien-va', t=240)
try:
    # la pista pregunta a la tabla del OTRO marco sin esperar: tienen que estar
    for fw, r in mc.espera_tablas(srv.call):
        check('V0 la tabla %s esta lista' % fw, not mc.tiene(r, 'DSGN-051') and not mc.fallo(r), r[:200])

    pf = fmx('UF')
    pv = vcl('UV')

    r = plano(srv.call('delphi_designer', {'path': pf, 'maxdepth': 3}))
    check('V1 sin command, con path y maxdepth: DSGN-047 y "goes with: tree"',
          mc.tiene(r, 'DSGN-047') and 'What you sent (path, maxdepth) goes with: tree.' in r, r[:400])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'to-text', 'out': JAIL}))
    check('V2 to-text con path y out: lo enviado va con preview',
          mc.tiene(r, 'DSGN-047') and 'What you sent (path, out) goes with: preview.' in r, r[:400])

    pu = os.path.join(JAIL, 'UF.pas')
    r = plano(srv.call('delphi_edit', {'path': pu, 'old': '  FormF: TFormF;', 'new': '  FormF: TFormF;',
                                       'code': 'procedure X;\r\nbegin\r\nend;'}))
    check('V3 delphi_edit old/new con code: "code" va con los dos insert',
          mc.tiene(r, 'EDIT-115') and '"code" goes with: insert=rutina-global, insert=metodo.' in r, r[:400])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Alignment', 'value': 'taRightJustify'}))
    check('V4 Alignment en un TLabel FMX: la del TLabel de la VCL, sin parecida',
          mc.tiene(r, 'DSGN-087') and pista('Alignment', 'VCL', 'TLabel', 'FMX') in r
          and 'Did you mean' not in r, r[:700])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Edit1',
                                           'prop': 'Font.Color', 'value': '-65536'}))
    check('V5 Font.Color en un TEdit FMX: la del TEdit de la VCL, y no Hint.Color',
          mc.tiene(r, 'DSGN-087') and pista('Font.Color', 'VCL', 'TEdit', 'FMX') in r
          and 'Hint.Color' not in r, r[:700])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'insert', 'classname': 'TButton',
                                           'component': 'Btn1', 'props': 'Caption=Guardar;Width=120'}))
    check('V6 insert de un TButton FMX con Caption: la del TButton de la VCL, y no Action',
          mc.tiene(r, 'DSGN-087') and pista('Caption', 'VCL', 'TButton', 'FMX') in r
          and 'Did you mean' not in r and 'Btn1' not in open(pf, 'rb').read().decode('utf-8-sig'), r[:700])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Position.X', 'value': '35'}))
    check('V7 Position.X en un TLabel VCL: la del TLabel de FMX',
          mc.tiene(r, 'DSGN-087') and pista('Position.X', 'FMX', 'TLabel', 'VCL') in r, r[:700])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Layout1',
                                           'prop': 'AlignTo', 'value': 'Edit1'}))
    check('V8 control: AlignTo en un TLayout FMX sigue diciendo "Did you mean Align?", sin pista',
          mc.tiene(r, 'DSGN-087') and 'Did you mean Align?' in r and 'is what the' not in r, r[:700])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'set', 'component': 'Label1',
                                           'prop': 'NoExisteEnNinguno120', 'value': '1'}))
    check('V9 control: lo que no existe en ningun marco, ni pista ni parecida',
          mc.tiene(r, 'DSGN-087') and 'is what the' not in r and 'Did you mean' not in r, r[:700])

    p10 = fmx('UF10', label="    Alignment = taRightJustify\r\n    TextSettings.Font.Color = clNavy\r\n")
    r = plano(srv.call('delphi_designer', {'path': p10, 'command': 'lint'}, t=240))
    check('V10 lint de un FMX a mano: Alignment (TLabel de la VCL) y el Color del TFont de la VCL',
          pista('Alignment', 'VCL', 'TLabel', 'FMX') in r and pista('Color', 'VCL', 'TFont', 'FMX') in r,
          r[:1200])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Hent.Color', 'value': 'clRed'}))
    check('V11 Hent.Color en un TLabel VCL: ni "Did you mean Hint.Color?" (Hint es una cadena)',
          mc.tiene(r, 'DSGN-087') and 'Hint.Color' not in r, r[:700])

    r = plano(srv.call('delphi_designer', {'path': pv, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Fant.Size', 'value': '12'}))
    check('V12 control: Fant.Size sigue proponiendo Font.Size, que existe',
          mc.tiene(r, 'DSGN-087') and 'Did you mean Font.Size?' in r, r[:700])

    pt = os.path.join(JAIL, 't.txt')
    open(pt, 'wb').write(b'a\r\n')
    r = plano(srv.call('delphi_textedit', {'path': pt, 'old': 'a', 'new': 'b', 'content': 'x'}))
    check('V13 la misma regla en otra tool: "content" va con create',
          mc.tiene(r, 'EDIT-115') and '"content" goes with: create.' in r, r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('con quien va un parametro y la propiedad de la otra plataforma 120 (DSGN-047, DSGN-087)')
