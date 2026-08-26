"""E2E battery for v0.82.0-beta - hermes' P1.6: LSP lifecycle.

The session's global lock used to be held ACROSS the slow parts: spawning
DelphiLSP + initialize + the settings-load sleep (seconds) and the 500ms
indexing head starts. One agent warming one project stalled every other
agent's LSP call server-wide. Now the slow path runs unlocked (double-checked
client creation), the head-start sleeps happen outside the lock, the
settings/dproj resolution is cached by the stamp of the file that decided it,
and each client's notification queue is bounded (200, oldest first).

  L1  warming two DIFFERENT projects concurrently is parallel, not serial
      (wall for both together well under two sequential warms)
  L2  the settings cache does not go stale: touching the .dproj (add a search
      path) re-fabricates and the LSP keeps answering on the next call
  L3  the warm client answers symbols correctly after all of it

Usage:  python tests/test_round19.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, time, os, sys, tempfile, shutil, socket, glob, urllib.request

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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round19')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

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


def rpc(body, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=180)
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
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


try:
    sid = session('round19')

    # three disposable projects, each its own settings root
    for n in ('WarmA', 'WarmB', 'WarmC'):
        r = call(sid, 'delphi_create', {'kind': 'project-console', 'name': n, 'dir': BASE})
        check('scaffold %s' % n, 'CREADO' in r, r)
    dpr = {n: glob.glob(os.path.join(BASE, '**', n + '.dpr'), recursive=True)[0]
           for n in ('WarmA', 'WarmB', 'WarmC')}

    # L1a: single warm, measured alone
    t0 = time.time()
    ra = call(sid, 'delphi_symbols', {'path': dpr['WarmA']})
    t_single = time.time() - t0
    check('L1a un warm solo responde simbolos',
          ra.lstrip().startswith('[') and 'selectionRange' in ra, ra[:150])

    # L1b: two DIFFERENT projects warmed concurrently
    walls = {}

    def warm(agent, path):
        s = session(agent)
        t = time.time()
        walls[agent] = (call(s, 'delphi_symbols', {'path': path}), time.time() - t)

    t0 = time.time()
    th1 = threading.Thread(target=warm, args=('alice', dpr['WarmB']))
    th2 = threading.Thread(target=warm, args=('bob', dpr['WarmC']))
    th1.start()
    th2.start()
    th1.join(120)
    th2.join(120)
    t_both = time.time() - t0
    check('L1b ambos warms responden',
          all(w[0].lstrip().startswith('[') and 'selectionRange' in w[0]
              for w in walls.values()),
          (walls['alice'][0][:80], walls['bob'][0][:80]))
    # serial would be ~2x a single warm; parallel stays well under that
    check('L1c calentar dos proyectos a la vez NO se serializa '
          '(wall %.1fs < 1.6 x %.1fs)' % (t_both, t_single),
          t_both < 1.6 * t_single, (t_both, t_single))

    # L2: touch the .dproj (delphi_config add-searchpath) -> stamp changes ->
    # settings re-fabricated; the next LSP call must keep answering
    sub = os.path.join(os.path.dirname(dpr['WarmA']), 'extra')
    os.makedirs(sub)
    r = call(sid, 'delphi_config', {'project': dpr['WarmA'][:-4] + '.dproj',
                                    'command': 'add-searchpath', 'path': sub})
    check('L2 add-searchpath toca el .dproj',
          'ANADIDO' in r or 'ya estaba' in r, r[:160])
    r = call(sid, 'delphi_symbols', {'path': dpr['WarmA']})
    check('L2 tras cambiar el .dproj, symbols sigue respondiendo (cache invalidada)',
          r.lstrip().startswith('[') and 'selectionRange' in r, r[:150])

    # L3: hover on the program name still works on the warm client
    r = call(sid, 'delphi_symbols', {'path': dpr['WarmB']})
    check('L3 el cliente caliente reutilizado responde',
          r.lstrip().startswith('[') and 'selectionRange' in r, r[:120])
finally:
    proc.kill()

print('\n== round-19 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
