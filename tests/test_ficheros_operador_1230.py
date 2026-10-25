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

Fase 4, el comodin y los choques (la nota de la fase 3 la miden test_mudanza,
test_contratos_1222, test_puerta_leer y test_resultados):
  W1  move *.pas a una carpeta que no existe: a.pas y b.pas, y b.pas2 se queda
      (casa como casa el sistema, por el nombre largo)
  W2  copy=true *.txt: copiados, y los de origen siguen
  W3  delete *.tmp: los dos a la papelera, lo demas sigue
  W4  nada casa: FILE-047, nada escrito
  W5  con comodin, dest es la CARPETA: un fichero, FILE-048
  W6  un comodin en una carpeta (de path o de dest): GUARD-024 en la entrada
      (FILE-049 es la segunda barrera, sin jaula)
  W7  un comodin en la papelera o con purge: FILE-050 (alli se nombra cada uno)
  C1  choques: FILE-025 con la LISTA de los que ya estan, y nada movido (tampoco
      el que no chocaba): todo o nada
  C2  una carpeta a otra que existe se MEZCLA en ella (subcarpetas incluidas) y
      la de origen se va
  C3  ...y con un fichero de dentro cogido: SYS-027 que lo nombra, y todo vuelve
  C4  renombrar cambiando solo las mayusculas, un fichero y una carpeta (r1222ce
      daba FILE-025, el destino "ya existia"; V19, MOVE-009)
  C5  MAX_PATH: GUARD-028 con la ruta mas larga que escribiria, y nada escrito
  C6  dos copias del mismo proyecto, y las dos compilan
  C7  la nota de una MEZCLA (move y copy) cuenta lo que entro y no lo que ya
      estaba: un .dproj del destino con una ruta que sale de el no se movio
      (salia en MOVE-023; medido el 25-oct-2026, sonda_mezcla_nota)

