"""E2E battery for v0.57.0-beta - delphi_git branch workflow: switch, merge
(--ff-only) and stash. Deep review 2026-08-25: an agent could CREATE a branch
and never move to it, so it could not work the way a programmer does (branch
per task, commit, back to main).

Usage:  python tests/test_git_branches.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('gitbranch')
# El servidor, FUERA del repo de prueba: si el repo es la carpeta del exe,
# 'git add .' mete el exe y, desde la 1.5.0, el log vivo (logs/actual.log),
# y cambiar de rama chocaba con el fichero que el servidor esta escribiendo
# (1 de cada 4 pasadas roja, medido 2026-09-26).
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
REPO_T = os.path.join(BASE, 'repo')
os.makedirs(REPO_T)

env = mc.entorno({'DELPHI_MCP_ROOTS': BASE})
srv = mc.Stdio(EXE, env, nombre='gb')
call = srv.call

def git(args): return call('delphi_git', dict({'repo': REPO_T}, **args))

# ---- repo con un commit ----
git({'command': 'init'})
git({'command': 'config', 'args': 'user.name', 'message': 'Probe Bot'})
git({'command': 'config', 'args': 'user.email', 'message': 'probe@example.com'})
open(os.path.join(REPO_T, 'a.txt'), 'w').write('uno\n')
git({'command': 'add', 'args': '.'})
r = git({'command': 'commit', 'message': 'inicial'})
check('commit inicial', 'exit=0' in r, r[:150])

# ---- switch -c: crear rama y MOVERSE (el hueco que cerramos) ----
r = git({'command': 'switch', 'args': 'tarea-1', 'create': True})
check('switch -c crea y cambia', 'exit=0' in r, r[:200])
r = git({'command': 'status'})
check('estamos EN la rama nueva', 'tarea-1' in r, r[:200])

# trabajo en la rama
open(os.path.join(REPO_T, 'b.txt'), 'w').write('trabajo\n')
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'trabajo de la tarea 1'})

# ---- volver a la rama base y fusionar ----
r = git({'command': 'switch', 'args': 'master'})
if 'exit=0' not in r:
    r = git({'command': 'switch', 'args': 'main'})
check('switch de vuelta a la rama base', 'exit=0' in r, r[:200])
check('el fichero de la otra rama NO esta aqui', not os.path.exists(os.path.join(REPO_T, 'b.txt')))
r = git({'command': 'merge', 'args': 'tarea-1'})
check('merge --ff-only integra', 'exit=0' in r, r[:200])
check('y ahora si esta el fichero', os.path.exists(os.path.join(REPO_T, 'b.txt')))

# ---- merge que NECESITARIA commit: rechazado, no a medias ----
git({'command': 'switch', 'args': 'divergente', 'create': True})
open(os.path.join(REPO_T, 'c.txt'), 'w').write('rama\n')
git({'command': 'add', 'args': '.'}); git({'command': 'commit', 'message': 'en divergente'})
r = git({'command': 'switch', 'args': 'master'})
if 'exit=0' not in r: git({'command': 'switch', 'args': 'main'})
open(os.path.join(REPO_T, 'd.txt'), 'w').write('tronco\n')
git({'command': 'add', 'args': '.'}); git({'command': 'commit', 'message': 'en tronco'})
r = git({'command': 'merge', 'args': 'divergente'})
check('merge no fast-forward RECHAZADO (no lo deja a medias)', 'exit=0' not in r, r[:250])

# ---- stash: aparcar para poder cambiar de rama ----
open(os.path.join(REPO_T, 'a.txt'), 'a').write('cambio sin commitear\n')
r = git({'command': 'stash'})
check('stash push aparca', 'exit=0' in r, r[:200])
check('el cambio desaparecio del arbol', 'sin commitear' not in open(os.path.join(REPO_T, 'a.txt')).read())
r = git({'command': 'stash', 'args': 'pop'})
check('stash pop lo recupera', 'exit=0' in r and 'sin commitear' in open(os.path.join(REPO_T, 'a.txt')).read(), r[:200])
r = git({'command': 'stash', 'args': 'drop'})
check('stash drop NO existe (destruye)', 'RECHAZADO' in r, r[:200])

# ---- contratos ----
r = git({'command': 'switch'})
check('switch sin rama rechazado con pista', 'RECHAZADO' in r and 'stash' in r, r[:250])
r = git({'command': 'merge'})
check('merge sin rama rechazado', 'RECHAZADO' in r, r[:200])
r = git({'command': 'switch', 'args': 'tarea-1; rm -rf /'})
check('metacaracteres rechazados', 'RECHAZADO' in r or 'error' in r.lower(), r[:200])

srv.mata()
mc.fin('git branches battery')
