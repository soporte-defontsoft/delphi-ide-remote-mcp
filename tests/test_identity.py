"""E2E battery for v0.68.0-beta - per-session agent identity.

The operator asked for two things at once: that each agent purge ITS OWN trash
without touching another's, and whether agents can be made to identify
themselves on the handshake and on requests. They are the same question.

The answer here is two-phase, over HTTP: the SHARED Bearer token is the door;
then the handshake's clientInfo.name is bound to the Mcp-Session-Id the server
issues - a secret it generated and the client echoes on every request. So the
name is fixed at connect time and cannot be re-declared per call: to be taken
for another agent you would have to steal their session id.

  I1  the mailbox knows who you are without you typing your id
  I2  a trashed item is tagged with who trashed it
  I3  one agent cannot purge another's copy; it can purge its own
  I4  an agent with no name (or the operator) is trusted with anyone's trash

Usage:  python tests/test_identity.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, time, os, sys, tempfile, shutil, socket, glob, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'identity')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
for name in ('a.txt', 'b.txt', 'c.txt'):
    open(os.path.join(BASE, name), 'w').write(name)

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE, '--http', str(PORT)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.5)
URL = 'http://127.0.0.1:%d/mcp' % PORT

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:300])


def rpc(body, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if sid:
        h['Mcp-Session-Id'] = sid
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers=h, method='POST')
    r = urllib.request.urlopen(req, timeout=30)
    raw = r.read().decode('utf-8', 'replace')
    newsid = r.headers.get('Mcp-Session-Id')
    msgs = []
    for line in raw.splitlines():
        if line.startswith('data:'):
            try:
                msgs.append(json.loads(line[5:].strip()))
            except Exception:
                pass
    if not msgs:
        try:
            msgs = [json.loads(raw)]
        except Exception:
            pass
    return msgs, newsid


def session(name):
    _, sid = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}})
    rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return sid


def call(sid, tool, args):
    m, _ = rpc({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                "params": {"name": tool, "arguments": args}}, sid)
    for x in m:
        if x.get('id') == 7:
            if 'result' in x:
                return x['result']['content'][0]['text']
            return 'ERR ' + json.dumps(x.get('error'))[:150]
    return '(no response)'


def trashed(name):
    return [x for x in glob.glob(os.path.join(BASE, '__delphi-patch', '*', 'deleted', name + '-*'))
            if not x.endswith('.by')]


try:
    alice = session('alice')
    bob = session('bob')

    # I1
    r = call(alice, 'delphi_messages', {'command': 'check'})
    check('I1 el buzon usa tu identidad sin que la teclees',
          'alice' in r, r[:150])

    # I2
    call(alice, 'delphi_delete', {'path': os.path.join(BASE, 'a.txt')})
    ca = trashed('a.txt')
    check('I2 la copia lleva marcador de quien la borro',
          bool(ca) and os.path.exists(ca[0] + '.by') and
          open(ca[0] + '.by').read().strip().endswith('alice'), ca)

    # I3
    r = call(bob, 'delphi_delete', {'path': ca[0], 'purge': True})
    check('I3 otro agente NO puede purgar tu copia',
          'RECHAZADO' in r and 'alice' in r and os.path.exists(ca[0]), r[:200])
    r = call(alice, 'delphi_delete', {'path': ca[0], 'purge': True})
    check('I3 pero tu SI purgas la tuya',
          'PURGADO' in r and not os.path.exists(ca[0]), r[:150])

    # I4 - a session with no name is trusted with anyone's trash
    call(bob, 'delphi_delete', {'path': os.path.join(BASE, 'b.txt')})
    cb = trashed('b.txt')
    anon = session('')  # no clientInfo.name
    r = call(anon, 'delphi_delete', {'path': cb[0], 'purge': True})
    check('I4 una sesion sin nombre (operador) purga cualquier copia',
          'PURGADO' in r and not os.path.exists(cb[0]), r[:150])
finally:
    proc.kill()

print('\n== identity battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
