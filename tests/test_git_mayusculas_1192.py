# -*- coding: utf-8 -*-
"""H10 de la 1.19.2 (de H4-01 de Hermes sobre la 1.19.1, "git status contradice a
stash/diff"; medido el 15-oct): una ruta de "paths" con OTRA MAYUSCULA que la del
repo daba un limpio falso. Con c01.txt modificado, `status paths=["C01.TXT"]`
contestaba "## master" y `diff` GIT-001 "NOTHING has changed": RutasDeGit componia
:(literal)<ruta>, que distingue mayusculas, en un repo con core.ignorecase=true
sobre un disco que no las distingue. Ahora, cuando GIT dice que el repo no las
distingue (core.ignorecase), las rutas van con la magia icase (:(literal,icase)),
medida con git 2.53 en status, diff, add, stash, fichero y carpeta.

  K1 status paths=["C01.TXT"]: " M c01.txt" (ROJO en produccion)
  K2 diff paths=["C01.TXT"]: el cambio de c01.txt, no GIT-001 (ROJO)
  K3 log paths=["C01.TXT"]: el commit que lo creo (ROJO)
  K4 add paths=["C01.TXT"] lo prepara y restore paths=["C01.TXT"] lo deshace (ROJO)
  K5 stash push paths=["SUB"] (la carpeta, en otra mayuscula): aparta Sub/Dos.txt
     (ROJO); y pop lo devuelve
  C1 control: con la mayuscula exacta, status lo ve igual

Uso:  python tests/test_git_mayusculas_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_mayusculas_1192')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
os.makedirs(os.path.join(REPO, 'Sub'))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='git-mayusculas', t=120)


def git(**kw):
    kw['repo'] = REPO
    return s.call('delphi_git', kw, t=120)


try:
    open(os.path.join(REPO, 'c01.txt'), 'wb').write(b'uno\r\n')
    open(os.path.join(REPO, 'Sub', 'Dos.txt'), 'wb').write(b'dos\r\n')
    git(command='init')
    git(command='config', name='user.name', message='Sonda')
    git(command='config', name='user.email', message='sonda@example.com')
    git(command='add', paths=['.'])
    git(command='commit', message='base')
    open(os.path.join(REPO, 'c01.txt'), 'wb').write(b'cambio\r\n')
    open(os.path.join(REPO, 'Sub', 'Dos.txt'), 'wb').write(b'otro\r\n')

    r = git(command='status', paths=['c01.txt'])
    check('C1 control: con la mayuscula exacta, status ve c01.txt', ' M c01.txt' in r, r[:200])
    r = git(command='status', paths=['C01.TXT'])
    check('K1 status paths=["C01.TXT"]: " M c01.txt", no un limpio falso', ' M c01.txt' in r, r[:200])
    r = git(command='diff', paths=['C01.TXT'])
    check('K2 diff paths=["C01.TXT"]: el cambio, no GIT-001', 'cambio' in r and 'GIT-001' not in r, r[:300])
    r = git(command='log', paths=['C01.TXT'])
    check('K3 log paths=["C01.TXT"]: el commit que lo creo', 'base' in r, r[:200])
    a = git(command='add', paths=['C01.TXT'])
    st = git(command='status')
    git(command='restore', paths=['C01.TXT'])
    st2 = git(command='status')
    check('K4 add paths=["C01.TXT"] lo prepara y restore lo deshace',
          'M  c01.txt' in st and ' M c01.txt' in st2 and 'M  c01.txt' not in st2, (a[:200], st[:200], st2[:200]))
    r = git(command='stash', paths=['SUB'], message='carpeta')
    apartado = open(os.path.join(REPO, 'Sub', 'Dos.txt'), 'rb').read()
    p = git(command='stash', action='pop')
    check('K5 stash push paths=["SUB"] aparta Sub/Dos.txt y pop lo devuelve',
          not mc.rechazado(r) and apartado == b'dos\r\n' and
          open(os.path.join(REPO, 'Sub', 'Dos.txt'), 'rb').read() == b'otro\r\n', (r[:300], p[:200]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git: rutas con otra mayuscula 1.19.2 (H10)')
