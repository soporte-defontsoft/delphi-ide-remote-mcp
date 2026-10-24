# -*- coding: utf-8 -*-
"""add de un fichero IGNORADO (1.19.3; encontrado el 15-oct midiendo los
consejos de git que reporto Hermes). La magia :(literal,icase) de H10 (1.19.2)
cambio lo que dice git: con :(literal), "The following paths are ignored by one
of your .gitignore files: x.log"; con icase, "fatal: pathspec
':(literal,icase)x.log' did not match any files" y no anade nada: el agente
creia que el fichero no existia. Ahora, si add falla, el servidor pregunta a
git check-ignore (respeta core.ignorecase y nombra la regla) y lo dice
(GIT-078). Una regla de fuera del repo (core.excludesFile) es de la casa del
servidor: se dice de donde es, sin su ruta.

  I1 add ["x.log"]: GIT-078 con la regla y su sitio (.gitignore line 1) (ROJO)
  I2 add ["X.LOG"] (otra mayuscula): GIT-078 lo nombra igual (ROJO)
  I3 add ["logs/y.txt"] (carpeta ignorada): GIT-078 con la regla "logs/" (ROJO)
  I4 add ["w.tmp"] (regla en .git/info/exclude): GIT-078 la nombra, relativa; git
     da su fuente ABSOLUTA y entrecomillada (barras invertidas del --git-dir),
     y la lee LeeRutaDeGit (ROJO)
  I5 add ["g.glob"] (regla en core.excludesFile, fuera): GIT-078 sin la ruta (ROJO)
  I6 add ["c01.txt", "x.log"]: GIT-078 nombra x.log y no c01.txt (ROJO)
  I7 add ["café/z.tmp2"] (regla en café/.gitignore): GIT-078 la nombra con su
     acento. Antes de core.quotePath=false (test_git_acentos_1193) git la daba
     "caf\\303\\251/.gitignore" y la leia LeeRutaDeGit; ahora llega tal cual (ROJO)
  C1 control: add de uno que no existe: fallo, sin GIT-078
  C2 control: add de un rastreado que casa con un patron: bien, sin GIT-078

Uso:  python tests/test_git_ignorado_1193.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_ignorado_1193')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(os.path.join(REPO, 'logs'))
os.makedirs(os.path.join(REPO, 'café'))
os.makedirs(FUERA)
EXCL = os.path.join(FUERA, 'excl-global.txt')
open(EXCL, 'wb').write(b'*.glob\n')
GLOBAL = os.path.join(FUERA, 'gitconfig-global')
open(GLOBAL, 'w').write('[core]\n\texcludesFile = %s\n' % EXCL.replace('\\', '/'))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'GIT_CONFIG_GLOBAL': GLOBAL}),
             nombre='git-ignorado', t=120)


def git(**kw):
    kw['repo'] = REPO
    return s.call('delphi_git', kw, t=120)


def escribe(nombre, datos):
    open(os.path.join(REPO, nombre), 'wb').write(datos)


def nota(texto):
    """La linea de GIT-078, o '' si no esta."""
    return next((l for l in texto.splitlines() if '[GIT-078]' in l), '')


try:
    escribe('c01.txt', b'base\r\n')
    escribe('t.bak', b'rastreado\r\n')
    git(command='init')
    git(command='config', name='user.name', message='Sonda')
    git(command='config', name='user.email', message='sonda@example.com')
    git(command='add', paths=['.'])
    git(command='commit', message='base')
    escribe('.gitignore', b'x.log\r\nlogs/\r\n*.bak\r\n')
    git(command='add', paths=['.gitignore'])
    git(command='commit', message='reglas')
    with open(os.path.join(REPO, '.git', 'info', 'exclude'), 'ab') as f:
        f.write(b'*.tmp\n')
    escribe('x.log', b'x\r\n')
    escribe(os.path.join('logs', 'y.txt'), b'y\r\n')
    escribe('w.tmp', b'w\r\n')
    escribe('g.glob', b'g\r\n')
    escribe(os.path.join('café', '.gitignore'), b'*.tmp2\r\n')
    escribe(os.path.join('café', 'z.tmp2'), b'z\r\n')

    r = git(command='add', paths=['x.log'])
    n = nota(r)
    check('I1 add ["x.log"]: GIT-078 con la regla y su sitio (.gitignore line 1)',
          mc.rechazado(r) and 'x.log' in n and '"x.log"' in n and '.gitignore line 1' in n, r[:600])

    r = git(command='add', paths=['X.LOG'])
    n = nota(r)
    check('I2 add ["X.LOG"] (otra mayuscula): GIT-078 lo nombra igual',
          mc.rechazado(r) and 'X.LOG' in n and '.gitignore line 1' in n, r[:600])

    r = git(command='add', paths=['logs/y.txt'])
    n = nota(r)
    check('I3 add ["logs/y.txt"] (carpeta ignorada): GIT-078 con la regla "logs/"',
          mc.rechazado(r) and 'logs/y.txt' in n and '"logs/"' in n and '.gitignore line 2' in n, r[:600])

    r = git(command='add', paths=['w.tmp'])
    n = nota(r)
    # relativa al arbol, exacta: git la da ABSOLUTA y entrecomillada (bajo el
    # --git-dir que fija el servidor), y sin leerla saldria la ruta de la jaula
    check('I4 add ["w.tmp"] (regla en .git/info/exclude): GIT-078 la nombra, relativa',
          mc.rechazado(r) and re.search(r'w\.tmp \(rule "\*\.tmp", \.git/info/exclude line \d+\)', n)
          and 'jail' not in n, r[:600])

    r = git(command='add', paths=['g.glob'])
    n = nota(r)
    check('I5 add ["g.glob"] (regla en core.excludesFile, fuera): GIT-078 sin la ruta',
          mc.rechazado(r) and 'g.glob' in n and '"*.glob"' in n and 'outside this working tree' in n
          and 'excl-global' not in r and 'fuera' not in r, r[:600])

    escribe('c01.txt', b'cambio\r\n')
    r = git(command='add', paths=['c01.txt', 'x.log'])
    n = nota(r)
    check('I6 add ["c01.txt", "x.log"]: GIT-078 nombra x.log y no c01.txt',
          mc.rechazado(r) and 'x.log' in n and 'c01.txt' not in n, r[:600])

    r = git(command='add', paths=['café/z.tmp2'])
    n = nota(r)
    check('I7 add ["café/z.tmp2"] (regla en café/.gitignore): GIT-078 la nombra con su acento',
          mc.rechazado(r) and 'café/z.tmp2' in n and 'café/.gitignore line 1' in n, r[:600])

    r = git(command='add', paths=['noexiste.txt'])
    check('C1 control: add de uno que no existe: fallo, sin GIT-078',
          mc.rechazado(r) and not mc.es(r, 'SN_GIT_ADD_IGNORADO_FMT'), r[:600])

    escribe('t.bak', b'cambio\r\n')
    r = git(command='add', paths=['t.bak'])
    st = git(command='status')
    check('C2 control: add de un rastreado que casa con un patron: bien, sin GIT-078',
          not mc.rechazado(r) and not mc.es(r, 'SN_GIT_ADD_IGNORADO_FMT') and 'M  t.bak' in st, (r[:300], st[:300]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git: add de un ignorado dice que lo esta y por que regla 1.19.3')
