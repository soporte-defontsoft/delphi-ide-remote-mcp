"""E2E battery for v0.45.0-beta - the F2613 helper of delphi_build and
delphi_components platform=X (the IDE's Library Search Path per platform).

Field 2026-08-22: a Linux64 build needed two failed builds per component to
locate by hand the Source folders OBR and Steema register only for Windows.
Now a failed build says WHERE each missing unit's .pas lives in the library
zone, and delphi_components platform=Linux64 lists the component roots other
platforms register and this one does not.

Usage:  python tests/test_missing_units.py [path-to-DelphiLspMcp.exe]
Needs a RAD Studio with the Linux64 compiler (dcclinux64); no PAServer.
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'missingunits')
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
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "missing-units-battery", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', (detail or '')[:400])

# --- delphi_components platform=X -------------------------------------------
r = call('delphi_components', {'platform': 'Linux64'})
check('platform view header', 'Library Search Path del IDE para Linux64' in r, r)
check('platform view lists folders', 'carpetas registradas' in r and 'srvc:' in r, r)
check('platform view names candidates or completeness',
      'registrados en otras plataformas' in r or 'lo estan tambien en Linux64' in r, r)
check('platform view never shows the IDE own documents tree as a candidate',
      '\\Studio\\37.0   (registrado' not in r, r)
r = call('delphi_components', {'platform': 'Marte'})
check('unknown platform refused with the list', 'no reconocida' in r and 'Linux64' in r, r)
r = call('delphi_components', {'platform': 'win64'})
check('platform is canonicalized (win64 -> Win64)', 'para Win64 ' in r, r)
r = call('delphi_components', {})
check('no platform = packages list as before', 'design packages' in r, r)

# --- delphi_build: missingUnits ----------------------------------------------
r = call('delphi_create', {'kind': 'project-console', 'name': 'MissU', 'dir': BASE})
check('project created', 'CREADO' in r, r)
dprs = glob.glob(os.path.join(BASE, '**', 'MissU.dpr'), recursive=True)
check('dpr on disk', bool(dprs))
dpr = dprs[0]
s = open(dpr, encoding='utf-8-sig').read()
s = s.replace('uses', 'uses\n  Tee.Grid, NoSuchUnitXyz,', 1)
open(dpr, 'w', encoding='utf-8').write(s)
dproj = dpr[:-4] + '.dproj'

r = call('delphi_build', {'project': dproj, 'platform': 'Linux64', 'config': 'Debug'})
try:
    j = json.loads(r)
except Exception:
    j = {}
check('build fails', j.get('success') is False, r)
mu = j.get('missingUnits') or []
check('missingUnits present', bool(mu), r)
names = [m.get('unit') for m in mu]
check('first missing unit named', 'Tee.Grid' in names, str(names))
tg = next((m for m in mu if m.get('unit') == 'Tee.Grid'), {})
check('Tee.Grid source folder found in the library zone (Steema Sources)',
      any('Steema' in d for d in tg.get('sourceFolders', [])), json.dumps(tg))
check('folders come masked (srvc:)', all(d.lower().startswith('srv') for d in tg.get('sourceFolders', [])), json.dumps(tg))
check('note explains add-searchpath', 'add-searchpath' in (j.get('missingUnitsNote') or ''), r)

# the suggested fix closes the loop: add-searchpath -> the unit resolves
folder = tg.get('sourceFolders', [''])[0]
if folder:
    r = call('delphi_config', {'command': 'add-searchpath', 'project': dproj, 'platform': 'Linux64', 'path': folder})
    check('add-searchpath accepted', 'RECHAZADO' not in r and 'error' not in r.lower()[:20], r)
    r = call('delphi_build', {'project': dproj, 'platform': 'Linux64', 'config': 'Debug'})
    try: j = json.loads(r)
    except Exception: j = {}
    mu = j.get('missingUnits') or []
    names = [m.get('unit') for m in mu]
    check('Tee.Grid resolved after add-searchpath', 'Tee.Grid' not in names, str(names))
    check('NoSuchUnitXyz still missing with no candidates',
          'NoSuchUnitXyz' in names and not next((m for m in mu if m.get('unit') == 'NoSuchUnitXyz'), {}).get('sourceFolders'), r)

# a successful build carries no missingUnits
s = open(dpr, encoding='utf-8-sig').read().replace('  Tee.Grid, NoSuchUnitXyz,\n', '')
open(dpr, 'w', encoding='utf-8').write(s)
r = call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'})
try: j = json.loads(r)
except Exception: j = {}
check('clean build succeeds', j.get('success') is True, r[:300])
r = call('delphi_build', {'project': dproj, 'platform': 'Linux64', 'config': 'Debug'})
try: j = json.loads(r)
except Exception: j = {}
check('Linux64 clean build succeeds', j.get('success') is True, r[:300])
out = j.get('output') or ''
check('Linux64 build declares output (ELF without extension, v0.46)',
      out.endswith(os.sep + 'MissU') and 'Linux64' in out, r[:300])
check('no missingUnits on success', 'missingUnits' not in j, r[:300])

proc.kill()
print('\n== missing units battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
