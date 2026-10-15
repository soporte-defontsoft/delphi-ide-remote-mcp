# -*- coding: utf-8 -*-
"""Hermes sobre la 1.19.2 (15-oct, informes 1405b, 1405c y 1405e): git escribe
consejos para quien lo usa a mano ("use git restore <file> to discard", "git
commit -a", "Use -f", "git merge --no-ff / git rebase", y en todos "git config
set advice.X false"), y por delphi_git casi ninguno se puede seguir: restore es
siempre --staged, no hay -f, ni rebase, ni config de advice. Hermes leyo el de
stash pop, llamo a restore y el arbol siguio sucio. El juez tiene su
interruptor: GIT_ADVICE=0 (git 2.46 en adelante) los quita todos y deja los
hechos (medido con git 2.53 en stash pop, commit, add, merge, pull y push). Y
restore, que acaba en silencio, dice ahora que el arbol no se toca y como se
descarta un cambio (GIT-077).

  A1 stash pop: nombra el fichero modificado, sin '(use "git' (ROJO en produccion)
  A2 commit sin nada preparado: GIT-036 con c01.txt, sin "git restore" ni
     "commit -a" (ROJO)
  A4 merge que no va en fast-forward: GIT-008 y "Not possible to fast-forward",
     sin lineas "hint:" (ROJO)
  A5 restore: GIT-077 nombra command=stash, y el arbol sigue " M c01.txt" (ROJO)
  C1 control: stash push con la ruta deja el arbol limpio (la via que nombra A5)

Los hechos y las pistas nuestras (GIT-008) se quedan: solo se van los consejos.

Uso:  python tests/test_git_consejos_1193.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_consejos_1193')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
os.makedirs(REPO)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='git-consejos', t=120)


def git(**kw):
    kw['repo'] = REPO
    return s.call('delphi_git', kw, t=120)


def escribe(nombre, datos):
    open(os.path.join(REPO, nombre), 'wb').write(datos)


def hay_hint(texto):
    return any(l.startswith('hint:') for l in texto.splitlines())


try:
    escribe('c01.txt', b'base\r\n')
    git(command='init')
    git(command='config', name='user.name', message='Sonda')
    git(command='config', name='user.email', message='sonda@example.com')
    git(command='add', paths=['.'])
    git(command='commit', message='base')
    m = re.search(r'^## (\S+)', git(command='status'), re.M)
    rama_base = m.group(1) if m else 'master'

    escribe('c01.txt', b'cambio\r\n')
    git(command='add', paths=['c01.txt'])
    r = git(command='restore', paths=['c01.txt'])
    st = git(command='status')
    check('A5 restore: GIT-077 nombra command=stash, y el arbol sigue " M c01.txt"',
          not mc.rechazado(r) and 'GIT-077' in r and 'command=stash' in r and ' M c01.txt' in st,
          (r[:400], st[:200]))

    r = git(command='commit', message='nada preparado')
    check('A2 commit sin nada preparado: GIT-036 con c01.txt, sin "git restore" ni "commit -a"',
          mc.rechazado(r) and 'GIT-036' in r and 'c01.txt' in r and 'git restore' not in r
          and 'commit -a' not in r, r[:600])

    git(command='stash', paths=['c01.txt'], message='aparca')
    st = git(command='status')
    check('C1 control: stash push con la ruta deja el arbol limpio',
          'c01.txt' not in st and open(os.path.join(REPO, 'c01.txt'), 'rb').read() == b'base\r\n', st[:200])
    p = git(command='stash', action='pop')
    check('A1 stash pop: nombra el fichero modificado, sin \'(use "git\'',
          not mc.rechazado(p) and 'c01.txt' in p and '(use "git' not in p, p[:600])

    git(command='stash', paths=['c01.txt'], message='aparca otra vez')
    git(command='switch', branch='rama', create=True)
    escribe('c02.txt', b'en rama\r\n')
    git(command='add', paths=['c02.txt'])
    git(command='commit', message='en rama')
    git(command='switch', branch=rama_base)
    escribe('c03.txt', b'en base\r\n')
    git(command='add', paths=['c03.txt'])
    git(command='commit', message='en base')
    r = git(command='merge', branch='rama')
    check('A4 merge que no va en fast-forward: GIT-008 y "Not possible to fast-forward", sin "hint:"',
          mc.rechazado(r) and 'GIT-008' in r and 'Not possible to fast-forward' in r and not hay_hint(r),
          r[:900])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git: sin los consejos de git que la tool no ofrece 1.19.3 (Hermes)')
