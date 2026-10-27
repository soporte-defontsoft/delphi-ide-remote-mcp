# -*- coding: utf-8 -*-
"""V66 de la 1.23.1: el estado que git imprime POR SU CUENTA no pasaba por
nuestra exclusion de la papelera. status y add la dejan fuera (LoNuestroFuera),
pero stash pop imprime el status largo de git despues de aplicar, y un commit
sin nada preparado imprime ese mismo status: los dos listaban
"Untracked files: __delphi-patch/" - el commit, ademas, con "nothing added to
commit but untracked files present", que invita a anadirla. Hallado por el
completo de Claude Opus 5.5 en Hermes (26-oct); medido en vivo el 27-oct.
Ahora stash pop va con --quiet y detras NUESTRO estado (GIT-083), y el commit
que no hizo nada porque no habia nada preparado - lo dice git, diff --cached
--quiet - contesta GIT-084 con nuestro estado.

  P1 stash pop: sin la papelera, con GIT-083 y el fichero modificado
  P2 commit sin nada preparado: sin la papelera, GIT-084 y el fichero
  P3 stash pop con conflicto: UU del fichero, sin la papelera, y el stash se queda
  C1 control: la papelera EXISTE en el disco en cada caso (si no, P1-P3 no miden)

Uso:  python tests/test_git_papelera_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_papelera_1231')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
os.makedirs(REPO)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# la config GLOBAL del usuario, vacia: lo que haya en la de la maquina no decide
GLOBAL = os.path.join(BASE, 'global.gitconfig')
open(GLOBAL, 'w').close()
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'GIT_CONFIG_GLOBAL': GLOBAL}), nombre='git-papelera', t=120)
PAPELERA = os.path.join(REPO, mc.PAPELERA)
FICH = os.path.join(REPO, 'c01.txt')


def git(**kw):
    kw['repo'] = REPO
    return s.call('delphi_git', kw, t=120)


def edita(viejo, nuevo):
    # por el servidor: su copia previa va a la papelera, como en el campo
    return s.call('delphi_textedit', {'path': FICH, 'old': viejo, 'new': nuevo})


try:
    open(FICH, 'wb').write(b'base\r\n')
    git(command='init')
    git(command='config', name='user.name', message='Sonda')
    git(command='config', name='user.email', message='sonda@example.com')
    git(command='add', paths=['c01.txt'])
    git(command='commit', message='base')

    edita('base', 'cambio')
    check('C1 la papelera EXISTE en el disco tras editar (si no, lo de abajo no mide nada)',
          os.path.isdir(PAPELERA) and os.listdir(PAPELERA), os.listdir(REPO))
    git(command='stash', paths=['c01.txt'], message='aparca')
    p = git(command='stash', action='pop')
    check('P1 stash pop: sin la papelera, con GIT-083 y " M c01.txt" (ROJO contra 1.23.x: la papelera en '
          '"Untracked files")', mc.PAPELERA not in p and mc.es(p, 'SN_GIT_ESTADO_TRAS_POP_FMT') and ' M c01.txt' in p,
          p[:600])

    r = git(command='commit', message='nada preparado')
    check('P2 commit sin nada preparado: sin la papelera, GIT-084 y c01.txt (ROJO: "nothing added to commit but '
          'untracked files present" con la papelera)',
          mc.rechazado(r) and mc.PAPELERA not in r and mc.es(r, 'SN_GIT_COMMIT_SIN_NADA_FMT') and 'c01.txt' in r,
          r[:600])

    git(command='stash', paths=['c01.txt'], message='aparca para chocar')
    open(FICH, 'wb').write(b'otra base\r\n')
    git(command='add', paths=['c01.txt'])
    git(command='commit', message='otra base')
    check('C1 ...la papelera sigue en el disco antes del conflicto', os.path.isdir(PAPELERA), os.listdir(REPO))
    p = git(command='stash', action='pop')
    lista = git(command='stash', action='list')
    check('P3 stash pop con conflicto: "UU c01.txt" de NUESTRO estado, sin la papelera, y el stash se queda',
          mc.rechazado(p) and 'UU c01.txt' in p and mc.PAPELERA not in p and re.search(r'stash@\{0\}', lista),
          (p[:600], lista[:200]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git: el estado que imprime git, sin la papelera 1.23.1 (V66)')
