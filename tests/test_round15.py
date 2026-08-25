"""E2E battery for v0.76.0-beta - hermes' release audit, P0 + supplement.

Two dangers and one wall, all measured by hermes on the live runtime:

  - builds were NOT serialized: Indy serves each request on its own thread and
    two concurrent delphi_build/delphi_test calls entered MSBuild at once,
    colliding DCUs, outputs and .deployproj. Now a global queue: one msbuild
    at a time, and a queued call reports queuedMs + queuedNote.
  - delphi_search had maxresults but no offset: a truncated search was a wall,
    the next page was unreachable. Now offset + hasMore + nextOffset.
  (- TLspSession.Instance could double-create on two first concurrent LSP
    calls; fixed lock-free with CompareExchange - covered by code review, the
    race window is too narrow for a deterministic E2E check.)

  E1  search pagination: pages don't overlap, walk reaches total, tail page ok
  E2  two concurrent builds both succeed and one waited in queue (queuedMs)

Usage:  python tests/test_round15.py [path-to-DelphiLspMcp.exe]
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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round15')
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


def rpc(body, sid=None, timeout=420):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=timeout)
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


def call(sid, tool, args, timeout=420):
    m, _ = rpc({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                "params": {"name": tool, "arguments": args}}, sid, timeout)
    for x in m:
        if x.get('id') == 7:
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


try:
    sid = session('round15')

    # ---- E1: search pagination -------------------------------------------
    sub = os.path.join(BASE, 'srch')
    os.makedirs(sub)
    lines = []
    for i in range(10):
        lines.append('  NeedleXyz := %d;' % i)
        lines.append('  Other := 0;')
    open(os.path.join(sub, 'many.pas'), 'w').write(
        'unit many;\ninterface\nimplementation\nprocedure X;\nbegin\n' +
        '\n'.join(lines) + '\nend;\nend.\n')

    r1 = json.loads(call(sid, 'delphi_search',
                         {'root': sub, 'query': 'NeedleXyz', 'maxresults': 3}))
    check('E1 page 1: total=10 shown=3 hasMore nextOffset=3',
          r1.get('total') == 10 and r1.get('shown') == 3 and
          r1.get('hasMore') is True and r1.get('nextOffset') == 3, r1)
    r2 = json.loads(call(sid, 'delphi_search',
                         {'root': sub, 'query': 'NeedleXyz', 'maxresults': 3, 'offset': 3}))
    l1 = [h['line'] for h in r1['hits']]
    l2 = [h['line'] for h in r2['hits']]
    check('E1 page 2 continues, no overlap',
          r2.get('offset') == 3 and l2 and not (set(l1) & set(l2)) and
          min(l2) > max(l1), (l1, l2))
    seen, ofs = [], 0
    while True:
        rp = json.loads(call(sid, 'delphi_search',
                             {'root': sub, 'query': 'NeedleXyz', 'maxresults': 4, 'offset': ofs}))
        seen += [h['line'] for h in rp['hits']]
        if not rp.get('hasMore'):
            break
        ofs = rp['nextOffset']
    check('E1 walking pages reaches every hit exactly once',
          len(seen) == 10 and len(set(seen)) == 10, seen)
    rt = json.loads(call(sid, 'delphi_search',
                         {'root': sub, 'query': 'NeedleXyz', 'offset': 99}))
    check('E1 offset past the end: shown 0, hasMore false',
          rt.get('shown') == 0 and rt.get('hasMore') is False, rt)

    # ---- E2: concurrent builds are serialized ----------------------------
    for name in ('BQa', 'BQb'):
        r = call(sid, 'delphi_create', {'kind': 'project-console', 'name': name, 'dir': BASE})
        check('E2 scaffold %s' % name, 'CREADO' in r, r)
    dprojs = {n: glob.glob(os.path.join(BASE, '**', n + '.dproj'), recursive=True)[0]
              for n in ('BQa', 'BQb')}

    results = {}

    def build(agent, proj):
        s = session(agent)
        results[agent] = call(s, 'delphi_build',
                              {'project': proj, 'platform': 'Win64', 'config': 'Debug'})

    t1 = threading.Thread(target=build, args=('alice', dprojs['BQa']))
    t2 = threading.Thread(target=build, args=('bob', dprojs['BQb']))
    t1.start()
    t2.start()
    t1.join(400)
    t2.join(400)

    ra = json.loads(results.get('alice', '{}'))
    rb = json.loads(results.get('bob', '{}'))
    check('E2 both concurrent builds succeed',
          ra.get('success') is True and rb.get('success') is True,
          (ra.get('firstError'), rb.get('firstError')))
    queued = [r for r in (ra, rb) if 'queuedMs' in r]
    check('E2 exactly one of them waited in the queue (queuedMs >= 500)',
          len(queued) == 1 and queued[0]['queuedMs'] >= 500,
          {'alice': ra.get('queuedMs'), 'bob': rb.get('queuedMs')})
    check('E2 the queued one explains itself (queuedNote)',
          bool(queued) and 'DE UNO EN UNO' in queued[0].get('queuedNote', ''),
          queued and queued[0].get('queuedNote'))
finally:
    proc.kill()

print('\n== round-15 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
