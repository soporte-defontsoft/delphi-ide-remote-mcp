# -*- coding: utf-8 -*-
"""Round 30 - delphi_adb_linux: el escritorio Linux de un target, como
delphi_adb da el de un Android (v0.96, nacida la noche del 18-sep despues de
construir y medir el nodo contra el Fedora real).

Aqui se comprueba el CONTRATO, que es lo que un agente ve antes de tener
target: que la tool existe, que su descripcion ENSENA el flujo (capturar,
mirar, medir, pulsar), y que rechaza con motivo claro lo que no puede hacer.
Lo que necesita maquina viva -capturar y pulsar de verdad- se prueba a mano
contra el Fedora; aqui no se finge.

Usage:  python tests/test_round30.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
DIR = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round30')
shutil.rmtree(DIR, ignore_errors=True)
os.makedirs(DIR)

P = F = 0

def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:260])

CRLF = '\r\n'
BASE = CRLF.join([
    'unit Round30;', '',
    'interface', '',
    'type',
    '  TCosa = class',
    '  private',
    '    FValor: Integer;',
    '  public',
    '    procedure Existente;',
    '    procedure Preparada(Sender: TObject);',
    '  end;', '',
    'implementation', '',
    'procedure TCosa.Existente;',
    'begin',
    '  FValor := 1;',
    'end;', '',
    'end.', ''])

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = DIR
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()

def rdr():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)

threading.Thread(target=rdr, daemon=True).start()
rid = [10]

def send(o):
    proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()

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

def call(name, args, t=60):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                 "clientInfo": {"name": "r28", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})



def tool_info(nombre):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/list"})
    r = recv(rid[0], 30)
    for t in (r or {}).get('result', {}).get('tools', []):
        if t['name'] == nombre:
            return t
    return None

T = tool_info('delphi_adb_linux')
check('la tool existe', T is not None, 'no aparece en tools/list')

desc = (T or {}).get('description', '')
check('su descripcion ensena el flujo (captura -> mide -> pulsa)',
      'screenshot' in desc and 'measured on' in desc.lower(), desc[:200])
check('avisa de que la escala la convierte el nodo',
      'scale' in desc.lower() and 'logical' in desc.lower(), desc[:200])
check('dice que el escritorio es del TARGET, no del agente',
      'PAServer profile' in desc, desc[:200])
check('cuenta como alcanzar una ventana tapada',
      'covers' in desc.lower() or 'covered' in desc.lower(), desc[:240])

props = (T or {}).get('inputSchema', {}).get('properties', {})
for p in ('command', 'profile', 'project', 'x', 'y', 'code', 'text'):
    check('el esquema declara "%s"' % p, p in props, sorted(props))
check('el parametro x dice que se mide SOBRE la captura',
      'SCREENSHOT' in props.get('x', {}).get('description', '').upper(), props.get('x'))
check('el parametro text avisa de que con x,y pulsa antes',
      'presses there first' in props.get('text', {}).get('description', ''), props.get('text'))
check('el command cuenta que type con x,y es UN solo viaje',
      'pays the startup once' in desc, desc[:300])

check('el parametro code avisa de que son codigos Linux, no X11',
      'X11' in props.get('code', {}).get('description', ''), props.get('code'))

PROJ = os.path.join(DIR, 'Nodo.dproj')
open(PROJ, 'w', encoding='utf-8').write('<Project/>')

r = call('delphi_adb_linux', {"command": "bailar", "profile": "x", "project": PROJ})
check('un command inventado se rechaza con la lista buena',
      r.startswith('RECHAZADO') and 'screenshot' in r, r[:160])

r = call('delphi_adb_linux', {"command": "tap", "profile": "x", "project": PROJ})
check('tap sin coordenadas se rechaza diciendo de donde salen',
      r.startswith('RECHAZADO') and 'screenshot' in r, r[:160])

r = call('delphi_adb_linux', {"command": "type", "profile": "x", "project": PROJ})
check('type sin texto se rechaza y explica el gesto de un solo viaje',
      r.startswith('RECHAZADO') and 'x e y' in r, r[:200])

r = call('delphi_adb_linux', {"command": "key", "profile": "x", "project": PROJ})
check('key sin codigo se rechaza con ejemplos',
      r.startswith('RECHAZADO') and ('Escape' in r or 'Tab' in r), r[:160])

fuera = os.path.join(tempfile.gettempdir(), 'fuera-de-la-jaula.dproj')
open(fuera, 'w', encoding='utf-8').write('<Project/>')
r = call('delphi_adb_linux', {"command": "screenshot", "profile": "x", "project": fuera})
check('un proyecto fuera de la jaula se rechaza',
      r.startswith('RECHAZADO') or 'FUERA' in r.upper(), r[:160])

print()
print('round30: %d PASS / %d FAIL' % (P, F))
proc.stdin.close()
try:
    proc.wait(timeout=10)
except Exception:
    proc.kill()
sys.exit(1 if F else 0)
