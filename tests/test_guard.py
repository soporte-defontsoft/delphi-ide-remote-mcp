"""E2E battery for the workspace jail (DELPHI_MCP_ROOTS / settings.ini
[Workspace] Roots): with roots configured, every disk-touching tool must
refuse paths outside them - reads, edits, scaffolding, builds, git, search.

Usage:  python tests/test_guard.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Win64', 'Debug', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-guard-tests')
shutil.rmtree(BASE, ignore_errors=True)
INSIDE = os.path.join(BASE, 'permitido')
OUTSIDE = os.path.join(BASE, 'prohibido')
os.makedirs(INSIDE, exist_ok=True)
os.makedirs(OUTSIDE, exist_ok=True)

SRC = 'unit Dentro;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'
open(os.path.join(INSIDE, 'Dentro.pas'), 'wb').write(SRC.encode('cp1252'))
open(os.path.join(OUTSIDE, 'Fuera.pas'), 'wb').write(SRC.replace('Dentro', 'Fuera').encode('cp1252'))

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = INSIDE  # the jail
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
        return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "guard-battery", "version": "1"}}})
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

def denied(out):
    return 'FUERA de los workspaces' in out or ('MCPERROR' in out and 'FUERA' in out)

IN_PAS = os.path.join(INSIDE, 'Dentro.pas')
OUT_PAS = os.path.join(OUTSIDE, 'Fuera.pas')

# inside: allowed
out = call('delphi_read', {"path": IN_PAS})
check('dentro: read permitido', 'unit Dentro' in out, out)
out = call('delphi_edit', {"path": IN_PAS, "old": "unit Dentro;", "new": "unit Dentro; // ok"})
check('dentro: edit permitido', out.startswith('ESCRITO'), out)

# outside: every door closed
out = call('delphi_read', {"path": OUT_PAS})
check('fuera: read vetado', denied(out), out)
out = call('delphi_edit', {"path": OUT_PAS, "old": "unit Fuera;", "new": "x"})
check('fuera: edit vetado', denied(out), out)
out = call('delphi_edit', {"path": os.path.join(OUTSIDE, 'Nueva.pas'), "createunit": True})
check('fuera: createunit vetado', denied(out), out)
out = call('delphi_create', {"kind": "project-console", "dir": OUTSIDE, "name": "Malo"})
check('fuera: crear proyecto vetado', denied(out), out)
out = call('delphi_build', {"project": os.path.join(OUTSIDE, 'Malo.dproj')})
check('fuera: build vetado', denied(out), out)
out = call('delphi_search', {"root": OUTSIDE, "query": "unit"})
check('fuera: search vetado', denied(out), out)
out = call('delphi_list', {"root": OUTSIDE})
check('fuera: list vetado', denied(out), out)
out = call('delphi_git', {"repo": OUTSIDE, "command": "status"})
check('fuera: git vetado', denied(out), out)
out = call('delphi_symbols', {"path": OUT_PAS})
check('fuera: symbols (LSP) vetado', denied(out), out)

# escape attempts
out = call('delphi_read', {"path": os.path.join(INSIDE, '..', 'prohibido', 'Fuera.pas')})
check('fuera: escape con ..\\ vetado', denied(out), out)
sneaky = INSIDE + '2'  # prefix cousin: permitido2
os.makedirs(sneaky, exist_ok=True)
open(os.path.join(sneaky, 'Primo.pas'), 'wb').write(SRC.encode('cp1252'))
out = call('delphi_read', {"path": os.path.join(sneaky, 'Primo.pas')})
check('fuera: primo de prefijo (permitido2) vetado', denied(out), out)

# delphi_run: inside allowed (real console exe built on the fly), outside denied
out = call('delphi_create', {"kind": "project-console", "dir": os.path.join(INSIDE, 'Hola'),
                             "name": "Hola"})
check('run: proyecto de prueba creado', out.startswith('CREADO'), out)
out = call('delphi_build', {"project": os.path.join(INSIDE, 'Hola', 'Hola.dproj'),
                            "platform": "Win64", "config": "Debug", "target": "Build"}, 600)
try:
    ok = json.loads(out)['success']
except Exception:
    ok = False
check('run: proyecto de prueba compila', ok, out[:150])
out = call('delphi_run', {"path": os.path.join(INSIDE, 'Hola', 'Win64', 'Debug', 'Hola.exe')}, 120)
check('run: dentro ejecuta y captura salida', out.startswith('exit=0') and 'funcionando' in out, out[:150])
out = call('delphi_run', {"path": os.path.join(OUTSIDE, 'Fuera.exe')})
check('run: fuera vetado', denied(out), out[:150])
out = call('delphi_fetch', {"path": OUT_PAS})
check('fetch: fuera vetado', denied(out), out[:150])
out = call('delphi_upload', {"path": os.path.join(OUTSIDE, 'Subido.bin'),
                             "offset": 0, "chunkbase64": "AAAA"})
check('upload: fuera vetado', denied(out), out[:150])
out = call('delphi_upload', {"path": os.path.join(INSIDE, 'Subido.bin'),
                             "offset": 0, "chunkbase64": "AAAA"})
check('upload: dentro permitido', 'written' in out, out[:150])
out = call('delphi_git', {"repo": os.path.join(OUTSIDE, 'clonado'),
                          "command": "clone",
                          "message": "https://example.com/x.git"})
check('clone: destino fuera vetado', denied(out), out[:150])

# --- B0c: Windows name-normalization bypasses (trailing dot/space, ADS) ---
for probe, label in ((INSIDE + '\\Evade.pas.', 'punto final'),
                     (INSIDE + '\\Evade2.pas ', 'espacio final'),
                     (INSIDE + '\\Evade3.pas::$DATA', 'flujo ADS')):
    out = call('delphi_textedit', {"path": probe, "create": True, "content": "x"})
    check('bypass %s: textedit lo rechaza' % label, 'RECHAZADO' in out, out[:120])
check('bypass: ningun .pas colado en disco',
      not any(f.startswith('Evade') for f in os.listdir(INSIDE)),
      os.listdir(INSIDE))
out = call('delphi_fetch', {"path": IN_PAS})
check('fetch: dentro permitido', 'chunkBase64' in out, out[:120])

# --- library read zone: RTL/component sources are READABLE despite the jail,
#     but NEVER writable ---
RTL = None
for cand in (r'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\sys\System.SysUtils.pas',
             r'C:\Program Files (x86)\Embarcadero\Studio\23.0\source\rtl\sys\System.SysUtils.pas'):
    if os.path.exists(cand):
        RTL = cand
        break
if RTL:
    out = call('delphi_read', {"path": RTL, "fromline": 1, "toline": 5})
    check('lib: leer fuente RTL permitido pese a la jaula', not denied(out) and '|' in out, out[:150])
    out = call('delphi_edit', {"path": RTL, "old": "interface", "new": "x"})
    check('lib: EDITAR fuente RTL vetado siempre', denied(out), out[:150])
    out = call('delphi_search', {"root": os.path.dirname(RTL), "query": "SysUtils",
                                 "maxresults": 3})
    check('lib: buscar en fuentes RTL permitido', not denied(out), out[:150])
else:
    print('SKIP - lib: fuentes RTL no encontradas en esta maquina')

# --- git args: file-writing / path-reading options rejected on read commands
#     (a jail escape usable even read-only; found in the field audit) ---
def gitclean(out):
    return 'RECHAZADO' in out and 'opcion de git' in out

# --output writes a file: even a "read" command (diff/show) must refuse it,
# whether the target is inside the jail or an absolute path outside it.
for tgt, label in ((os.path.join(INSIDE, 'PWNED.txt'), 'dentro jaula'),
                   (os.path.join(OUTSIDE, 'PWNED.txt'), 'fuera jaula (absoluto)')):
    out = call('delphi_git', {"repo": INSIDE, "command": "diff",
                              "args": "--output=" + tgt})
    check('git escape: diff --output %s rechazado' % label, gitclean(out), out[:150])
    check('git escape: %s no se escribio' % label, not os.path.exists(tgt), tgt)
out = call('delphi_git', {"repo": INSIDE, "command": "show",
                          "args": "--output=" + os.path.join(INSIDE, 'PWNED2.txt')})
check('git escape: show --output rechazado', gitclean(out), out[:150])
check('git escape: show output no escrito',
      not os.path.exists(os.path.join(INSIDE, 'PWNED2.txt')), 'PWNED2')
# --no-index reads two arbitrary paths (content leak outside the repo)
out = call('delphi_git', {"repo": INSIDE, "command": "diff",
                          "args": "--no-index " + OUT_PAS + " " + IN_PAS})
check('git escape: diff --no-index rechazado', gitclean(out), out[:150])
# -c arbitrary config (core.pager/sshCommand -> RCE) stays refused
out = call('delphi_git', {"repo": INSIDE, "command": "log", "args": "-c core.pager=calc"})
check('git escape: -c config rechazado', gitclean(out), out[:150])
# a legitimate read still works (no false positive)
out = call('delphi_git', {"repo": INSIDE, "command": "log", "args": "--oneline -5"})
check('git: log --oneline sigue permitido (sin falso positivo)', not gitclean(out), out[:120])

print()
print('== guard battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