Mutante: produccion r1222ce, 11 rojos: W1-W5 y W7 (GUARD-024 a todo comodin), C1
(GUARD-024), C2-C4 (FILE-025: ni mezcla ni mayusculas) y C5 (MOVE-012 INTERNAL a
mitad). W6 y C6 son guardas: GUARD-024 ya era asi, y la copia es de la fase 2.

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

    # --- fase 4: el comodin
    def escribe(p, t='x\n'):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'w').write(t)

    def arbol(d):
        return sorted(os.path.relpath(os.path.join(r_, f), d) for r_, _, fs in os.walk(d) for f in fs
                      if mc.PAPELERA not in r_)

    W = os.path.join(JAIL, 'w')
    for n in ('a.pas', 'b.pas', 'b.pas2', 'c.txt', 'd.txt', 'e.tmp', 'f.tmp'):
        escribe(os.path.join(W, n))
    r = srv.call('delphi_move', {'path': os.path.join(W, '*.pas'), 'dest': os.path.join(W, 'pas')})
    check('W1 move *.pas a una carpeta que no existe: a.pas y b.pas, y b.pas2 se queda',
          mc.ids(r).count(mc.id_de('SK_MOVE_MOVIDO_FMT')) == 2 and
          arbol(W) == ['b.pas2', 'c.txt', 'd.txt', 'e.tmp', 'f.tmp', os.path.join('pas', 'a.pas'),
                       os.path.join('pas', 'b.pas')], (r[:300], arbol(W)))
    r = srv.call('delphi_move', {'path': os.path.join(W, '*.txt'), 'dest': os.path.join(W, 'txt'), 'copy': True})
    check('W2 copy=true *.txt: copiados, y los de origen siguen',
          mc.ids(r).count(mc.id_de('SK_MOVE_COPIADO_FMT')) == 2 and
          all(os.path.isfile(os.path.join(W, *p)) for p in (('c.txt',), ('d.txt',), ('txt', 'c.txt'), ('txt', 'd.txt'))),
          (r[:300], arbol(W)))
    r = srv.call('delphi_delete', {'path': os.path.join(W, '*.tmp')})
    check('W3 delete *.tmp: los dos a la papelera, lo demas sigue',
          mc.ids(r).count(mc.id_de('SK_FILE_BORRADO_PAPELERA_FMT')) == 2 and
          mc.copias(W, 'e.tmp', 'CAJON_BORRADOS') and mc.copias(W, 'f.tmp', 'CAJON_BORRADOS') and
          not os.path.exists(os.path.join(W, 'e.tmp')) and os.path.isfile(os.path.join(W, 'b.pas2')), r[:300])
    antes = arbol(W)
    r = srv.call('delphi_move', {'path': os.path.join(W, '*.zzz'), 'dest': os.path.join(W, 'z')})
    check('W4 nada casa: FILE-047 y nada escrito', mc.abre(r, 'SR_FILE_COMODIN_NADA_FMT') and arbol(W) == antes,
          r[:300])
    r = srv.call('delphi_move', {'path': os.path.join(W, '*.txt'), 'dest': os.path.join(W, 'c.txt')})
    check('W5 con comodin dest es la CARPETA: un fichero, FILE-048', mc.abre(r, 'SR_FILE_COMODIN_DEST_FICHERO_FMT') and
          arbol(W) == antes, r[:300])
    r = srv.call('delphi_move', {'path': os.path.join(W, 'p*', 'a.pas'), 'dest': os.path.join(W, 'otra')})
    r2 = srv.call('delphi_move', {'path': os.path.join(W, 'c.txt'), 'dest': os.path.join(W, 'x*', 'c.txt')})
    check('W6 un comodin en una carpeta, de path o de dest: GUARD-024 en la entrada',
          mc.abre(r, 'SR_GUARD_COMODIN_FMT') and mc.abre(r2, 'SR_GUARD_COMODIN_FMT') and arbol(W) == antes,
          (r[:200], r2[:200]))
    cajon = os.path.dirname(mc.copias(W, 'e.tmp', 'CAJON_BORRADOS')[0]) if mc.copias(W, 'e.tmp', 'CAJON_BORRADOS') else W
    r = srv.call('delphi_delete', {'path': os.path.join(cajon, '*')})
    r2 = srv.call('delphi_delete', {'path': os.path.join(W, '*.txt'), 'purge': True})
    check('W7 un comodin en la papelera o con purge: FILE-050, y la papelera y lo demas como estaban',
          mc.abre(r, 'SR_FILE_COMODIN_PAPELERA_FMT') and mc.abre(r2, 'SR_FILE_COMODIN_PAPELERA_FMT') and
          arbol(W) == antes and len(mc.copias(W, None, 'CAJON_BORRADOS')) >= 2, (r[:200], r2[:200]))

    # --- fase 4: los choques y la mezcla
    C = os.path.join(JAIL, 'c')
    for n in ('u1.txt', 'u2.txt', 'u3.txt'):
        escribe(os.path.join(C, 'src', n), 'src\n')
    escribe(os.path.join(C, 'dst', 'u2.txt'), 'dst\n')
    escribe(os.path.join(C, 'dst', 'u3.txt'), 'dst\n')
    antes = arbol(C)
    r = srv.call('delphi_move', {'path': os.path.join(C, 'src', '*.txt'), 'dest': os.path.join(C, 'dst')})
    check('C1 choques: FILE-025 con la LISTA (u2 y u3) y nada movido, tampoco u1',
          mc.abre(r, 'SR_FILE_DESTINO_YA_EXISTE_FMT') and 'u2.txt' in r and 'u3.txt' in r and 'u1.txt' not in r and
          arbol(C) == antes and open(os.path.join(C, 'dst', 'u2.txt')).read() == 'dst\n', (r[:400], arbol(C)))
    escribe(os.path.join(C, 'm1', 'k', 'a.txt'))
    escribe(os.path.join(C, 'm1', 'k', 'sub', 'b.txt'))
    escribe(os.path.join(C, 'm2', 'k', 'c.txt'))
    r = srv.call('delphi_move', {'path': os.path.join(C, 'm1', 'k'), 'dest': os.path.join(C, 'm2', 'k')})
    check('C2 una carpeta a otra que existe se mezcla en ella (con su subcarpeta) y la de origen se va',
          mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and not os.path.exists(os.path.join(C, 'm1', 'k')) and
          arbol(os.path.join(C, 'm2', 'k')) == ['a.txt', 'c.txt', os.path.join('sub', 'b.txt')], (r[:300], arbol(C)))
    escribe(os.path.join(C, 'n1', 'k', 'a.txt'))
    escribe(os.path.join(C, 'n1', 'k', 'b.txt'))
    escribe(os.path.join(C, 'n2', 'k', 'c.txt'))
    with mc.bloqueado(os.path.join(C, 'n1', 'k', 'b.txt'), lectura=True):  # leer si; mover no
        r = srv.call('delphi_move', {'path': os.path.join(C, 'n1', 'k'), 'dest': os.path.join(C, 'n2', 'k')})
    check('C3 ...y con un fichero de dentro cogido: SYS-027 que lo nombra, y todo vuelve a su sitio',
          mc.abre(r, 'SR_FICHERO_OCUPADO_FMT') and 'b.txt' in r and
          arbol(os.path.join(C, 'n1', 'k')) == ['a.txt', 'b.txt'] and arbol(os.path.join(C, 'n2', 'k')) == ['c.txt'],
          (r[:300], arbol(C)))
    escribe(os.path.join(C, 'may', 'abc.txt'))
    escribe(os.path.join(C, 'may', 'carpeta', 'dentro.txt'))
    r = srv.call('delphi_move', {'path': os.path.join(C, 'may', 'abc.txt'), 'dest': os.path.join(C, 'may', 'ABC.txt')})
    r2 = srv.call('delphi_move', {'path': os.path.join(C, 'may', 'carpeta'), 'dest': os.path.join(C, 'may', 'CARPETA')})
    check('C4 renombrar cambiando solo las mayusculas, un fichero y una carpeta (con lo de dentro)',
          mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and mc.abre(r2, 'SK_MOVE_MOVIDO_FMT') and
          sorted(n for n in os.listdir(os.path.join(C, 'may')) if n != mc.PAPELERA) == ['ABC.txt', 'CARPETA'] and
          os.listdir(os.path.join(C, 'may', 'CARPETA')) == ['dentro.txt'], (r[:200], r2[:200]))
    hondo = os.path.join(C, 'h', 'x' * 60, 'y' * 60)
    escribe(os.path.join(hondo, 'z' * 40 + '.txt'))
    largo = os.path.join(C, 'destino' + 'q' * 90)
    r = srv.call('delphi_move', {'path': os.path.join(C, 'h'), 'dest': largo})
    check('C5 MAX_PATH: GUARD-028 con la ruta mas larga que escribiria, y nada escrito',
          mc.abre(r, 'SR_GUARD_RUTA_LARGA_FMT') and ('z' * 40 + '.txt') in r and
          os.path.isfile(os.path.join(hondo, 'z' * 40 + '.txt')) and not os.path.exists(largo), r[:300])

    # --- C6: varias copias del mismo proyecto, y compilan
    for n in ('proyA', 'proyB'):
        srv.call('delphi_move', {'path': PDIR, 'dest': os.path.join(JAIL, n), 'copy': True})
    oks = []
    for n in ('proyA', 'proyB'):
        b = mc.como_json(srv.call('delphi_build', {'project': os.path.join(JAIL, n, 'Pr.dproj')}, 600))
        oks.append(b.get('success') is True)
    check('C6 dos copias del mismo proyecto, y las dos compilan', oks == [True, True], oks)

    # --- C7: la nota de una mezcla, solo de lo que entro
    for modo in ('move', 'copy'):
        d = os.path.join(C, 'nota-' + modo)
        for l in ('m1', 'm2'):
            os.makedirs(os.path.join(d, l, 'lib'))
        srv.call('delphi_create', {'kind': 'project-console', 'name': 'Ya', 'dir': os.path.join(d, 'm2', 'k')})
        srv.call('delphi_config', {'command': 'add-searchpath', 'path': '..\\lib',
                                   'project': os.path.join(d, 'm2', 'k', 'Ya.dproj')})
        srv.call('delphi_create', {'kind': 'project-console', 'name': 'Llega', 'dir': os.path.join(d, 'm1', 'k', 'sub')})
        srv.call('delphi_config', {'command': 'add-searchpath', 'path': '..\\..\\lib',
                                   'project': os.path.join(d, 'm1', 'k', 'sub', 'Llega.dproj')})
        args = {'path': os.path.join(d, 'm1', 'k'), 'dest': os.path.join(d, 'm2', 'k')}
        if modo == 'copy':
            args['copy'] = True
        r = srv.call('delphi_move', args)
        check('C7 la nota de una mezcla (%s) cuenta lo que entro (Llega.dproj) y no lo que ya estaba (Ya.dproj)' % modo,
              mc.es(r, 'SN_REFERENCIAS_CRUZAN_FMT') and 'Llega.dproj (' in r and 'Ya.dproj (' not in r and
              os.path.isfile(os.path.join(d, 'm2', 'k', 'sub', 'Llega.dproj')), r[-600:])
finally:
    srv.cierra()
    try:
        mc.fin('ficheros como un operador 1230 (V19)')
    finally:
        mc.borra(BASE)
