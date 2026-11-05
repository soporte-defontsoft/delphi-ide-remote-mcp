"""E2E battery for v0.70.0-beta - delphi_designer command=layout.

The gap this closes, in the operator's words: an agent building a VCL/FMX form
has the numbers - it wrote them - but not the arithmetic that turns
Left/Top/Width/Height plus Align into a screen. A form can bind perfectly,
compile, load, and still be a stack of controls on top of each other, a button
of size zero, or a panel hanging off the edge of the window. Nothing in the
build says a word about it.

What is pinned here:
  L1  a form that is fine is reported fine - no false positives, which is the
      whole difference between a tool an agent trusts and one it learns to
      ignore
  L2  two free controls sharing pixels (one hides the other)
  L3  a control with a side of zero
  L4  a control that falls outside its container, nested containers included
  L5  Align resolved the way the VCL does it: each aligned child eats its band
      off the remaining client rectangle
  L6  a second alClient gets nothing
  L7  non-visual components (TTimer, TPopupMenu: Left/Top only, no size) are
      not geometry and are not judged
  L8  a size the .dfm does not write is declared unknown, never guessed at -
      by the text arithmetic; with the renderer it is MEASURED (R8 of 1.27)
  R8  with the renderer every judgment comes from the boxes the VCL measured,
      not from the text: a TLabel with AutoSize wider than the Width it wrote
  L9  the doctrine holds: read jail, text designers only, binary refused
  A2  FMX and VCL are judged by ONE judge of the measured boxes (1.27): a warning's
      coordinates are relative to the parent it names, and the children of a
      container that places them itself are not judged outside it, in both

Usage:  python tests/test_layout.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('layout')
EXE = mc.copia_exe(BASE, con_render=True)  # un binario lo convierte el ayudante de 32 bits (V71)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='layout-battery', t=60)
# el modo TEXTO, el que queda cuando el renderizador no contesta (la aritmetica de Walk): un
# servidor SIN renderizadores al lado. Su doctrina se media en la misma carpeta que el otro y solo
# porque alli un form truncado (Trunc) hacia fallar al renderizador: pasaba por casualidad
BASE_T = mc.carpeta('layout-texto')
srv_t = mc.Stdio(mc.copia_exe(BASE_T), mc.entorno({'DELPHI_MCP_ROOTS': BASE_T}), nombre='layout-texto', t=60)


def call(args):
    # toda la bateria habla con delphi_designer
    return srv.call('delphi_designer', args)


def layout(name, body, texto=False):
    p = os.path.join(BASE_T if texto else BASE, name + '.dfm')
    open(p, 'w', encoding='utf-8', newline='').write(body)
    r = (srv_t.call('delphi_designer', {'command': 'layout', 'path': p}) if texto
         else call({'command': 'layout', 'path': p}))
    try:
        return json.loads(r)
    except Exception:
        return {'RAW': r}


def all_text(o, *keys):
    return json.dumps([o.get(k, []) for k in keys], ensure_ascii=False)


# L1/L5/L7 - a real, correct form: a top bar, a status bar, a grid filling the
# rest, buttons inside the bar, and a TTimer that is not on screen at all.
GOOD = """object FormMain: TFormMain
  Caption = 'Bien'
  ClientHeight = 300
  ClientWidth = 500
  object PanelTop: TPanel
    Align = alTop
    Width = 500
    Height = 40
    object BtnBuscar: TButton
      Left = 8
      Top = 8
      Width = 75
      Height = 25
    end
    object BtnLimpiar: TButton
      Left = 90
      Top = 8
      Width = 75
      Height = 25
    end
  end
  object StatusBar1: TStatusBar
    Align = alBottom
    Width = 500
    Height = 19
  end
  object Grid: TStringGrid
    Align = alClient
    Width = 500
    Height = 241
  end
  object Timer1: TTimer
    Left = 240
    Top = 120
  end
end
"""
o = layout('Bien', GOOD)
check('L1 un form correcto sale limpio', o.get('clean') is True, o)
# (revisor de baterias de la 1.27) la caja del Grid, no clientWidth/clientHeight: esos los copia del .dfm
# y pasaban sin resolver nada. El alClient empieza donde acaba la banda de arriba, acaba donde empieza la
# de abajo y ocupa el ancho entero
bx = {b['name']: b for b in o.get('boxes', [])}
g, top, bot = bx.get('Grid', {}), bx.get('PanelTop', {}), bx.get('StatusBar1', {})
check('L5 Align resuelto: el alClient recibe el hueco que queda',
      bool(g and top and bot) and g.get('y') == top.get('y', 0) + top.get('h', -1) and
      g.get('y', 0) + g.get('h', 0) == bot.get('y') and g.get('x') == 0 and g.get('w') == 500, o)
check('L7 un TTimer no tiene geometria que juzgar',
      'Timer1' not in all_text(o, 'zeroSize', 'outsideParent', 'overlapping',
                               'clipped', 'sizeNotWritten'), o)

# L2 - two free controls sharing pixels
OVER = """object F: TF
  ClientHeight = 200
  ClientWidth = 400
  object BtnA: TButton
    Left = 10
    Top = 10
    Width = 100
    Height = 25
  end
  object BtnB: TButton
    Left = 60
    Top = 20
    Width = 100
    Height = 25
  end
