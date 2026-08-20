"""E2E battery for delphi_search / delphi_list / delphi_git over MCP stdio.

Usage:  python tests/test_workspace_tools.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green. Uses this very repository as the git fixture.
"""
import json, subprocess, threading, queue, time, os, sys, base64, hashlib
import tempfile, shutil, stat

# Every scratch folder this battery needs lives under ONE parent with a FIXED
# name. mkdtemp gave each run a new random path, which scatters leftovers all
# over %TEMP% and - for anything that opens a port - makes Windows Firewall
# treat each run as a brand-new program and ask again.
def _fixed(name):
    d = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', name)
    # rmtree(ignore_errors=True) is NOT enough here and failing silently is the
    # worst outcome: a cloned repo leaves read-only files under .git\objects, so
    # the folder survives, the next run finds a repo already there, git clone
    # refuses and three checks quietly stop running. Clear the read-only bit and
    # try again, then assert the folder is really gone.
    for _ in range(3):
        shutil.rmtree(d, ignore_errors=True)
        if not os.path.isdir(d):
            break
        for root, _dirs, files in os.walk(d):
            for f in files:
                try:
                    os.chmod(os.path.join(root, f), stat.S_IWRITE)
                except OSError:
                    pass
    assert not os.path.isdir(d), 'no se pudo limpiar la carpeta de scratch: ' + d
    os.makedirs(d, exist_ok=True)
    return d


HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = os.path.join(REPO, 'src')
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

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

# --- list: artifact filtering is RELATIVE to the root (v0.29) ---
# from above, build output stays hidden but the result SAYS so
out = call('delphi_list', {"root": SRC, "pattern": "*.exe"})
try:
    d = json.loads(out)
    check('list: build output oculto pero DECLARADO (hidden+note)',
          d.get('hidden', 0) >= 1 and 'delphi_package' in d.get('note', ''), out[:200])
except Exception:
    check('list: parsea (hidden)', False, out[:200])
# naming the build-output folder itself as root serves its contents
RELDIR = os.path.dirname(os.path.abspath(EXE))
out = call('delphi_list', {"root": RELDIR, "pattern": "*.exe"})
try:
    d = json.loads(out)
    check('list: root explicito DENTRO de build output lista el exe',
          any(os.path.basename(EXE).lower() == os.path.basename(f['path']).lower()
              for f in d['files']), out[:200])
except Exception:
    check('list: parsea (root en build output)', False, out[:200])
# dirs browse of the folder holding the platform dirs: hidden children counted
out = call('delphi_list', {"root": os.path.join(SRC, 'Compiled'), "dirs": True})
try:
    d = json.loads(out)
    check('list dirs: hijos de build output contados en hidden con nota',
          d.get('hidden', 0) >= 1 and 'note' in d, out[:200])
except Exception:
    check('list dirs: parsea (hidden)', False, out[:200])
# dirs browse INSIDE artifact territory serves the children (explicit root)
out = call('delphi_list', {"root": os.path.dirname(RELDIR), "dirs": True})
try:
    d = json.loads(out)
    names = [os.path.basename(x) for x in d['dirs']]
    check('list dirs: root dentro de build output muestra sus hijos',
          os.path.basename(RELDIR) in names, out[:200])
except Exception:
    check('list dirs: parsea (root en build output)', False, out[:200])

# --- projects locator ---
out = call('delphi_projects', {"root": REPO})
try:
    d = json.loads(out)
    names = sorted(p['name'] for p in d['projects'])
    # ONE server project now: the terminal, the service and the tray are three
    # modes of the same executable, not three projects.
    check('projects: encuentra los del repo',
          'DelphiLspMcp' in names and 'LspCoreTest' in names, names)
    check('projects: el proyecto del tray ya no existe por separado',
          'DelphiLspMcpTray' not in names, names)
except Exception:
    check('projects: parsea', False, out[:200])
out = call('delphi_projects', {"root": REPO, "name": "core"})
d = json.loads(out)
check('projects: filtro por nombre', d['total'] == 1 and d['projects'][0]['name'] == 'LspCoreTest', out[:150])
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
# --oneline -20: assert on the SHAPE (hash + subject lines), never on a
# specific old commit message - it scrolls out of the window as we release.
check('git: log', out.startswith('exit=0')
      and len([l for l in out.splitlines()[1:] if l.strip()]) >= 5, out[:150])
