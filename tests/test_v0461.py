"""E2E battery for v0.46.1-beta - parameter aliases at the gate, delphi_search over ONE file,
delphi_list brace refusal, log flushed per line.

Usage:  python tests/test_v0461.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'v0461')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

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
def recv(r, t=300):
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
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "v0461-battery", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', (detail or '')[:400])

# --- fixtures
open(os.path.join(BASE, 'Big.dproj'), 'w', encoding='utf-8').write(
    '<Project>\n' + '  <Line/>\n' * 600 + '  <DCC_UnitSearchPath>..\Lib</DCC_UnitSearchPath>\n' + '  <Line/>\n' * 600 + '</Project>\n')
open(os.path.join(BASE, 'U1.pas'), 'w', encoding='utf-8').write('unit U1;\ninterface\nimplementation\nend.\n')
open(os.path.join(BASE, 'U1.dfm'), 'w', encoding='utf-8').write('object F: TF\nend\n')

# --- delphi_search over ONE file
r = call('delphi_search', {'root': os.path.join(BASE, 'Big.dproj'), 'query': 'DCC_UnitSearchPath'})
try: j = json.loads(r)
except Exception: j = {}
check('search root=file: one hit at the right line', j.get('total') == 1 and j['hits'][0]['line'] == 602, r[:300])
check('search root=file: filesScanned = 1', j.get('filesScanned') == 1, r[:200])
r = call('delphi_search', {'root': os.path.join(BASE, 'Nope.dproj'), 'query': 'x'})
check('search root=missing file: error', 'not found' in r, r)
# alias: text -> query
r = call('delphi_search', {'root': BASE, 'text': 'DCC_UnitSearchPath'})
try: j = json.loads(r)
except Exception: j = {}
check('search alias text->query', j.get('total') == 1, r[:200])

# --- delphi_list
r = call('delphi_list', {'root': BASE, 'pattern': '*.{pas,dfm}'})
check('list: braces refused with hint', 'RECHAZADO' in r and ';' in r, r[:200])
r = call('delphi_list', {'root': BASE, 'pattern': '*.pas;*.dfm'})
try: j = json.loads(r)
except Exception: j = {}
check('list: ";" list works', j.get('total') == 2, r[:200])
r = call('delphi_list', {'root': BASE, 'filter': '*.pas'})
try: j = json.loads(r)
except Exception: j = {}
check('list alias filter->pattern', j.get('total') == 1 and j['files'][0]['path'].endswith('U1.pas'), r[:200])
r = call('delphi_list', {'root': BASE, 'filter': '*.pas', 'pattern': '*.dfm'})
try: j = json.loads(r)
except Exception: j = {}
check('alias never overrides the real name', j.get('total') == 1 and j['files'][0]['path'].endswith('U1.dfm'), r[:200])

# --- delphi_read aliases
r = call('delphi_read', {'path': os.path.join(BASE, 'Big.dproj'), 'startline': 602, 'endline': 602})
check('read alias startline/endline', 'DCC_UnitSearchPath' in r and 'Unknown parameter' not in r, r[:200])

# --- delphi_components alias
r = call('delphi_components', {'query': 'zzz-no-such-package'})
check('components alias query->filter', 'Unknown parameter' not in r and 'zzz-no-such-package' in r, r[:200])

# --- log flushed per line (the tray never closes the writer)
r = call('delphi_workspace', {})
check('workspace ok', 'roots' in r, r[:100])
logs = glob.glob(os.path.join(BASE, 'logs', '*.log')) + glob.glob(os.path.join(BASE, '*.log'))
if logs:
    txt = open(max(logs, key=os.path.getmtime), encoding='utf-8', errors='ignore').read()
    check('log flushed per line (last call already on disk)', 'delphi_workspace' in txt, logs)
else:
    print('SKIP log flush (no log file in scratch: file logging off in stdio mode)')

proc.kill()
print('\n== v0.46.1 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