end
"""
o = layout('Over', OVER)
check('L2 dos controles solapados: uno tapa al otro',
      o.get('clean') is False and len(o.get('overlapping', [])) == 1
      and 'BtnA' in json.dumps(o) and 'BtnB' in json.dumps(o), o)

# ...and two that merely touch do NOT overlap
TOUCH = OVER.replace('Left = 60', 'Left = 110')
o = layout('Touch', TOUCH)
check('L2 dos controles pegados NO se solapan (sin falso positivo)',
      o.get('clean') is True, o)

# L3 - a side of zero
ZERO = """object F: TF
  ClientHeight = 200
  ClientWidth = 400
  object Edt: TEdit
    Left = 10
    Top = 10
    Width = 0
    Height = 21
  end
end
"""
o = layout('Zero', ZERO)
check('L3 un control con un lado a cero',
      o.get('clean') is False and len(o.get('zeroSize', [])) == 1, o)

# L4 - outside the container, and the container is a nested panel
OUT = """object F: TF
  ClientHeight = 200
  ClientWidth = 400
  object Panel1: TPanel
    Align = alTop
    Width = 400
    Height = 50
    object BtnFuera: TButton
      Left = 360
      Top = 10
      Width = 120
      Height = 25
    end
    object BtnAlto: TButton
      Left = 10
      Top = 40
      Width = 75
      Height = 25
    end
  end
end
"""
o = layout('Out', OUT)
# (revisor de baterias, 18-oct-2026) el nombre DENTRO de outsideParent: en el
# JSON entero salian siempre (boxes trae todos los controles), y con los dos
# botones fuera a la vez cada mitad pasaba por la otra
fuera = json.dumps(o.get('outsideParent') or [], ensure_ascii=False)
check('L4 se sale por la derecha del panel que lo contiene',
      o.get('clean') is False and 'BtnFuera' in fuera and 'Panel1' in fuera, o)
check('L4 y tambien por abajo', 'BtnAlto' in fuera, o)
# en la VCL un contenedor recorta lo que se sale: esa parte no se ve (su texto lo dice;
# el de FMX no, V74i)
check('L4c en la VCL el aviso dice que esa parte no se ve',
      any(t.startswith('BtnFuera') and 'not visible' in t for t in o.get('outsideParent') or []), o)

# L4b - negative coordinates count as outside too
NEG = OUT.replace('Left = 360', 'Left = -20').replace('Left = 10', 'Left = 10')
o = layout('Neg', NEG)
check('L4 una coordenada negativa tambien se sale',
      o.get('clean') is False and 'BtnFuera' in json.dumps(o.get('outsideParent') or []), o)

# L5 - aligned children eating the whole parent
NOROOM = """object F: TF
  ClientHeight = 100
  ClientWidth = 400
  object P1: TPanel
    Align = alTop
    Width = 400
    Height = 60
  end
  object P2: TPanel
    Align = alTop
    Width = 400
    Height = 60
  end
  object P3: TPanel
    Align = alTop
    Width = 400
    Height = 60
  end
end
"""
o = layout('NoRoom', NOROOM)
check('L5 los alineados consumen el form y al siguiente no le queda sitio',
      o.get('clean') is False and len(o.get('clipped', [])) >= 1, o)

# L6 - a second alClient
TWOCLIENT = """object F: TF
  ClientHeight = 200
  ClientWidth = 400
  object M1: TMemo
    Align = alClient
    Width = 400
    Height = 200
  end
  object M2: TMemo
    Align = alClient
    Width = 400
    Height = 200
  end
end
"""
o = layout('TwoClient', TWOCLIENT)
# (revisor de baterias, 18-oct-2026) la premisa ya no era la del servidor: un
# alClient toma TODO el hueco y dos se solapan al 100% (lo mide tambien Bug3,
# con otro form); "M2 en el JSON" pasaba con cualquier respuesta
check('L6 dos alClient: el segundo tapa al primero al 100%',
      o.get('clean') is False and 'M2' in json.dumps(o.get('overlapping') or [])
      and '100%' in json.dumps(o.get('overlapping') or []), o)

# L8 - a size the .dfm never wrote
NOSIZE = """object F: TF
  ClientHeight = 200
  ClientWidth = 400
  object Lbl: TLabel
    Left = 10
    Top = 10
    Width = 50
  end
end
"""
o = layout('NoSize', NOSIZE, texto=True)
check('L8 fixture: sin renderizador al lado, las cajas son las del texto', o.get('boxesFrom') == 'text', o)
check('L8 sin renderizador, un tamano no escrito se declara desconocido, no se inventa',
      len(o.get('sizeNotWritten', [])) == 1 and o.get('zeroSize') == [], o)
o = layout('NoSize', NOSIZE)
bx = {b['name']: b for b in o.get('boxes', [])}
check('L8 con el renderizador, ese tamano se MIDE: la caja con su alto y nada desconocido (R8)',
      o.get('boxesFrom') == 'renderer' and bx.get('Lbl', {}).get('h', 0) > 0
      and o.get('sizeNotWritten') == [] and o.get('zeroSize') == [], o)

# L10 - el Width de un ITEM de coleccion no es el del objeto (2.2 de la 1.18.0:
# el lector propio de layout, PropRaw, lo tomaba por suyo; ahora lee
# TStyleDoc.ValorDe, el nivel propio del objeto)
ITEMW = """object F: TF
  ClientHeight = 200
  ClientWidth = 400
  object LV: TListView
    Left = 10
    Top = 10
    Height = 100
    Columns = <
      item
        Width = 999
      end>
  end
