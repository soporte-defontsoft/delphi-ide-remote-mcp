"""E2E battery for delphi_search / delphi_list / delphi_git over MCP stdio.

Usage:  python tests/test_workspace_tools.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green. Uses this very repository as the git fixture.
"""
import json, subprocess, threading, queue, time, os, sys, base64, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = os.path.join(REPO, 'src')
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, 'Win64', 'Debug', 'DelphiLspMcp.exe')

proc = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()

def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)

threading.Thread(target=reader, daemon=True).start()
rid = [10]

def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()

def recv(r, t=90):
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

def call(name, args, t=90):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:150]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "ws-battery", "version": "1"}}})
assert recv(1, 20), 'no initialize response'
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:170])

# --- search ---
out = call('delphi_search', {"root": SRC, "query": "RequestWithRetry", "wholeword": True})
try:
    d = json.loads(out)
    ok = d['total'] >= 3 and any('Lsp.Client.pas' in h['path'] for h in d['hits'])
    check('search: encuentra en Lsp.Client', ok, out[:200])
    check('search: linea 1-based y texto', all(h['line'] >= 1 and h['text'] for h in d['hits']), '')
except Exception as e:
    check('search: parsea', False, out[:200])

out = call('delphi_search', {"root": SRC, "query": "retry", "wholeword": True})
d = json.loads(out)
out2 = call('delphi_search', {"root": SRC, "query": "retry", "wholeword": False})
d2 = json.loads(out2)
check('search: wholeword filtra', d2['total'] > d['total'], '%s vs %s' % (d['total'], d2['total']))

# --- list ---
out = call('delphi_list', {"root": SRC, "pattern": "*.pas"})
try:
    d = json.loads(out)
    names = [os.path.basename(f['path']) for f in d['files']]
    check('list: unidades presentes', 'Lsp.Patch.pas' in names and 'Lsp.Client.pas' in names, names[:10])
    check('list: sin artefactos', not any('Win64' in f['path'] for f in d['files']), '')
except Exception:
    check('list: parsea', False, out[:200])

# --- list dirs (explorer mode) ---
out = call('delphi_list', {"root": REPO, "dirs": True})
try:
    d = json.loads(out)
    names = [os.path.basename(x) for x in d['dirs']]
    check('list dirs: carpetas de primer nivel', 'src' in names and 'docs' in names
          and 'vendor' in names, names)
    check('list dirs: oculta artefactos', '.git' not in names, names)
except Exception:
    check('list dirs: parsea', False, out[:200])

# --- projects locator ---
out = call('delphi_projects', {"root": REPO})
try:
    d = json.loads(out)
    names = sorted(p['name'] for p in d['projects'])
    check('projects: encuentra los del repo',
          'DelphiLspMcp' in names and 'LspCoreTest' in names and 'DelphiLspMcpTray' in names, names)
except Exception:
    check('projects: parsea', False, out[:200])
out = call('delphi_projects', {"root": REPO, "name": "tray"})
d = json.loads(out)
check('projects: filtro por nombre', d['total'] == 1 and d['projects'][0]['name'] == 'DelphiLspMcpTray', out[:150])
out = call('delphi_projects', {})
check('projects: sin root ni ini configurado avisa', out.startswith('error:') and 'Roots' in out, out[:150])

# --- fetch (chunked download with sha256) ---
LIC = os.path.join(REPO, 'LICENSE')
blob = b''
off = 0
sha = None
while True:
    out = call('delphi_fetch', {"path": LIC, "offset": off, "maxbytes": 400})
    d = json.loads(out)
    if off == 0:
        sha = d.get('sha256')
    blob += base64.b64decode(d['chunkBase64'])
    if d['eof']:
        break
    off += d['bytes']
local = open(LIC, 'rb').read()
check('fetch: reensamblado identico byte a byte', blob == local, '%d vs %d' % (len(blob), len(local)))
check('fetch: sha256 cuadra', sha and sha.lower() == hashlib.sha256(local).hexdigest(), sha)
check('fetch: fue en varios chunks', len(local) > 400, len(local))

