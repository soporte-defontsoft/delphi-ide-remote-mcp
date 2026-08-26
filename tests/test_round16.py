"""E2E battery for v0.77.0-beta - hermes' release audit P1.5: compact outputs.

Measured walls (hermes, 2026-08-26, live runtime over a real project):
`delphi_config view` answered 11.7k chars and `delphi_symbols` 37.5k chars for
a 912-line unit - a small model drowned before doing anything. Now:

  - delphi_config view defaults to a SUMMARY (framework, configurations,
    enabled platforms, counts) and `section=platforms|searchpaths|deploy|
    units|all` brings each detail on demand.
  - delphi_symbols on a FILE: big trees answer with a compact skeleton
    (mode summary, auto above 6k chars of full tree), `mode=full` keeps the
    old complete tree, and `filter=name` finds symbols without the tree.

  C1..C7  config sections
  S1..S5  symbols modes and filter

Usage:  python tests/test_round16.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round16')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
# a real big unit for the symbols wall (typ. >30k chars of full tree)
shutil.copy(os.path.join(REPO, 'src', 'Lsp.Guard.pas'),
            os.path.join(BASE, 'Big.pas'))
open(os.path.join(BASE, 'Small.pas'), 'w').write(
    'unit Small;\ninterface\nprocedure Uno;\nimplementation\n'
    'procedure Uno;\nbegin\nend;\nend.\n')

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        text=True, encoding='utf-8')
q = queue.Queue()


def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)


threading.Thread(target=reader, daemon=True).start()
rid = [10]
P = F = 0


def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


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


def call(tool, args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": tool, "arguments": args}})
    r = recv(rid[0])
    if not r:
        return '(sin respuesta)'
    return r.get('result', {}).get('content', [{}])[0].get('text', 'ERR')


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


def jload(s):
    try:
        return json.loads(s)
    except Exception:
        return {}


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round16", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

# ---- config sections -------------------------------------------------------
r = call('delphi_create', {'kind': 'project-console', 'name': 'SecCfg', 'dir': BASE})
check('scaffold para config', 'CREADO' in r, r)
dproj = glob.glob(os.path.join(BASE, '**', 'SecCfg.dproj'), recursive=True)[0]

rsum = call('delphi_config', {'project': dproj})
j = jload(rsum)
check('C1 view por defecto = summary (marco, configs, plataformas, counts)',
      j.get('frameworkType') is not None and 'configurations' in j and
      'platformsEnabled' in j and 'counts' in j and 'sections' in j, rsum[:300])
check('C1 el summary NO arrastra el detalle (ni units ni searchPaths ni platforms)',
      'units' not in j and 'searchPaths' not in j and 'platforms' not in j, list(j.keys()))

j = jload(call('delphi_config', {'project': dproj, 'section': 'units'}))
check('C2 section=units trae las units y solo eso',
      isinstance(j.get('units'), list) and
      'counts' not in j and 'searchPaths' not in j, list(j.keys()))

j = jload(call('delphi_config', {'project': dproj, 'section': 'platforms'}))
check('C3 section=platforms trae el detalle por plataforma',
      isinstance(j.get('platforms'), list) and
      all('enabled' in p and 'canTarget' in p for p in j['platforms']),
      list(j.keys()))

j = jload(call('delphi_config', {'project': dproj, 'section': 'searchpaths'}))
check('C4 section=searchpaths responde su area',
      ('searchPaths' in j) or ('searchPathsNote' in j), list(j.keys()))

rall = call('delphi_config', {'project': dproj, 'section': 'all'})
j = jload(rall)
check('C5 section=all lo trae todo junto (la vista antigua)',
      'units' in j and 'platforms' in j and
      ('searchPaths' in j or 'searchPathsNote' in j) and
      j.get('frameworkType') is not None, list(j.keys()))
check('C6 el summary pesa bastante menos que all',
      len(rsum) < len(rall), (len(rsum), len(rall)))
r = call('delphi_config', {'project': dproj, 'section': 'Marte'})
check('C7 section invalida se rechaza con la lista',
      'error' in r and 'summary' in r and 'units' in r, r)

# ---- symbols modes ---------------------------------------------------------
big = os.path.join(BASE, 'Big.pas')
small = os.path.join(BASE, 'Small.pas')

rbig = call('delphi_symbols', {'path': big})
j = jload(rbig)
check('S1 arbol grande por defecto = summary compacto con secciones',
      j.get('mode') == 'summary' and isinstance(j.get('sections'), list) and
      j.get('totalSymbols', 0) > 50 and 'autoNote' in j, rbig[:260])
check('S1 y de verdad es compacto (<8k chars, antes 38k)',
      len(rbig) < 8000, len(rbig))

rfull = call('delphi_symbols', {'path': big, 'mode': 'full'})
check('S2 mode=full conserva el arbol completo con rangos',
      rfull.lstrip().startswith('[') and 'selectionRange' in rfull and
      len(rfull) > 20000, len(rfull))

rsmall = call('delphi_symbols', {'path': small})
check('S3 un arbol pequeno sigue viniendo entero sin pedirlo',
      rsmall.lstrip().startswith('[') and 'selectionRange' in rsmall, rsmall[:200])

j = jload(call('delphi_symbols', {'path': big, 'filter': 'pathdenied'}))
ms = j.get('matches', [])
check('S4 filter encuentra el simbolo con kind, linea y contenedor',
      j.get('total', 0) >= 2 and ms and
      all('pathdenied' in m['name'].lower() and 'line' in m for m in ms) and
      any('in' in m for m in ms), str(j)[:260])

r = call('delphi_symbols', {'path': big, 'mode': 'arbol'})
check('S5 mode invalido se rechaza explicando los validos',
      'error' in r and 'summary' in r and 'full' in r, r)

proc.kill()
print('\n== round-16 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