end
"""
o = layout('ItemW', ITEMW, texto=True)
check('L10 el Width de una columna no es el del control: su anchura sigue sin escribir, '
      'no se sale del form',
      'LV' in all_text(o, 'sizeNotWritten') and 'LV' not in all_text(o, 'outsideParent', 'clipped'), o)
o = layout('ItemW', ITEMW)
bx = {b['name']: b for b in o.get('boxes', [])}
check('L10 con el renderizador, la anchura es la que mide la VCL y no la de la columna (999): '
      'no se sale del form ni queda desconocida (R8)',
      o.get('boxesFrom') == 'renderer' and 0 < bx.get('LV', {}).get('w', 0) < 400
      and 'LV' not in all_text(o, 'outsideParent', 'clipped', 'sizeNotWritten'), o)

# a form that does not say how big it is
NOFORM = """object F: TF
  Caption = 'x'
  object B: TButton
    Left = 1
    Top = 1
    Width = 10
    Height = 10
  end
end
"""
o = layout('NoForm', NOFORM, texto=True)
check('un form sin tamano se dice, no se adivina',
      o.get('clean') is False and len(o.get('clipped', [])) == 1, o)
o = layout('NoForm', NOFORM)
check('un form sin tamano, con el renderizador: su area cliente es la que la VCL le da, medida y no '
      'estimada (R8)',
      o.get('boxesFrom') == 'renderer' and o.get('clientWidth', 0) > 0 and o.get('clientHeight', 0) > 0
      and 'clientEstimated' not in o and o.get('clean') is True, o)

# L9 - doctrine
r = call({'command': 'layout', 'path': 'C:\\Windows\\win.ini'})
check('L9 fuera de la carcel: RECHAZADO', mc.rechazado(r) and mc.es(r, 'SR_JAIL_FMT'), r[:160])
p = os.path.join(BASE, 'Bin.dfm')
open(p, 'wb').write(b'\xff\x0a\x00FORMBIN\x00TPF0\x08TFormBin\x00')
r = call({'command': 'layout', 'path': p})
check('L9 designer binario: RECHAZADO',
      mc.abre(r, 'SR_DSGN_BINARIO_DANADO_FMT'), r[:160])
p = os.path.join(BASE, 'algo.pas')
open(p, 'w').write('unit algo;\ninterface\nimplementation\nend.\n')
r = call({'command': 'layout', 'path': p})
check('L9 un .pas no es un designer', mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_NOT_FORM'), r[:160])
# ruta de relleno ABSOLUTA y dentro: la relativa la niega la puerta (GUARD-021)
r = call({'command': 'volar', 'path': os.path.join(BASE, 'x.dfm')})
check('layout aparece en el error de comando', mc.es(r, 'SR_DESIGNER_CMD') and 'layout' in r, r[:200])

# ============================================================
# Round-8 report (agent layout9): VCL semantics correct forms need.
# ============================================================
DFMS = {}
DFMS['Scroll'] = 'object F: TF\n  ClientWidth = 200\n  ClientHeight = 100\n  object ScrollBox1: TScrollBox\n    Align = alClient\n    Width = 200\n    Height = 100\n    object Memo1: TMemo\n      Left = 8\n      Top = 8\n      Width = 300\n      Height = 300\n    end\n  end\nend\n'
DFMS['Hidden'] = 'object F: TF\n  ClientWidth = 200\n  ClientHeight = 100\n  object pnl1: TPanel\n    Align = alClient\n    Width = 200\n    Height = 100\n  end\n  object pnl2: TPanel\n    Align = alClient\n    Width = 200\n    Height = 100\n    Visible = False\n  end\nend\n'
DFMS['Swap'] = 'object F: TF\n  ClientWidth = 300\n  ClientHeight = 100\n  object edtTexto: TEdit\n    Left = 16\n    Top = 16\n    Width = 200\n    Height = 23\n  end\n  object cbLista: TComboBox\n    Left = 16\n    Top = 16\n    Width = 200\n    Height = 23\n    Visible = False\n  end\nend\n'
DFMS['Deco'] = 'object F: TF\n  ClientWidth = 460\n  ClientHeight = 200\n  object Bevel1: TBevel\n    Left = 16\n    Top = 16\n    Width = 428\n    Height = 145\n  end\n  object edtNombre: TEdit\n    Left = 176\n    Top = 61\n    Width = 240\n    Height = 23\n  end\nend\n'
DFMS['Defaults'] = 'object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object StatusBar1: TStatusBar\n    Left = 0\n    Top = 0\n    Width = 400\n    Height = 19\n  end\n  object ToolBar1: TToolBar\n    Left = 0\n    Top = 0\n    Width = 400\n    Height = 29\n  end\n  object Memo1: TMemo\n    Align = alClient\n    Width = 400\n    Height = 300\n  end\nend\n'
DFMS['Grid'] = 'object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object GridPanel1: TGridPanel\n    Align = alClient\n    Width = 400\n    Height = 200\n    object btnUno: TButton\n      Align = alClient\n      Width = 200\n      Height = 100\n    end\n    object btnDos: TButton\n      Align = alClient\n      Width = 200\n      Height = 100\n    end\n  end\nend\n'
DFMS['Cover'] = 'object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object btnOculto: TButton\n    Left = 16\n    Top = 16\n    Width = 75\n    Height = 25\n  end\n  object MemoTapa: TMemo\n    Align = alClient\n    Width = 400\n    Height = 200\n  end\nend\n'
DFMS['TwoClient'] = 'object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object M1: TMemo\n    Align = alClient\n    Width = 400\n    Height = 200\n  end\n  object M2: TMemo\n    Align = alClient\n    Width = 400\n    Height = 200\n  end\nend\n'
DFMS['ClientFirst'] = 'object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object Grid: TStringGrid\n    Align = alClient\n    Width = 400\n    Height = 300\n  end\n  object PanelBottom: TPanel\n    Align = alBottom\n    Width = 400\n    Height = 40\n  end\nend\n'
DFMS['Tab'] = "object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object pc: TPageControl\n    Align = alClient\n    Width = 400\n    Height = 300\n    object ts1: TTabSheet\n      Caption = 'Uno'\n      object edtCero: TEdit\n        Left = 8\n        Top = 8\n        Width = 0\n        Height = 23\n      end\n      object edtA: TEdit\n        Left = 8\n        Top = 40\n        Width = 100\n        Height = 23\n      end\n      object edtB: TEdit\n        Left = 50\n        Top = 45\n        Width = 100\n        Height = 23\n      end\n    end\n  end\nend\n"
DFMS['Boxes'] = 'object F: TF\n  ClientWidth = 500\n  ClientHeight = 300\n  object Barra: TPanel\n    Align = alTop\n    Width = 500\n    Height = 40\n    object Btn: TButton\n      Left = 8\n      Top = 8\n      Width = 75\n      Height = 25\n    end\n  end\n  object Grid: TStringGrid\n    Align = alClient\n    Width = 500\n    Height = 260\n  end\nend\n'
DFMS['Overflow'] = 'object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object pnlL: TPanel\n    Align = alLeft\n    Width = 250\n    Height = 300\n  end\n  object pnlR: TPanel\n    Align = alRight\n    Width = 250\n    Height = 300\n    object hijo: TButton\n      Left = 10\n      Top = 10\n      Width = 50\n      Height = 25\n    end\n  end\nend\n'
DFMS['Trunc'] = 'object F: TF\n  ClientWidth = 100\n  ClientHeight = 100\n  object P: TPanel\n    Width = 100\n    Height = 100\n'
DFMS['OldForm'] = 'object F: TF\n  Width = 544\n  Height = 375\n  object btnAbajo: TButton\n    Left = 16\n    Top = 345\n    Width = 75\n    Height = 25\n  end\nend\n'

o = layout('Scroll', DFMS['Scroll'])
check('S1 un TScrollBox con contenido mayor NO es error', o.get('clean') is True, o)

o = layout('Hidden', DFMS['Hidden'])
check('S2 un panel Visible=False no cuenta (ni como segundo alClient)', o.get('clean') is True, o)
o = layout('Swap', DFMS['Swap'])
check('S2 dos controles en el mismo hueco, uno oculto: sin solape', o.get('clean') is True, o)

o = layout('Deco', DFMS['Deco'])
check('S4 un TBevel de marco no "tapa" a los controles de dentro', o.get('clean') is True, o)

o = layout('Defaults', DFMS['Defaults'])
check('S6 StatusBar/ToolBar por defecto van a su banda, no se solapan', o.get('clean') is True, o)

o = layout('Grid', DFMS['Grid'])
check('S3 los hijos alClient de un TGridPanel no se marcan como solape', o.get('clean') is True, o)

o = layout('Cover', DFMS['Cover'])
check('FN2 un alClient que tapa a un alNone SI se detecta',
      o.get('clean') is False and len(o.get('overlapping', [])) == 1, o)

o = layout('TwoClient', DFMS['TwoClient'])
check('Bug3 dos alClient visibles se tapan al 100%',
      o.get('clean') is False and len(o.get('overlapping', [])) == 1 and '100%' in json.dumps(o), o)

o = layout('ClientFirst', DFMS['ClientFirst'])
check('alClient declarado ANTES de un alBottom no se solapa con el', o.get('clean') is True, o)

o = layout('Tab', DFMS['Tab'])
check('FN1 el contenido de un TTabSheet SI se revisa',
      o.get('clean') is False and len(o.get('zeroSize', [])) == 1 and len(o.get('overlapping', [])) == 1, o)

o = layout('Boxes', DFMS['Boxes'])
bx = {b['name']: b for b in o.get('boxes', [])}
check('MURO boxes: el rectangulo resuelto de cada control, en coords del form',
      o.get('clean') is True and len(bx) == 3 and bx['Grid']['y'] == 40 and bx['Grid']['h'] == 260
      and bx['Btn']['x'] == 8 and bx['Btn']['y'] == 8 and bx['Btn']['parent'] == 'Barra', o)

o = layout('Overflow', DFMS['Overflow'])
check('Bug1 un desbordamiento no cascadea tamanos negativos',
      len(o.get('clipped', [])) == 1 and '-' not in json.dumps(o.get('clipped')), o)

o = layout('Trunc', DFMS['Trunc'])
check('Bug4 un .dfm truncado se avisa', 'truncatedNote' in o, o)

p_fmx = os.path.join(BASE, 'F.fmx')
open(p_fmx, 'w', newline='').write(
    'object F: TF\n  ClientHeight = 200\n  ClientWidth = 300\n'
    '  object Barra: TLayout\n    Align = Top\n    Size.Height = 40.000000000000000000\n    Size.PlatformDefault = False\n  end\n'
    '  object Cuerpo: TRectangle\n    Align = Client\n    Size.PlatformDefault = False\n  end\n'
    '  object Fuera: TRectangle\n    Position.X = 250.000000000000000000\n    Position.Y = 150.000000000000000000\n'
    '    Size.Width = 100.000000000000000000\n    Size.Height = 100.000000000000000000\n    Size.PlatformDefault = False\n  end\n'
    '  object Nulo: TRectangle\n    Position.X = 10.000000000000000000\n    Position.Y = 10.000000000000000000\n'
    '    Size.Width = 0.000000000000000000\n    Size.Height = 50.000000000000000000\n    Size.PlatformDefault = False\n  end\nend\n')
r = call({'command': 'layout', 'path': p_fmx})
j = json.loads(r) if r.startswith('{') else {}
bx = {b['name']: b for b in j.get('boxes', [])}
check('V74 un .fmx se mide con lo que resuelve FMX: Align Top y Client donde quedan',
      bx.get('Barra', {}).get('h') == 40 and bx.get('Barra', {}).get('w') == 300 and
      bx.get('Cuerpo', {}).get('y') == 40 and bx.get('Cuerpo', {}).get('h') == 160, r[:700])
check('V74b lo que se sale y lo de lado cero, dichos; clean false; un solape solo no lo quitaria',
      'Fuera' in json.dumps(j.get('outsideParent')) and 'Nulo' in json.dumps(j.get('zeroSize')) and j.get('clean') is False, r[:700])

# lo que guardan en un contenido que no se guarda: un TTabControl, un TVertScrollBox, un TExpander
os.makedirs(os.path.join(BASE, 'dentro'))
def edit_fmx(nombre, x, y, w):
    return ("      object %s: TEdit\n        TabOrder = 0\n        Position.X = %d.000000000000000000\n        Position.Y = %d.000000000000000000\n"
            "        Size.Width = %d.000000000000000000\n        Size.Height = 22.000000000000000000\n        Size.PlatformDefault = False\n      end\n" % (nombre, x, y, w))
p_dentro = os.path.join(BASE, 'dentro', 'D.fmx')
open(p_dentro, 'w', newline='').write(
    'object F: TF\n  ClientHeight = 480\n  ClientWidth = 640\n'
    '  object Tab: TTabControl\n    Position.X = 10.000000000000000000\n    Position.Y = 10.000000000000000000\n'
    '    Size.Width = 300.000000000000000000\n    Size.Height = 200.000000000000000000\n    Size.PlatformDefault = False\n    TabIndex = 0\n    TabOrder = 0\n'
    "    object Item1: TTabItem\n      Text = 'A'\n" + edit_fmx('ECero', 5, 5, 0) + edit_fmx('EBien', 5, 40, 100) + edit_fmx('EFuera', 500, 40, 100) + '    end\n'
    "    object Item2: TTabItem\n      Text = 'B'\n" + edit_fmx('EOtra', 5, 5, 100) + '    end\n  end\n'
    '  object Scroll: TVertScrollBox\n    Position.X = 10.000000000000000000\n    Position.Y = 230.000000000000000000\n'
    '    Size.Width = 200.000000000000000000\n    Size.Height = 100.000000000000000000\n    Size.PlatformDefault = False\n    TabOrder = 1\n'
    + edit_fmx('ELejos', 5, 500, 100) + '  end\nend\n')
r = call({'command': 'layout', 'path': p_dentro})
j = json.loads(r) if r.startswith('{') else {}
bx = {b['name']: b for b in j.get('boxes', [])}
check('V74c FMX baja a lo que guardan un TTabControl y un TVertScrollBox: sus hijos salen, con su padre con nombre',
      bx.get('ECero', {}).get('parent') == 'Item1' and bx.get('EOtra', {}).get('parent') == 'Item2' and bx.get('ELejos', {}).get('parent') == 'Scroll', r[:900])
check('V74d lo de lado cero y lo que se sale de su pagina, dichos, con la pagina y no con la pestana; clean false',
      'ECero' in json.dumps(j.get('zeroSize')) and 'EFuera' in json.dumps(j.get('outsideParent')) and j.get('clean') is False, r[:900])
check('V74e lo que cabe en su pagina y lo que se alcanza con el scroll no se dicen',
      not any(n in json.dumps(j.get('outsideParent')) for n in ('EBien', 'EOtra', 'ELejos')), r[:900])

# A2 (revisor del paisaje de la 1.27): el juez de FMX y el de la VCL eran dos copias que ya divergian.
# FMX daba las coordenadas de un aviso ABSOLUTAS, del form, con el mismo texto que en la VCL las da
# relativas al padre que nombra ('and "Caja" is only 100 x 100'), y no eximia de 'fuera del padre' a un
# contenedor que coloca a sus hijos (un TFlowLayout), como la VCL (un TFlowPanel). Ahora es UN juez.
# Rojo contra c582da0: Sale "from (130,70) to (180,90)", el solape "(70,120) to (90,150)" y Ancho fuera
def rect_fmx(nombre, x, y, w, h):
    return ("    object %s: TRectangle\n      Position.X = %d.000000000000000000\n      Position.Y = %d.000000000000000000\n"
            "      Size.Width = %d.000000000000000000\n      Size.Height = %d.000000000000000000\n"
            "      Size.PlatformDefault = False\n    end\n" % (nombre, x, y, w, h))
os.makedirs(os.path.join(BASE, 'relativo'))
p_rel = os.path.join(BASE, 'relativo', 'R.fmx')
open(p_rel, 'w', newline='').write(
    'object F: TF\n  ClientHeight = 300\n  ClientWidth = 400\n'
    '  object Caja: TLayout\n    Position.X = 50.000000000000000000\n    Position.Y = 60.000000000000000000\n'
    '    Size.Width = 100.000000000000000000\n    Size.Height = 100.000000000000000000\n    Size.PlatformDefault = False\n'
    + rect_fmx('Sale', 80, 10, 50, 20) + rect_fmx('Uno', 0, 50, 40, 40) + rect_fmx('Otro', 20, 60, 40, 40) + '  end\n'
    '  object Flujo: TFlowLayout\n    Position.X = 200.000000000000000000\n    Position.Y = 60.000000000000000000\n'
    '    Size.Width = 100.000000000000000000\n    Size.Height = 100.000000000000000000\n    Size.PlatformDefault = False\n'
    + rect_fmx('Ancho', 0, 0, 150, 20) + '  end\nend\n')
r = call({'command': 'layout', 'path': p_rel})
j = json.loads(r) if r.startswith('{') else {}
bx = {b['name']: b for b in j.get('boxes', [])}


def tramo(avisos, empieza):
    # el (x1,y1)-(x2,y2) del aviso que empieza por 'empieza'; None si no esta
    for t in avisos or []:
        if t.startswith(empieza):
            m = re.search(r'from \((-?\d+),(-?\d+)\) to \((-?\d+),(-?\d+)\)', t)
            return tuple(int(v) for v in m.groups()) if m else None
    return None


# (las cajas, en coordenadas del form: Sale en x=50+80; el aviso, en las de Caja)
check('V74f FMX: lo que se sale de su padre, con coordenadas RELATIVAS al padre que nombra, como en la VCL',
      bx.get('Sale', {}).get('x') == 130 and tramo(j.get('outsideParent'), 'Sale:') == (80, 10, 130, 30)
      and '"Caja" is only 100 x 100' in ' '.join(j.get('outsideParent') or []),
      (bx.get('Sale'), j.get('outsideParent') if j else r[:300]))
check('V74g FMX: dos que se solapan, con el tramo compartido relativo a su padre',
      tramo(j.get('overlapping'), 'Uno ') == (20, 60, 40, 90), j.get('overlapping') if j else r[:300])
check('V74h FMX: lo de un contenedor que coloca a sus hijos (TFlowLayout) no se juzga fuera del padre, como en la VCL',
      bx.get('Ancho', {}).get('parent') == 'Flujo' and 'Ancho' not in json.dumps(j.get('outsideParent')),
      (bx.get('Ancho'), j.get('outsideParent') if j else r[:300]))
# FMX no recorta a los hijos salvo ClipChildren, y el renderizador dibuja lo que se sale:
# el aviso no puede decir que esa parte no se ve (dirigido de Hermes de la 1.27: el
# preview lo mostraba entero y el aviso decia "not visible")
_sale = [t for t in (j.get('outsideParent') or []) if t.startswith('Sale:')]
check('V74i FMX: lo que se sale no se da por invisible: FMX lo dibuja salvo ClipChildren',
      _sale and 'not visible' not in _sale[0] and 'ClipChildren' in _sale[0], _sale or (j.get('outsideParent') if j else r[:300]))

# B11 de la 1.28: lo que se VE de lo que se sale lo dice FMX con los controles vivos (UpdateRect, lo que
# repinta de cada control: su caja cortada por cada antecesor que recorta a sus hijos, y AbsoluteClipRect,
# por el form), no una regla del texto. Un TLayout con ClipChildren corta a Cortado a medias y deja fuera a
# Fuera; Borde se sale del form. ROJA contra la 1.27.1: los tres "FMX draws that part over what is around it"
os.makedirs(os.path.join(BASE, 'recorte'))
p_rec = os.path.join(BASE, 'recorte', 'C.fmx')
open(p_rec, 'w', newline='').write(
    'object F: TF\n  ClientHeight = 300\n  ClientWidth = 400\n'
    '  object Corta: TLayout\n    ClipChildren = True\n    Position.X = 50.000000000000000000\n'
    '    Position.Y = 60.000000000000000000\n    Size.Width = 100.000000000000000000\n'
    '    Size.Height = 100.000000000000000000\n    Size.PlatformDefault = False\n'
    + rect_fmx('Cortado', 80, 10, 50, 20) + rect_fmx('Fuera', 150, 10, 30, 20) + '  end\n'
    + rect_fmx('Borde', 380, 10, 50, 20).replace('    ', '  ', 1).replace('\n    ', '\n  ') + 'end\n')
r = call({'command': 'layout', 'path': p_rec})
j = json.loads(r) if r.startswith('{') else {}


def dibujado(avisos, empieza):
    # el (x1,y1)-(x2,y2) que el aviso dice dibujado; None si no lo dice
    for t in avisos or []:
        if t.startswith(empieza):
            m = re.search(r'only \((-?\d+),(-?\d+)\)-\((-?\d+),(-?\d+)\) of it is drawn', t)
            return tuple(int(v) for v in m.groups()) if m else None
    return None


_av = j.get('outsideParent') or []
check('V74j FMX con ClipChildren: de Cortado solo se dibuja (80,10)-(100,30) de "Corta", y no dice que se dibuje '
      'por encima', dibujado(_av, 'Cortado:') == (80, 10, 100, 30) and
      not any(t.startswith('Cortado:') and 'over what is around it' in t for t in _av), _av or r[:400])
check('V74k FMX con ClipChildren: de Fuera no se dibuja nada',
      any(t.startswith('Fuera:') and 'none of it is drawn' in t for t in _av), _av or r[:400])
check('V74l FMX: lo que se sale del FORM lo corta el form: de Borde solo (380,10)-(400,30)',
      dibujado(_av, 'Borde:') == (380, 10, 400, 30), _av or r[:400])

# (en su carpeta: el renderizador juzga los hermanos del form, y aqui los hay truncados a proposito)
os.makedirs(os.path.join(BASE, 'paginas'))
o = layout('paginas\\Paginas', "object FPag: TFPag\n  ClientWidth = 400\n  ClientHeight = 300\n  object PageControl1: TPageControl\n    Align = alClient\n    Width = 400\n    Height = 300\n    object TabSheet1: TTabSheet\n      Caption = 'A'\n      object B: TButton\n        Left = 8\n        Top = 8\n        Width = 75\n        Height = 25\n        TabOrder = 0\n      end\n    end\n  end\nend\n")
bx = {b['name']: b for b in o.get('boxes', [])}
check('V24 con el renderizador, la caja de una pagina es la de verdad: sin la banda de pestanas',
      o.get('boxesFrom') == 'renderer' and 0 < bx['TabSheet1']['h'] < 300 and bx['TabSheet1']['y'] > 0, o)

o = layout('OldForm', DFMS['OldForm'], texto=True)
check('FN3 un form sin ClientWidth se estima y lo declara',
      o.get('clientEstimated') is True and 'estimatedNote' in o, o)
# (con el renderizador, en su carpeta: en esta lo tumba Trunc)
os.makedirs(os.path.join(BASE, 'viejo'))
o = layout('viejo\\OldForm', DFMS['OldForm'])
check('FN3 con el renderizador, el area cliente de un form que solo escribe Width/Height se mide: '
      'menor que la ventana y sin estimar (R8)',
      o.get('boxesFrom') == 'renderer' and 0 < o.get('clientWidth', 0) < 544 and 0 < o.get('clientHeight', 0) < 375
      and 'clientEstimated' not in o and 'estimatedNote' not in o, o)

# R8 (revisor del paisaje de la 1.27): con las cajas medidas, lo juzgado seguia saliendo del texto.
# Un TLabel (AutoSize, el de su clase) con un Width viejo: el texto lo da por 30 de ancho y no toca
# al TEdit; la VCL lo ensancha hasta su Caption y lo pisa. Medido contra el build anterior: la
# caja medida de 155 y clean=True
ETIQUETA = ("object FL: TFL\n  ClientWidth = 400\n  ClientHeight = 200\n"
            "  object Label1: TLabel\n    Left = 8\n    Top = 12\n    Width = 30\n    Height = 15\n"
            "    Caption = 'Nombre completo del cliente'\n  end\n"
            "  object Edit1: TEdit\n    Left = 60\n    Top = 8\n    Width = 121\n    Height = 23\n    TabOrder = 0\n  end\nend\n")
os.makedirs(os.path.join(BASE, 'etiqueta'))
o = layout('etiqueta\\Etiqueta', ETIQUETA)
check('R8 con el renderizador se juzga lo que mide la VCL: la etiqueta que su Caption ensancha pisa al TEdit',
      o.get('boxesFrom') == 'renderer' and o.get('clean') is False
      and 'Label1' in all_text(o, 'overlapping') and 'Edit1' in all_text(o, 'overlapping'), o)
o = layout('Etiqueta', ETIQUETA, texto=True)
check('R8 ...y el texto, que no la mide, no lo ve: lo que anade medir',
      o.get('boxesFrom') == 'text' and o.get('clean') is True, o)


o = layout('PC', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object PageControl1: TPageControl\n    Align = alClient\n    Width = 400\n    Height = 300\n    object TabSheet1: TTabSheet\n    end\n    object TabSheet2: TTabSheet\n    end\n    object TabSheet3: TTabSheet\n    end\n  end\nend\n")
check('R10 un TPageControl con varias TTabSheet NO es solape', o.get('clean') is True, o)

o = layout('Flow', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object FlowPanel1: TFlowPanel\n    Align = alClient\n    Width = 400\n    Height = 200\n    object B1: TButton\n      Left = 1\n      Top = 1\n      Width = 100\n      Height = 40\n    end\n    object B2: TButton\n      Left = 1\n      Top = 1\n      Width = 100\n      Height = 40\n    end\n  end\nend\n")
check('R10 los hijos de un TFlowPanel no se juzgan por Left/Top', o.get('clean') is True, o)

o = layout('Rel', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object RelativePanel1: TRelativePanel\n    Align = alClient\n    Width = 400\n    Height = 200\n    object E1: TEdit\n      Left = 0\n      Top = 0\n      Width = 100\n      Height = 23\n    end\n    object E2: TEdit\n      Left = 0\n      Top = 0\n      Width = 100\n      Height = 23\n    end\n  end\nend\n")
check('R10 los hijos de un TRelativePanel tampoco', o.get('clean') is True, o)

o = layout('Custom', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object P1: TPanel\n    Align = alCustom\n    Left = 0\n    Top = 0\n    Width = 100\n    Height = 100\n  end\n  object P2: TPanel\n    Align = alCustom\n    Left = 0\n    Top = 0\n    Width = 100\n    Height = 100\n  end\nend\n")
check('R10 alCustom no se juzga por coordenadas de diseno', o.get('clean') is True, o)

o = layout('Margins', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object PanelTop: TPanel\n    AlignWithMargins = True\n    Align = alTop\n    Width = 400\n    Height = 50\n  end\n  object PanelClient: TPanel\n    Align = alClient\n    Width = 400\n    Height = 244\n  end\nend\n")
bx = {b['name']: b for b in o.get('boxes', [])}
check('R10 AlignWithMargins desplaza el rectangulo (boxes exactos)',
      bx['PanelTop']['x'] == 3 and bx['PanelTop']['y'] == 3 and bx['PanelTop']['w'] == 394
      and bx['PanelClient']['y'] == 56 and bx['PanelClient']['h'] == 244, o)

# V24b (dirigido de Hermes de la 1.24, punto 4): un frame inline y lo que lleva dentro no estan en
# el texto del form; con el renderizador entran en boxes (medido a pelo: BOX=Marco1 y
# BOX=Marco1.EdMarco salian del ayudante y el servidor los tiraba), listados y sin juzgar
os.makedirs(os.path.join(BASE, 'marco'))
open(os.path.join(BASE, 'marco', 'UMarco.pas'), 'w', encoding='utf-8', newline='').write(
    "unit UMarco;\n\ninterface\n\nuses\n  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls;\n\ntype\n  TFrameUMarco = class(TFrame)\n    EdMarco: TEdit;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n")
open(os.path.join(BASE, 'marco', 'UMarco.dfm'), 'w', encoding='utf-8', newline='').write(
    "object FrameUMarco: TFrameUMarco\n  Left = 0\n  Top = 0\n  Width = 320\n  Height = 240\n  TabOrder = 0\n  object EdMarco: TEdit\n    Left = 10\n    Top = 10\n    Width = 121\n    Height = 23\n    TabOrder = 0\n    Text = 'EdMarco'\n  end\nend\n")
open(os.path.join(BASE, 'marco', 'UConMarco.pas'), 'w', encoding='utf-8', newline='').write(
    "unit UConMarco;\n\ninterface\n\nuses\n  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, UMarco;\n\ntype\n  TFConMarco = class(TForm)\n    Marco1: TFrameUMarco;\n    B: TButton;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n")
o = layout('marco\\UConMarco', "object FConMarco: TFConMarco\n  ClientWidth = 400\n  ClientHeight = 300\n  object B: TButton\n    Left = 8\n    Top = 260\n    Width = 75\n    Height = 25\n    TabOrder = 0\n  end\n  inline Marco1: TFrameUMarco\n    Left = 24\n    Top = 30\n    TabOrder = 1\n  end\nend\n")
bx = {b['name']: b for b in o.get('boxes', [])}
# (y lo de dentro, con la linea de su fichero, el del frame, y ese fichero: salia line=0 sin decir donde;
# Hermes, dirigido de la 1.26)
check('V24b con el renderizador, un frame inline y lo de dentro salen en boxes (el texto no los lista), con su padre y su linea',
      o.get('boxesFrom') == 'renderer' and bx.get('Marco1', {}).get('x') == 24 and bx.get('Marco1', {}).get('h') == 240
      and bx.get('Marco1.EdMarco', {}).get('parent') == 'Marco1' and bx.get('Marco1.EdMarco', {}).get('x') == 34
      and bx.get('Marco1.EdMarco', {}).get('line') == 7 and (bx.get('Marco1.EdMarco', {}).get('file') or '').endswith('UMarco.dfm')
      and 'file' not in bx.get('Marco1', {'file': 1}) and bx.get('B', {}).get('align') == 'alNone', o)

srv.mata()
srv_t.mata()
mc.borra(BASE)  # con el servidor va su caja de paquetes: cien megas (V65 de la 1.24)
mc.borra(BASE_T)
mc.fin('layout battery')
