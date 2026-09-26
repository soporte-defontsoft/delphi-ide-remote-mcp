"""E2E battery for delphi_git worktree (1.4.0): ANOTHER version of the repo
next to it, so an agent - a remote one above all - can build and compare an
old release without leaving the MCP. Like clone: the agent picks a NEW folder
inside its roots; no temp folders, no cleanups at start. remove takes away
only what list shows, never the main copy, never with changes (no --force)
and never with a link inside: measured 2026-09-26, git worktree remove
crosses a junction in an ignored folder and empties what is behind it.

Usage:  python tests/test_git_worktree.py [path-to-DelphiLspMcp.exe]
"""
import json, os, shutil, stat, subprocess, sys, tempfile, threading, queue, time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO_ROOT, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'git-worktree')


def quita_enlaces(base):
    # junctions first, with rmdir (removes the LINK, never its target)
    r = subprocess.run(['cmd', '/c', 'dir', '/AL', '/S', '/B', base], capture_output=True, text=True)
    for j in sorted(r.stdout.split('\n'), key=len, reverse=True):
        j = j.strip()
        if j and os.path.isdir(j):
            os.rmdir(j)


def borra(base):
    def reintenta(fn, p, exc):
        os.chmod(p, stat.S_IWRITE)
        fn(p)
    quita_enlaces(base)
    if os.path.isdir(base):
        shutil.rmtree(base, onexc=reintenta)


borra(BASE)
MINE = os.path.join(BASE, 'mio')          # Roots
OUT = os.path.join(BASE, 'fuera')         # outside everything
VIC = os.path.join(OUT, 'victima')
os.makedirs(MINE)
os.makedirs(VIC)
open(os.path.join(VIC, 'v.txt'), 'w').write('fuera')

# the fixture repo (git directly: the scaffolding, not what is measured)
REPO = os.path.join(MINE, 'repo')
os.makedirs(REPO)


def g(*a, cwd=REPO):
    return subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *a],
                          cwd=cwd, capture_output=True, text=True)


g('init', '-q')
open(os.path.join(REPO, '.gitignore'), 'w').write('Compiled/\n')
open(os.path.join(REPO, 'version.txt'), 'w').write('uno')
g('add', '-A')
g('commit', '-qm', 'uno')
g('tag', 'v1')
open(os.path.join(REPO, 'version.txt'), 'w').write('dos')
g('commit', '-qam', 'dos')

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        print('  FAIL', name, '--', str(detail)[:300])


class Server:
    def __init__(self, env):
        e = {k: v for k, v in os.environ.items() if not k.startswith('DELPHI_MCP_')}
        e.update(env)
        self.proc = subprocess.Popen([EXE], env=e, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, encoding='utf-8',
                                     errors='replace', bufsize=1)
        self.q = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()
        self.n = 0
        self.send({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize', 'params': {
            'protocolVersion': '2025-03-26', 'capabilities': {},
            'clientInfo': {'name': 'bateria-git-worktree', 'version': '1'}}})
        self.recv(0)
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def _reader(self):
        for line in self.proc.stdout:
            self.q.put(line)

    def send(self, o):
        self.proc.stdin.write(json.dumps(o) + '\n')
        self.proc.stdin.flush()

    def recv(self, rid, t=180):
        end = time.time() + t
        while time.time() < end:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == rid:
                return m
        return {'error': 'timeout'}

    def call(self, name, args, t=180):
        self.n += 1
        self.send({'jsonrpc': '2.0', 'id': self.n, 'method': 'tools/call',
                   'params': {'name': name, 'arguments': args}})
        r = self.recv(self.n, t)
        if 'error' in r:
            return 'MCPERROR: ' + json.dumps(r['error'])
        c = r['result'].get('content', [])
        return c[0].get('text', '') if c else '(no content)'

    def kill(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        time.sleep(0.5)
        self.proc.kill()


def rechazado(out):
    # RECHAZADO de la tool: un 'error: unknown command' de un servidor sin
    # worktree no cuenta (pasaria por el motivo equivocado)
    return out.startswith('RECHAZADO')


print('== git-worktree battery ==')
srv = Server({'DELPHI_MCP_ROOTS': MINE})


def wt(**kw):
    return srv.call('delphi_git', dict(repo=REPO, command='worktree', **kw))


WT = os.path.join(MINE, 'repo-v1')
out = wt(args='list')
check('list: solo la copia principal', out.startswith('exit=0') and 'repo-v1' not in out, out)
out = wt(args='add', path=WT, ref='v1')
check('add: crea la copia con la version v1', out.startswith('exit=0') and os.path.isfile(os.path.join(WT, 'version.txt'))
      and open(os.path.join(WT, 'version.txt')).read() == 'uno', out)
check('add: dice que es suya de limpiar y como', 'args=remove' in out, out)
check('...y el arbol principal sigue en su version', open(os.path.join(REPO, 'version.txt')).read() == 'dos', '')
out = wt(args='list')
check('list: la ensena', 'repo-v1' in out, out)

# ---- add: what is refused
out = wt(args='add', path=WT, ref='v1')
check('add a una carpeta que ya existe: RECHAZADO', rechazado(out) and 'ya existe' in out, out)
out = wt(args='add', path=os.path.join(OUT, 'wt'), ref='v1')
check('add fuera de las raices: RECHAZADO', rechazado(out) and not os.path.exists(os.path.join(OUT, 'wt')), out)
out = wt(args='add', path=os.path.join(REPO, 'dentro'), ref='v1')
check('add dentro del propio repo: RECHAZADO', rechazado(out) and not os.path.exists(os.path.join(REPO, 'dentro')), out)
out = wt(args='add', path=os.path.join(MINE, '__delphi-temp', 'wt'), ref='v1')
check('add en una carpeta muerta: RECHAZADO', rechazado(out) and not os.path.exists(os.path.join(MINE, '__delphi-temp', 'wt')), out)
for ref in ('-x', 'v1;dir', 'v1 --orphan', ''):
    out = wt(args='add', path=os.path.join(MINE, 'r'), ref=ref)
    check('add con ref raro: RECHAZADO (%r)' % ref, rechazado(out) and not os.path.exists(os.path.join(MINE, 'r')), out)
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(MINE, 'aFuera'), OUT], capture_output=True)
out = wt(args='add', path=os.path.join(MINE, 'aFuera', 'wt'), ref='v1')
check('add a traves de un junction a fuera: RECHAZADO (ruta real)', rechazado(out)
      and not os.path.exists(os.path.join(OUT, 'wt')), out)
