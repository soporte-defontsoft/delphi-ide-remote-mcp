"""E2E battery for v0.74.0-beta - round 10 sweep (agent sweep10).

The data-loss trap sweep10 found: deleting a FOLDER whose content is locked (a
running .exe, a git process, the IDE) reported "A MEDIAS - the recoverable copy
IS made, the original could not be removed" - but the content had ALREADY been
moved into that copy and the original gutted, and every retry made another full
copy. A human reading "half done, retry" who purged those "leftover" copies
deleted real code.

Root cause: TDirectory.Move falls back to a recursive copy+delete of its own
accord when the atomic rename fails. The fix uses the raw Windows MoveFile,
which never copies: same-volume it renames atomically, and on a locked tree it
fails with everything untouched. Move or nothing.

  D1  a locked folder is NOT deleted and NOTHING is touched - no partial copy in
      the trash, the original intact, and a retry does not duplicate
  D2  the same folder, once unlocked, deletes cleanly

29-sep-2026 (Hermes, in the field): the lock was OURS. The server keeps one
DelphiLSP engine per project, alive from the first request; when the engine
loads the project's settings it makes the folder of the project's main source
its own current directory, and Windows will not rename or delete the current
directory of a live process (measured with the engine launched by hand). After
a single hover, deleting or moving the project's folder answered FILE-036 and
the agent had no way to close it. Every case below has its OWN project: a
check that inherits the scenario of the one before goes red for the other's
failure and never for its own (review of 1.7.7).

  D3   a project folder OUR engine holds is deleted: the server stops its own
       engine first - that one and no other
  D4   the same project created again at the SAME path gets a fresh engine
       that answers (it rests on D3's delete: it is its second half)
  D5   moving (renaming) the folder of a warm project works too, and the LSP
       answers in the new place
  D6   purging a project of the trash with an engine inside: gone, whole (it
       used to delete the content and leave the empty shell, FILE-011)
  D7   git worktree remove of a worktree with an engine inside: removed (git
       used to delete the content, fail on the folder and exit 255)
  D8   deleting a PARENT folder of a warm project stops the engine inside
  D9   deleting a SUBFOLDER of a warm project keeps its engine: it was never
       held (measured)
  D10  the LINTER engine (delphi_diagnostics) is one more engine: stopped too
  D11  deleting a JUNCTION to a folder with a warm project stops nothing:
       what goes is the link, not what is behind it
  D12  an EMPTY folder that is an engine's current directory is deleted (the
       empty-folder branch of delphi_delete does not go through the mover)
  D13  what the engine holds is the folder of the .dpr, not the one of the
       .dproj: with the main source in a subfolder, that subfolder is deleted
  D14  git, when it rewrites the tree: switching to a branch WITHOUT the
       project's folder leaves no empty shell behind (git deleted the files,
       could not remove the folder and said exit=0)
  D15  ...and the other commands that rewrite the tree: a fast-forward
       merge that takes the project's folder away
  D16  stash push of a project that is only staged takes its folder away,
       and stash pop brings it back
  D17  pull of a commit that removes the project's folder
  D18  what rewrites nothing stops nobody: stash list and switch create=true
       leave every engine of the repository running (they stopped them all)
  D19  stash push -- <path> stops the engines of THAT folder and no other
  D20  an engine that ENDS BY ITSELF (here: killed from outside) is replaced
       at the next request of its project. It stayed in the session's table,
       and every request of the project answered the transport's error until
       the server stopped or the folder left (fourth review of 1.7.7,
       measured: four hovers out of four)

Usage:  python tests/test_round14.py [path-to-DelphiLspMcp.exe]
"""
import os, glob, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round14')
EXE = mc.copia_exe(BASE)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='round14', t=30)
call = srv.call


def copies():
    return mc.copias(BASE, 'proj', bajo=True)  # el lector de la papelera

