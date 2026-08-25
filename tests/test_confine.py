"""E2E battery for v0.75.0-beta - optional per-agent write confinement.

sweep10 found that the jail is per-ROOT, not per-agent: any agent could write
into another agent's folder inside a shared workspace. The operator asked for an
OPTIONAL confined mode (off by default): with it on, an identified agent may
WRITE only inside <root>\\<its-name>\\... or a folder the operator marked shared;
reading the whole tree stays open, and a caller with no identity (stdio, the
operator's console) is unconfined - the same rule the recoverable trash uses.

  C0  OFF by default: nothing changes, an agent writes anywhere in the jail
  C1  ON: an agent writes inside its own folder
  C2  ON: an agent CANNOT write into another agent's folder
  C3  ON: a folder the operator marked shared is writable by anyone
  C4  ON: writing loose at the root is refused
  C5  ON: reading is NOT confined - the whole tree is readable
  C6  ON: a caller with no identity is not confined (stdio path)

Usage:  python tests/test_confine.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, time, os, sys, tempfile, shutil, socket, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:220])


def start(confine):
    base = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests',
                        'confine-%s-%d' % ('on' if confine else 'off', int(time.time() * 1000) % 100000))
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    exe = os.path.join(base, 'DelphiLspMcp.exe')
    shutil.copy(SRC, exe)
    for a in ('alice', 'bob', 'shared'):
        os.makedirs(os.path.join(base, a))
    open(os.path.join(base, 'bob', 'b.pas'), 'w').write('unit b;\n')
    sk = socket.socket()
    sk.bind(('127.0.0.1', 0))
    port = sk.getsockname()[1]
    sk.close()
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = base
    if confine:
        env['DELPHI_MCP_AGENT_CONFINEMENT'] = '1'
        env['DELPHI_MCP_SHARED_FOLDERS'] = 'shared'
    proc = subprocess.Popen([exe, '--http', str(port)], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2.3)
    return base, port, proc


def rpc(url, body, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        url, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=20)
    raw = r.read().decode('utf-8', 'replace')
    msgs = []
    for l in raw.splitlines():
        if l.startswith('data:'):
            try:
                msgs.append(json.loads(l[5:].strip()))
            except Exception:
                pass
    if not msgs:
        try:
            msgs = [json.loads(raw)]
        except Exception:
            pass
    return msgs, r.headers.get('Mcp-Session-Id')


def session(url, name):
    _, sid = rpc(url, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}})
    rpc(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return sid


def call(url, sid, tool, args):
    m, _ = rpc(url, {"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                     "params": {"name": tool, "arguments": args}}, sid)
    for x in m:
        if x.get('id') == 7:
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


def ok(r):
    return 'RECHAZADO' not in r and r != 'ERR' and '(no)' not in r


# ---- OFF by default ----
base, port, proc = start(False)
url = 'http://127.0.0.1:%d/mcp' % port
try:
    a = session(url, 'alice')
    check('C0 OFF por defecto: un agente escribe donde sea del jail',
          ok(call(url, a, 'delphi_textedit',
                  {'path': os.path.join(base, 'bob', 'off.txt'), 'create': True, 'content': 'x'})))
finally:
    proc.kill()

# ---- ON ----
base, port, proc = start(True)
url = 'http://127.0.0.1:%d/mcp' % port
try:
    a = session(url, 'alice')
    check('C1 ON: escribe en su propia carpeta',
          ok(call(url, a, 'delphi_textedit',
                  {'path': os.path.join(base, 'alice', 'n.txt'), 'create': True, 'content': 'x'})))
    r = call(url, a, 'delphi_textedit',
             {'path': os.path.join(base, 'bob', 'hack.txt'), 'create': True, 'content': 'x'})
    check('C2 ON: NO escribe en la carpeta de otro agente',
          'RECHAZADO' in r and 'confinado' in r, r)
    check('C3 ON: una carpeta compartida es escribible',
          ok(call(url, a, 'delphi_textedit',
                  {'path': os.path.join(base, 'shared', 's.txt'), 'create': True, 'content': 'x'})))
    r = call(url, a, 'delphi_textedit',
             {'path': os.path.join(base, 'loose.txt'), 'create': True, 'content': 'x'})
    check('C4 ON: escribir suelto en la raiz se rechaza', 'RECHAZADO' in r, r)
    check('C5 ON: leer NO esta confinado (lee el arbol entero)',
          ok(call(url, a, 'delphi_read', {'path': os.path.join(base, 'bob', 'b.pas')})))
finally:
    proc.kill()

# ---- ON, but stdio has no identity: unconfined ----
base = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'confine-stdio-%d' % (int(time.time() * 1000) % 100000))
shutil.rmtree(base, ignore_errors=True)
os.makedirs(base)
exe = os.path.join(base, 'DelphiLspMcp.exe')
shutil.copy(SRC, exe)
os.makedirs(os.path.join(base, 'bob'))
env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = base
env['DELPHI_MCP_AGENT_CONFINEMENT'] = '1'
proc = subprocess.Popen([exe], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')


def sio(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


sio({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "", "version": "1"}}})
sio({"jsonrpc": "2.0", "method": "notifications/initialized"})
sio({"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {
    "name": "delphi_textedit",
    "arguments": {"path": os.path.join(base, 'bob', 'stdio.txt'), "create": True, "content": "x"}}})
res = ''
t0 = time.time()
while time.time() - t0 < 15:
    line = proc.stdout.readline()
    if not line:
        break
    try:
        m = json.loads(line)
    except Exception:
        continue
    if m.get('id') == 7:
        res = m.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
        break
proc.kill()
check('C6 ON: una sesion sin identidad (stdio/operador) no esta confinada',
      'RECHAZADO' not in res and res not in ('', 'ERR'), res)

print('\n== confine battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
