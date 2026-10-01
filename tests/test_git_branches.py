"""E2E battery for v0.57.0-beta - delphi_git branch workflow: switch, merge
(--ff-only) and stash. Deep review 2026-08-25: an agent could CREATE a branch
and never move to it, so it could not work the way a programmer does (branch
per task, commit, back to main).

Usage:  python tests/test_git_branches.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess
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
check('merge no fast-forward RECHAZADO (no lo deja a medias)', mc.abre(r, 'SR_GIT_EXIT_FMT'), r[:250])

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
      mc.rechazado(r) and mc.es(r, 'SR_GIT_STASH_ARGS_FMT') and 'args="drop"' in r, r[:200])

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
      mc.rechazado(r) and mc.es(r, 'SR_GIT_STASH_ARGS_FMT') and 'args="push -u"' in r, r[:200])
r = git({'command': 'stash', 'args': 'push -- ../fuera.txt'})
check('stash push -- <ruta FUERA del repo> rechazado, y no guarda nada',
      mc.rechazado(r) and mc.es(r, 'SR_GIT_STASH_RUTA_FMT') and
      git({'command': 'stash', 'args': 'list'}) == antes and
      'descartable' in leer('a.txt'), r[:200])
r = git({'command': 'stash', 'args': 'push -- "*.txt"'})
check('stash push -- <comodin> rechazado: un comodin no es un nombre',
      mc.rechazado(r) and mc.es(r, 'SR_GIT_STASH_RUTA_FMT') and
      'descartable' in leer('a.txt') and 'se queda' in leer('d.txt'), r[:200])
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'lo de antes del stash con rutas'})

# ---- restore: deshacer un add sin tocar el arbol (1.7.6) ----
# Hermes (28-sep-2026): sin rm ni reset en la lista, tras un add no habia forma de
# deshacer el staging por el MCP y borro el .git para volver a empezar.
open(os.path.join(REPO_T, 'e.txt'), 'w').write('nuevo\n')
open(os.path.join(REPO_T, 'a.txt'), 'a').write('cambio en a\n')
git({'command': 'add', 'args': '.'})
r = git({'command': 'restore', 'args': 'e.txt'})
st = git({'command': 'status', 'args': '--porcelain'})
check('restore <ruta>: sale del indice y el fichero sigue en el arbol',
      'exit=0' in r and os.path.exists(os.path.join(REPO_T, 'e.txt')) and '?? e.txt' in st and 'M  a.txt' in st,
      r[:120] + ' | ' + st[:120])
r = git({'command': 'restore', 'args': '.'})
st = git({'command': 'status', 'args': '--porcelain'})
check('restore .: nada staged y los cambios siguen en el arbol',
      'exit=0' in r and ' M a.txt' in st and 'cambio en a' in leer('a.txt'), r[:120] + ' | ' + st[:120])
r = git({'command': 'restore'})
check('restore sin rutas: rechazado (no adivina)', mc.rechazado(r) and mc.es(r, 'SR_GIT_RESTORE_ARGS_FMT'), r[:200])
r = git({'command': 'restore', 'args': '--worktree a.txt'})
check('restore con una opcion: rechazado (nunca toca el arbol)',
      mc.rechazado(r) and mc.es(r, 'SR_GIT_RESTORE_ARGS_FMT') and 'cambio en a' in leer('a.txt'), r[:200])
r = git({'command': 'restore', 'args': '../fuera.txt'})
check('restore <ruta fuera del repo>: rechazado', mc.rechazado(r) and mc.es(r, 'SR_GIT_RESTORE_RUTA_FMT'), r[:200])
r = git({'command': 'restore', 'args': '*.txt'})
check('restore <comodin>: rechazado (un comodin no es un nombre)', mc.rechazado(r) and mc.es(r, 'SR_GIT_RESTORE_RUTA_FMT'), r[:200])
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'tras el restore'})

# ---- contratos ----
r = git({'command': 'switch'})
check('switch sin rama rechazado con pista',
      mc.rechazado(r) and mc.es(r, 'SR_GIT_SWITCH_NEEDS') and 'stash' in r, r[:250])
r = git({'command': 'merge'})
check('merge sin rama rechazado', mc.rechazado(r) and mc.es(r, 'SR_GIT_MERGE_NEEDS'), r[:200])
r = git({'command': 'switch', 'args': 'tarea-1; rm -rf /'})
check('metacaracteres rechazados',
      mc.fallo(r) and mc.es(r, 'SR_GIT_SHELL_METACHARS_ARGS'), r[:200])

# ---- pull: siempre por fast-forward, como merge (1.7.7) ----
# pull es bajar e INTEGRAR, y lo segundo lo hacia como git quisiera: con las
# dos historias divergidas, sin ninguna opcion, dejaba un commit de mezcla
# (lo que merge promete aqui que no puede pasar); con --rebase reescribia la
# historia y con --squash dejaba el arbol a medias. Medido el 29-sep-2026.
# El remoto es una carpeta de la bateria: lo monta el git de la maquina.
def fuera(*a, cwd):
    r = subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@example.com'] + list(a),
                       cwd=cwd, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def cabeza():
    return fuera('rev-parse', 'HEAD', cwd=REPO_T)


ORIGEN = os.path.join(BASE, 'origen.git')
OTRO = os.path.join(BASE, 'otro')
rama = fuera('branch', '--show-current', cwd=REPO_T)
fuera('clone', '-q', '--bare', REPO_T, ORIGEN, cwd=BASE)
fuera('remote', 'add', 'origin', ORIGEN, cwd=REPO_T)
fuera('clone', '-q', ORIGEN, OTRO, cwd=BASE)
fuera('switch', '-q', rama, cwd=OTRO)


def llega_al_remoto(nombre, etiqueta=None):
    open(os.path.join(OTRO, nombre), 'w').write('del remoto\n')
    fuera('add', '.', cwd=OTRO)
    fuera('commit', '-qm', 'remoto: ' + nombre, cwd=OTRO)
    if etiqueta:
        fuera('tag', etiqueta, cwd=OTRO)
    return fuera('push', '-q', '--tags', 'origin', rama, cwd=OTRO)


llega_al_remoto('r1.txt')
r = git({'command': 'pull', 'args': 'origin ' + rama})
check('pull de lo que va por delante (fast-forward): integra',
      'exit=0' in r and os.path.exists(os.path.join(REPO_T, 'r1.txt')), r[:250])
llega_al_remoto('r2.txt', 'v-remoto')
r = git({'command': 'pull', 'args': '--tags origin ' + rama})
check('pull con una opcion de la BAJADA (--tags): integra y trae la etiqueta',
      'exit=0' in r and os.path.exists(os.path.join(REPO_T, 'r2.txt'))
      and 'v-remoto' in git({'command': 'tag'}), r[:250])
# ahora DIVERGEN: el remoto avanza por un lado y el repo por otro
llega_al_remoto('r3.txt')
open(os.path.join(REPO_T, 'local.txt'), 'w').write('local\n')
git({'command': 'add', 'args': '.'})
git({'command': 'commit', 'message': 'local, por su lado'})
partida = cabeza()
r = git({'command': 'pull', 'args': 'origin ' + rama})
check('pull con las historias DIVERGIDAS: rechazado, sin commit de mezcla y sin dejarlo a medias',
      mc.abre(r, 'SR_GIT_EXIT_FMT') and mc.es(r, 'SN_GIT_MERGE_DIVERGED') and cabeza() == partida
      and not os.path.exists(os.path.join(REPO_T, '.git', 'MERGE_HEAD'))
      and not os.path.exists(os.path.join(REPO_T, 'r3.txt')), r[:300])
mal = []
for opcion in ('--rebase', '-r', '--no-rebase', '--no-ff', '--squash', '--no-commit', '--autostash'):
    r = git({'command': 'pull', 'args': '%s origin %s' % (opcion, rama)})
    limpio = git({'command': 'status', 'args': '--porcelain'})
    if not (mc.rechazado(r) and mc.es(r, 'SR_GIT_PULL_ARGS_FMT') and cabeza() == partida
            and 'r3.txt' not in limpio):
        mal.append('%s: %s | %s' % (opcion, ' '.join(r.split())[:120], ' '.join(limpio.split())[:60]))
        fuera('rebase', '--abort', cwd=REPO_T)
        fuera('merge', '--abort', cwd=REPO_T)
        fuera('reset', '-q', '--hard', partida, cwd=REPO_T)
check('pull con una opcion que cambia COMO se integra (rebase, mezcla, squash...): rechazado, y '
      'la historia y el arbol como estaban', not mal, mal[:3])

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
      mc.rechazado(r) and mc.es(r, 'SR_REFERENCE_ROOT_FMT') and
      'tocado' in leer('ro/x.txt'), r[:200])
r = git({'command': 'stash', 'args': 'push -- a.txt'})
check('...y una ruta escribible del mismo repo si se descarta',
      'exit=0' in r and 'otra vez' not in leer('a.txt'), r[:200])
srv.mata()

# ---- un servidor SIN git (1.8.1) ----
# Medido el 30-sep-2026 en una maquina sin git instalado: init y status
# contestaban "[SYS-006 INTERNAL] Error executing tool: CreateProcess failed
# (2)", que no dice ni que falta ni de quien es el arreglo. El servidor lanza
# git.exe por su nombre y Windows lo busca: con un PATH donde no esta (y sin
# un git.exe junto al exe ni en las carpetas del sistema), esta maquina es
# aquella. TESTIGO: el mismo servidor, con el PATH de la maquina, llega a git.
env_red = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_GIT_REMOTES': 'allowed.example'})
srv = mc.Stdio(EXE, env_red, nombre='gb4')
call = srv.call
r = git({'command': 'status'})
check('TESTIGO: con el PATH de la maquina, status llega a git',
      mc.llego_a_git(r) and not mc.fallo(r), r[:200])
# ---- el CONTENIDO de un diff viaja como esta en el disco (1.9.0) ----
# El enmascarador de unidades reescribia las lineas de un diff como si fueran
# rutas del servidor: '%s:' salia '%srv0:' y un '\\equipo' de un literal,
# '\\srvhost' (visto repasando un diff por la tool). Las lineas de contenido
# (las que empiezan por +, - o espacio) no se tocan; las de git, si.
CONT = "S := Format('%s: %d', [A, B]); P := '\\\\equipo\\f.txt'; Q := 'Z:\\x';"
open(os.path.join(REPO_T, 'cont.pas'), 'w').write('uno\n')
git({'command': 'add', 'args': 'cont.pas'}); git({'command': 'commit', 'message': 'cont'})
open(os.path.join(REPO_T, 'cont.pas'), 'w').write(CONT + '\n')
r = git({'command': 'diff', 'args': 'cont.pas'})
check('diff: las lineas de contenido salen como estan en el disco (ni %srv0: ni \\\\srvhost)',
      'exit=0' in r and ('+' + CONT) in r, r[-300:])
git({'command': 'add', 'args': 'cont.pas'}); git({'command': 'commit', 'message': 'cont 2'})
r = git({'command': 'diff', 'args': 'HEAD~1 HEAD'})
check('...y entre dos commits, lo mismo', 'exit=0' in r and ('+' + CONT) in r, r[-300:])
# ...y el otro lado de la regla: una linea que NO empieza como el contenido
# es de git y se enmascara. El log de la tool pone el mensaje detras del
# hash: esa linea no es contenido
RUTA = BASE[0].upper() + ':\\carpeta\\de\\nadie'
open(os.path.join(REPO_T, 'cont.pas'), 'a').write('otra\n')
git({'command': 'add', 'args': 'cont.pas'}); git({'command': 'commit', 'message': 'mirar ' + RUTA})
r = git({'command': 'log', 'args': '-1'})
check('log: la linea que no empieza como el contenido (hash + mensaje) sigue enmascarada',
      'exit=0' in r and RUTA not in r and ('mirar srv%s:' % BASE[0].lower()) in r, r[:200])
NUEVO = os.path.join(BASE, 'repo-nuevo')
os.makedirs(NUEVO)
r = call('delphi_git', {'repo': NUEVO, 'command': 'init'})
check('(control) ...y lo que dice GIT sigue enmascarado: la ruta del repo, en init, con su unidad virtual',
      'exit=0' in r and (NUEVO[0].upper() + ':') not in r.upper().replace('SRV' + NUEVO[0].upper() + ':', '')
      and ('srv%s:' % NUEVO[0].lower()) in r, r[:300])
# La regla del clone que no ocurrio tiene dos mitades, y la de siempre - git
# ARRANCA y acaba con error - no la media ninguna bateria (revisor de la
# 1.8.1). El host no existe (.example no resuelve nunca): git sale con error.
FALLA = os.path.join(BASE, 'clon-falla', 'dentro')
r = call('delphi_git', {'repo': FALLA, 'command': 'clone', 'message': 'https://allowed.example/a.git'})
check('un clone que git empieza y no acaba (el host no existe) no deja las carpetas que creo',
      mc.abre(r, 'SR_GIT_EXIT_FMT') and not os.path.exists(os.path.dirname(FALLA)),
      '%s | queda: %s' % (' '.join(r.split())[:240], os.path.exists(os.path.dirname(FALLA))))
srv.mata()
env_sin = dict(env_red, PATH=os.path.join(os.environ['SystemRoot'], 'System32'))
srv = mc.Stdio(EXE, env_sin, nombre='gb5')
call = srv.call
r = git({'command': 'status'})
check('sin git en el servidor: status lo DICE, con su etiqueta (no un "CreateProcess failed")',
      mc.abre(r, 'SR_GIT_NO_HAY_GIT_FMT') and mc.resultado(r) == 'INTERNAL' and 'CreateProcess' not in r
      and '(error 2)' in r,
      r[:300])
SIN_GIT = os.path.join(BASE, 'sin-git')
os.makedirs(SIN_GIT)
r = call('delphi_git', {'repo': SIN_GIT, 'command': 'init'})
check('...e init tambien (no pasa por la jaula del repo: otro camino al mismo lanzador)',
      mc.abre(r, 'SR_GIT_NO_HAY_GIT_FMT'), r[:300])
CLON = os.path.join(BASE, 'clon-sin-git', 'dentro')
r = call('delphi_git', {'repo': CLON, 'command': 'clone', 'message': 'https://allowed.example/a.git'})
check('...y un clone que no pudo ni empezar lo dice y no deja las carpetas que creo',
      mc.abre(r, 'SR_GIT_NO_HAY_GIT_FMT') and not os.path.exists(os.path.dirname(CLON)),
      '%s | queda: %s' % (r[:240], os.path.exists(os.path.dirname(CLON))))
r = call('delphi_list', {'root': BASE, 'dirs': True})
check('...y lo que no es git sigue funcionando en ese servidor',
      not mc.fallo(r) and os.path.basename(REPO_T) in r and 'clon-' not in r, r[:300])
srv.mata()
mc.fin('git branches battery')
