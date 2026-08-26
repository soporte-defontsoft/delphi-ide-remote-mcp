"""E2E battery for v0.81.0-beta - hermes' P1.7: shared SHA-256 cache.

delphi_fetch offset=0 hashed the whole file, then the /files download hashed
it AGAIN before streaming, and delphi_run hashed the exe too: one big zip was
read end-to-end three times for a single download. Now one shared cache keyed
by (path, mtime, size). The contract must be untouched:

  H1  fetch sha256 equals a locally computed sha256 (correctness)
  H2  /files X-File-SHA256 equals the fetch sha (shared, consistent)
  H3  changing the file changes the sha (the stamp invalidates the entry)
  H4  a repeat fetch of the unchanged file still answers the same sha

Usage:  python tests/test_round18.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, time, os, sys, tempfile, shutil, socket, hashlib, urllib.request

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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:240])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round18')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
BIG = os.path.join(BASE, 'gordo.bin')
data1 = os.urandom(1024) * 5120  # ~5 MB, above the 4 MB link threshold
open(BIG, 'wb').write(data1)

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE, '--http', str(PORT)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
HOST = 'http://127.0.0.1:%d' % PORT


def rpc(body, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=60)
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


def call(sid, tool, args):
    m, _ = rpc({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                "params": {"name": tool, "arguments": args}}, sid)
    for x in m:
        if x.get('id') == 7:
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


try:
    _, sid = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "round18", "version": "1"}}})
    rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)

    local1 = hashlib.sha256(data1).hexdigest()
    j1 = json.loads(call(sid, 'delphi_fetch', {'path': BIG}))
    check('H1 fetch sha256 == sha256 local', j1.get('sha256') == local1,
          (j1.get('sha256'), local1))

    dl = j1.get('download', '')
    check('H1b fichero grande responde enlace, no base64',
          j1.get('bytes') == 0 and dl != '', j1)
    r = urllib.request.urlopen(HOST + dl, timeout=60)
    body = r.read()
    check('H2 /files X-File-SHA256 == fetch sha y el contenido casa',
          r.headers.get('X-File-SHA256') == local1 and
          hashlib.sha256(body).hexdigest() == local1,
          r.headers.get('X-File-SHA256'))

    # H3: mutate the file - the stamp must invalidate the cached hash
    time.sleep(1.1)  # ensure a distinct mtime even on coarse filesystems
    data2 = os.urandom(1024) * 5120
    open(BIG, 'wb').write(data2)
    local2 = hashlib.sha256(data2).hexdigest()
    j2 = json.loads(call(sid, 'delphi_fetch', {'path': BIG}))
    check('H3 tras cambiar el fichero, sha nuevo y correcto (invalidacion)',
          j2.get('sha256') == local2 and j2.get('sha256') != local1,
          (j2.get('sha256'), local2))

    j3 = json.loads(call(sid, 'delphi_fetch', {'path': BIG}))
    check('H4 repetir sin cambios: mismo sha', j3.get('sha256') == local2,
          j3.get('sha256'))
finally:
    proc.kill()

print('\n== round-18 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
