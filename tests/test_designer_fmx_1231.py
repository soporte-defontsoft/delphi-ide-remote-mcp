# -*- coding: utf-8 -*-
"""delphi_designer insert en FMX escribe lo que guarda el IDE al soltar un
control: ALINEADO, y con el TabOrder que le da su padre (1.23.1, V68 y V72).

Medido el 27-oct-2026 con el juez (el renderizador en --writeback): la VCL
alinea al cargar; FMX no alinea lo que cuelga del form hasta que algo lo
realinea (la preview lo hace al pintar), y un TPanel Align=Bottom se escribia
en 10,10 sin su tamano: al cargar se estiraba y lo anclado a la derecha salia
fuera. El IDE escribe Position.Y y Size del alineado (Samples, Mobile Tasks,
FormMain.fmx:94-99). Y FMX solo mete un hijo en la lista de tabulacion de su
padre fuera de la lectura: un boton nuevo en un panel HEREDADO salia con
TabOrder = 0 junto al 0 del heredado (la VCL da 1).

  A1 insert TPanel Align=Bottom en un form de 640x480: Position.Y = 360,
     Size.Width = 640 y sin Position.X, como el IDE
  A2 ...un TButton Align=Right dentro: Position.X = 560 (alineado en su padre)
  A3 ...un TLayout Align=Client: Size 640x360
  A4 (el oraculo) la preview, que alinea al pintar, los pone en esos sitios
  A5 la nota del insert alineado dice que lo coloca su Align (decia DSGN-169,
     "esta clase no guarda posicion", o "cae en 10,10")
  A6 VCL: un TPanel alBottom sale alineado como siempre, y su nota ya no dice
     10,10 (la VCL alineaba al cargar; la nota mentia ya en la 1.23.0)
  T1 form heredado: un boton nuevo en el panel heredado, TabOrder = 1 (tras el
     BtnCerrar heredado, 0)
  T2 control: un boton escrito a mano DENTRO de un panel y SIN linea TabOrder
     sigue sin ella tras un set (solo el que se suelta entra en el tabulador:
     FMX no mete en el de un control al que lee sin ella, y el IDE tampoco se
     la pone; el form si mete a sus hijos al leer, TCommonCustomForm.DoAddObject)

Uso:  python tests/test_designer_fmx_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_fmx_1231')
JAIL = os.path.join(BASE, 'jail')
FMX = os.path.join(JAIL, 'fmx')
HER = os.path.join(JAIL, 'heredado')
VCL = os.path.join(JAIL, 'vcl')
for c in (FMX, HER, VCL):
    os.makedirs(c)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-fmx-1231', t=300)


def d(**kw):
    return s.call('delphi_designer', kw, t=300)


def props(fichero, nombre):
    """{propiedad: valor} del nivel propio del bloque de nombre."""
    dentro, sangria, res = False, None, {}
    for l in mc.lee(fichero).splitlines():
        t = l.strip()
        if not dentro:
            if t.startswith(('object ' + nombre + ':', 'inherited ' + nombre + ':')):
                dentro, sangria = True, len(l) - len(l.lstrip()) + 2
            continue
        if t.startswith(('object ', 'inherited ', 'inline ')) or t == 'end':
            break
        if len(l) - len(l.lstrip()) == sangria and ' = ' in t:
            k, v = t.split(' = ', 1)
            res[k] = v
    return res


def num(p, k):
    try:
        return float(p.get(k, 'x'))
    except ValueError:
        return None


def escribe(ruta, texto):
    with open(ruta, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))


BASE_PAS = '''unit UBase;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls;

type
  TFormBase = class(TForm)
    PnlBotones: TPanel;
    BtnCerrar: TButton;
  private
  public
  end;

var
  FormBase: TFormBase;

implementation

{$R *.fmx}

end.
'''
BASE_FMX = '''object FormBase: TFormBase
  Left = 0
  Top = 0
  Caption = 'FormBase'
  ClientHeight = 480
  ClientWidth = 640
  FormFactor.Width = 320
  FormFactor.Height = 480
  FormFactor.Devices = [Desktop]
  DesignerMasterStyle = 0
  object PnlBotones: TPanel
    Align = Bottom
    Position.Y = 439.000000000000000000
    Size.Width = 640.000000000000000000
    Size.Height = 41.000000000000000000
    Size.PlatformDefault = False
    TabOrder = 0
    object BtnCerrar: TButton
      Anchors = [akTop, akRight]
      Position.X = 557.000000000000000000
      Position.Y = 8.000000000000000000
      TabOrder = 0
      Text = 'Cerrar'
    end
  end
end
'''
HIJA_PAS = '''unit UHija;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, UBase,
  FMX.StdCtrls, FMX.Controls.Presentation;

type
  TFormHija = class(TFormBase)
  private
  public
  end;

var
  FormHija: TFormHija;

implementation

{$R *.fmx}

end.
'''
HIJA_FMX = '''inherited FormHija: TFormHija
  Caption = 'FormHija'
  inherited PnlBotones: TPanel
    inherited BtnCerrar: TButton
      Text = 'Salir'
    end
  end
end
'''

try:
    listas = mc.espera_tablas(lambda tool, args, t=120: s.call(tool, args, t=t))
    check('fixture: las tablas del disenador estan listas',
          all(mc.tabla_lista(r) for _, r in listas), str(listas)[:300])
    s.call('delphi_create', {'kind': 'project-fmx', 'name': 'Ali', 'dir': FMX})
    F = os.path.join(FMX, 'UMain.fmx')
    check('fixture: el form nuevo es de 640x480',
          'ClientHeight = 480' in mc.lee(F) and 'ClientWidth = 640' in mc.lee(F), mc.lee(F)[:300])

    r = d(command='insert', path=F, classname='TPanel', component='PnlAbajo', props='Align=Bottom')
    p = props(F, 'PnlAbajo')
    check('A1 insert TPanel Align=Bottom: Position.Y = 360, Size.Width = 640, sin Position.X (el IDE)',
          not mc.fallo(r) and num(p, 'Position.Y') == 360 and num(p, 'Size.Width') == 640
          and num(p, 'Size.Height') == 120 and 'Position.X' not in p, (p, r[:400]))
    nota = str((mc.como_json(r) or {}).get('note'))
    check('A5 ...y su nota dice que lo coloca su Align, no que cae en 10,10 ni que no tiene sitio',
          'Its Align (Bottom) places it' in nota and '10,10' not in nota
          and not mc.es(nota, 'SN_DESIGNER_INSERT_SIN_SITIO_NOTE'), nota)
    r = d(command='insert', path=F, classname='TButton', component='BtnDer', parent='PnlAbajo',
          props='Align=Right')
    p = props(F, 'BtnDer')
    check('A2 ...un TButton Align=Right dentro: Position.X = 560, alineado en su padre',
          not mc.fallo(r) and num(p, 'Position.X') == 560 and num(p, 'Size.Width') == 80, (p, r[:400]))
    r = d(command='insert', path=F, classname='TLayout', component='LayCentro', props='Align=Client')
    p = props(F, 'LayCentro')
    check('A3 ...un TLayout Align=Client: Size 640x360',
          not mc.fallo(r) and num(p, 'Size.Width') == 640 and num(p, 'Size.Height') == 360, (p, r[:400]))
    esperado = {'PnlAbajo': '0,360,640,120', 'BtnDer': '560,360,80,120', 'LayCentro': '0,0,640,360'}
    vistos = {}
    for c in esperado:
        r = d(command='preview', path=F, component=c, out=os.path.join(FMX, c + '.png'))
        vistos[c] = (mc.como_json(r) or {}).get('componentRect')
    check('A4 (el oraculo) la preview, que alinea al pintar, los pone en esos mismos sitios',
          all(str(vistos[c]).replace(' ', '') == esperado[c] for c in esperado), vistos)

    # la VCL ya alineaba al cargar, y la nota decia 10,10 de un panel alineado
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'AliV', 'dir': VCL})
    V = os.path.join(VCL, 'UMain.dfm')
    r = d(command='insert', path=V, classname='TPanel', component='PnlAbajoV', props='Align=alBottom')
    p = props(V, 'PnlAbajoV')
    nota = str((mc.como_json(r) or {}).get('note'))
    check('A6 VCL: un TPanel alBottom, alineado como siempre, y su nota ya no dice 10,10',
          not mc.fallo(r) and p.get('Align') == 'alBottom' and p.get('Top') != '10'
          and 'Its Align (alBottom) places it' in nota and '10,10' not in nota, (p, nota))

    escribe(os.path.join(HER, 'UBase.pas'), BASE_PAS)
    escribe(os.path.join(HER, 'UBase.fmx'), BASE_FMX)
    escribe(os.path.join(HER, 'UHija.pas'), HIJA_PAS)
    H = os.path.join(HER, 'UHija.fmx')
    escribe(H, HIJA_FMX)
    r = d(command='insert', path=H, classname='TButton', component='BtnGuardar', parent='PnlBotones')
    p = props(H, 'BtnGuardar')
    check('T1 form heredado: el boton nuevo en el panel heredado, TabOrder = 1 (tras el heredado)',
          not mc.fallo(r) and p.get('TabOrder') == '1', (p, r[:400]))

    # un boton escrito a mano DENTRO de un panel, sin su linea TabOrder: un set
    # no se la pone (el form si mete a sus hijos al leer, FMX.Forms
    # TCommonCustomForm.DoAddObject; un control no, FMX.Controls:2310)
    t = mc.lee(F).replace('\r\n', '\n')
    ancla = "      Text = 'BtnDer'\n    end\n"
    i = t.index(ancla) + len(ancla)
    escribe(F, t[:i] + '    object BtnSinTab: TButton\n      Position.X = 300.000000000000000000\n'
            '      Position.Y = 5.000000000000000000\n      Text = \'Sin\'\n    end\n' + t[i:])
    r = d(command='set', path=F, component='BtnSinTab', prop='Text', value="'Otro'")
    p = props(F, 'BtnSinTab')
    check('T2 control: uno escrito sin TabOrder sigue sin el tras un set (solo el soltado entra)',
          not mc.fallo(r) and p.get('Text') == "'Otro'" and 'TabOrder' not in p, (p, r[:400]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('designer FMX como al soltarlo en el IDE 1.23.1 (V68, V72)')