# --- git (this repo as fixture) ---
out = call('delphi_git', {"repo": REPO, "command": "status"})
check('git: status', out.startswith('exit=0') and '## main' in out, out[:150])
out = call('delphi_git', {"repo": REPO, "command": "log"})
check('git: log', out.startswith('exit=0') and 'Phase' in out, out[:150])
out = call('delphi_git', {"repo": REPO, "command": "branch"})
check('git: branch', out.startswith('exit=0') and 'main' in out, out[:150])
out = call('delphi_git', {"repo": REPO, "command": "diff", "args": "--stat"})
check('git: diff --stat', out.startswith('exit='), out[:120])
out = call('delphi_git', {"repo": REPO, "command": "rebase"})
check('git: comando fuera de whitelist rechaza', out.startswith('error: unknown command'), out[:120])
out = call('delphi_git', {"repo": REPO, "command": "log", "args": "; del *"})
check('git: metacaracteres rechazados', out.startswith('error: shell metacharacters'), out[:120])

# --- git init / tag / push (in a THROWAWAY dir - never against this repo) ---
import tempfile, shutil
tmpgit = tempfile.mkdtemp(prefix='mcp-git-')
try:
    out = call('delphi_git', {"repo": tmpgit, "command": "init"})
    check('git: init crea repo', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "status"})
    check('git: status tras init', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "tag"})
    check('git: tag sin args lista (permitido)', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "push"})
    check('git: push permitido (falla sin remote, pero NO por whitelist)',
          out.startswith('exit=') and 'unknown command' not in out, out[:150])
finally:
    shutil.rmtree(tmpgit, ignore_errors=True)

# --- delphi_textedit (non-Delphi text files) ---
tmptxt = tempfile.mkdtemp(prefix='mcp-txt-')
try:
    md = os.path.join(tmptxt, 'README.md')
    out = call('delphi_textedit', {"path": md, "create": True,
        "content": "# Titulo\r\nlinea con acentos: gestoria admision\r\nfin\r\n"})
    check('textedit: create .md', out.startswith('CREADO'), out[:150])
    out = call('delphi_textedit', {"path": md, "create": True, "content": "x"})
    check('textedit: create nunca sobreescribe', 'RECHAZADO' in out, out[:150])
    out = call('delphi_textedit', {"path": md,
        "old": "linea con acentos: gestoria admision",
        "new": "linea EDITADA por MCP"})
    check('textedit: edit con ancla', out.startswith('OK'), out[:200])
    body = open(md, 'rb').read().decode('utf-8')
    check('textedit: contenido correcto en disco',
          'linea EDITADA por MCP' in body and '# Titulo' in body and 'fin' in body, body[:120])
    check('textedit: CRLF preservado', '\r\n' in body, repr(body[:40]))
    out = call('delphi_textedit', {"path": md, "old": "no existe esta linea",
                                   "new": "x"})
    check('textedit: ancla inexistente rechaza', 'RECHAZADO' in out, out[:150])
    out = call('delphi_textedit', {"path": md, "new": "reescritura entera"})
    check('textedit: reescritura sin ancla rechaza', 'RECHAZADO' in out, out[:150])
    out = call('delphi_textedit', {"path": os.path.join(SRC, 'Lsp.Guard.pas'),
                                   "old": "interface", "new": "x"})
    check('textedit: .pas vetado (usa delphi_edit)', 'RECHAZADO' in out and 'delphi_edit' in out, out[:150])
    out = call('delphi_textedit', {"path": os.path.join(SRC, 'DelphiLspMcp.dproj'),
                                   "old": "x", "new": "y"})
    check('textedit: .dproj vetado', 'RECHAZADO' in out, out[:150])
    html = os.path.join(tmptxt, 'index.html')
    out = call('delphi_textedit', {"path": html, "create": True,
        "content": "<html><body>hola</body></html>\r\n"})
    check('textedit: crea .html (proyectos web)', out.startswith('CREADO'), out[:120])
    out = call('delphi_textedit', {"path": html,
        "old": "<html><body>hola</body></html>",
        "new": "<html><body>hola MCP</body></html>"})
    check('textedit: edita .html', out.startswith('OK'), out[:150])
    # backup exists next to the file
    bdir = os.path.join(tmptxt, '__delphi-patch')
    check('textedit: backup automatico creado', os.path.isdir(bdir), bdir)
finally:
    shutil.rmtree(tmptxt, ignore_errors=True)
out = call('delphi_git', {"repo": REPO, "command": "commit"})
check('git: commit sin message rechaza', 'needs the "message"' in out, out[:120])

print()
print('== workspace battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
