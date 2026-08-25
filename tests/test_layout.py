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
  L8  a size the .dfm does not write is declared unknown, never guessed at
  L9  the doctrine holds: read jail, text designers only, binary refused

Usage:  python tests/test_layout.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'layout')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        text=True, encoding='utf-8')
q = queue.Queue()


def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)


threading.Thread(target=reader, daemon=True).start()
rid = [10]
P = F = 0


def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


def recv(r, t=60):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = q.get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None


def call(args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": "delphi_designer", "arguments": args}})
    r = recv(rid[0])
    if not r:
        return '(sin respuesta)'
    if 'result' in r:
        return r['result']['content'][0]['text']
    return 'ERROR ' + json.dumps(r.get('error'), ensure_ascii=False)[:200]


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:300])


def layout(name, body):
    p = os.path.join(BASE, name + '.dfm')
    open(p, 'w', encoding='utf-8', newline='').write(body)
    r = call({'command': 'layout', 'path': p})
    try:
        return json.loads(r)
    except Exception:
        return {'RAW': r}


def all_text(o, *keys):
    return json.dumps([o.get(k, []) for k in keys], ensure_ascii=False)


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "layout-battery", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

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
check('L1 un form correcto sale limpio', o.get('ok') is True, o)
check('L5 Align resuelto: el alClient recibe el hueco que queda',
      o.get('clientWidth') == 500 and o.get('clientHeight') == 300, o)
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
      o.get('ok') is False and len(o.get('overlapping', [])) == 1
      and 'BtnA' in json.dumps(o) and 'BtnB' in json.dumps(o), o)

# ...and two that merely touch do NOT overlap
TOUCH = OVER.replace('Left = 60', 'Left = 110')
o = layout('Touch', TOUCH)
check('L2 dos controles pegados NO se solapan (sin falso positivo)',
      o.get('ok') is True, o)

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
      o.get('ok') is False and len(o.get('zeroSize', [])) == 1, o)

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
txt = json.dumps(o, ensure_ascii=False)
check('L4 se sale por la derecha del panel que lo contiene',
      o.get('ok') is False and 'BtnFuera' in txt and 'Panel1' in txt, o)
check('L4 y tambien por abajo', 'BtnAlto' in txt, o)

# L4b - negative coordinates count as outside too
NEG = OUT.replace('Left = 360', 'Left = -20').replace('Left = 10', 'Left = 10')
o = layout('Neg', NEG)
check('L4 una coordenada negativa tambien se sale',
      o.get('ok') is False and 'BtnFuera' in json.dumps(o), o)

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
      o.get('ok') is False and len(o.get('clipped', [])) >= 1, o)

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
check('L6 el segundo alClient no recibe nada',
      o.get('ok') is False and 'M2' in json.dumps(o), o)

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
o = layout('NoSize', NOSIZE)
check('L8 un tamano no escrito se declara desconocido, no se inventa',
      len(o.get('sizeNotWritten', [])) == 1 and o.get('zeroSize') == [], o)

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
o = layout('NoForm', NOFORM)
check('un form sin tamano se dice, no se adivina',
      o.get('ok') is False and len(o.get('clipped', [])) == 1, o)

# L9 - doctrine
r = call({'command': 'layout', 'path': 'C:\\Windows\\win.ini'})
check('L9 fuera de la carcel: RECHAZADO', 'RECHAZADO' in r, r[:160])
p = os.path.join(BASE, 'Bin.dfm')
open(p, 'wb').write(b'\xff\x0a\x00FORMBIN\x00TPF0\x08TFormBin\x00')
r = call({'command': 'layout', 'path': p})
check('L9 designer binario: RECHAZADO',
      'RECHAZADO' in r and 'BINARIO' in r, r[:160])
p = os.path.join(BASE, 'algo.pas')
open(p, 'w').write('unit algo;\ninterface\nimplementation\nend.\n')
r = call({'command': 'layout', 'path': p})
check('L9 un .pas no es un designer', 'RECHAZADO' in r, r[:160])
r = call({'command': 'volar', 'path': 'x'})
check('layout aparece en el error de comando', 'layout' in r, r[:200])

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
check('S1 un TScrollBox con contenido mayor NO es error', o.get('ok') is True, o)

o = layout('Hidden', DFMS['Hidden'])
check('S2 un panel Visible=False no cuenta (ni como segundo alClient)', o.get('ok') is True, o)
o = layout('Swap', DFMS['Swap'])
check('S2 dos controles en el mismo hueco, uno oculto: sin solape', o.get('ok') is True, o)

o = layout('Deco', DFMS['Deco'])
check('S4 un TBevel de marco no "tapa" a los controles de dentro', o.get('ok') is True, o)

o = layout('Defaults', DFMS['Defaults'])
check('S6 StatusBar/ToolBar por defecto van a su banda, no se solapan', o.get('ok') is True, o)

