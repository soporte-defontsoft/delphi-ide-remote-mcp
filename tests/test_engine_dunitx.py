"""The engine's own DUnitX suite (src/LspUnitTests), run THROUGH the server.

The Python batteries are black-box: a non-Delphi client talks to the exe as
shipped. This is the step below: unit tests of the engine's units (the
encoding detector and its inverses, the designer binary shape and the RTL
round trip, the .dproj hazard scan) written in DUnitX, born through
`delphi_create kind=project-test` (24-sep-2026) and executed here by
`delphi_test run`, so the suite is part of the regression and the tool that
runs tests is measured on a real suite every release.

Usage:  python tests/test_engine_dunitx.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRCDIR = os.path.join(REPO, 'src')
SUITE = os.path.join(SRCDIR, 'UnitTests', 'LspUnitTests.dproj')
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    SRCDIR, 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'engine-dunitx')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

# The jail is the whole repo, like the real workspace: the suite lives in src/
# and the engine units it links include files from sibling folders (the
# node key .inc under src/DesktopNode), which a src-only jail refuses -
# measured the day this battery was born. AllowTests comes from the
# environment, the way a workspace would declare it in settings.ini.
env = dict(os.environ); env['DELPHI_MCP_ROOTS'] = REPO; env['DELPHI_MCP_ALLOW_TESTS'] = '1'
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
def recv(r, t=900):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(name, args, t=900):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "eng", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:400])
def J(t):
    try: return json.loads(t)
    except Exception: return {}

check('la suite existe en src/', os.path.isfile(SUITE), SUITE)
j = J(call('delphi_test', {'command': 'discover', 'path': SUITE}))
names = [p.get('project', '') for p in j.get('projects', [])]
check('discover la reconoce como DUnitX', any('LspUnitTests' in n for n in names) and
      all(p.get('framework') == 'DUnitX' for p in j.get('projects', []) if 'LspUnitTests' in p.get('project', '')), str(j)[:300])

raw = call('delphi_test', {'command': 'run', 'project': SUITE, 'platform': 'Win64'}, t=900)
j = J(raw)
if not j:
    print('RESPUESTA CRUDA:', raw[:1200])
check('run: compila y corre', j.get('result') in ('pass', 'fail'), str(j)[:500])
check('run: result=pass (0 fallos)', j.get('result') == 'pass' and j.get('failed') == 0, str(j)[:600])
MIN_TESTS = 37  # 14 encodings + 8 designer + 5 dproj on 24-sep-2026; +10 images/frame on 25-sep; only grows
check('run: al menos %d tests, todos pasados' % MIN_TESTS,
      j.get('total', 0) >= MIN_TESTS and j.get('passed') == j.get('total'), str(j)[:300])
check('run: veredicto por numeros, no por exit code', j.get('verdictFrom') == 'counts', str(j)[:200])
check('run: exitCode 0', j.get('exitCode') == 0, str(j)[:200])
if j.get('failures'):
    print('FALLOS:', json.dumps(j.get('failures'), ensure_ascii=False)[:1500])

proc.kill()
shutil.rmtree(BASE, ignore_errors=True)
print('\n== engine-dunitx battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
