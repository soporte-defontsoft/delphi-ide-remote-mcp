# -*- coding: utf-8 -*-
"""git no REESCRIBE un fichero de solo lectura DENTRO del repo al cambiar el
arbol (1.18.2, 2x). switch/merge/pull/stash pop reescriben el arbol entero;
solo Raiz/GitDir/Comun pasaban por la puerta, no los ficheros de dentro. Ahora
se le pregunta a git (el juez) que ficheros tocaria (diff --name-only HEAD
<destino>, stash show --name-only) y cada uno pasa por la puerta de siempre
(PathDenied); si alguno es ReadOnlyPaths/ReadOnlyRoots, se niega NOMBRANDOLO.

  X1 ReadOnlyPaths=repo\\U.dfm, b2 cambia U.dfm: switch b2 -> GIT-065 nombrando
     U.dfm, y U.dfm NO cambia
  X2 ReadOnlyRoots=repo\\vendor, b2 cambia vendor\\V.txt: switch b2 -> GIT-065
     nombrando vendor/V.txt, y V.txt NO cambia
  X3 el control: una rama que cambia solo src\\ (sin tocar lo protegido) SI se
     permite y cambia src
  X4 merge --ff-only de b2 con U.dfm protegido: GIT-065, U.dfm intacto
  X5 stash pop que devolveria U.dfm protegido: GIT-065, U.dfm intacto

Las formas que el juez no leia (revision 5.5, medido: las tres reescribian U.dfm
con el juez de la primera version, que solo miraba "switch <un trozo>" y salia
sin negar si git no contestaba). Desde la 1.19.0 no hay args: la rama llega
con tipo (branch=) y git la juzga como nombre (check-ref-format) antes que nada:
  X6 switch - ya no se escribe (branch="-": GIT-071); la rama anterior por el
     nombre que git le da (branch="@{-1}", b2): GIT-065, U.dfm intacto
  X7 switch --detach b2 ya no se escribe (GIT-071), U.dfm intacto; y el juez
     sigue fallando CERRADO: un pull cuyo fetch previo falla (una rama que el
     remoto no tiene) deja el destino sin leer y, en un repo con un lugar
     protegido dentro, se NIEGA (GIT-066), U.dfm intacto
  X8 switch -c nb b2 (create con punto de partida) ya no se escribe:
     branch="nb b2" create=true -> GIT-071, U.dfm intacto
  X9 el control de X8: switch -c nb2 (sin punto de partida) no mueve el arbol y
     se permite
  X10 el control de X7: el mismo pull en un repo SIN nada protegido dentro no
     se juzga y llega a git, que dice que no encuentra la rama (el fallo
     cerrado es solo donde hay algo que proteger)
  X11 lo mismo con el repo SIENDO la raiz del workspace: la raiz no es "algo
     protegido dentro" (ASoloDentro); llega a git
  X12 una rama que se llama como el fichero protegido (U.dfm): el juez pregunta
     "diff HEAD U.dfm --" (sin el -- git no sabe si es rama o ruta y no
     contesta) -> GIT-065 nombrando U.dfm

No medible aqui, y por eso una GUARDA (sigue verde con su mutante): que un git
que no contesta sea un "no". Con el -- de X12, todo destino que git no sabe
leer tambien hace fallar la operacion misma; queda para un git que se cuelga.

El remoto de X7, X10 y X11 es un repo bare de la jaula, sin red (el de X11,
dentro del propio repo: la raiz es el repo). Lo demas no lo necesita: basta
la historia del repo.

Uso:  python tests/test_git_reescribe_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_reescribe_1182')
JAIL = os.path.join(BASE, 'jail')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def nuevo_repo(nombre):
    """Un repo con main (U.dfm, vendor/V.txt, src/S.txt) y una rama b2 que
    cambia los tres. Devuelve la carpeta del repo."""
    repo = os.path.join(JAIL, nombre)
    os.makedirs(os.path.join(repo, 'vendor'))
    os.makedirs(os.path.join(repo, 'src'))

    def git(*a):
        subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@e.com'] + list(a),
                       cwd=repo, capture_output=True, text=True)

    def w(rel, txt):
        open(os.path.join(repo, rel.replace('/', os.sep)), 'w').write(txt)
    w('U.dfm', 'EN_MAIN\n'); w('vendor/V.txt', 'VENDOR_MAIN\n'); w('src/S.txt', 'SRC_MAIN\n')
    git('init', '-q', '-b', 'main'); git('add', '.'); git('commit', '-qm', 'base')
    git('switch', '-qc', 'b2')
    w('U.dfm', 'DE_B2\n'); w('vendor/V.txt', 'VENDOR_B2\n'); w('src/S.txt', 'SRC_B2\n')
    git('add', '.'); git('commit', '-qm', 'b2')
    git('switch', '-qc', 'solosrc', 'main')
    w('src/S.txt', 'SRC_SOLO\n')
    git('add', '.'); git('commit', '-qm', 'solosrc')
    git('switch', '-q', 'main')
    return repo, git


def con_remoto(repo, bare):
    """origin = un clon bare del repo en la carpeta bare (dentro de la raiz):
    el pull de X7/X10/X11 sin red."""
    subprocess.run(['git', 'clone', '-q', '--bare', repo, bare], capture_output=True, text=True)
    subprocess.run(['git', 'remote', 'add', 'origin', bare], cwd=repo, capture_output=True, text=True)


def arranca(ro_paths='', ro_roots='', raiz=JAIL):
    env = {'DELPHI_MCP_ROOTS': raiz}
    if ro_paths:
        env['DELPHI_MCP_READONLY_PATHS'] = ro_paths
    if ro_roots:
        env['DELPHI_MCP_READONLY_ROOTS'] = ro_roots
    return mc.Stdio(EXE, mc.entorno(env), nombre='git-reescribe', t=120)


def lee(repo, rel):
    p = os.path.join(repo, rel.replace('/', os.sep))
    return open(p).read().strip() if os.path.exists(p) else '<no esta>'


# --------- X1: ReadOnlyPaths dentro del repo, switch lo tocaria
repo, _ = nuevo_repo('r1')
srv = arranca(ro_paths=os.path.join(repo, 'U.dfm'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'b2'})
    check('X1 switch a una rama que cambia un ReadOnlyPaths: GIT-065 nombrando U.dfm, y U.dfm intacto',
          mc.abre(r, 'SR_GIT_REESCRIBE_PROTEGIDO_FMT') and 'U.dfm' in r and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
    # X3 el control, sobre el MISMO servidor: una rama que cambia solo src/ pasa
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'solosrc'})
    check('X3 el control: switch a una rama que cambia solo src/ (nada protegido) se permite y cambia src',
          not mc.rechazado(r) and lee(repo, 'src/S.txt') == 'SRC_SOLO', (r[:200], lee(repo, 'src/S.txt')))
finally:
    srv.cierra()

# --------- X2: ReadOnlyRoots=vendor, switch lo tocaria
repo, _ = nuevo_repo('r2')
srv = arranca(ro_roots=os.path.join(repo, 'vendor'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'b2'})
    check('X2 switch a una rama que cambia un fichero de ReadOnlyRoots: GIT-065 nombrando vendor/V.txt, y V.txt intacto',
          # el FICHERO protegido, no 'vendor' (el texto de GIT-065 dice "a vendor"
          # siempre), y no los que no lo son (revisor de baterias, 18-oct-2026)
          mc.abre(r, 'SR_GIT_REESCRIBE_PROTEGIDO_FMT') and 'vendor/V.txt' in r.replace('\\\\', '/').replace('\\', '/')
          and 'U.dfm' not in r and 'src/S.txt' not in r.replace('\\\\', '/').replace('\\', '/') and
          lee(repo, 'vendor/V.txt') == 'VENDOR_MAIN', (r[:260], lee(repo, 'vendor/V.txt')))
finally:
    srv.cierra()

# --------- X4: merge --ff-only
repo, _ = nuevo_repo('r4')
srv = arranca(ro_paths=os.path.join(repo, 'U.dfm'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'merge', 'branch': 'b2'})
    check('X4 merge --ff-only de una rama que cambia un ReadOnlyPaths: GIT-065, U.dfm intacto',
          mc.abre(r, 'SR_GIT_REESCRIBE_PROTEGIDO_FMT') and lee(repo, 'U.dfm') == 'EN_MAIN', (r[:260], lee(repo, 'U.dfm')))
finally:
    srv.cierra()

# --------- X5: stash pop
repo, g = nuevo_repo('r5')
# en main, un cambio sin commit en U.dfm, aparcado; pop lo devolveria
open(os.path.join(repo, 'U.dfm'), 'w').write('CAMBIO_LOCAL\n')
g('stash', 'push', '-q')
srv = arranca(ro_paths=os.path.join(repo, 'U.dfm'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'stash', 'action': 'pop'})
    check('X5 stash pop que devolveria un ReadOnlyPaths: GIT-065, U.dfm intacto (sigue en HEAD)',
          mc.abre(r, 'SR_GIT_REESCRIBE_PROTEGIDO_FMT') and lee(repo, 'U.dfm') == 'EN_MAIN', (r[:260], lee(repo, 'U.dfm')))
finally:
    srv.cierra()

# --------- X6-X9: las formas que el juez no leia, con U.dfm protegido
repo, g = nuevo_repo('r6')
con_remoto(repo, os.path.join(JAIL, 'r6.git'))
srv = arranca(ro_paths=os.path.join(repo, 'U.dfm'))
try:
    # cada check desde main limpio: el rojo de uno no arrastra a los demas
    # (con su mutante, X7 reescribe U.dfm y X8/X9 lo leian ya cambiado)
    # la rama anterior (@{-1}) tiene que ser b2
    g('switch', '-q', '-f', 'b2'); g('switch', '-q', '-f', 'main')
    # 1.19.0: "switch -" ya no se escribe ("-" no es un nombre de rama: GIT-071);
    # la rama anterior es @{-1}, que git admite como nombre, y el juez la lee
    r0 = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': '-'})
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': '@{-1}'})
    check('X6 switch - ya no se escribe (GIT-071); la rama anterior como @{-1} cambia un ReadOnlyPaths: '
          'GIT-065 nombrando U.dfm, y U.dfm intacto',
          mc.abre(r0, 'SR_GIT_NOMBRE_NO_VALE_FMT') and mc.abre(r, 'SR_GIT_REESCRIBE_PROTEGIDO_FMT')
          and 'U.dfm' in r and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r0[:160], r[:260], lee(repo, 'U.dfm')))
    g('switch', '-q', '-f', 'main')
    # 1.19.0: sin args; --detach ni se puede escribir (no es un nombre: GIT-071)
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': '--detach b2'})
    check('X7 switch --detach b2 ya no se escribe: GIT-071, U.dfm intacto',
          mc.abre(r, 'SR_GIT_NOMBRE_NO_VALE_FMT') and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
    g('switch', '-q', '-f', 'main')
    # el fallo CERRADO del juez (GIT-066), con lo que queda sin leer en 1.19.0:
    # el fetch previo de un pull de una rama que el remoto no tiene falla, y
    # el destino (FETCH_HEAD) no es el del pull
    r = srv.call('delphi_git', {'repo': repo, 'command': 'pull', 'remote': 'origin', 'branch': 'noexiste'})
    check('X7 ...y el juez falla CERRADO: un pull cuyo destino no lee (su fetch previo fallo) en un repo con '
          'algo protegido dentro: GIT-066, U.dfm intacto',
          mc.abre(r, 'SR_GIT_REESCRIBE_SIN_JUEZ_FMT') and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
    g('switch', '-q', '-f', 'main')
    # 1.19.0: create con punto de partida ya no se escribe ("nb b2" no es un nombre)
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'nb b2', 'create': True})
    check('X8 switch -c nb b2 (create con punto de partida) ya no se escribe: GIT-071, U.dfm intacto',
          mc.abre(r, 'SR_GIT_NOMBRE_NO_VALE_FMT') and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
    g('switch', '-q', '-f', 'main')
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'nb2', 'create': True})
    check('X9 el control: switch -c nb2 (sin punto de partida, el arbol no se mueve) se permite',
          r.startswith('exit=0') and lee(repo, 'U.dfm') == 'EN_MAIN', (r[:260], lee(repo, 'U.dfm')))
finally:
    srv.cierra()

# --------- X10: el control de X7, en un repo SIN nada protegido dentro
repo, _ = nuevo_repo('r10')
con_remoto(repo, os.path.join(JAIL, 'r10.git'))
srv = arranca()
try:
    # 1.19.0: el control del fallo cerrado es el pull de X7 (--detach ya no se escribe)
    r = srv.call('delphi_git', {'repo': repo, 'command': 'pull', 'remote': 'origin', 'branch': 'noexiste'})
    check('X10 el control: el pull de X7 en un repo sin nada protegido dentro no se juzga y llega a git, '
          'que dice que no encuentra la rama',
          mc.abre(r, 'SR_GIT_EXIT_FMT') and 'noexiste' in r and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
finally:
    srv.cierra()

# --------- X11: el repo ES la raiz, sin nada protegido dentro
repo, _ = nuevo_repo('r11')
# el remoto, dentro del propio repo: la raiz de la sesion es el repo
con_remoto(repo, os.path.join(repo, 'remoto.git'))
srv = arranca(raiz=repo)
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'pull', 'remote': 'origin', 'branch': 'noexiste'})
    check('X11 el control: el repo ES la raiz y no hay nada protegido dentro: el pull de X7 llega a git',
          mc.abre(r, 'SR_GIT_EXIT_FMT') and 'noexiste' in r and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
finally:
    srv.cierra()

# --------- X12: una rama que se llama como el fichero protegido
repo, g = nuevo_repo('r12')
g('branch', 'U.dfm', 'b2')
srv = arranca(ro_paths=os.path.join(repo, 'U.dfm'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'U.dfm'})
    check('X12 una rama llamada U.dfm (como el protegido): el juez la lee como rama (--) -> GIT-065 nombrando U.dfm',
          mc.abre(r, 'SR_GIT_REESCRIBE_PROTEGIDO_FMT') and 'U.dfm' in r and lee(repo, 'U.dfm') == 'EN_MAIN',
          (r[:260], lee(repo, 'U.dfm')))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('git no reescribe un protegido 1182')