o = layout('Grid', DFMS['Grid'])
check('S3 los hijos alClient de un TGridPanel no se marcan como solape', o.get('ok') is True, o)

o = layout('Cover', DFMS['Cover'])
check('FN2 un alClient que tapa a un alNone SI se detecta',
      o.get('ok') is False and len(o.get('overlapping', [])) == 1, o)

o = layout('TwoClient', DFMS['TwoClient'])
check('Bug3 dos alClient visibles se tapan al 100%',
      o.get('ok') is False and len(o.get('overlapping', [])) == 1 and '100%' in json.dumps(o), o)

o = layout('ClientFirst', DFMS['ClientFirst'])
check('alClient declarado ANTES de un alBottom no se solapa con el', o.get('ok') is True, o)

o = layout('Tab', DFMS['Tab'])
check('FN1 el contenido de un TTabSheet SI se revisa',
      o.get('ok') is False and len(o.get('zeroSize', [])) == 1 and len(o.get('overlapping', [])) == 1, o)

o = layout('Boxes', DFMS['Boxes'])
bx = {b['name']: b for b in o.get('boxes', [])}
check('MURO boxes: el rectangulo resuelto de cada control, en coords del form',
      o.get('ok') is True and len(bx) == 3 and bx['Grid']['y'] == 40 and bx['Grid']['h'] == 260
      and bx['Btn']['x'] == 8 and bx['Btn']['y'] == 8 and bx['Btn']['parent'] == 'Barra', o)

o = layout('Overflow', DFMS['Overflow'])
check('Bug1 un desbordamiento no cascadea tamanos negativos',
      len(o.get('clipped', [])) == 1 and '-' not in json.dumps(o.get('clipped')), o)

o = layout('Trunc', DFMS['Trunc'])
check('Bug4 un .dfm truncado se avisa', 'truncatedNote' in o, o)

p_fmx = os.path.join(BASE, 'F.fmx')
open(p_fmx, 'w', newline='').write('object F: TF\n  object R: TRectangle\n  end\nend\n')
r = call({'command': 'layout', 'path': p_fmx})
check('FP7 un .fmx se rechaza (no se contesta ok en falso)', 'RECHAZADO' in r, r[:120])

o = layout('OldForm', DFMS['OldForm'])
check('FN3 un form sin ClientWidth se estima y lo declara',
      o.get('clientEstimated') is True and 'estimatedNote' in o, o)


o = layout('PC', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object PageControl1: TPageControl\n    Align = alClient\n    Width = 400\n    Height = 300\n    object TabSheet1: TTabSheet\n    end\n    object TabSheet2: TTabSheet\n    end\n    object TabSheet3: TTabSheet\n    end\n  end\nend\n")
check('R10 un TPageControl con varias TTabSheet NO es solape', o.get('ok') is True, o)

o = layout('Flow', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object FlowPanel1: TFlowPanel\n    Align = alClient\n    Width = 400\n    Height = 200\n    object B1: TButton\n      Left = 1\n      Top = 1\n      Width = 100\n      Height = 40\n    end\n    object B2: TButton\n      Left = 1\n      Top = 1\n      Width = 100\n      Height = 40\n    end\n  end\nend\n")
check('R10 los hijos de un TFlowPanel no se juzgan por Left/Top', o.get('ok') is True, o)

o = layout('Rel', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object RelativePanel1: TRelativePanel\n    Align = alClient\n    Width = 400\n    Height = 200\n    object E1: TEdit\n      Left = 0\n      Top = 0\n      Width = 100\n      Height = 23\n    end\n    object E2: TEdit\n      Left = 0\n      Top = 0\n      Width = 100\n      Height = 23\n    end\n  end\nend\n")
check('R10 los hijos de un TRelativePanel tampoco', o.get('ok') is True, o)

o = layout('Custom', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 200\n  object P1: TPanel\n    Align = alCustom\n    Left = 0\n    Top = 0\n    Width = 100\n    Height = 100\n  end\n  object P2: TPanel\n    Align = alCustom\n    Left = 0\n    Top = 0\n    Width = 100\n    Height = 100\n  end\nend\n")
check('R10 alCustom no se juzga por coordenadas de diseno', o.get('ok') is True, o)

o = layout('Margins', "object F: TF\n  ClientWidth = 400\n  ClientHeight = 300\n  object PanelTop: TPanel\n    AlignWithMargins = True\n    Align = alTop\n    Width = 400\n    Height = 50\n  end\n  object PanelClient: TPanel\n    Align = alClient\n    Width = 400\n    Height = 244\n  end\nend\n")
bx = {b['name']: b for b in o.get('boxes', [])}
check('R10 AlignWithMargins desplaza el rectangulo (boxes exactos)',
      bx['PanelTop']['x'] == 3 and bx['PanelTop']['y'] == 3 and bx['PanelTop']['w'] == 394
      and bx['PanelClient']['y'] == 56 and bx['PanelClient']['h'] == 244, o)

proc.kill()
print('\n== layout battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
