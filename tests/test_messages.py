"""E2E battery for v0.44.0-beta - delphi_messages: the operator's mailbox
(the way back of delphi_report). Messages are .md files in messages\ next to
the server exe (messages\<agent>\ for one agent, messages\ for everyone);
while one waits EVERY tool answer ends with a MENSAJES PENDIENTES line;
read delivers once (moved to messages\_entregados).

Usage:  python tests/test_messages.py [path-to-DelphiLspMcp.exe]
The exe is COPIED to a scratch folder so the mailbox is private to the run.
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'messages')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
MSG = os.path.join(BASE, 'messages')
os.makedirs(os.path.join(MSG, 'dsh'))
open(os.path.join(MSG, 'dsh', '20260823-0100-deploy.md'), 'w', encoding='utf-8').write(
    '# Reconecta y sigue con el Deploy\n\nEl server se reinicio. Sigue con target=Deploy.\n')
open(os.path.join(MSG, '20260823-0059-aviso.md'), 'w', encoding='utf-8').write(
    '# Aviso general\n\nVentana de mantenimiento a las 02:00.\n')

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
def send(o):
    proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=60):
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
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "messages-battery", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, cond, detail=''):
    global P, F
    if cond: P += 1; print('  PASS', name)
    else: F += 1; print('  FAIL', name, '|', str(detail)[:300])

print('== messages battery ==')
t = call('delphi_workspace', {})
# El aviso NO nombra buzones ajenos (v0.60): el correo "para todos" se anuncia
# porque es del que lee; el dirigido a otro solo se cuenta. Tres agentes
# distintos reportaron el ruido y la fuga del id ajeno.
check('aviso al final de cualquier tool', 'MENSAJES PENDIENTES: 1 para TODOS' in t, t[-200:])
check('el aviso NO nombra el buzon de otro agente', 'dsh' not in t, t[-200:])
check('el correo dirigido a otro se cuenta sin decir a quien',
      '1 mensaje(s) dirigidos a agentes concretos' in t, t[-200:])
t = call('delphi_messages', {"command": "check", "agent": "dsh"})
check('check lista sin consumir', 'pendientes: 2' in t and 'Reconecta' in t and 'para todos' in t, t)
t = call('delphi_messages', {"command": "check", "agent": "hermes"})
check('otro agente solo ve el broadcast', 'pendientes: 1' in t and 'Aviso general' in t, t)
t = call('delphi_messages', {"agent": "dsh"})
check('read entrega los dos (el propio primero)', 'MENSAJE 1/2' in t and t.index('Sigue con target=Deploy') < t.index('Aviso general') and 'entregados' in t, t)
check('entregado movido a _entregados/dsh', not os.path.exists(os.path.join(MSG, 'dsh', '20260823-0100-deploy.md')) and os.path.exists(os.path.join(MSG, '_entregados', 'dsh', '20260823-0100-deploy.md')))
check('broadcast archivado bajo quien lo recogio', os.path.exists(os.path.join(MSG, '_entregados', 'dsh', '20260823-0059-aviso.md')))
t = call('delphi_messages', {"agent": "dsh"})
check('segunda lectura: nada', t.startswith('Sin mensajes para "dsh"'), t)
t = call('delphi_workspace', {})
check('sin aviso cuando no hay nada', 'MENSAJES PENDIENTES' not in t, t[-80:])
t = call('delphi_messages', {})
check('sin agent: pista', 'Sin mensajes para todos' in t and 'agent=' in t, t)
t = call('delphi_messages', {"command": "x"})
check('command invalido', t.startswith('error:'), t)
# the agent id is slugged like delphi_report: no path tricks
open(os.path.join(MSG, 'dsh', 'otro.md'), 'w', encoding='utf-8').write('# Otro\n\nhola\n')
t = call('delphi_messages', {"agent": "..\dsh"})
check('agent se normaliza (sin ..)', 'MENSAJE 1/1' in t and 'hola' in t, t)
t = call('delphi_messages', {"command": "read", "agent": "dsh"})
check('tras leer, vacio', t.startswith('Sin mensajes'), t)

proc.stdin.close(); time.sleep(1); proc.kill()
print()
print('== messages battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
