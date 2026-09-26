"""E2E battery for delphi_git worktree (1.4.0): ANOTHER version of the repo
next to it, so an agent - a remote one above all - can build and compare an
old release without leaving the MCP. Like clone: the agent picks a NEW folder
inside its roots; no temp folders, no cleanups at start. remove takes away
only what list shows, never the main copy, never with changes (no --force)
and never with a link inside: measured 2026-09-26, git worktree remove
crosses a junction in an ignored folder and empties what is behind it.

Usage:  python tests/test_git_worktree.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = os.path.join(mc.RAIZ, 'git-worktree')


def quita_enlaces(base):
    # junctions first, with rmdir (removes the LINK, never its target)
    r = subprocess.run(['cmd', '/c', 'dir', '/AL', '/S', '/B', base], capture_output=True, text=True)
    for j in sorted(r.stdout.split('\n'), key=len, reverse=True):
        j = j.strip()
        if j and os.path.isdir(j):
            os.rmdir(j)


def borra(base):
    # los junctions de DENTRO primero (esta bateria los planta); el resto,
    # objetos de git de solo lectura incluidos, es de mc.borra
    quita_enlaces(base)
    mc.borra(base)


quita_enlaces(BASE)
BASE = mc.carpeta('git-worktree')
# su propia copia del servidor, fuera de las raices (MINE) y de la victima
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
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


def Server(env):
    # el protocolo con el que esta bateria nacio, y su plazo de 180 s
    return mc.Stdio(EXE, mc.entorno(env), nombre='bateria-git-worktree',
                    protocolo='2025-03-26', t=180)


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
srv.cierra()

# ---- read-only mode (local stdio with no roots): list yes, add no
ro = Server({})
out = ro.call('delphi_git', {'repo': REPO, 'command': 'worktree', 'args': 'list'})
check('solo lectura: list SI', out.startswith('exit=0'), out)
out = ro.call('delphi_git', {'repo': REPO, 'command': 'worktree', 'args': 'add',
                             'path': os.path.join(MINE, 'ro-wt'), 'ref': 'v1'})
check('solo lectura: add RECHAZADO', rechazado(out) and not os.path.exists(os.path.join(MINE, 'ro-wt')), out)
ro.cierra()

borra(BASE)
mc.fin('git-worktree battery')