out = call('delphi_git', {"repo": REPO, "command": "branch"})
check('git: branch', out.startswith('exit=0') and 'main' in out, out[:150])
out = call('delphi_git', {"repo": REPO, "command": "diff", "args": "--stat"})
check('git: diff --stat', out.startswith('exit='), out[:120])
out = call('delphi_git', {"repo": REPO, "command": "rebase"})
check('git: comando fuera de whitelist rechaza', out.startswith('error: unknown command'), out[:120])
out = call('delphi_git', {"repo": REPO, "command": "log", "args": "; del *"})
check('git: metacaracteres rechazados', out.startswith('error: shell metacharacters'), out[:120])

# --- delphi_signature + definition kind variants (real LSP semantics) ---
GUARD = os.path.join(SRC, 'Lsp.Guard.pas')
lines = open(GUARD, 'rb').read().decode('utf-8-sig', 'replace').replace('\r\n', '\n').split('\n')
sig_line = ident_line = -1
for i, ln in enumerate(lines):
    if 'Result := PathDenied(APath);' in ln:
        sig_line = ident_line = i
        paren_char = ln.index('PathDenied(') + len('PathDenied(')
        ident_char = ln.index('PathDenied') + 3
        break
if sig_line >= 0:
    out = call('delphi_signature', {"path": GUARD, "line": sig_line,
                                    "character": paren_char}, 180)
    check('signature: firma de PathDenied en la llamada',
          'PathDenied' in out or 'APath' in out, out[:200])
    out = call('delphi_definition', {"path": GUARD, "line": ident_line,
                                     "character": ident_char, "kind": "xx"})
    check('definition: kind invalido rechaza', 'RECHAZADO' in out, out[:120])
else:
    check('signature: ancla de test encontrada en Lsp.Guard.pas', False, 'no anchor')

# decl vs impl only split for METHODS (measured: for global routines both
# return the interface declaration) - so test on a TLspClient method usage.
CLIENT = os.path.join(SRC, 'Lsp.Client.pas')
clines = open(CLIENT, 'rb').read().decode('utf-8-sig', 'replace').replace('\r\n', '\n').split('\n')
m_line = -1
for i, ln in enumerate(clines):
    if "Result := RequestWithRetry('textDocument/hover'" in ln:
        m_line = i
        m_char = ln.index('RequestWithRetry') + 4
        break
if m_line >= 0:
    out_decl = call('delphi_definition', {"path": CLIENT, "line": m_line,
                                          "character": m_char,
                                          "kind": "declaration"}, 180)
    out_def = call('delphi_definition', {"path": CLIENT, "line": m_line,
                                         "character": m_char}, 180)
    # measured semantics: definition = the body, declaration = the
    # interface declaration (two different lines of the same unit)
    ok = ('Lsp.Client.pas' in out_decl and 'Lsp.Client.pas' in out_def
          and out_decl != out_def and 'null' not in out_decl[:6])
    check('definition: kind declaration vs default (las dos mitades)',
          ok, ('decl=%s | def=%s' % (out_decl[:90], out_def[:90])))
else:
    check('definition: ancla de metodo encontrada en Lsp.Client.pas', False, 'no anchor')

# --- workspace: roots as the round-trip variable (server vs own paths) ---
out = call('delphi_workspace', {})
try:
    d = json.loads(out)
    check('workspace: expone roots', isinstance(d.get('roots'), list), out[:200])
    check('workspace: avisa que son rutas del servidor',
          'REMOTE' in d.get('note', '') or 'server' in d.get('note', '').lower(),
          out[:200])
    check('workspace: nivel de acceso', d.get('access') in ('read-write', 'read-only'),
          out[:200])
except Exception:
    check('workspace: parsea', False, out[:200])

# --- installs: every Delphi on the machine, as a list ---
out = call('delphi_installs', {})
try:
    d = json.loads(out)
    check('installs: al menos una instalacion', d['total'] >= 1, out[:200])
    check('installs: la activa tiene DelphiLSP',
          d['activeForLsp'] != '' and any(
              i['active'] and i['delphilsp'] for i in d['installs']), out[:200])
    check('installs: rootdir descubierto no vacio',
          all(i['rootdir'] for i in d['installs']), out[:200])
except Exception:
    check('installs: parsea', False, out[:200])

