# -*- coding: utf-8 -*-
r"""move, copy y delete como un operador (V19 de la 1.23; plan en el vault:
decisions/plan-v19-ficheros-operador). David, 17-oct-2026: "copiar, mover,
borrar carpetas y su contenido o ficheros, punto, como haria el operador en su
sistema operativo"; y "se copia TODO, git incluido, la historia sigue en ese
proyecto, siempre y cuando su git este dentro de la carpeta del proyecto a
copiar".

Fase 2, la copia:
  G1  una carpeta con un PROYECTO se copia como cualquier carpeta (era MOVE-004,
      "un proyecto nunca vive en dos sitios", una regla de nuestro flujo)
  G2  ...y un .dproj suelto
  G3  un repo entero se copia con su git: la copia es un repo suyo (su
      toplevel es la copia) y el original, intacto
  G4  un worktree enlazado (su .git es un FICHERO que apunta a los metadatos de
      otro repo): MOVE-022, nada creado
  G5  un repo con core.worktree fuera (medido: git da esa raiz, exit 0):
      MOVE-022 (working tree), nada creado
  G6  un repo al que se llega por un ENLACE que la copia sigue: no esta dentro,
      MOVE-022, nada creado
  G7  control: una subcarpeta de un repo (sin su .git) se copia

Mutante: produccion anterior (r1222cd): G1, G2 y G3 rojos (MOVE-004 y GUARD-033)
y G4-G6 tambien (otra negativa, no la que dice por que).

Uso:  python tests/test_ficheros_operador_1230.py [exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ficheros_operador_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def git(*args, cwd=None):
    return subprocess.run(['git', '-c', 'user.name=bateria', '-c', 'user.email=b@t'] + list(args),
                          cwd=cwd, capture_output=True, text=True)


def repo(path, fichero='a.txt'):
    os.makedirs(path, exist_ok=True)
    git('init', '-q', path)
    open(os.path.join(path, fichero), 'w').write('uno\n')
    git('add', '-A', cwd=path)
    git('commit', '-q', '-m', 'uno', cwd=path)
    return path


def nada(p):
    return not os.path.exists(p)


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='operador1230', t=300)
try:
    # --- G1, G2: un proyecto se copia
    PDIR = os.path.join(JAIL, 'proy')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Pr', 'dir': PDIR})
    r = srv.call('delphi_move', {'path': PDIR, 'dest': os.path.join(JAIL, 'proy2'), 'copy': True})
    check('G1 una carpeta con un proyecto se copia como cualquier carpeta (era MOVE-004)',
          mc.abre(r, 'SK_MOVE_COPIADO_FMT') and os.path.isfile(os.path.join(JAIL, 'proy2', 'Pr.dproj'))
          and os.path.isfile(os.path.join(PDIR, 'Pr.dproj')), r[:300])
    r = srv.call('delphi_move', {'path': os.path.join(PDIR, 'Pr.dproj'), 'dest': os.path.join(JAIL, 'Suelto.dproj'),
                                 'copy': True})
    check('G2 un .dproj suelto se copia', mc.abre(r, 'SK_MOVE_COPIADO_FMT') and
          os.path.isfile(os.path.join(JAIL, 'Suelto.dproj')), r[:300])

    # --- G3: un repo entero, con su git
    R = repo(os.path.join(JAIL, 'repo'))
    COPIA = os.path.join(JAIL, 'repo-copia')
    r = srv.call('delphi_move', {'path': R, 'dest': COPIA, 'copy': True})
    top = git('rev-parse', '--show-toplevel', cwd=COPIA).stdout.strip() if os.path.isdir(COPIA) else ''
    check('G3 un repo entero se copia con su git: la copia es un repo suyo y el original sigue',
          mc.abre(r, 'SK_MOVE_COPIADO_FMT') and os.path.isfile(os.path.join(COPIA, '.git', 'HEAD'))
          and os.path.normcase(os.path.abspath(top)) == os.path.normcase(mc.larga(COPIA))
          and git('log', '--oneline', cwd=COPIA).stdout.strip() != ''
          and os.path.isfile(os.path.join(R, '.git', 'HEAD')), (r[:300], top))

    # --- G4: un worktree enlazado
    W = os.path.join(JAIL, 'wt')
    git('worktree', 'add', '-q', W, '-b', 'rama-wt', cwd=R)
    check('G4 previo: el worktree tiene un .git FICHERO', os.path.isfile(os.path.join(W, '.git')))
    r = srv.call('delphi_move', {'path': W, 'dest': os.path.join(JAIL, 'wt-copia'), 'copy': True})
    check('G4 un worktree enlazado no se copia: MOVE-022 (su git esta en otro repo), nada creado',
          mc.abre(r, 'SR_MOVE_COPIA_GIT_FUERA_FMT') and nada(os.path.join(JAIL, 'wt-copia')), r[:300])

    # --- G5: core.worktree fuera de lo que se copia
    C = repo(os.path.join(JAIL, 'conarbol'))
    T = os.path.join(JAIL, 'arbolfuera')
    os.makedirs(T)
    git('config', 'core.worktree', T, cwd=C)
    r = srv.call('delphi_move', {'path': C, 'dest': os.path.join(JAIL, 'conarbol-copia'), 'copy': True})
    check('G5 un repo con core.worktree fuera no se copia: MOVE-022 (working tree), nada creado',
          mc.abre(r, 'SR_MOVE_COPIA_GIT_FUERA_FMT') and mc.catalogo()['SF_MOVE_GIT_ARBOL'] in r
          and nada(os.path.join(JAIL, 'conarbol-copia')), r[:300])

    # --- G6: un repo detras de un enlace que la copia sigue
    E = os.path.join(JAIL, 'conenlace')
    os.makedirs(E)
    open(os.path.join(E, 'propio.txt'), 'w').write('mio\n')
    if mc.junction(os.path.join(E, 'lib'), R):
        r = srv.call('delphi_move', {'path': E, 'dest': os.path.join(JAIL, 'conenlace-copia'), 'copy': True})
        check('G6 un repo al que se llega por un enlace que la copia sigue no esta dentro: MOVE-022, nada creado',
              mc.abre(r, 'SR_MOVE_COPIA_GIT_FUERA_FMT') and mc.catalogo()['SF_MOVE_GIT_DETRAS_DE_ENLACE'] in r
              and nada(os.path.join(JAIL, 'conenlace-copia')), r[:300])
        os.rmdir(os.path.join(E, 'lib'))  # el enlace, no lo de detras
    else:
        check('G6 el junction de la prueba se crea', False)

    # --- G7: control, una subcarpeta de un repo sin su .git
    os.makedirs(os.path.join(R, 'sub'))
    open(os.path.join(R, 'sub', 'b.txt'), 'w').write('dos\n')
    r = srv.call('delphi_move', {'path': os.path.join(R, 'sub'), 'dest': os.path.join(JAIL, 'sub-copia'), 'copy': True})
    check('G7 control: una subcarpeta de un repo (sin su .git) se copia',
          mc.abre(r, 'SK_MOVE_COPIADO_FMT') and os.path.isfile(os.path.join(JAIL, 'sub-copia', 'b.txt')), r[:300])
finally:
    srv.cierra()
    try:
        mc.fin('ficheros como un operador 1230 (V19)')
    finally:
        mc.borra(BASE)
