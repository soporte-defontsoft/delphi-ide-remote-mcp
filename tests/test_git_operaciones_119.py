# -*- coding: utf-8 -*-
"""delphi_git sin "args" (1.19.0; David, 14-oct-2026: "el agente pide una
operacion; por defecto lo nuestro"). Cada comando toma SUS campos y el
servidor compone la orden eligiendo de lo que git dice: una revision que
encuentra, un nombre que admite, un remoto del repo, una ruta del repo.

  O1  args: GIT-068, nada hecho
  O2  paths como texto suelto: GIT-069
  O3  status con paths
  O4  add + commit; log count=1 format=dated: hash, fecha y asunto
  O5  diff ref/to format=stat; diff staged
  O6  una ref que no existe: GIT-070
  O7  switch create y vuelta; una rama "-f" no es una opcion: GIT-071
  O8  merge de una rama (ff); merge action=otra: GIT-007
  O9  stash con paths devuelve SOLO ese fichero a HEAD; pop lo trae
  O10 restore paths saca del indice y no toca el fichero
  O11 tag con nombre y mensaje (anotado); tag lista; tag sin nombre con ref: GIT-038
  O12 show patch=true trae el diff; sin el, el stat
  O13 log search encuentra el commit; sin resultado, GIT-058
  O14 un campo que no va con el comando: GIT-038
  O15 push sin remote con ref: GIT-074; push origin main al remoto de la
      jaula; un ref "+main" (forzar) no es un nombre: GIT-046
  O16 pull remote+branch (ff)
  O17 una ruta de paths fuera del repo: GIT-012
  O18 una ruta de paths en su unidad virtual (srvX:) llega traducida
  O19 config name=user.name
  O20 worktree action=list

Uso:  python tests/test_git_operaciones_119.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_operaciones_119')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
REMOTO = os.path.join(JAIL, 'remoto.git')
OTRO = os.path.join(JAIL, 'otro')
os.makedirs(REPO)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def git(*a, cwd=REPO):
    return subprocess.run(['git'] + list(a), cwd=cwd, capture_output=True, text=True).stdout


git('init', '-q', '-b', 'main')
git('config', 'user.name', 'Bateria')
git('config', 'user.email', 'b@x')
open(os.path.join(REPO, 'a.txt'), 'w').write('uno\n')
git('add', 'a.txt')
git('commit', '-q', '-m', 'primero')
# con su HEAD en main: con el de por defecto (master) un clone no saca nada
# y el commit "desde fuera" de O16 no llegaba a main (medido)
subprocess.run(['git', 'init', '-q', '--bare', '-b', 'main', REMOTO], capture_output=True)
git('remote', 'add', 'origin', REMOTO)
git('push', '-q', 'origin', 'main')
os.makedirs(OTRO)
open(os.path.join(OTRO, 'fuera.txt'), 'w').write('x')

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='git-operaciones', t=180)


def g(**kw):
    kw.setdefault('repo', REPO)
    return s.call('delphi_git', kw)


try:
    r = g(command='status', args='--short')
    check('O1 args: GIT-068 y nada hecho', 'GIT-068' in r and 'exit=' not in r, r[:200])
    r = g(command='status', paths='a.txt')
    check('O2 paths como texto suelto: GIT-069', 'GIT-069' in r, r[:200])

    open(os.path.join(REPO, 'a.txt'), 'w').write('uno\ndos\n')
    open(os.path.join(REPO, 'b.txt'), 'w').write('be\n')
    r = g(command='status', paths=['a.txt'])
    check('O3 status con paths: solo a.txt', 'exit=0' in r and 'a.txt' in r and 'b.txt' not in r, r[:300])

    r = g(command='add', paths=['a.txt', 'b.txt'])
    r2 = g(command='commit', message='segundo: a y b')
    r3 = g(command='log', count=1, format='dated')
    check('O4 add + commit; log count=1 format=dated', 'exit=0' in r and 'exit=0' in r2 and
          'segundo: a y b' in r3 and r3.count('\n') <= 2 and '20' in r3, (r[:120], r2[:120], r3[:200]))

    r = g(command='diff', ref='HEAD~1', to='HEAD', format='stat')
    open(os.path.join(REPO, 'b.txt'), 'w').write('be\nbe2\n')
    g(command='add', paths=['b.txt'])
    r2 = g(command='diff', staged=True)
    check('O5 diff ref/to stat; diff staged', 'a.txt' in r and '|' in r and '+be2' in r2, (r[:300], r2[:300]))

    r = g(command='diff', ref='no-existe-esta-rama')
    check('O6 una ref que no existe: GIT-070', 'GIT-070' in r, r[:200])

    g(command='commit', message='tercero')
    r = g(command='switch', branch='rama1', create=True)
    open(os.path.join(REPO, 'c.txt'), 'w').write('ce\n')
    g(command='add', paths=['c.txt'])
    g(command='commit', message='en rama1')
    r2 = g(command='switch', branch='main')
    r3 = g(command='switch', branch='-f')
    check('O7 switch create y vuelta; "-f" no es opcion: GIT-071', 'exit=0' in r and 'exit=0' in r2 and
          'GIT-071' in r3 and git('branch', '--show-current').strip() == 'main', (r[:150], r2[:150], r3[:200]))

    r = g(command='merge', branch='rama1')
    r2 = g(command='merge', action='squash')
    check('O8 merge ff de rama1; action=squash: GIT-007', 'exit=0' in r and os.path.isfile(os.path.join(REPO, 'c.txt'))
          and 'GIT-007' in r2, (r[:200], r2[:200]))

    open(os.path.join(REPO, 'a.txt'), 'w').write('cambiado\n')
    open(os.path.join(REPO, 'b.txt'), 'w').write('cambiado b\n')
    r = g(command='stash', paths=['a.txt'], message='aparco a')
    a_tras = open(os.path.join(REPO, 'a.txt')).read()
    b_tras = open(os.path.join(REPO, 'b.txt')).read()
    r2 = g(command='stash', action='pop')
    check('O9 stash con paths: SOLO a.txt vuelve a HEAD; pop lo trae',
          'exit=0' in r and a_tras != 'cambiado\n' and b_tras == 'cambiado b\n' and
          open(os.path.join(REPO, 'a.txt')).read() == 'cambiado\n', (r[:200], r2[:200], a_tras, b_tras))

    g(command='add', paths=['a.txt'])
    r = g(command='restore', paths=['a.txt'])
    staged = git('diff', '--cached', '--name-only')
    check('O10 restore saca del indice y no toca el fichero', 'exit=0' in r and 'a.txt' not in staged and
          open(os.path.join(REPO, 'a.txt')).read() == 'cambiado\n', (r[:200], staged))
    git('checkout', '--', 'a.txt', 'b.txt')

    r = g(command='tag', name='v0.1', message='la primera')
    r2 = g(command='tag')
    r3 = g(command='tag', ref='HEAD')
    check('O11 tag anotado; tag lista; tag sin nombre con ref: GIT-038',
          'exit=0' in r and 'v0.1' in r2 and git('cat-file', '-t', 'v0.1').strip() == 'tag' and 'GIT-038' in r3,
          (r[:150], r2[:150], r3[:200]))

    r = g(command='show', ref='HEAD~1', patch=True)
    r2 = g(command='show', ref='HEAD~1')
    check('O12 show patch=true trae el diff; sin el, el stat', '@@' in r and '@@' not in r2 and '|' in r2,
          (r[:300], r2[:300]))

    r = g(command='log', search='be2')
    r2 = g(command='log', search='texto-que-no-esta')
    check('O13 log search lo encuentra; sin resultado, GIT-058', 'tercero' in r and 'GIT-058' in r2,
          (r[:200], r2[:300]))

    r = g(command='status', branch='main')
    check('O14 un campo que no va con el comando: GIT-038', 'GIT-038' in r, r[:200])

    r = g(command='push', ref='main')
    r2 = g(command='push', remote='origin', ref='main')
    r3 = g(command='push', remote='origin', ref='+main')
    check('O15 push: ref sin remote GIT-074; origin main sube; "+main" GIT-046',
          'GIT-074' in r and 'exit=0' in r2 and
          git('rev-parse', 'main', cwd=REMOTO).strip() == git('rev-parse', 'main').strip() and 'GIT-046' in r3,
          (r[:200], r2[:200], r3[:200]))

    otro_clon = os.path.join(BASE, 'clon2')
    subprocess.run(['git', 'clone', '-q', REMOTO, otro_clon], capture_output=True)
    subprocess.run(['git', '-C', otro_clon, '-c', 'user.name=x', '-c', 'user.email=x@x', 'commit', '-q',
                    '--allow-empty', '-m', 'desde fuera'], capture_output=True)
    subprocess.run(['git', '-C', otro_clon, 'push', '-q', 'origin', 'main'], capture_output=True)
    r = g(command='pull', remote='origin', branch='main')
    check('O16 pull remote+branch (ff)', 'exit=0' in r and 'desde fuera' in git('log', '-1', '--format=%s'),
          r[:300])

    r = g(command='add', paths=[os.path.join(OTRO, 'fuera.txt')])
    check('O17 una ruta de paths fuera del repo: GIT-012', 'GIT-012' in r, r[:200])

    open(os.path.join(REPO, 'v.txt'), 'w').write('ve\n')
    r = g(command='add', paths=[mc.virtual(os.path.join(REPO, 'v.txt'))])
    check('O18 una ruta de paths en su unidad virtual llega traducida',
          'exit=0' in r and 'v.txt' in git('diff', '--cached', '--name-only'), r[:200])

    r = g(command='config', name='user.name', message='Otro Nombre')
    check('O19 config name=user.name', 'exit=0' in r and git('config', 'user.name').strip() == 'Otro Nombre', r[:200])

    r = g(command='worktree', action='list')
    check('O20 worktree action=list', 'exit=0' in r and 'repo' in r, r[:200])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git operaciones 1.19.0')
