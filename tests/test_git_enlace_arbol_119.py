# -*- coding: utf-8 -*-
"""delphi_git con un ENLACE dentro del arbol de trabajo (1.19.0; revision A
del cierre, 14-oct-2026). CLAUDE.md: "Nothing outside the workspace is ever
written" y "toda tool que escribe una carpeta, con su bateria de junction a
una victima de fuera".

git atraviesa un junction como si fuera una carpeta: add mete lo de detras
en el indice (LEE fuera de las raices) y switch, merge, pull y stash lo
reescriben o lo borran (unpack_trees ESCRIBE fuera). La puerta del repo
mira sus tres carpetas (raiz, .git, comun), no el arbol. Medido contra la
1.18.3+ (produccion 04141de): add paths=["."] metia victima\\v.txt en el
indice; switch borraba el fichero de detras; merge y pull creaban uno; stash
push y pop lo reescribian.

Desde la 1.19.0, antes de toda orden que RECORRE (status, diff, add) o
REESCRIBE (switch de rama, merge, pull, stash push y pop) el arbol, el
servidor lo recorre el mismo con el recorredor del guard (.git aparte): un
enlace cuyo destino real esta sesion no puede leer (las que recorren) o
escribir (las que reescriben) niega la orden con GIT-076 antes de lanzar
git y antes de la red. Un enlace a un sitio de las raices se admite, y lo
de detras se recorre tambien (el enlace detras de un enlace cuenta). Una
carpeta del arbol que no se deja listar para la orden (GUARD-040). Lo que
no toca el arbol (log, branch, stash list, restore --staged, switch create)
sigue funcionando con el enlace ahi.

  E1  fixture: Windows sigue el junction
  E2  status: GIT-076 y no nombra lo de detras
  E3  add paths=["."]: GIT-076, indice limpio, victima intacta
  E4  add paths=["enlace"]: negado, indice limpio
  E5  diff: GIT-076
  E6  switch branch=main con HEAD que tiene el fichero de detras: GIT-076,
      el fichero sigue, HEAD no cambia
  E7  merge branch=conlink desde main: GIT-076, nada nuevo en la victima
  E8  pull remote=origin branch=conlink: GIT-076 antes de la red (sin
      FETCH_HEAD), nada nuevo en la victima
  E9  stash push con el fichero de detras modificado: GIT-076, no se toca
  E10 stash pop con un cambio aparcado de ese fichero: GIT-076, no se toca
  E11 lo que no toca el arbol corre con el enlace ahi: log, branch, stash
      list, restore --staged, switch create
  E12 un enlace a una carpeta DE LAS RAICES: status, add y switch corren
  E13 un enlace detras de ese enlace, hacia la victima: GIT-076
  E14 una carpeta del repo que no se deja listar: GUARD-040
  E15 la victima, intacta al final

Uso:  python tests/test_git_enlace_arbol_119.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

NOMBRE = 'git-enlace-arbol-119'
NEGADO = 'SR_GIT_ENLACE_AJENO_FMT'


def quita_enlaces(base):
    # los junctions primero, con rmdir (quita el ENLACE, nunca lo de detras)
    r = mc.consola(['cmd', '/c', 'dir', '/AL', '/S', '/B', base])
    for j in sorted(r.stdout.split('\n'), key=len, reverse=True):
        j = j.strip()
        if j and os.path.isdir(j):
            os.rmdir(j)


if os.path.isdir(os.path.join(mc.RAIZ, NOMBRE)):
    quita_enlaces(os.path.join(mc.RAIZ, NOMBRE))
BASE = mc.carpeta(NOMBRE)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
MINE = os.path.join(BASE, 'mio')            # las raices
OUT = os.path.join(BASE, 'fuera')           # fuera de todo
VIC = os.path.join(OUT, 'victima')
V = os.path.join(VIC, 'v.txt')              # el fichero del dueno de la victima: nunca versionado
W = os.path.join(VIC, 'w.txt')              # el que la rama conlink versiona como enlace/w.txt
OTRA = os.path.join(MINE, 'otra')           # una carpeta de las raices, destino legitimo
REPO = os.path.join(MINE, 'repo')
REMOTO = os.path.join(MINE, 'remoto.git')
ENLACE = os.path.join(REPO, 'enlace')
DENTRO = os.path.join(REPO, 'dentro')
SALTO = os.path.join(OTRA, 'salto')
FETCH_HEAD = os.path.join(REPO, '.git', 'FETCH_HEAD')
for d in (VIC, OTRA, REPO):
    os.makedirs(d)
open(os.path.join(OTRA, 'o.txt'), 'w').write('dentro')


def g(*a, cwd=REPO):
    return subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *a],
                          cwd=cwd, capture_output=True, text=True)


def foto():
    """Lo que hay en la victima, con su contenido."""
    return {n: hashlib.sha256(open(os.path.join(VIC, n), 'rb').read()).hexdigest()
            for n in sorted(os.listdir(VIC))}


def victima(con_w):
    """El dueno de la victima deja v.txt; w.txt solo cuando la rama lo tiene
    (para que el arbol este limpio)."""
    open(V, 'w').write('fuera')
    if con_w:
        open(W, 'w').write('de la rama')
    elif os.path.exists(W):
        os.remove(W)


def estado(rama):
    """HEAD en la rama, arbol limpio, el junction plantado y la victima
    entera. Las ordenes del arnes van SIN el enlace (lo que escribe git aqui
    es andamio, no lo medido)."""
    if os.path.isjunction(ENLACE):
        os.rmdir(ENLACE)
    g('reset', '-q', '--hard')
    g('switch', '-q', '-f', rama)
    if os.path.isdir(ENLACE):
        mc.borra(ENLACE)   # la carpeta real que dejo el checkout
    mc.junction(ENLACE, VIC)
    victima(con_w=(rama == 'conlink'))
    if os.path.exists(FETCH_HEAD):
        os.remove(FETCH_HEAD)


# el repo: main con a.txt; conlink anade enlace/w.txt (como carpeta real)
g('init', '-q', '-b', 'main')
open(os.path.join(REPO, 'a.txt'), 'w').write('uno')
g('add', 'a.txt')
g('commit', '-qm', 'uno')
g('switch', '-q', '-c', 'conlink')
os.makedirs(ENLACE)
open(os.path.join(ENLACE, 'w.txt'), 'w').write('de la rama')
g('add', 'enlace/w.txt')
g('commit', '-qm', 'con w.txt')
subprocess.run(['git', 'init', '-q', '--bare', '-b', 'main', REMOTO], capture_output=True)
g('remote', 'add', 'origin', REMOTO)
g('push', '-q', 'origin', 'main', 'conlink')
estado('main')
check('E1 fixture: Windows sigue el junction', os.path.isjunction(ENLACE) and os.listdir(ENLACE) == ['v.txt'],
      os.listdir(ENLACE))
ANTES = foto()

print('== git enlace en el arbol (1.19.0) ==')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE}), nombre=NOMBRE, t=180)


def tool(**kw):
    kw.setdefault('repo', REPO)
    return srv.call('delphi_git', kw)


def negado(r):
    return mc.rechazado(r) and mc.es(r, NEGADO)


try:
    # ---- lo que RECORRE: status, diff, add
    r = tool(command='status')
    check('E2 status: GIT-076 y no nombra lo de detras', negado(r) and 'v.txt' not in r, r[:400])
    r = tool(command='add', paths=['.'])
    check('E3 add paths=["."]: GIT-076, indice limpio, victima intacta',
          negado(r) and 'enlace' not in g('ls-files').stdout and foto() == ANTES,
          r[:300] + ' | ' + g('ls-files').stdout)
    g('reset', '-q')
    r = tool(command='add', paths=['enlace'])
    check('E4 add paths=["enlace"]: negado, indice limpio',
          # SU negativa (GIT-076), como E3: un SYS-015 o cualquier otra puerta
          # tambien dejaban el indice limpio (revisor de baterias, 18-oct-2026)
          negado(r) and 'enlace' not in g('ls-files').stdout, r[:300] + ' | ' + g('ls-files').stdout)
    g('reset', '-q')
    r = tool(command='diff')
    check('E5 diff: GIT-076', negado(r), r[:300])

    # ---- lo que REESCRIBE: switch, merge, pull, stash push, stash pop
    estado('conlink')
    con_w = foto()
    r = tool(command='switch', branch='main')
    check('E6 switch branch=main: GIT-076, el fichero de detras sigue y HEAD no cambia',
          negado(r) and foto() == con_w and os.path.isjunction(ENLACE)
          and g('branch', '--show-current').stdout.strip() == 'conlink', r[:300] + ' | ' + str(foto()))
    estado('main')
    r = tool(command='merge', branch='conlink')
    check('E7 merge branch=conlink: GIT-076, nada nuevo en la victima',
          negado(r) and foto() == ANTES and g('branch', '--show-current').stdout.strip() == 'main',
          r[:300] + ' | ' + str(foto()))
    estado('main')
    r = tool(command='pull', remote='origin', branch='conlink')
    check('E8 pull remote=origin branch=conlink: GIT-076 antes de la red, nada nuevo en la victima',
          negado(r) and foto() == ANTES and not os.path.exists(FETCH_HEAD), r[:300] + ' | ' + str(foto()))
    estado('conlink')
    open(W, 'w').write('cambiado por el dueno')
    cambiado = foto()
    r = tool(command='stash')
    check('E9 stash push con el fichero de detras modificado: GIT-076, no se toca',
          negado(r) and foto() == cambiado and g('stash', 'list').stdout.strip() == '',
          r[:300] + ' | ' + str(foto()))
    # un cambio aparcado de ese fichero, hecho por el arnes sin el enlace
    estado('conlink')
    os.rmdir(ENLACE)
    os.makedirs(ENLACE)
    open(os.path.join(ENLACE, 'w.txt'), 'w').write('aparcado')
    g('stash', '-q')
    mc.borra(ENLACE)
    mc.junction(ENLACE, VIC)
    victima(con_w=True)
    r = tool(command='stash', action='pop')
    check('E10 stash pop con un cambio aparcado de ese fichero: GIT-076, no se toca',
          negado(r) and foto() == con_w and g('stash', 'list').stdout.strip() != '',
          r[:300] + ' | ' + str(foto()))
    os.rmdir(ENLACE)
    g('stash', 'drop', '-q')

    # ---- lo que NO toca el arbol corre con el enlace ahi
    estado('main')
    corren = []
    for nombre, campos in (('log', {'count': 1}), ('branch', {}), ('stash list', {'command': 'stash', 'action': 'list'}),
                           ('restore --staged', {'command': 'restore', 'paths': ['a.txt']}),
                           ('switch create', {'command': 'switch', 'branch': 'nueva', 'create': True})):
        campos.setdefault('command', nombre)
        r = tool(**campos)
        if not r.startswith('exit=0'):
            corren.append(nombre + ': ' + r[:200])
    check('E11 lo que no toca el arbol corre con el enlace ahi (log, branch, stash list, restore, switch create)',
          not corren and foto() == ANTES, corren)

    # ---- un enlace a una carpeta DE LAS RAICES se admite...
    estado('main')
    os.rmdir(ENLACE)
    mc.junction(DENTRO, OTRA)
    r1 = tool(command='status')
    r2 = tool(command='add', paths=['.'])
    indice = g('ls-files').stdout
    g('reset', '-q')
    r3 = tool(command='switch', branch='conlink')
    check('E12 un enlace a una carpeta de las raices: status, add y switch corren',
          r1.startswith('exit=0') and 'dentro' in r1 and r2.startswith('exit=0') and 'dentro/o.txt' in indice
          and r3.startswith('exit=0') and g('branch', '--show-current').stdout.strip() == 'conlink',
          (r1 + ' | ' + r2 + ' | ' + r3)[:600])
    g('switch', '-q', '-f', 'main')
    if os.path.isdir(ENLACE):
        mc.borra(ENLACE)
    # ...y lo que hay DETRAS se recorre tambien: un enlace alli hacia la victima
    mc.junction(SALTO, VIC)
    r = tool(command='status')
    check('E13 un enlace detras de ese enlace, hacia la victima: GIT-076',
          negado(r) and 'salto' in r and 'v.txt' not in r, r[:400])
    os.rmdir(SALTO)
    os.rmdir(DENTRO)

    # ---- una carpeta del repo que no se deja listar: no se da por revisada
    CIEGA = os.path.join(REPO, 'ciega')
    os.makedirs(CIEGA)
    with mc.ilegible(CIEGA):
        r = tool(command='status')
    check('E14 una carpeta del repo que no se deja listar: GUARD-040',
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_CARPETA_ILEGIBLE_FMT'), r[:400])
    os.rmdir(CIEGA)
    check('E15 la victima, intacta al final', foto() == ANTES, foto())
finally:
    srv.cierra()
    quita_enlaces(BASE)

mc.borra(BASE)
mc.fin('git enlace en el arbol 1.19.0')
