# -*- coding: utf-8 -*-
"""El juez de un NOMBRE de ref y de una REVISION es GIT (9.A, norma 6 del
paisaje: lo medible no se hardcodea). En vez de la regex de EsNombreDeRef:
  - un NOMBRE que el agente escribe (el destino de un refspec de push, el ref
    de worktree add que debe existir) -> git check-ref-format --branch /
    rev-parse --verify --quiet --end-of-options.
Lo que git ACEPTA entra (no ASCII, llaves {}), lo que niega (rangos, x.lock,
-x) se niega, sin lista propia. Y la FORMA del refspec sigue cerrada ANTES de
preguntar a git: un '+' inicial (forzar) y un src vacio (:dst, borrar) se
niegan por la forma, porque check-ref-format ACEPTA '+main' como nombre
(medido 9-oct). "nada de destruccion remota" (David, 29-sep).

Mutante (binario de antes, 4d6c63d): los checks de NO-ASCII / {} que ENTRAN
salen ROJOS (la regex los negaba); los de negacion (+main, :borrar, rangos,
x.lock, -x) siguen verdes (eran guardas ya en la regex).

Control FUERA de las raices: un worktree add a una carpeta de fuera se niega y
la victima de fuera queda intacta.

Uso:  python tests/test_git_refs.py [exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git-refs')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
MINE = os.path.join(BASE, 'mio')      # Roots
OUT = os.path.join(BASE, 'fuera')     # fuera de todo
VIC = os.path.join(OUT, 'victima')
os.makedirs(MINE)
os.makedirs(VIC)
open(os.path.join(VIC, 'v.txt'), 'w').write('fuera')

REPO = os.path.join(MINE, 'repo')
BARE = os.path.join(MINE, 'origin.git')   # el remoto, una carpeta de dentro
os.makedirs(REPO)


def g(*a, cwd=REPO):
    return subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *a],
                          cwd=cwd, capture_output=True, text=True)


g('init', '-q', '-b', 'main')
open(os.path.join(REPO, 'a.txt'), 'w').write('uno')
g('add', '-A')
g('commit', '-qm', 'uno')
open(os.path.join(REPO, 'a.txt'), 'w').write('dos')
g('commit', '-qam', 'dos')
# una rama con llaves: git la acepta (check-ref-format --branch 'x{y}' -> 0),
# la regex vieja la negaba. ASCII, sin lios de codificacion al crearla.
g('branch', 'x{y}')
subprocess.run(['git', 'init', '-q', '--bare', BARE], capture_output=True, text=True)
g('remote', 'add', 'origin', BARE)


def Server(env):
    return mc.Stdio(EXE, mc.entorno(env), nombre='bateria-git-refs',
                    protocolo='2025-03-26', t=180)


srv = Server({'DELPHI_MCP_ROOTS': MINE})


def push(args):
    return srv.call('delphi_git', {'repo': REPO, 'command': 'push', 'args': args})


def wt(**kw):
    return srv.call('delphi_git', dict(repo=REPO, command='worktree', **kw))


def llega(out):
    # la puerta de refs lo dejo pasar a git: corrio (exit=0) o corrio y fallo
    return out.startswith('exit=0') or mc.abre(out, 'SR_GIT_EXIT_FMT')


# ===== push: la FORMA del refspec, cerrada ANTES de git (no destruccion) =====
r = push('origin +main')
check('push "+main" (forzar): negado por la forma, no llega a git',
      mc.es(r, 'SR_GIT_PUSH_NOMBRE_FMT') and not mc.llego_a_git(r), r[:200])
r = push('origin :sobra')
check('push ":sobra" (borrar, src vacio): negado por la forma, no llega a git',
      mc.es(r, 'SR_GIT_PUSH_NOMBRE_FMT') and not mc.llego_a_git(r), r[:200])

# ===== push: lo que git niega, negado (sin regex propia) =====
r = push('origin a..b')
check('push "a..b" (rango): negado',
      mc.es(r, 'SR_GIT_PUSH_NOMBRE_FMT') and not mc.llego_a_git(r), r[:200])
r = push('origin x.lock')
check('push "x.lock": negado',
      mc.es(r, 'SR_GIT_PUSH_NOMBRE_FMT') and not mc.llego_a_git(r), r[:200])

# ===== push: lo que git ACEPTA, entra =====
r = push('origin main')
check('push "main" (nombre): llega a git y empuja (exit=0)', r.startswith('exit=0'), r[:200])
r = push('origin HEAD')
check('push "HEAD" (trozo suelto que vale como REVISION, no como nombre): llega a git',
      llega(r), r[:200])
# NUEVO (la regex negaba las llaves): un destino con {} ENTRA y git lo crea
r = push('origin HEAD:x{y}2')
check('push "HEAD:x{y}2" (destino con llaves): ENTRA y git lo crea (exit=0)',
      r.startswith('exit=0'), r[:200])
# NUEVO: un destino NO ASCII ENTRA (la regex solo A-Za-z0-9)
r = push('origin HEAD:' + 'ñandú')
check('push "HEAD:ñandú" (destino no ASCII): ENTRA y git lo crea (exit=0)',
      r.startswith('exit=0'), r[:200])

# ===== worktree ref: una REVISION que debe EXISTIR, por rev-parse =====
# NUEVO: un ref con {} que EXISTE entra (la regex lo negaba)
WTX = os.path.join(MINE, 'wt-llaves')
r = wt(args='add', path=WTX, ref='x{y}')
check('worktree ref="x{y}" (rama con llaves que existe): ENTRA y git la saca',
      r.startswith('exit=0') and os.path.isfile(os.path.join(WTX, 'a.txt')), r[:200])
r = wt(args='add', path=os.path.join(MINE, 'wt-no'), ref='HEAD~9')
check('worktree ref="HEAD~9" (no existe): negado (rev-parse)',
      mc.es(r, 'SR_GIT_WORKTREE_REF') and not os.path.exists(os.path.join(MINE, 'wt-no')), r[:200])
r = wt(args='add', path=os.path.join(MINE, 'wt-dash'), ref='-x')
check('worktree ref="-x" (empieza por guion): negado (--end-of-options)',
      mc.es(r, 'SR_GIT_WORKTREE_REF') and not os.path.exists(os.path.join(MINE, 'wt-dash')), r[:200])

# ===== control FUERA de las raices =====
r = wt(args='add', path=os.path.join(OUT, 'wt'), ref='main')
check('worktree add FUERA de las raices: negado (control)',
      mc.rechazado(r) and not os.path.exists(os.path.join(OUT, 'wt')), r[:200])
check('la victima de fuera sigue intacta', os.listdir(VIC) == ['v.txt'], os.listdir(VIC))

srv.cierra()
mc.borra(BASE)
mc.fin('git refs (9.A)')
