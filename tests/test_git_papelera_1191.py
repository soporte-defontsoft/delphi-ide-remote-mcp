# -*- coding: utf-8 -*-
"""delphi_git no mete lo NUESTRO en el repo del agente (1.19.1; Hermes, 15-oct-2026).

La papelera (__delphi-patch, con las copias de cada fichero y sus marcas .by) y la
carpeta temporal vieja (__delphi-temp) viven dentro de las raices, junto a lo que
se edita. El .gitignore que escribe delphi_create las cubre en la carpeta del
proyecto, pero no en la raiz de un repo que esta por encima ni en una carpeta de
units sueltas: medido el 15-oct contra 1bdb4d7, `add paths=["."]` metia en el
indice app/__delphi-patch/<dia>/U.pas, el before-restore y su .by, y status las
listaba como sin seguimiento. Desde la 1.19.1 status y add las dejan fuera con el
mecanismo de git (un pathspec de exclusion con los nombres de su nombrador), sin
tocar el .gitignore del agente.

  P1 fixture: una edicion por la tool deja su papelera en app/ (sin .gitignore)
  P2 status no lista la papelera ni la temporal
  P3 add paths=["."] mete el fichero editado y NADA de la papelera ni de la temporal
  P4 add paths=["app/__delphi-patch"] (nombrada a proposito) no la mete
  P5 lo demas sigue: un fichero nuevo de verdad entra con add "."

Uso:  python tests/test_git_papelera_1191.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_papelera_1191')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
APP = os.path.join(REPO, 'app')
os.makedirs(APP)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def git(*a):
    return subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t'] + list(a),
                          cwd=REPO, capture_output=True, text=True).stdout


git('init', '-q', '-b', 'main')
U = os.path.join(APP, 'UApp.pas')
open(U, 'w', newline='\r\n').write('unit UApp;\ninterface\nimplementation\nend.\n')
git('add', '.')
git('commit', '-qm', 'uno')
# la temporal de versiones viejas, con algo dentro
TEMP = os.path.join(REPO, mc.TEMPORALES)
os.makedirs(TEMP)
open(os.path.join(TEMP, 'resto.txt'), 'w').write('x')

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='git-papelera', t=180)


def g(**kw):
    kw.setdefault('repo', REPO)
    return s.call('delphi_git', kw)


try:
    r = s.call('delphi_edit', {'path': U, 'old': 'interface', 'new': 'interface // editado'})
    papelera = os.path.join(APP, mc.PAPELERA)
    check('P1 fixture: la edicion deja su papelera en app/ (sin .gitignore)',
          os.path.isdir(papelera) and any(fs for _, _, fs in os.walk(papelera)), r[:200])

    r = g(command='status')
    check('P2 status no lista la papelera ni la temporal',
          r.startswith('exit=0') and mc.PAPELERA not in r and mc.TEMPORALES not in r
          and 'UApp.pas' in r, r[:400])

    r = g(command='add', paths=['.'])
    indice = git('ls-files', '--cached')
    check('P3 add "." mete el fichero editado y nada de la papelera ni de la temporal',
          r.startswith('exit=0') and mc.PAPELERA not in indice and mc.TEMPORALES not in indice
          and git('diff', '--cached', '--name-only').strip() == 'app/UApp.pas', r[:200] + ' | ' + indice)

    r = g(command='add', paths=['app/' + mc.PAPELERA])
    indice = git('ls-files', '--cached')
    check('P4 la papelera nombrada a proposito tampoco entra', mc.PAPELERA not in indice,
          r[:200] + ' | ' + indice)

    open(os.path.join(APP, 'nuevo.txt'), 'w').write('nuevo')
    r = g(command='add', paths=['.'])
    check('P5 un fichero nuevo de verdad entra con add "."',
          r.startswith('exit=0') and 'app/nuevo.txt' in git('ls-files', '--cached'), r[:200])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git papelera 1.19.1')
