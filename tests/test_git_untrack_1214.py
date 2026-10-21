# -*- coding: utf-8 -*-
r"""delphi_git untrack: rm --cached (1.21.4). Quitar del INDICE lo que git sigue sin
borrarlo del disco: dos .res regenerados por msbuild obligaron a la consola el 14-oct-2026
y Hermes choco con la falta de rm/reset el 28-sep. Como restore, el arbol de trabajo no
se toca nunca; --quiet y la nota GIT-081 dicen lo que viene despues.

  U1  untrack paths=[x.res]: exit=0, GIT-081, el fichero sigue en disco y status lo
      da como borrado del indice ('D  x.res')
  U2  commit: el fichero sigue en disco y git lo ve como no seguido ('?? x.res')
  U3  untrack de una carpeta entera (-r): sus ficheros fuera del indice, en disco
  U4  untrack sin paths: GIT-080 (no adivina)
  U5  untrack de un fichero que git no sigue: git lo dice (exit<>0), nada cambia
  U6  untrack de una ruta fuera del repo: rechazada (la de siempre)
  U7  untrack de un comodin: rechazado (un comodin no es un nombre)
  U8  el contenido de los ficheros, byte a byte, de principio a fin

U1 a U7 son ROJAS contra 1.21.3 (untrack no existia: GIT-034).

Uso:  python tests/test_git_untrack_1214.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git-untrack')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
REPO_T = os.path.join(BASE, 'repo')
os.makedirs(os.path.join(REPO_T, 'build'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='gu')


def git(args):
    return srv.call('delphi_git', dict({'repo': REPO_T}, **args))


def escribe(rel, datos):
    with open(os.path.join(REPO_T, rel), 'wb') as f:
        f.write(datos)


def lee(rel):
    with open(os.path.join(REPO_T, rel), 'rb') as f:
        return f.read()


try:
    git({'command': 'init'})
    git({'command': 'config', 'name': 'user.name', 'message': 'Probe Bot'})
    git({'command': 'config', 'name': 'user.email', 'message': 'probe@example.com'})
    RES = b'\x00\x00res-bytes\x01'
    escribe('a.txt', b'uno\n')
    escribe('x.res', RES)
    escribe('build/b1.dcu', b'dcu1')
    escribe('build/b2.dcu', b'dcu2')
    git({'command': 'add', 'paths': ['.']})
    r = git({'command': 'commit', 'message': 'inicial'})
    check('fixture: commit inicial con a.txt, x.res y build/', 'exit=0' in r, r[:150])

    r = git({'command': 'untrack', 'paths': ['x.res']})
    st = git({'command': 'status'})
    check('U1 untrack paths=[x.res]: exit=0 y la nota GIT-081',
          'exit=0' in r and mc.es(r, 'SN_GIT_UNTRACK_SOLO_INDICE'), r[:300])
    check('U1 ...el fichero sigue en disco, byte a byte, y status lo da como borrado del indice',
          lee('x.res') == RES and 'D  x.res' in st, st[:200])
    r = git({'command': 'commit', 'message': 'x.res fuera del indice'})
    st = git({'command': 'status'})
    check('U2 commit: x.res sigue en disco y git ya no lo sigue (?? x.res)',
          'exit=0' in r and lee('x.res') == RES and '?? x.res' in st, (r[:100], st[:200]))

    r = git({'command': 'untrack', 'paths': ['build']})
    st = git({'command': 'status'})
    check('U3 untrack de una carpeta (-r): sus ficheros fuera del indice y en disco',
          'exit=0' in r and 'D  build/b1.dcu' in st and 'D  build/b2.dcu' in st
          and lee('build/b1.dcu') == b'dcu1' and lee('build/b2.dcu') == b'dcu2', st[:300])
    git({'command': 'commit', 'message': 'build fuera'})

    r = git({'command': 'untrack'})
    check('U4 untrack sin paths: GIT-080', mc.rechazado(r) and mc.es(r, 'SR_GIT_UNTRACK_NEEDS_PATHS'), r[:200])

    st0 = git({'command': 'status'})
    r = git({'command': 'untrack', 'paths': ['x.res']})
    st = git({'command': 'status'})
    check('U5 untrack de un fichero que git ya no sigue: git lo dice (exit<>0) y nada cambia',
          mc.abre(r, 'SR_GIT_EXIT_FMT') and st == st0 and lee('x.res') == RES, r[:200])

    r = git({'command': 'untrack', 'paths': ['../fuera.txt']})
    check('U6 untrack de una ruta fuera del repo: rechazada', mc.rechazado(r) and mc.es(r, 'SR_GIT_STASH_RUTA_FMT'), r[:200])
    r = git({'command': 'untrack', 'paths': ['*.txt']})
    check('U7 untrack de un comodin: rechazado', mc.rechazado(r) and mc.es(r, 'SR_GUARD_COMODIN_FMT'), r[:200])
    check('U8 a.txt intacto de principio a fin', lee('a.txt') == b'uno\n')
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('git untrack 1214')
