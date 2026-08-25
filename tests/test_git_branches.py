"""E2E battery for v0.57.0-beta - delphi_git branch workflow: switch, merge
(--ff-only) and stash. Deep review 2026-08-25: an agent could CREATE a branch
and never move to it, so it could not work the way a programmer does (branch
per task, commit, back to main).

Usage:  python tests/test_git_branches.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'gitbranch')
for _ in range(10):
    shutil.rmtree(BASE, ignore_errors=True)
    if not os.path.exists(BASE):
        break
    time.sleep(0.5)   # git holds handles for a moment on Windows
os.makedirs(BASE, exist_ok=True)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

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
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=120):
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
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "gb", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:300])
def git(args): return call('delphi_git', dict({'repo': BASE}, **args))

# ---- repo con un commit ----
git({'command': 'init'})
git({'command': 'config', 'args': 'user.name', 'message': 'Probe Bot'})
git({'command': 'config', 'args': 'user.email', 'message': 'probe@example.com'})
open(os.path.join(BASE, 'a.txt'), 'w').write('uno\n')
git({'command': 'add', 'args': '.'})
r = git({'command': 'commit', 'message': 'inicial'})
check('commit inicial', 'exit=0' in r, r[:150])

# ---- switch -c: crear rama y MOVERSE (el hueco que cerramos) ----
r = git({'command': 'switch', 'args': 'tarea-1', 'create': True})
check('switch -c crea y cambia', 'exit=0' in r, r[:200])
r = git({'command': 'status'})
check('estamos EN la rama nueva', 'tarea-1' in r, r[:200])

# trabajo en la rama
open(os.path.join(BASE, 'b.txt'), 'w').write('trabajo\n')
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'trabajo de la tarea 1'})

# ---- volver a la rama base y fusionar ----
r = git({'command': 'switch', 'args': 'master'})
if 'exit=0' not in r:
    r = git({'command': 'switch', 'args': 'main'})
check('switch de vuelta a la rama base', 'exit=0' in r, r[:200])
check('el fichero de la otra rama NO esta aqui', not os.path.exists(os.path.join(BASE, 'b.txt')))
r = git({'command': 'merge', 'args': 'tarea-1'})
check('merge --ff-only integra', 'exit=0' in r, r[:200])
check('y ahora si esta el fichero', os.path.exists(os.path.join(BASE, 'b.txt')))

# ---- merge que NECESITARIA commit: rechazado, no a medias ----
git({'command': 'switch', 'args': 'divergente', 'create': True})
open(os.path.join(BASE, 'c.txt'), 'w').write('rama\n')
git({'command': 'add', 'args': '.'}); git({'command': 'commit', 'message': 'en divergente'})
r = git({'command': 'switch', 'args': 'master'})
if 'exit=0' not in r: git({'command': 'switch', 'args': 'main'})
open(os.path.join(BASE, 'd.txt'), 'w').write('tronco\n')
git({'command': 'add', 'args': '.'}); git({'command': 'commit', 'message': 'en tronco'})
r = git({'command': 'merge', 'args': 'divergente'})
check('merge no fast-forward RECHAZADO (no lo deja a medias)', 'exit=0' not in r, r[:250])

# ---- stash: aparcar para poder cambiar de rama ----
open(os.path.join(BASE, 'a.txt'), 'a').write('cambio sin commitear\n')
r = git({'command': 'stash'})
check('stash push aparca', 'exit=0' in r, r[:200])
check('el cambio desaparecio del arbol', 'sin commitear' not in open(os.path.join(BASE, 'a.txt')).read())
r = git({'command': 'stash', 'args': 'pop'})
check('stash pop lo recupera', 'exit=0' in r and 'sin commitear' in open(os.path.join(BASE, 'a.txt')).read(), r[:200])
r = git({'command': 'stash', 'args': 'drop'})
check('stash drop NO existe (destruye)', 'RECHAZADO' in r, r[:200])

# ---- contratos ----
r = git({'command': 'switch'})
check('switch sin rama rechazado con pista', 'RECHAZADO' in r and 'stash' in r, r[:250])
r = git({'command': 'merge'})
check('merge sin rama rechazado', 'RECHAZADO' in r, r[:200])
r = git({'command': 'switch', 'args': 'tarea-1; rm -rf /'})
check('metacaracteres rechazados', 'RECHAZADO' in r or 'error' in r.lower(), r[:200])

proc.kill()
print('\n== git branches battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