out = wt(args='nada')
check('worktree con un args que no es list/add/remove: RECHAZADO', rechazado(out), out)

# ---- remove: only what list shows, never across a link, never with changes
out = wt(args='remove', path=os.path.join(MINE, 'otra'))
check('remove de algo que no es worktree: RECHAZADO', rechazado(out), out)
out = wt(args='remove', path=REPO)
check('remove de la copia principal: RECHAZADO', rechazado(out) and os.path.isdir(REPO), out)
os.makedirs(os.path.join(WT, 'Compiled'))
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(WT, 'Compiled', 'aFuera'), VIC], capture_output=True)
check('fixture: junction a la victima en una carpeta ignorada del worktree',
      os.path.isjunction(os.path.join(WT, 'Compiled', 'aFuera')), '')
out = wt(args='remove', path=WT)
check('remove con un enlace dentro: RECHAZADO', rechazado(out) and 'enlace' in out and os.path.isdir(WT), out)
check('...y la victima de fuera sigue intacta', os.listdir(VIC) == ['v.txt'], os.listdir(VIC))
os.rmdir(os.path.join(WT, 'Compiled', 'aFuera'))   # quita el ENLACE, nunca lo de detras
open(os.path.join(WT, 'version.txt'), 'w').write('cambiado')
out = wt(args='remove', path=WT)
check('remove con cambios: git se niega (sin forzar) y la copia sigue', out.startswith('exit=')
      and not out.startswith('exit=0') and os.path.isdir(WT), out)
g('checkout', '--', 'version.txt', cwd=WT)
out = wt(args='remove', path=WT)
check('remove limpio: quitado', out.startswith('exit=0') and not os.path.exists(WT), out)
out = wt(args='list')
check('list: ya no la ensena', out.startswith('exit=0') and 'repo-v1' not in out, out)
check('la victima de fuera sigue intacta al final', os.listdir(VIC) == ['v.txt'], os.listdir(VIC))
srv.kill()

# ---- read-only mode (local stdio with no roots): list yes, add no
ro = Server({})
out = ro.call('delphi_git', {'repo': REPO, 'command': 'worktree', 'args': 'list'})
check('solo lectura: list SI', out.startswith('exit=0'), out)
out = ro.call('delphi_git', {'repo': REPO, 'command': 'worktree', 'args': 'add',
                             'path': os.path.join(MINE, 'ro-wt'), 'ref': 'v1'})
check('solo lectura: add RECHAZADO', rechazado(out) and not os.path.exists(os.path.join(MINE, 'ro-wt')), out)
ro.kill()

borra(BASE)
print()
print('== git-worktree battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
