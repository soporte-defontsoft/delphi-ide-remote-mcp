"""Docs-vs-reality battery (v0.50.0-beta): the numbers the docs claim must
match what tools/list actually returns. Field 2026-08-24: an external review
found the README still saying 29/28 tools while the server registered 36 -
not a server bug, but it paints the project wrong. This battery makes that
drift a test failure.

Checks:
  - every "N tools" / "N core tools" / "the other N" figure in README.md;
  - every tool has its "### `name`" section in docs/TOOLS.md, and none extra;
  - docs/CAPABILITIES.json (the generated manifest) matches tools/list.

Usage:  python tests/test_docs_consistency.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'docscheck')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)
VAULT = os.path.join(BASE, 'vault'); os.makedirs(VAULT)
open(os.path.join(VAULT, 'MEMORY.md'), 'w').write('# MEMORY\n')

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_VAULT_PATH'] = VAULT
env['DELPHI_MCP_VAULT_READONLY'] = '0'  # full surface: the 3 write tools too   # vault tools registered: FULL surface
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def reader():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=reader, daemon=True).start()
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=60):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "docs", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
resp = recv(2)
TOOLS = sorted(t['name'] for t in resp['result']['tools'])
proc.kill()

TOTAL = len(TOOLS)
VAULT_TOOLS = sorted(t for t in TOOLS if t.startswith('vault_'))
CORE = TOTAL - len(VAULT_TOOLS)
LSP_BACKED = ['delphi_symbols', 'delphi_definition', 'delphi_hover',
              'delphi_completion', 'delphi_signature', 'delphi_diagnostics',
              'delphi_references']
NON_LSP_CORE = CORE - len(LSP_BACKED)

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:300])

check('tools/list responde', TOTAL > 0, TOTAL)
check('las 7 LSP-backed existen todas', all(t in TOOLS for t in LSP_BACKED),
      [t for t in LSP_BACKED if t not in TOOLS])

# ---- README ------------------------------------------------------------
readme = open(os.path.join(REPO, 'README.md'), encoding='utf-8').read()
for m in re.finditer(r'\b(\d+) tools\b', readme):
    n = int(m.group(1))
    check('README "%d tools" == %d reales' % (n, TOTAL), n == TOTAL,
          readme[max(0, m.start() - 60):m.end() + 20])
for m in re.finditer(r'\b(\d+) core tools\b', readme):
    n = int(m.group(1))
    check('README "%d core tools" == %d' % (n, CORE), n == CORE,
          readme[max(0, m.start() - 60):m.end() + 20])
for m in re.finditer(r'the other (\d+)\b', readme):
    n = int(m.group(1))
    ok = n in (TOTAL - len(LSP_BACKED), NON_LSP_CORE)
    check('README "the other %d" cuadra (no-LSP: %d con vault, %d core)' %
          (n, TOTAL - len(LSP_BACKED), NON_LSP_CORE), ok,
          readme[max(0, m.start() - 60):m.end() + 20])
check('README nombra los 5 vault_* como opcionales',
      '5 optional `vault_*`' in readme and len(VAULT_TOOLS) == 5, VAULT_TOOLS)

# ---- TOOLS.md ----------------------------------------------------------
toolsmd = open(os.path.join(REPO, 'docs', 'TOOLS.md'), encoding='utf-8').read()
documented = sorted(set(re.findall(r'^### `([a-z_]+)`', toolsmd, re.M)))
missing = [t for t in TOOLS if t not in documented]
extra = [t for t in documented if t not in TOOLS]
check('TOOLS.md documenta TODAS las tools', not missing, missing)
check('TOOLS.md no documenta tools inexistentes', not extra, extra)

# ---- CAPABILITIES.json -------------------------------------------------
cap_path = os.path.join(REPO, 'docs', 'CAPABILITIES.json')
check('docs/CAPABILITIES.json existe', os.path.exists(cap_path))
if os.path.exists(cap_path):
    cap = json.load(open(cap_path, encoding='utf-8'))
    check('manifest: total', cap.get('tools') == TOTAL, cap.get('tools'))
    check('manifest: lista identica a tools/list',
          sorted(cap.get('toolNames', [])) == TOOLS,
          [t for t in TOOLS if t not in cap.get('toolNames', [])])
    check('manifest: core/optional', cap.get('coreTools') == CORE and
          cap.get('optionalTools') == len(VAULT_TOOLS), cap)
    check('manifest: lspBacked', sorted(cap.get('lspBacked', [])) == sorted(LSP_BACKED), cap.get('lspBacked'))

print('\n== docs consistency: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
