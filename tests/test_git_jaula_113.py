"""Jaula de git: consulta remota, raiz enlazada y decisiones previas a ejecutar."""
import os, subprocess, uuid, hashlib
import mcp_cliente as mc
from mcp_cliente import check
BASE = mc.carpeta('git-jaula-113')
MINE = os.path.join(BASE, 'mio')
OUT = os.path.join(BASE, 'victima')
os.makedirs(MINE)
os.makedirs(OUT)
REPO = os.path.join(MINE, 'repo')
REMOTE = os.path.join(MINE, 'remote.git')
os.makedirs(REPO)
def git(*a, cwd=REPO):
    r = subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *a],
                       cwd=cwd, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout
git('init', '-q', '-b', 'main')
open(os.path.join(REPO, 'uno.txt'), 'w').write('uno')
git('add', '.')
git('commit', '-qm', 'uno')
git('clone', '-q', '--bare', REPO, REMOTE, cwd=MINE)
git('remote', 'add', 'origin', REMOTE)
BARE = os.path.join(MINE, 'bare.git')
git('clone', '-q', '--bare', REPO, BARE, cwd=MINE)
SUB = os.path.join(BARE, 'sub')
os.makedirs(SUB)
DEP = os.path.join(OUT, 'dependencia')
os.makedirs(DEP)
git('init', '-q', '-b', 'main', cwd=DEP)
open(os.path.join(DEP, 'privado.txt'), 'w').write('intacto')
git('add', '.', cwd=DEP)
git('commit', '-qm', 'privado', cwd=DEP)
git('-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', DEP, 'modulo')
git('commit', '-qam', 'modulo')
git('push', '-q', 'origin', 'main')
git('config', 'fetch.recurseSubmodules', 'true')
# Tambien un ajuste propio del submodulo: la opcion de la orden manda.
git('config', 'submodule.modulo.fetchRecurseSubmodules', 'true')
def snapshot(root):
    return {os.path.relpath(os.path.join(d, n), root):
            hashlib.sha256(open(os.path.join(d, n), 'rb').read()).hexdigest()
            for d, _, ns in os.walk(root) for n in ns}
FETCH_MOD = os.path.join(REPO, '.git', 'modules', 'modulo', 'FETCH_HEAD')
if os.path.exists(FETCH_MOD):
    os.remove(FETCH_MOD)
TRACE = os.path.join(BASE, 'git.trace')
LINK = os.path.join(MINE, 'enlace')
check('fixture junction hacia victima fuera', mc.junction(LINK, OUT))
open(os.path.join(OUT, 'no_tocar.txt'), 'w').write('intacto')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
before = snapshot(OUT)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE,
    'GIT_ALLOW_PROTOCOL': 'file', 'GIT_TRACE': TRACE}), nombre='git-jaula-113', t=180)
try:
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'ls-remote', 'args': 'origin'})
    check('ls-remote local autorizado contesta las refs', out.startswith('exit=0') and 'refs/heads/main' in out, out)
    check('ls-remote no escribe FETCH_HEAD', not os.path.exists(os.path.join(REPO, '.git', 'FETCH_HEAD')))
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'ls-remote', 'args': LINK})
    check('ls-remote hacia victima rechazado sin nombrar sus ficheros',
          mc.es(out, 'SR_GIT_REMOTO_FUERA_FMT') and 'no_tocar' not in out, out)
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'ls-remote', 'args': 'https://no-permitido.invalid/r.git'})
    check('ls-remote conserva la lista de hosts', mc.es(out, 'SR_GIT_REMOTE_OFF_FMT'), out)
    lst = srv.request('tools/list')['result']['tools']
    meta = next(x for x in lst if x['name'] == 'delphi_git')['_meta']
    check('ls-remote anunciado como consulta', 'ls-remote' in meta['readOnlyCommands'], meta)
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'status'})
    check('status control dentro de la jaula', out.startswith('exit=0'), out)
    out = srv.call('delphi_git', {'repo': SUB, 'command': 'fetch', 'args': '../../remote.git'})
    check('bare desde subcarpeta resuelve el remoto como Git', out.startswith('exit=0'), out)
    for cmd, args in (('fetch', 'origin'), ('pull', 'origin main')):
        if os.path.exists(FETCH_MOD):
            os.remove(FETCH_MOD)
        open(TRACE, 'w').close()
        out = srv.call('delphi_git', {'repo': REPO, 'command': cmd, 'args': args})
        trace = mc.lee(TRACE)
        check(cmd + ': no consulta el submodulo fuera', out.startswith('exit=0') and
              'Fetching submodule' not in out and not os.path.exists(FETCH_MOD), out)
        network = [s for s in trace.splitlines() if 'built-in: git ' in s and
                   (' fetch ' in s or ' pull ' in s)]
        check(cmd + ': todas las ordenes de red prohiben recursion',
              bool(network) and all('--no-recurse-submodules' in s or
                                    '--recurse-submodules=no' in s for s in network), network)
        if cmd == 'pull':
            check('pull mide tambien su fetch previo', any(' fetch ' in s for s in network), network)
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'fetch', 'args': 'origin inexistente'})
    check('fallo de Git real se distingue del rechazo previo', mc.es(out, 'SR_GIT_EXIT_FMT') and
          'couldn' in out, out)
    check('victima intacta', snapshot(OUT) == before)
finally:
    srv.cierra()
    os.rmdir(LINK)
ALIAS = os.path.join(BASE, 'raiz_enlazada')
check('fixture raiz declarada enlazada', mc.junction(ALIAS, REPO))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': ALIAS}), nombre='git-raiz-enlazada')
try:
    out = srv.call('delphi_git', {'repo': ALIAS, 'command': 'status'})
    check('raiz declarada por junction conserva su forma', out.startswith('exit=0'), out)
finally:
    srv.cierra()
    os.rmdir(ALIAS)
PORT = mc.puerto_libre()
RW, RO = uuid.uuid4().hex, uuid.uuid4().hex
with open(os.path.join(os.path.dirname(EXE), 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n'
            '[Workspace.Op]\nToken=%s\nReadOnlyToken=%s\nRoots=%s\n'
            % (PORT, RW, RO, MINE))
proc = mc.lanza_http(EXE, None, mc.entorno(), espera_en=PORT)
try:
    srv = mc.Http(PORT, RO)
    srv.session('git-jaula-113-ro')
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'init'})
    check('control: la credencial RO deniega una escritura', mc.rechazado(out), out)
    out = srv.call('delphi_git', {'repo': REPO, 'command': 'ls-remote', 'args': 'origin'})
    check('ls-remote funciona con credencial de solo lectura', out.startswith('exit=0') and 'refs/heads/main' in out, out)
finally:
    proc.terminate()
    proc.wait(timeout=20)
check('victima intacta tras todos los clientes', snapshot(OUT) == before)
mc.fin('git jaula 113')
