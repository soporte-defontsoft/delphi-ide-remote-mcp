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
                               'noRoomLeft', 'sizeNotWritten'), o)

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
      o.get('ok') is False and len(o.get('noRoomLeft', [])) >= 1, o)

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
      o.get('ok') is False and len(o.get('noRoomLeft', [])) == 1, o)

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

proc.kill()
print('\n== layout battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
