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
# ...y el rechazo dice lo que RECIBIO: contestaba "drop no esta" a un push con
# rutas que nadie habia pedido tirar (1.5.1)
check('stash drop NO existe (destruye)',
      'RECHAZADO' in r and 'args="drop"' in r, r[:200])

# ---- stash push con RUTAS: descartar unos ficheros sin perderlos (1.5.1) ----
# Hasta la 1.5.0 no habia forma de devolver UN fichero a HEAD por el MCP (ni
# restore ni stash con rutas): hubo que salir a la consola.
def leer(n):
    return open(os.path.join(REPO_T, n), encoding='utf-8').read()
# el pop de arriba dejo a.txt con cambios: se commitean, para que "a HEAD"
# sea exactamente a0
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'antes del stash con rutas'})
a0 = leer('a.txt')
open(os.path.join(REPO_T, 'a.txt'), 'a').write('descartable\n')
open(os.path.join(REPO_T, 'd.txt'), 'a').write('se queda\n')
r = git({'command': 'stash', 'args': 'push -- a.txt', 'message': 'solo a'})
check('stash push -- <ruta>: SOLO esa vuelve a HEAD',
      'exit=0' in r and leer('a.txt') == a0 and 'se queda' in leer('d.txt'), r[:200])
r = git({'command': 'stash', 'args': 'list'})
check('...con su etiqueta (message) en la lista', 'solo a' in r, r[:200])
r = git({'command': 'stash', 'args': 'pop'})
check('...y pop devuelve lo descartado',
      'exit=0' in r and 'descartable' in leer('a.txt'), r[:200])
antes = git({'command': 'stash', 'args': 'list'})
r = git({'command': 'stash', 'args': 'push -u'})
check('stash push con una OPCION rechazado, diciendo lo que recibio',
      'RECHAZADO' in r and 'args="push -u"' in r, r[:200])
r = git({'command': 'stash', 'args': 'push -- ../fuera.txt'})
check('stash push -- <ruta FUERA del repo> rechazado, y no guarda nada',
      'RECHAZADO' in r and 'no es una ruta de este repositorio' in r and
      git({'command': 'stash', 'args': 'list'}) == antes and
      'descartable' in leer('a.txt'), r[:200])
r = git({'command': 'stash', 'args': 'push -- "*.txt"'})
check('stash push -- <comodin> rechazado: un comodin no es un nombre',
      'RECHAZADO' in r and 'no es una ruta de este repositorio' in r and
      'descartable' in leer('a.txt') and 'se queda' in leer('d.txt'), r[:200])
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'lo de antes del stash con rutas'})

# ---- contratos ----
r = git({'command': 'switch'})
check('switch sin rama rechazado con pista', 'RECHAZADO' in r and 'stash' in r, r[:250])
r = git({'command': 'merge'})
check('merge sin rama rechazado', 'RECHAZADO' in r, r[:200])
r = git({'command': 'switch', 'args': 'tarea-1; rm -rf /'})
check('metacaracteres rechazados', 'RECHAZADO' in r or 'error' in r.lower(), r[:200])

srv.mata()

# ---- stash push con rutas pasa CADA ruta por la puerta de escritura ----
# Devolver un fichero a HEAD es escribirlo: en una carpeta de solo lectura
# (ReadOnlyRoots) dentro del repo, esa ruta se rechaza y las demas no.
os.makedirs(os.path.join(REPO_T, 'ro'), exist_ok=True)
open(os.path.join(REPO_T, 'ro', 'x.txt'), 'w').write('referencia\n')
srv = mc.Stdio(EXE, env, nombre='gb2')
call = srv.call
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'carpeta ro'})
srv.mata()
env_ro = mc.entorno({'DELPHI_MCP_ROOTS': BASE,
                     'DELPHI_MCP_READONLY_ROOTS': os.path.join(REPO_T, 'ro')})
srv = mc.Stdio(EXE, env_ro, nombre='gb3')
call = srv.call
open(os.path.join(REPO_T, 'ro', 'x.txt'), 'a').write('tocado\n')
open(os.path.join(REPO_T, 'a.txt'), 'a').write('otra vez\n')
r = git({'command': 'stash', 'args': 'push -- ro/x.txt'})
# el rechazo de la PUERTA (referencia de solo lectura), no el de la gramatica:
# un servidor que lo rechazase todo pasaba este check
check('stash push -- <ruta de SOLO LECTURA> rechazado por la puerta de escritura',
      r.startswith('RECHAZADO') and 'REFERENCIA' in r and
      'tocado' in leer('ro/x.txt'), r[:200])
r = git({'command': 'stash', 'args': 'push -- a.txt'})
check('...y una ruta escribible del mismo repo si se descarta',
      'exit=0' in r and 'otra vez' not in leer('a.txt'), r[:200])
srv.mata()
mc.fin('git branches battery')