sub = os.path.join(BASE, 'proj')
os.makedirs(sub)
open(os.path.join(sub, 'a.txt'), 'w').write('a' * 100)
lh = open(os.path.join(sub, 'locked.exe'), 'w')          # keep the handle open
lh.write('x' * 50)
lh.flush()

# D1 - locked folder: nothing touched, nothing copied, retry does not duplicate
r1 = call('delphi_delete', {'path': sub})
r2 = call('delphi_delete', {'path': sub})
intact = (os.path.exists(os.path.join(sub, 'a.txt')) and
          os.path.exists(os.path.join(sub, 'locked.exe')) and
          open(os.path.join(sub, 'a.txt')).read() == 'a' * 100)
check('D1 carpeta bloqueada: no la borra y NO toca nada',
      mc.es(r1, 'SR_FILE_DELETE_LOCKED_FMT') and intact, r1)
check('D1 no deja copia a medias en la papelera (ni al reintentar)',
      len(copies()) == 0, copies())
check('D1 el reintento tampoco duplica ni gutea', mc.es(r2, 'SR_FILE_DELETE_LOCKED_FMT') and intact, r2)

# D2 - once unlocked, it deletes cleanly
lh.close()
r3 = call('delphi_delete', {'path': sub})
check('D2 sin lock, borra limpio', mc.abre(r3, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.exists(sub), r3)
check('D2 y AHORA si hay una copia recuperable', len(copies()) == 1, copies())


# D3-D13 (29-sep-2026): el bloqueo era NUESTRO (ver la cabecera)
def motores():
    # los pids de los DelphiLSP.exe hijos de ESTE servidor
    return mc.hijos_lsp(srv.p.pid)


def proyecto(nombre, dentro=None):
    d = os.path.join(dentro or BASE, nombre)
    r = call('delphi_create', {'kind': 'project-vcl', 'name': nombre, 'dir': d}, t=120)
    return d, os.path.join(d, nombre + '.dpr'), r


def hover(dpr, linea=9):
    # "Application.Initialize;" es la linea 10 del .dpr de la plantilla (9
    # contando desde cero); con una unit mas en el uses, la siguiente
    return call('delphi_hover', {'path': dpr, 'line': linea, 'character': 4}, t=180)


def caliente(h):
    return 'TApplication' in h


def borrada(r, carpeta):
    return mc.abre(r, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.lexists(carpeta)


def corto(*textos):
    return ' | '.join(' '.join(t.split())[-110:] for t in textos)


def otra_rama(texto):
    # la rama que NO es la actual, de lo que contesta command=branch (la
    # actual lleva el asterisco): con init.defaultBranch a otro nombre no era
    # ni master ni main, que es lo que se buscaba
    for l in texto.splitlines():
        t = l.split()
        if t and t[0] != '*' and not l.startswith('exit='):
            return t[0]
    return '(sin otra rama)'


# D3 - borrar la carpeta del proyecto
d1, dpr1, c1 = proyecto('Uno')
d2, dpr2, c2 = proyecto('Dos')
h1, h2 = hover(dpr1), hover(dpr2)
antes = motores()
check('D3 (preparacion) dos proyectos con el motor caliente, un proceso cada uno',
      caliente(h1) and caliente(h2) and len(antes) == 2,
      'motores=%s | %s' % (antes, corto(c1, c2, h1, h2)))
r = call('delphi_delete', {'path': d1}, t=60)
check('D3 la carpeta de un proyecto con NUESTRO motor dentro se borra: el servidor suelta lo suyo',
      borrada(r, d1), r)
quedan = motores()
check('D3 ...y para ESE motor y ningun otro: queda uno, y es de los de antes',
      len(quedan) == 1 and quedan[0] in antes, 'antes=%s quedan=%s' % (antes, quedan))

# D4 - la segunda mitad de D3: la misma ruta, otra vez
d1b, dpr1b, c1b = proyecto('Uno')
h1b = hover(dpr1b)
check('D4 el mismo proyecto creado de nuevo en la MISMA ruta: motor nuevo, y contesta',
      not mc.fallo(c1b) and caliente(h1b) and len(motores()) == 2, corto(c1b, h1b))

# D5 - mover (renombrar) la carpeta
d3, dpr3, c3 = proyecto('Tres')
h = hover(dpr3)
dm = os.path.join(BASE, 'TresMovido')
r = call('delphi_move', {'path': d3, 'dest': dm}, t=120)
check('D5 mover (renombrar) la carpeta de un proyecto con el motor caliente: tambien',
      caliente(h) and not mc.fallo(r) and os.path.exists(os.path.join(dm, 'Tres.dpr'))
      and not os.path.exists(d3), corto(c3, h, r))
h = hover(os.path.join(dm, 'Tres.dpr'))
check('D5 ...y en su sitio nuevo el LSP contesta', caliente(h), h[:120])

# D6 - la purga: a la papelera ANTES de ningun hover, hover en la copia, purga
d4, dpr4, c4 = proyecto('Cuatro')
rb = call('delphi_delete', {'path': d4}, t=60)
copia = [c for c in mc.copias(BASE, 'Cuatro', 'CAJON_BORRADOS') if os.path.isdir(c)]
h = hover(os.path.join(copia[0], 'Cuatro.dpr')) if copia else ''
n0 = len(motores())
r = call('delphi_delete', {'path': copia[0], 'purge': True}, t=60) if copia else 'sin copia'
check('D6 purgar un proyecto de la papelera con NUESTRO motor dentro: se va entero, sin cascaron',
      len(copia) == 1 and caliente(h) and not mc.fallo(r) and not os.path.exists(copia[0])
      and len(motores()) == n0 - 1, corto(c4, rb, h, r))

# D7 - git worktree remove: la carpeta la borra git, no el guard
repo = os.path.join(BASE, 'repo')
pasos = [call('delphi_create', {'kind': 'project-vcl', 'name': 'Wt', 'dir': repo}, t=120),
         call('delphi_git', {'repo': repo, 'command': 'init'}, t=60),
         call('delphi_git', {'repo': repo, 'command': 'config', 'args': 'user.name',
                             'message': 'round14'}, t=60),
         call('delphi_git', {'repo': repo, 'command': 'config', 'args': 'user.email',
                             'message': 'round14@example.com'}, t=60),
         call('delphi_git', {'repo': repo, 'command': 'add', 'args': '.'}, t=60),
         call('delphi_git', {'repo': repo, 'command': 'commit', 'message': 'uno'}, t=60)]
wt = os.path.join(BASE, 'wt')
pasos.append(call('delphi_git', {'repo': repo, 'command': 'worktree', 'args': 'add',
                                 'path': wt, 'ref': 'HEAD'}, t=120))
h = hover(os.path.join(wt, 'Wt.dpr'))
n0 = len(motores())
check('D7 (preparacion) el worktree existe y su motor esta caliente',
      not any(mc.fallo(p) for p in pasos) and os.path.exists(os.path.join(wt, 'Wt.dpr'))
      and caliente(h), corto(*pasos, h))
r = call('delphi_git', {'repo': repo, 'command': 'worktree', 'args': 'remove', 'path': wt}, t=120)
check('D7 git worktree remove con NUESTRO motor dentro: git la quita entera, y su motor se paro',
      not mc.fallo(r) and not os.path.exists(wt) and len(motores()) == n0 - 1,
      'motores %s -> %s | %s' % (n0, len(motores()), r))

# D8 - una carpeta PADRE del proyecto
grupo = os.path.join(BASE, 'grupo')
d5, dpr5, c5 = proyecto('Cinco', grupo)
h = hover(dpr5)
n0 = len(motores())
r = call('delphi_delete', {'path': grupo}, t=60)
check('D8 borrar una carpeta PADRE de un proyecto caliente: para el motor de dentro',
      caliente(h) and borrada(r, grupo) and len(motores()) == n0 - 1,
      'motores %s -> %s | %s' % (n0, len(motores()), corto(c5, h, r)))

# D9 - una SUBCARPETA del proyecto: nunca estuvo retenida, y su motor se queda
d6, dpr6, c6 = proyecto('Seis')
u = call('delphi_create', {'kind': 'unit', 'name': 'USub', 'project': dpr6, 'dir': 'Sub'}, t=120)
h = hover(dpr6, 10)      # el uses tiene una linea mas: la de USub
antes = motores()
subc = os.path.join(d6, 'Sub')
r = call('delphi_delete', {'path': subc}, t=60)
check('D9 borrar una SUBCARPETA de un proyecto caliente: se borra y su motor SIGUE (los mismos procesos)',
      caliente(h) and borrada(r, subc) and motores() == antes,
      'motores %s -> %s | %s' % (antes, motores(), corto(c6, u, h, r)))

# D10 - el motor del LINTER
d7, dpr7, c7 = proyecto('Siete')
n0 = len(motores())
dg = call('delphi_diagnostics', {'path': os.path.join(d7, 'UMain.pas')}, t=180)
n1 = len(motores())
r = call('delphi_delete', {'path': d7}, t=60)
check('D10 el motor del LINTER (delphi_diagnostics) es uno mas: arranca, retiene y tambien se para',
      '"errors"' in dg and n1 == n0 + 1 and borrada(r, d7) and len(motores()) == n0,
      'motores %s -> %s -> %s | %s' % (n0, n1, len(motores()), corto(c7, dg, r)))

# D11 - un ENLACE: lo que se va es el enlace, no lo de detras
real = os.path.join(BASE, 'real')
d8, dpr8, c8 = proyecto('Ocho', real)
h = hover(dpr8)
enlace = os.path.join(BASE, 'enlace')
mk = subprocess.run(['cmd', '/c', 'mklink', '/J', enlace, real], capture_output=True, text=True)
antes = motores()
r = call('delphi_delete', {'path': enlace}, t=60)
check('D11 borrar un ENLACE a una carpeta con un proyecto caliente: se va el enlace y NO se para nada',
      mk.returncode == 0 and caliente(h) and borrada(r, enlace) and os.path.exists(dpr8)
      and motores() == antes, 'motores %s -> %s | %s' % (antes, motores(), corto(c8, h, r)))

# D12 - una carpeta VACIA que es el directorio de trabajo de un motor: algo
# de fuera la vacio (git, al cambiar de rama) y queda el cascaron
d9, dpr9, c9 = proyecto('Nueve')
h = hover(dpr9)
for f in os.listdir(d9):
    os.remove(os.path.join(d9, f))
r = call('delphi_delete', {'path': d9}, t=60)
check('D12 una carpeta VACIA con un motor dentro se borra (la rama de carpeta vacia no pasa por el mudador)',
      caliente(h) and mc.es(r, 'SN_FILE_DELETE_EMPTY_OK_FMT') and not os.path.exists(d9), corto(c9, h, r))

# D13 - el .dpr en una SUBCARPETA del .dproj: el motor retiene la del .dpr
d10, dpr10, c10 = proyecto('Diez')
src = os.path.join(d10, 'src')
os.makedirs(src)
fuente = open(dpr10, 'rb').read().replace(b"'UMain.pas'", b"'..\\UMain.pas'")
open(os.path.join(src, 'Diez.dpr'), 'wb').write(fuente)
os.remove(dpr10)
dproj = os.path.join(d10, 'Diez.dproj')
xml = open(dproj, 'rb').read()
cambia = xml.count(b'<MainSource>Diez.dpr</MainSource>') == 1
open(dproj, 'wb').write(xml.replace(b'<MainSource>Diez.dpr</MainSource>',
                                    b'<MainSource>src\\Diez.dpr</MainSource>'))
h = hover(os.path.join(src, 'Diez.dpr'))
n0 = len(motores())
r = call('delphi_delete', {'path': src}, t=60)
check('D13 con el .dpr en una subcarpeta, ESA subcarpeta (la que retiene el motor) se borra',
      cambia and caliente(h) and borrada(r, src) and len(motores()) == n0 - 1,
      'motores %s -> %s | %s' % (n0, len(motores()), corto(c10, h, r)))

# D14 - git al cambiar de rama: la de destino no tiene la carpeta del proyecto
rg = os.path.join(BASE, 'ramas')
os.makedirs(rg)
open(os.path.join(rg, 'LEEME.txt'), 'w').write('uno')


def g(**kw):
    return call('delphi_git', dict(repo=rg, **kw), t=120)


pasos = [g(command='init'),
         g(command='config', args='user.name', message='round14'),
         g(command='config', args='user.email', message='round14@example.com'),
         g(command='add', args='.'),
         g(command='commit', message='base'),
         g(command='switch', args='con-proyecto', create=True)]
dr, dprr, cr = proyecto('Rama', rg)
pasos += [cr, g(command='add', args='.'), g(command='commit', message='proyecto')]
h = hover(dprr)
principal = otra_rama(g(command='branch'))
n0 = len(motores())
check('D14 (preparacion) el repo tiene dos ramas, el proyecto solo en una, y su motor esta caliente',
      not any(mc.fallo(p) for p in pasos) and os.path.exists(dprr) and caliente(h), corto(*pasos, h))
r = g(command='switch', args=principal)
check('D14 git switch a una rama SIN la carpeta del proyecto: no deja el cascaron, y su motor se paro',
      not mc.fallo(r) and not os.path.exists(dr) and len(motores()) == n0 - 1,
      'queda la carpeta: %s | motores %s -> %s | %s' % (os.path.exists(dr), n0, len(motores()), r))


# D15-D19 (segunda revision de la 1.7.7): lo demas de git que reescribe el
# arbol, y lo que NO lo reescribe. Un repo por caso.
def repo_nuevo(nombre):
    d = os.path.join(BASE, nombre)
    os.makedirs(d)
    open(os.path.join(d, 'LEEME.txt'), 'w').write('uno')

    def git(**kw):
        return call('delphi_git', dict(repo=d, **kw), t=120)
    p = [git(command='init'),
         git(command='config', args='user.name', message='round14'),
         git(command='config', args='user.email', message='round14@example.com'),
         git(command='add', args='.'),
         git(command='commit', message='base')]
    return d, git, p


def retienen(carpeta):
    return mc.motores_en(srv.p.pid, carpeta)


def vivos(pids):
    # de ESOS motores, los que siguen siendo hijos del servidor. Que un motor
    # se paro se mide por su pid: "nadie retiene la carpeta" lo dice tambien
    # una carpeta que ya no esta, y un motor cuyo directorio de trabajo no se
    # dejo leer (cuarta revision de la 1.7.7)
    return sorted(set(pids) & set(motores()))


def git_fuera(*a, cwd):
    # el git de la maquina, para montar lo que la tool no hace (un remoto)
    r = subprocess.run(['git', '-c', 'user.name=round14', '-c', 'user.email=round14@example.com']
                       + list(a), cwd=cwd, capture_output=True, text=True)
    return '%s%s' % (r.stdout, r.stderr)


# D15 - merge (fast-forward) de una rama que QUITA la carpeta del proyecto
rm_, gm, pasos = repo_nuevo('funde')
df, dprf, cf = proyecto('Funde', rm_)
pasos += [cf, gm(command='add', args='.'), gm(command='commit', message='proyecto'),
          gm(command='switch', args='quita', create=True)]
mc.borra(df)
pasos += [gm(command='add', args='.'), gm(command='commit', message='sin el proyecto')]
pasos.append(gm(command='switch', args=otra_rama(gm(command='branch'))))
h = hover(dprf)
de_f = retienen(df)
check('D15 (preparacion) la rama de destino quita la carpeta, y en esta su motor la retiene',
      not any(mc.fallo(p) for p in pasos) and caliente(h) and len(de_f) == 1,
      'retienen=%s | %s' % (de_f, corto(*pasos, h)))
r = gm(command='merge', args='quita')
check('D15 git merge de una rama SIN la carpeta del proyecto: no deja el cascaron, y su motor se paro',
      not mc.fallo(r) and not os.path.exists(df) and not vivos(de_f),
      'queda la carpeta: %s | su motor %s, vivos %s | %s' % (os.path.exists(df), de_f, vivos(de_f), r))

# D16 - stash push de un proyecto que solo esta en el indice, y pop
ra, ga, pasos = repo_nuevo('aparca')
da, dpra, ca = proyecto('Aparca', ra)
pasos += [ca, ga(command='add', args='.')]
h = hover(dpra)
de_a = retienen(da)
check('D16 (preparacion) el proyecto esta en el indice y su motor retiene la carpeta',
      not any(mc.fallo(p) for p in pasos) and caliente(h) and len(de_a) == 1,
      'retienen=%s | %s' % (de_a, corto(*pasos, h)))
r = ga(command='stash')
check('D16 git stash de un proyecto recien anadido: se lleva la carpeta entera, y su motor se paro',
      not mc.fallo(r) and not os.path.exists(da) and not vivos(de_a),
      'queda la carpeta: %s | su motor %s, vivos %s | %s' % (os.path.exists(da), de_a, vivos(de_a), r))
r = ga(command='stash', args='pop')
h = hover(dpra)
check('D16 ...y stash pop la devuelve, y el LSP contesta en ella',
      not mc.fallo(r) and os.path.exists(dpra) and caliente(h), corto(r, h))

# D18 - lo que no reescribe nada no para a nadie. Con SU repo y su proyecto
# (iba sobre el motor de D16: rojo por el fallo de otro)
rq, gq, pasos = repo_nuevo('quieto')
dq, dprq, cq = proyecto('Quieto', rq)
pasos += [cq, gq(command='add', args='.')]
h = hover(dprq)
de_q = retienen(dq)
antes = motores()
r1 = gq(command='stash', args='list')
r2 = gq(command='switch', args='nueva', create=True)
check('D18 stash list y switch create=true no paran ningun motor (paraban los del repo entero)',
      not any(mc.fallo(p) for p in pasos) and caliente(h) and len(de_q) == 1
      and not mc.fallo(r1) and not mc.fallo(r2) and vivos(de_q) == de_q and motores() == antes,
      'su motor %s | motores %s -> %s | %s' % (de_q, antes, motores(), corto(*pasos, h, r1, r2)))

# D19 - stash push -- <ruta>: los motores de ESA carpeta, y ningun otro
rd, gd, pasos = repo_nuevo('pareja')   # ('dos' es la carpeta del proyecto Dos, de D3)
dx, dprx, cx = proyecto('Equis', rd)
dy, dpry, cy = proyecto('Ye', rd)
pasos += [cx, cy, gd(command='add', args='.'), gd(command='commit', message='dos proyectos')]
open(os.path.join(dx, 'UMain.pas'), 'a').write('\n// un cambio\n')
hx, hy = hover(dprx), hover(dpry)
de_x, de_y = retienen(dx), retienen(dy)
check('D19 (preparacion) dos proyectos del mismo repo, cada uno con su motor',
      not any(mc.fallo(p) for p in pasos) and caliente(hx) and caliente(hy)
      and len(de_x) == 1 and len(de_y) == 1 and de_x != de_y, corto(*pasos, hx, hy))
r = gd(command='stash', args='push -- Equis/UMain.pas')
check('D19 stash push -- <ruta>: para el motor de ESA carpeta y el del otro proyecto sigue',
      not mc.fallo(r) and not vivos(de_x) and vivos(de_y) == de_y,
      'Equis %s, vivos %s | Ye %s, vivos %s | %s' % (de_x, vivos(de_x), de_y, vivos(de_y), r))

# D17 - pull de un commit que quita la carpeta del proyecto. El remoto es una
# carpeta de la bateria (la tool no tiene "remote add": lo monta el git de la
# maquina, que es andamio)
origen = os.path.join(BASE, 'origen.git')
clon = os.path.join(BASE, 'clon')
otro = os.path.join(BASE, 'otro')
andamio = [git_fuera('init', '--bare', origen, cwd=BASE), git_fuera('clone', origen, clon, cwd=BASE)]


def gc(**kw):
    return call('delphi_git', dict(repo=clon, **kw), t=180)


dt, dprt, ct = proyecto('Trae', clon)
pasos = [ct, gc(command='config', args='user.name', message='round14'),
         gc(command='config', args='user.email', message='round14@example.com'),
         gc(command='add', args='.'), gc(command='commit', message='con el proyecto'),
         gc(command='push', args='origin HEAD')]
rama = git_fuera('branch', '--show-current', cwd=clon).strip()
andamio += [git_fuera('clone', origen, otro, cwd=BASE)]
mc.borra(os.path.join(otro, 'Trae'))
open(os.path.join(otro, 'LEEME.txt'), 'w').write('sin el proyecto')
andamio += [git_fuera('add', '-A', cwd=otro), git_fuera('commit', '-m', 'sin el proyecto', cwd=otro),
            git_fuera('push', 'origin', 'HEAD', cwd=otro)]
h = hover(dprt)
de_t = retienen(dt)
check('D17 (preparacion) el remoto ya no tiene la carpeta, y aqui su motor la retiene',
      not any(mc.fallo(p) for p in pasos) and rama != '' and caliente(h) and len(de_t) == 1,
      'rama=%r retienen=%s | %s | %s' % (rama, de_t, corto(*pasos, h), corto(*andamio)))
r = gc(command='pull', args='origin ' + rama)
check('D17 git pull de un commit SIN la carpeta del proyecto: no deja el cascaron, y su motor se paro',
      not mc.fallo(r) and not os.path.exists(dt) and not vivos(de_t),
      'queda la carpeta: %s | su motor %s, vivos %s | %s' % (os.path.exists(dt), de_t, vivos(de_t), r))

# D20 - un motor que se acaba SOLO se sustituye en la siguiente peticion
dm, dprm, cm = proyecto('Muere')
h = hover(dprm)
de_m = retienen(dm)
for pid in de_m:
    subprocess.run(['taskkill', '/PID', str(pid), '/F'], capture_output=True)   # andamio
muerto = not vivos(de_m)
h2 = hover(dprm)
ahora = retienen(dm)
check('D20 un motor que se acaba solo (aqui, matado desde fuera) se sustituye en la siguiente '
      'peticion de su proyecto: contesta, con un motor NUEVO',
      not mc.fallo(cm) and caliente(h) and len(de_m) == 1 and muerto
      and caliente(h2) and len(ahora) == 1 and ahora != de_m,
      'era %s (muerto: %s), ahora %s | %s' % (de_m, muerto, ahora, corto(h, h2)))

# Salida LIMPIA (el servidor para sus motores) y nada en la maquina: mata()
# dejaba motores huerfanos con su carpeta como directorio de trabajo, la
# carpeta de la bateria entera y sus caches de configuracion.
srv.cierra()
for j in mc.copias(BASE, 'enlace', bajo=True) + [enlace]:
    if os.path.isjunction(j):
        os.rmdir(j)              # el enlace como ENTRADA, nunca lo de detras
if mc.F == 0:
    mc.borra(BASE)
    mc.limpia_caches_lsp()
mc.fin('round-14 battery')