# --- git init / tag / push (in a THROWAWAY dir - never against this repo) ---
import tempfile, shutil
tmpgit = _fixed('git')
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

    # identity via whitelisted config + commit with normal punctuation
    out = call('delphi_git', {"repo": tmpgit, "command": "config",
                              "args": "user.name", "message": "Agente Remoto"})
    check('git: config user.name', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "config",
                              "args": "user.email", "message": "agente@test.local"})
    check('git: config user.email', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "config",
                              "args": "core.sshCommand", "message": "evil"})
    check('git: config fuera de user.name/email rechazado',
          out.startswith('error:'), out[:150])
    with open(os.path.join(tmpgit, 'nota.txt'), 'w') as f:
        f.write('hola\n')
    call('delphi_git', {"repo": tmpgit, "command": "add", "args": "."})
    out = call('delphi_git', {"repo": tmpgit, "command": "commit",
        "message": "Commit de prueba (con parentesis), 'comillas' y ¡signos!"})
    check('git: commit con puntuacion normal en message', out.startswith('exit=0'),
          out[:200])
    out = call('delphi_git', {"repo": tmpgit, "command": "log"})
    check('git: log muestra el commit', 'parentesis' in out, out[:200])
    check('git: acentos del mensaje SIN mojibake (utf-8 bien decodificado)',
          '¡signos!' in out and 'Ã' not in out, out[:200])
finally:
    shutil.rmtree(tmpgit, ignore_errors=True)

# --- delphi_upload: mirror of fetch, byte-identical reassembly ---
import base64, secrets
tmpup = _fixed('upload')
try:
    blob = secrets.token_bytes(120000)
    sha = hashlib.sha256(blob).hexdigest()
    dst = os.path.join(tmpup, 'sub', 'Artefacto.res')
    half = len(blob) // 2
    o1 = call('delphi_upload', {"path": dst, "offset": 0,
                                "chunkbase64": base64.b64encode(blob[:half]).decode()})
    try:
        d1 = json.loads(o1)
        o2 = call('delphi_upload', {"path": dst, "offset": d1['nextOffset'],
                                    "chunkbase64": base64.b64encode(blob[half:]).decode(),
                                    "sha256": sha})
        d2 = json.loads(o2)
        check('upload: dos chunks, tamano final correcto',
              d2['size'] == len(blob), o2[:150])
        check('upload: sha256 verificado por el servidor',
              d2.get('verified') is True, o2[:150])
        check('upload: fichero byte-identico en disco',
              open(dst, 'rb').read() == blob, 'mismatch')
        check('upload: crea subcarpetas', os.path.isdir(os.path.dirname(dst)), dst)
    except Exception as e:
        check('upload: parsea', False, '%s | %s' % (e, o1[:150]))
    out = call('delphi_upload', {"path": os.path.join(tmpup, 'X.bin'), "offset": 99,
                                 "chunkbase64": "AAAA"})
    check('upload: offset>0 sobre fichero inexistente rechaza',
          out.startswith('error:'), out[:120])
    out = call('delphi_upload', {"path": os.path.join(tmpup, 'Y.bin'), "offset": 0,
                                 "chunkbase64": "no-es-base64!!"})
    check('upload: base64 invalido rechaza (no escribe basura)',
          out.startswith('error:') and not os.path.exists(os.path.join(tmpup, 'Y.bin')),
          out[:120])
finally:
    shutil.rmtree(tmpup, ignore_errors=True)

# --- git clone: whole repo in one call (network; skipped if offline) ---
tmpcl = _fixed('clone')
try:
    dest = os.path.join(tmpcl, 'repo')
    out = call('delphi_git', {"repo": dest, "command": "clone",
        "message": "https://github.com/soporte-defontsoft/delphi-lsp-mcp-service.git"}, 600)
    if 'exit=0' in out:
        check('git clone: repo entero en una llamada',
              os.path.isdir(os.path.join(dest, 'src')), out[:150])
        out2 = call('delphi_git', {"repo": dest, "command": "clone",
            "message": "https://github.com/soporte-defontsoft/delphi-lsp-mcp-service.git"})
        check('git clone: no re-clona sobre un repo existente',
              out2.startswith('error:'), out2[:120])
        out3 = call('delphi_git', {"repo": dest, "command": "pull"}, 300)
        check('git pull: permitido', out3.startswith('exit='), out3[:120])
    else:
        print('SKIP - git clone (sin red o repo inaccesible):', out[:100])
    out = call('delphi_git', {"repo": dest, "command": "clone",
                              "message": "file:///C:/Windows"})
    check('git clone: URL no http/ssh rechazada', out.startswith('error:'), out[:120])
finally:
    shutil.rmtree(tmpcl, ignore_errors=True)

# --- delphi_textedit (non-Delphi text files) ---
tmptxt = _fixed('textedit')
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
