"""E2E battery for v0.52.0-beta - delphi_designer phase 1 (read + lint):
class metadata from the generated RTTI tables, component tree of text
designers, one component's block, and the designer lint on demand.

Usage:  python tests/test_designer.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'designer')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

env = dict(os.environ); env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def reader():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=reader, daemon=True).start()
rid = [10]
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=120):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(name, args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(rid[0])
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "dg", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:300])
def J(t):
    try: return json.loads(t)
    except Exception: return {}

# ---- fixtures: a hand-made VCL dfm (valid + broken bits) and a binary one
DFM = os.path.join(BASE, 'Main.dfm')
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormMain: TFormMain
  Caption = 'Prueba'
  ClientHeight = 300
  object PanelTop: TPanel
    Align = alTop
    Caption = 'panel'
    object BotonUno: TButton
      Caption = 'Uno'
      TabOrder = 0
    end
  end
  object EditNombre: TEdit
    Text = 'hola'
  end
end
""")
BAD = os.path.join(BASE, 'Roto.dfm')
open(BAD, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormRoto: TFormRoto
  object B1: TButton
    Caption = 'x'
    Alineacion = alTop
    Align = alMarte
  end
  object Raro: TClaseInventada
    Color = clRed
  end
  object ImagenesLista: TImageList
    Left = 320
    Top = 200
  end
end
""")
BIN = os.path.join(BASE, 'Bin.dfm')
open(BIN, 'wb').write(b'TPF0\x08TFormBin\x00')

# ---- info ----
j = J(call('delphi_designer', {'command': 'info', 'class': 'TButton', 'framework': 'vcl'}))
props = [p['name'] for p in j.get('properties', [])]
check('info TButton (VCL): Caption y TabOrder publicados', 'Caption' in props and 'TabOrder' in props, str(j)[:250])
check('info: eventos aparte (OnClick)', any('OnClick' in e for e in j.get('events', [])), str(j.get('events'))[:200])
j = J(call('delphi_designer', {'command': 'info', 'class': 'TButton', 'framework': 'vcl', 'filter': 'Cap'}))
check('info con filter acota', j.get('total', 99) <= 3 and any(p['name'] == 'Caption' for p in j.get('properties', [])), str(j)[:200])
r = call('delphi_designer', {'command': 'info', 'class': 'TClaseInventada', 'framework': 'vcl'})
check('info clase desconocida rechazada', 'RECHAZADO' in r, r[:150])
j = J(call('delphi_designer', {'command': 'info', 'class': 'TLayout', 'framework': 'fmx'}))
check('info FMX (TLayout)', j.get('class') == 'TLayout' and j.get('framework') == 'FMX', str(j)[:150])

# ---- prop ----
j = J(call('delphi_designer', {'command': 'prop', 'class': 'TPanel', 'prop': 'Align', 'framework': 'vcl'}))
check('prop TPanel.Align: enum con miembros', j.get('kind') == 'enum' and 'alTop' in (j.get('members') or ''), str(j)[:250])
r = call('delphi_designer', {'command': 'prop', 'class': 'TPanel', 'prop': 'NoExiste', 'framework': 'vcl'})
check('prop inexistente rechazada con pista', 'RECHAZADO' in r and 'info' in r, r[:200])

# ---- tree ----
j = J(call('delphi_designer', {'command': 'tree', 'path': DFM}))
root = j.get('root') or {}
kids = root.get('children', [])
check('tree: raiz FormMain', root.get('name') == 'FormMain' and root.get('class') == 'TFormMain', str(root)[:200])
check('tree: jerarquia (Panel con Button dentro)',
      any(k.get('name') == 'PanelTop' and any(g.get('name') == 'BotonUno' for g in k.get('children', [])) for k in kids), str(kids)[:300])
check('tree: lineas 1-based', root.get('line') == 1, root.get('line'))

# ---- get ----
r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'BotonUno'})
check('get: bloque del componente', 'BotonUno (TButton)' in r and "Caption = 'Uno'" in r, r[:250])
r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'NoEsta'})
check('get: componente inexistente', 'RECHAZADO' in r, r[:150])

# ---- lint ----
r = call('delphi_designer', {'command': 'lint', 'path': DFM})
check('lint limpio en el form bueno', 'LINT LIMPIO' in r, r[:200])
r = call('delphi_designer', {'command': 'lint', 'path': BAD})
# una clase DESCONOCIDA no es aviso: los componentes de terceros no estan en
# las tablas y son legitimos; sus propiedades simplemente no se comprueban
check('lint NO inventa avisos dentro de la clase desconocida', 'clRed' not in r and 'Color' not in r, r[:400])
check('lint pilla la propiedad no publicada', 'Alineacion' in r, r[:400])
check('lint pilla el valor de enum inexistente', 'alMarte' in r, r[:400])
# field report 2026-08-24: Left/Top on non-visual components are the form
# designer's own placement - the IDE writes them in every form with a
# TImageList/TPopupMenu and no class publishes them: pure noise
check('lint NO avisa de Left/Top de componentes no visuales', '"Left"' not in r and '"Top"' not in r, r[:400])

# ---- doctrina ----
r = call('delphi_designer', {'command': 'tree', 'path': BIN})
check('designer binario (TPF0) rechazado', 'RECHAZADO' in r and 'BINARIO' in r, r[:200])
r = call('delphi_designer', {'command': 'tree', 'path': os.path.join(BASE, 'nx.dfm')})
check('fichero inexistente', 'RECHAZADO' in r or 'no existe' in r, r[:150])
r = call('delphi_designer', {'command': 'tree', 'path': 'C:\\Windows\\win.ini'})
check('fuera de jaula / no designer rechazado', 'RECHAZADO' in r, r[:150])
r = call('delphi_designer', {'command': 'volar'})
check('comando invalido', 'error' in r.lower() or 'RECHAZADO' in r, r[:120])

proc.kill()
print('\n== designer battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
