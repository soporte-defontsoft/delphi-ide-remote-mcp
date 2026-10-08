"""E2E battery (1.7.7): delphi_git stays inside the workspace.

git does not work on the folder it is given: it climbs from it until it finds
the repository, and reads and rewrites THAT whole tree. The tool's gate looked
at the folder alone. Measured 2026-09-29 (the second review of 1.7.7 read it,
David asked, a probe measured it): a session whose only root was mono/a, with
the .git in mono, was shown the content of mono/b by diff, rewrote it with
stash and with switch, and wrote mono/.git with commit and config -
delphi_read of the same file answered GUARD-002, as it should.

Now the three folders of the repository go through the gate the folder went
through - the root of the working tree, its git folder and the common one (the
main repository's, for a linked worktree) - and git runs PINNED to them
(--git-dir, --work-tree): it works where the gate looked.

  J1  the repository's root is ABOVE the session's root: every command is
      refused (GIT-041), and nothing outside is read or touched - the
      neighbour's file, the history, the config
  J2  the control: the same commands on a repository that lives inside the
      roots work, from its root and from a subfolder
  J3  a linked worktree inside the roots of a repository that lives outside:
      its git folder is outside, and it is refused too
  J4  init inside a folder of the session under somebody else's repository
      makes ITS OWN repository there, and from then on git works on that one
  J5  a bare repository inside the roots (no working tree): log and branch
      answer
  J6  a folder that is no repository at all is told so by git, as before
  J7  a repository in a folder with spaces and an accent in its name: the
      pinned paths reach git whole
  J8  "repo" pointing at the .git folder itself: git says it has no working
      tree there, as it always did. Pinned with --git-dir alone it took the
      current directory for the working tree: status listed the content of
      .git as sources and switch wrote the branch's files INSIDE .git
      (third review of 1.7.7, measured with plain git)
  J9  the REMOTE of fetch, pull and push is where git reads from or writes
      to: a network address the operator allows, or a folder that passes
      the jail's gate. A folder OUTSIDE the roots is refused, given by its
      path, as file:// or by the name of a remote of the repository, and
      nothing changes out there. Measured 2026-09-29: fetch brought its
      history and push wrote branches in it
  J10 the control: a folder INSIDE the roots is a remote like any other, by
      its path and by its name
  J11 of the options, fetch and push take a short list and no other
  J12 what push SENDS, after the remote, is names: it adds to the remote and
      never overwrites or deletes what is there. Measured 2026-09-29, with
      --force and --delete already refused by their name: "origin +main"
      rewrote the remote's branch and "origin :sobra" deleted it
  J13 of file:// ONE form is taken, the one that reads the same here and in
      git: file:///<drive>:/<path> with nothing percent-encoded. git decodes
      %xx and the judge read it as it came (two folders), and a remote of
      the repository with its address as file://C:/... (two slashes) passed
      for a network address: fetch and push reached a folder outside the
      roots (fourth review of 1.7.7, measured through the tool)
  J14 a remote that is a folder INSIDE the roots whose repository lives
      OUTSIDE (a linked worktree: its .git is a pointer) is refused: git
      serves and writes the repository the pointer names. And a remote that
      is a folder is a folder that IS THERE: given the pointer file itself
      (<worktree>/.git), or a path git adds .git to, what git opened was not
      what had been looked at (measured by the review of this same fix)
  J15 a remote of the repository whose address is ssh in its short form,
      with no user (host:path), reaches git: it was taken for a folder
  J16 with no names in the call, what push sends is decided by the
      repository's configuration, and that is judged too: from a MIRROR
      repository a bare push deleted a branch of the remote
  J17 the roots on a NETWORK DRIVE LETTER (X: connected to a share): git
      answers where the repository lives with its REAL path, which there is
      the UNC (//host/share/...), and the gate judges by the declared form.
      Measured 2026-09-30 on a machine with its roots on such a letter:
      GIT-041 to every command that works on an existing repository. git's
      answer is now written in the declared
      form before it is judged (Lsp.Lugares.FormaDeclarada). Needs a connected
      network drive in the session that runs the battery:
      DELPHI_MCP_TEST_NETDIR names a folder of it to work in; without it the
      battery says so (NOTA) and the rule alone is in LspTests.Rutas

Usage:  python tests/test_git_jaula.py [path-to-DelphiLspMcp.exe]
"""
import os, re, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git-jaula')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
MONO = os.path.join(BASE, 'mono')          # el repo de OTRO: fuera de las raices
A = os.path.join(MONO, 'a')                # la unica raiz de la sesion
B = os.path.join(MONO, 'b')                # el vecino
SECRETO = os.path.join(B, 'secreto.txt')
EXTRA = os.path.join(B, 'extra.txt')


def git(*a, cwd):
    # el git de la maquina: el andamio, no lo que se mide
    r = subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@example.com'] + list(a),
                       cwd=cwd, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def lee(p):
    return open(p, encoding='utf-8').read().strip() if os.path.exists(p) else '<no esta>'


def corto(t, n=150):
    return ' '.join(t.split())[:n]


os.makedirs(A)
os.makedirs(B)
open(os.path.join(A, 'uno.txt'), 'w').write('uno de a\n')
open(SECRETO, 'w').write('SECRETO-BASE\n')
git('init', '-q', '-b', 'main', cwd=MONO)
git('add', '.', cwd=MONO)
git('commit', '-qm', 'base', cwd=MONO)
git('switch', '-qc', 'otra', cwd=MONO)
open(SECRETO, 'w').write('SECRETO-OTRA\n')
open(EXTRA, 'w').write('solo en otra\n')
git('add', '.', cwd=MONO)
git('commit', '-qm', 'otra', cwd=MONO)
git('switch', '-q', 'main', cwd=MONO)
open(SECRETO, 'w').write('SECRETO-SIN-COMMIT\n')      # un cambio del vecino, sin guardar
open(os.path.join(A, 'nuevo.txt'), 'w').write('nuevo\n')   # y algo que anadir, en lo de la sesion


def foto():
    # todo lo de fuera que git podria tocar
    return (lee(SECRETO), lee(EXTRA), git('rev-parse', 'HEAD', cwd=MONO),
            git('branch', '--show-current', cwd=MONO), git('stash', 'list', cwd=MONO),
            git('tag', cwd=MONO), lee(os.path.join(MONO, '.git', 'config')),
            git('status', '--porcelain', cwd=MONO))


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': A}), nombre='git-jaula', t=120)
call = srv.call

# J1 - la raiz del repo, por ENCIMA de la raiz de la sesion
antes = foto()
CASOS = [
    ('status', {}), ('diff', {}), ('log', {}), ('show', {'args': 'otra'}), ('branch', {}),
    ('stash', {}), ('stash', {'args': 'list'}), ('stash', {'args': 'pop'}),
    ('switch', {'args': 'otra'}), ('switch', {'args': 'mia', 'create': True}),
    ('merge', {'args': 'otra'}), ('add', {'args': '.'}), ('restore', {'args': '.'}),
    ('commit', {'message': 'desde a'}), ('tag', {'args': 'v9'}),
    ('config', {'args': 'user.name', 'message': 'intruso'}),
    ('pull', {}), ('fetch', {}), ('push', {}),
    ('worktree', {'args': 'list'}),
    # (worktree add lo negaba ya otra regla, GIT-018: dentro del propio repo.
    # Aqui cuenta solo que la negativa sea la de la jaula, que va antes)
    ('worktree', {'args': 'add', 'path': os.path.join(A, 'wt'), 'ref': 'otra'}),
]
pasan, fugas = [], []
for cmd, mas in CASOS:
    r = call('delphi_git', dict(repo=A, command=cmd, **mas))
    nombre = (cmd + ' ' + mas.get('args', '')).strip()
    if not mc.abre(r, 'SR_GIT_REPO_FUERA_FMT'):
        pasan.append('%s: %s' % (nombre, corto(r)))
    if 'SECRETO' in r or 'solo en otra' in r or 'secreto.txt' in r:
        fugas.append('%s: %s' % (nombre, corto(r, 200)))
check('J1 con la raiz del repo por ENCIMA de la raiz de la sesion, los %d comandos se niegan '
      '(GIT-041)' % len(CASOS), not pasan, pasan[:4])
check('J1 ...y ninguna respuesta ensena nada del vecino (su fichero, su contenido)', not fugas, fugas[:3])
despues = foto()
check('J1 ...y fuera no se ha tocado nada: el fichero del vecino, la rama, la historia, el stash, '
      'los tags, la configuracion', despues == antes,
      [(x, y) for x, y in zip(antes, despues) if x != y][:2])
r = call('delphi_read', {'path': SECRETO})
check('J1 (control) la jaula de ficheros ya lo negaba', mc.es(r, 'SR_JAIL_FMT'), corto(r))

# J4 - init en una carpeta de la sesion, bajo el repo de otro: hace el SUYO
r0 = call('delphi_git', {'repo': A, 'command': 'init'})
pasos = [call('delphi_git', {'repo': A, 'command': 'config', 'args': 'user.name', 'message': 'jaula'}),
         call('delphi_git', {'repo': A, 'command': 'config', 'args': 'user.email',
                             'message': 'jaula@example.com'}),
         call('delphi_git', {'repo': A, 'command': 'add', 'args': '.'}),
         call('delphi_git', {'repo': A, 'command': 'commit', 'message': 'lo mio'})]
st = call('delphi_git', {'repo': A, 'command': 'status'})
check('J4 init en una carpeta de la sesion hace SU repo alli, y git trabaja ya sobre ese',
      not mc.fallo(r0) and not any(mc.fallo(p) for p in pasos) and not mc.fallo(st)
      and os.path.isdir(os.path.join(A, '.git')) and 'secreto' not in st,
      corto(' | '.join([r0] + pasos + [st]), 300))
check('J4 ...y lo de fuera sigue como estaba (el commit fue al repo nuevo)',
      foto()[:7] == antes[:7], [(x, y) for x, y in zip(antes, foto()) if x != y][:2])
srv.cierra()

# J2 - el control: un repo que vive DENTRO de las raices, desde su raiz y
# desde una subcarpeta
DENTRO = os.path.join(BASE, 'dentro')
REPO = os.path.join(DENTRO, 'repo')
SUB = os.path.join(REPO, 'sub', 'mas')
os.makedirs(SUB)
open(os.path.join(REPO, 'raiz.txt'), 'w').write('raiz\n')
open(os.path.join(SUB, 'hoja.txt'), 'w').write('hoja\n')
git('init', '-q', '-b', 'main', cwd=REPO)
git('add', '.', cwd=REPO)
git('commit', '-qm', 'base', cwd=REPO)
open(os.path.join(REPO, 'raiz.txt'), 'w').write('raiz cambiada\n')
open(os.path.join(SUB, 'nueva.txt'), 'w').write('nueva\n')
# J3 - un worktree enlazado DENTRO de las raices de un repo de FUERA
ENLAZADO = os.path.join(DENTRO, 'enlazado')
git('worktree', 'add', '--detach', ENLAZADO, 'otra', cwd=MONO)
# J5 - un repo bare dentro de las raices
BARE = os.path.join(DENTRO, 'bare.git')
git('clone', '-q', '--bare', REPO, BARE, cwd=DENTRO)
# J6 - una carpeta que no es un repo
NADA = os.path.join(DENTRO, 'nada')
os.makedirs(NADA)
# J7 - espacios y un acento en la ruta del repo
RARO = os.path.join(DENTRO, 'mi repo de a\u00f1o')
os.makedirs(os.path.join(RARO, 'sub carpeta'))
open(os.path.join(RARO, 'sub carpeta', 'uno.txt'), 'w').write('uno\n')
git('init', '-q', '-b', 'main', cwd=RARO)
git('add', '.', cwd=RARO)
git('commit', '-qm', 'base', cwd=RARO)
open(os.path.join(RARO, 'sub carpeta', 'dos.txt'), 'w').write('dos\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': DENTRO}), nombre='git-jaula-2', t=120)
call = srv.call


def g(repo, **kw):
    return call('delphi_git', dict(repo=repo, **kw))


s1, s2 = g(REPO, command='status'), g(SUB, command='status')
check('J2 un repo que vive dentro de las raices: status desde su raiz y desde una subcarpeta, y dicen '
      'lo mismo', not mc.fallo(s1) and s1 == s2 and 'raiz.txt' in s1 and 'sub/mas/nueva.txt' in s1,
      corto(s1 + ' | ' + s2, 300))
pasos = [g(SUB, command='config', args='user.name', message='jaula'),
         g(SUB, command='config', args='user.email', message='jaula@example.com'),
         g(SUB, command='add', args='.'),
         g(SUB, command='commit', message='desde la subcarpeta')]
en_commit = git('show', '--stat', '--format=', 'HEAD', cwd=REPO)
check('J2 ...add . desde la subcarpeta anade lo de la subcarpeta, y commit lo guarda',
      not any(mc.fallo(p) for p in pasos) and 'sub/mas/nueva.txt' in en_commit
      and 'raiz.txt' not in en_commit, corto(' | '.join(pasos) + ' | ' + en_commit, 300))
pasos = [g(SUB, command='stash'), g(SUB, command='stash', args='list')]
aparcado = lee(os.path.join(REPO, 'raiz.txt'))
pasos += [g(SUB, command='stash', args='pop'),
          g(SUB, command='switch', args='otra', create=True),
          g(SUB, command='switch', args='main'),
          g(SUB, command='log'), g(SUB, command='diff')]
check('J2 ...y stash, stash pop, switch, log y diff, tambien desde la subcarpeta',
      not any(mc.fallo(p) for p in pasos) and aparcado == 'raiz'
      and lee(os.path.join(REPO, 'raiz.txt')) == 'raiz cambiada' and 'raiz cambiada' in pasos[-1],
      corto(' | '.join(pasos), 400))

antes = foto()
r = [g(ENLAZADO, command=c, **m) for c, m in (('status', {}), ('log', {}), ('stash', {}),
                                                ('commit', {'message': 'x'}))]
check('J3 un worktree enlazado de un repo de FUERA: su carpeta de git esta fuera, y se niega',
      all(mc.abre(x, 'SR_GIT_REPO_FUERA_FMT') for x in r) and foto() == antes,
      corto(' | '.join(r), 300))

r1, r2 = g(BARE, command='log'), g(BARE, command='branch')
check('J5 un repo bare dentro de las raices (sin arbol de trabajo): log y branch contestan',
      not mc.fallo(r1) and 'base' in r1 and not mc.fallo(r2) and 'main' in r2, corto(r1 + ' | ' + r2))

r = g(NADA, command='status')
check('J6 una carpeta que no es un repo: lo dice git, como antes',
      mc.abre(r, 'SR_GIT_EXIT_FMT') and 'not a git repository' in r, corto(r))

pasos = [g(os.path.join(RARO, 'sub carpeta'), command='status'),
         g(os.path.join(RARO, 'sub carpeta'), command='add', args='.'),
         g(RARO, command='stash'), g(RARO, command='stash', args='pop'), g(RARO, command='log')]
check('J7 un repo con espacios y un acento en la ruta: status, add, stash, pop y log llegan enteros a git',
      not any(mc.fallo(p) for p in pasos) and 'dos.txt' in pasos[0] and 'base' in pasos[-1]
      and os.path.exists(os.path.join(RARO, 'sub carpeta', 'dos.txt')), corto(' | '.join(pasos), 400))

# J8 - "repo" es la propia .git
GITDIR = os.path.join(REPO, '.git')
dentro_antes = sorted(os.listdir(GITDIR))
r1 = g(GITDIR, command='status')
r2 = g(GITDIR, command='switch', args='otra')
r3 = g(GITDIR, command='log')
check('J8 con "repo" en la propia .git: status y switch dicen que ahi no hay arbol de trabajo, log '
      'contesta, y DENTRO de .git no aparece nada',
      mc.abre(r1, 'SR_GIT_EXIT_FMT') and 'work tree' in r1 and mc.abre(r2, 'SR_GIT_EXIT_FMT')
      and not mc.fallo(r3) and 'base' in r3
      and not [f for f in os.listdir(GITDIR) if f.endswith('.txt')]
      and lee(os.path.join(REPO, 'raiz.txt')) == 'raiz cambiada',
      corto(' | '.join([r1, r2, r3]), 300) + ' | nuevo en .git: %s'
      % sorted(set(os.listdir(GITDIR)) - set(dentro_antes)))

# J9-J11 - el REMOTO: una carpeta de fuera, una de dentro, y las opciones
AJENO = os.path.join(BASE, 'ajeno.git')            # fuera de las raices (DENTRO)
MIO = os.path.join(DENTRO, 'mio.git')
git('clone', '-q', '--bare', MONO, AJENO, cwd=BASE)
git('clone', '-q', '--bare', REPO, MIO, cwd=DENTRO)
git('remote', 'add', 'origin', MIO, cwd=REPO)
git('remote', 'add', 'vecino', AJENO, cwd=REPO)


def refs(bare):
    return git('for-each-ref', '--format=%(refname) %(objectname)', cwd=bare)


def bajado():
    # lo que el repo sabe de fuera: sus ramas de seguimiento y lo ultimo que bajo
    return (git('for-each-ref', '--format=%(refname)', 'refs/remotes/vecino', cwd=REPO),
            lee(os.path.join(REPO, '.git', 'FETCH_HEAD')))


antes, antes_bajado = refs(AJENO), bajado()
URL = 'file:///' + AJENO.replace(os.sep, '/')
pasan = []
for cmd, args in (('fetch', AJENO), ('fetch', 'vecino'), ('fetch', URL),
                  ('pull', AJENO + ' main'), ('pull', 'vecino main'),
                  ('push', AJENO + ' HEAD:refs/heads/x1'), ('push', 'vecino HEAD:refs/heads/x2'),
                  ('push', URL + ' HEAD:refs/heads/x3'), ('fetch', '--all'),
                  # relativa: desde la raiz del repo, ../../ajeno.git es la de fuera
                  ('fetch', '../../ajeno.git'), ('push', '../../ajeno.git HEAD:refs/heads/x4')):
    r = g(REPO, command=cmd, args=args)
    if not mc.abre(r, 'SR_GIT_REMOTO_FUERA_FMT'):
        pasan.append('%s %s: %s' % (cmd, args[-30:], corto(r)))
check('J9 un remoto que es una carpeta de FUERA de las raices se niega (GIT-044): por su ruta, como '
      'file:// y por su nombre, en fetch, pull y push', not pasan, pasan[:3])
check('J9 ...y fuera no ha cambiado nada, ni se ha bajado nada de alli',
      refs(AJENO) == antes and bajado() == antes_bajado,
      '%s | %s' % (corto(refs(AJENO)), corto(' '.join(bajado()))))

git('remote', 'remove', 'vecino', cwd=REPO)        # (fetch sin remoto los juzga todos)
mio_antes = refs(MIO)
pasos = [g(REPO, command='push', args=MIO + ' HEAD:refs/heads/por-ruta'),
         g(REPO, command='push', args='origin HEAD:refs/heads/por-nombre'),
         g(REPO, command='fetch', args='origin'), g(REPO, command='fetch', args=MIO),
         g(REPO, command='fetch'),
         # relativa a la RAIZ del arbol, se llame desde donde se llame: asi la
         # resuelve git (medido), y asi tiene que juzgarla la puerta
         g(SUB, command='fetch', args='../mio.git')]
check('J10 un remoto que es una carpeta de DENTRO: push y fetch por su ruta, por su nombre, sin '
      'nombrarlo y por una ruta relativa',
      not any(mc.fallo(p) for p in pasos) and 'por-ruta' in refs(MIO) and 'por-nombre' in refs(MIO)
      and refs(MIO) != mio_antes,
      [corto(p, 200) for p in pasos if mc.fallo(p)] or corto(refs(MIO), 300))

mal = []
for cmd, args, nombre in (('push', '--force origin main', 'SR_GIT_RED_OPCION_FMT'),
                          ('push', '--repo=' + MIO, 'SR_GIT_RED_OPCION_FMT'),
                          ('fetch', '--upload-pack=x origin', None),
                          ('fetch', '--recurse-submodules origin', 'SR_GIT_RED_OPCION_FMT')):
    r = g(REPO, command=cmd, args=args)
    if not (mc.rechazado(r) and (nombre is None or mc.es(r, nombre))):
        mal.append('%s %s: %s' % (cmd, args, corto(r)))
bien = [g(REPO, command='fetch', args='--tags --prune origin'),
        g(REPO, command='push', args='--dry-run --tags origin'),
        g(REPO, command='fetch', args='--no-tags origin'),
        g(REPO, command='fetch', args='--all'),
        g(REPO, command='push', args='--set-upstream origin main'),
        g(REPO, command='push', args='-u origin main')]
check('J11 de las opciones, fetch y push admiten su lista corta y ninguna otra',
      not mal and not any(mc.fallo(p) for p in bien), (mal + [corto(p) for p in bien])[:4])

# J12 - lo que push ENVIA: nombres. Un repo aparte, con la historia local
# divergida de la del remoto (que es una carpeta de dentro)
ENVIO = os.path.join(DENTRO, 'envio')
ENVIO_GIT = os.path.join(DENTRO, 'envio.git')
os.makedirs(ENVIO)
open(os.path.join(ENVIO, 'uno.txt'), 'w').write('base\n')
git('init', '-q', '-b', 'main', cwd=ENVIO)
git('config', 'user.name', 'jaula', cwd=ENVIO)
git('config', 'user.email', 'jaula@example.com', cwd=ENVIO)
git('add', '.', cwd=ENVIO)
git('commit', '-qm', 'base', cwd=ENVIO)
open(os.path.join(ENVIO, 'uno.txt'), 'w').write('lo del remoto\n')
git('commit', '-qam', 'lo del remoto', cwd=ENVIO)
git('branch', 'sobra', cwd=ENVIO)
git('clone', '-q', '--bare', ENVIO, ENVIO_GIT, cwd=DENTRO)
git('remote', 'add', 'origin', ENVIO_GIT, cwd=ENVIO)
git('reset', '-q', '--hard', 'HEAD~1', cwd=ENVIO)
open(os.path.join(ENVIO, 'uno.txt'), 'w').write('lo local\n')
git('commit', '-qam', 'lo local', cwd=ENVIO)
alli = refs(ENVIO_GIT)
pasan = []
for args in ('origin +main', 'origin :sobra', 'origin +HEAD:refs/heads/main', 'origin main:'):
    r = g(ENVIO, command='push', args=args)
    if not mc.abre(r, 'SR_GIT_PUSH_NOMBRE_FMT'):
        pasan.append('%s: %s' % (args, corto(r)))
check('J12 lo que push envia son NOMBRES: lo que reescribiria o borraria en el remoto se niega '
      '(GIT-046)', not pasan, pasan[:3])
check('J12 ...y en el remoto sigue todo como estaba: la rama, con lo suyo, y la que sobraba',
      refs(ENVIO_GIT) == alli and 'sobra' in alli, '%s | antes: %s' % (corto(refs(ENVIO_GIT)), corto(alli)))
r = g(ENVIO, command='push', args='origin main')
check('J12 (control) el push de siempre, con las historias divergidas, lo niega git y el remoto no '
      'cambia', mc.abre(r, 'SR_GIT_EXIT_FMT') and refs(ENVIO_GIT) == alli, corto(r))
git('branch', 'nueva', cwd=ENVIO)
pasos = [g(ENVIO, command='push', args='origin nueva'),
         g(ENVIO, command='push', args='origin HEAD:refs/heads/copia'),
         g(ENVIO, command='push', args='-u origin HEAD~1:refs/heads/anterior')]
check('J12 (control) lo que ANADE pasa: una rama nueva por su nombre, y local:remoto con un nombre a '
      'cada lado',
      not any(mc.fallo(p) for p in pasos)
      and all(n in refs(ENVIO_GIT) for n in ('nueva', 'copia', 'anterior', 'sobra')),
      [corto(p, 200) for p in pasos if mc.fallo(p)] or corto(refs(ENVIO_GIT), 300))

# J9 (cuarta revision) - la ruta relativa se juzga desde la RAIZ del arbol:
# desde la subcarpeta, ../../ajeno.git cae dentro; desde la raiz, que es
# desde donde la resuelve git, es la carpeta de fuera
antes, antes_bajado = refs(AJENO), bajado()
r = g(SUB, command='fetch', args='../../ajeno.git')
check('J9 ...y una ruta relativa se juzga desde la RAIZ del arbol, se llame desde donde se llame: '
      'desde una subcarpeta, ../../ajeno.git es la carpeta de FUERA',
      mc.abre(r, 'SR_GIT_REMOTO_FUERA_FMT') and bajado() == antes_bajado, corto(r))

# J16 (control, antes de anadir remotos raros al repo) - push sin nombres
# desde un repo corriente
r0 = g(REPO, command='push', args='--set-upstream origin main')   # (su rama de seguimiento, aqui)
r = g(REPO, command='push', args='origin')
check('J16 (control) push sin nombres desde un repo corriente funciona',
      not mc.fallo(r0) and not mc.fallo(r), corto(r0 + ' | ' + r))

# J13 - las formas de la direccion de un remoto
CON_ESPACIO = os.path.join(DENTRO, 'mi repo.git')
git('clone', '-q', '--bare', REPO, CON_ESPACIO, cwd=DENTRO)
URL_DENTRO = 'file:///' + CON_ESPACIO.replace(os.sep, '/')
git('remote', 'add', 'dosbarras', 'file://' + AJENO.replace(os.sep, '/'), cwd=REPO)
pasan = []
for cmd, args in (('fetch', URL_DENTRO.replace(' ', '%20')), ('fetch', 'dosbarras'),
                  ('push', 'dosbarras HEAD:refs/heads/x5')):
    r = g(REPO, command=cmd, args=args)
    if not mc.abre(r, 'SR_GIT_REMOTO_ILEGIBLE_FMT'):
        pasan.append('%s %s: %s' % (cmd, args[-30:], corto(r)))
check('J13 de file:// se admite UNA forma: con algo codificado (%xx) o con dos barras se niega '
      '(GIT-045), tambien cuando es la direccion de un remoto del repo', not pasan, pasan[:3])
check('J13 ...y fuera no ha cambiado nada, ni se ha bajado nada',
      refs(AJENO) == antes and bajado() == antes_bajado,
      '%s | %s' % (corto(refs(AJENO)), corto(' '.join(bajado()))))
r = g(REPO, command='fetch', args='"%s"' % URL_DENTRO)
check('J13 (control) file:///<unidad>:/<ruta> de una carpeta de dentro, con su espacio tal cual, funciona',
      not mc.fallo(r), corto(r))

# J14 - un worktree enlazado de DENTRO cuyo repo vive FUERA, de remoto
antes, antes_bajado = foto(), bajado()
pasan = []
for cmd, args in (('fetch', '"%s"' % ENLAZADO), ('pull', '"%s" main' % ENLAZADO),
                  ('push', '"%s" HEAD:refs/heads/x6' % ENLAZADO)):
    r = g(REPO, command=cmd, args=args)
    if not mc.abre(r, 'SR_GIT_REMOTO_FUERA_FMT'):
        pasan.append('%s: %s' % (cmd, corto(r)))
check('J14 un remoto que es una carpeta de DENTRO cuyo repo vive FUERA (un worktree enlazado) se '
      'niega (GIT-044)', not pasan, pasan[:3])
check('J14 ...y fuera no ha cambiado nada, ni se ha bajado nada de alli',
      foto() == antes and bajado() == antes_bajado and 'x6' not in git('branch', '-a', cwd=MONO),
      [(x, y) for x, y in zip(antes, foto()) if x != y][:2] or corto(' '.join(bajado())))

# J14 - ...y una carpeta-remoto es una carpeta que ESTA: el fichero puntero
# del worktree, o una ruta a la que git le pone el .git, no lo son
antes, antes_bajado = foto(), bajado()
PUNTERO = os.path.join(ENLAZADO, '.git')
pasan = []
for cmd, args in (('fetch', '"%s"' % PUNTERO), ('push', '"%s" HEAD:refs/heads/x7' % PUNTERO),
                  ('fetch', '"%s"' % MIO[:-4])):
    r = g(REPO, command=cmd, args=args)
    if not mc.abre(r, 'SR_GIT_REMOTO_NO_ESTA_FMT'):
        pasan.append('%s %s: %s' % (cmd, args[-24:], corto(r)))
check('J14 ...y una carpeta-remoto es una carpeta que ESTA: el fichero puntero del worktree (es un '
      'fichero: %s) y una ruta sin su .git se niegan (GIT-049), y fuera no cambia nada'
      % os.path.isfile(PUNTERO),
      os.path.isfile(PUNTERO) and not pasan and foto() == antes and bajado() == antes_bajado
      and 'x7' not in git('branch', '-a', cwd=MONO), pasan[:3] or corto(' '.join(bajado())))

# J15 - la forma corta de ssh sin usuario, en un remoto del repo. Su host SI
# esta en GitRemotes (servidor propio): asi se mide que un host:ruta RECONOCIDO
# y PERMITIDO llega a git (donde el DNS falla), no que se niega por "forma"
# (GIT-045) ni, con la lista vacia, por la lista (GIT-004). GitUrlHost y
# ClaseDeDireccion son UN solo lector (host:ruta tambien, no solo user@host:).
git('remote', 'add', 'corto', 'maquina-que-no-existe.invalid:org/repo.git', cwd=REPO)
srv15 = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': DENTRO,
    'DELPHI_MCP_GIT_REMOTES': 'maquina-que-no-existe.invalid'}), nombre='git-jaula-j15', t=120)
try:
    r = srv15.call('delphi_git', dict(repo=REPO, command='fetch', args='corto'))
finally:
    srv15.cierra()
check('J15 un remoto del repo con direccion de ssh en su forma corta, sin usuario, LLEGA a git (se '
      'negaba por "forma ilegible" GIT-045)',
      mc.abre(r, 'SR_GIT_EXIT_FMT') and 'maquina-que-no-existe' in r, corto(r, 400))

# J15b - ...y la @ de la RUTA no es la del usuario (revisor "adivinar vs medir",
# 8-oct-2026, medido): con el host permitido detras de una @ de la ruta, estas
# direcciones -que van a otra maquina- pasaban, porque GitUrlHost tomaba lo que
# seguia a la ULTIMA @ de toda la cadena. La puerta las niega por SU host.
git('remote', 'add', 'arroba1', 'otra-maquina.invalid:x@maquina-que-no-existe.invalid', cwd=REPO)
git('remote', 'add', 'arroba2', 'git@otra-maquina.invalid:x@maquina-que-no-existe.invalid', cwd=REPO)
srv15b = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': DENTRO,
    'DELPHI_MCP_GIT_REMOTES': 'maquina-que-no-existe.invalid'}), nombre='git-jaula-j15b', t=120)
try:
    rs = [srv15b.call('delphi_git', dict(repo=REPO, command='fetch', args=n))
          for n in ('arroba1', 'arroba2')]
finally:
    srv15b.cierra()
check('J15b un remoto host:ruta o user@host:ruta con el host PERMITIDO detras de una @ de la ruta '
      'se niega por el host de verdad (otra-maquina), sin llegar a git',
      all(not mc.abre(r, 'SR_GIT_EXIT_FMT') and 'otra-maquina' in r for r in rs),
      [corto(r, 200) for r in rs])

# J16 - push sin nombres desde un repo ESPEJO
ESPEJO = os.path.join(DENTRO, 'espejo.git')
git('clone', '-q', '--mirror', ENVIO_GIT, ESPEJO, cwd=DENTRO)
git('branch', '-D', 'copia', cwd=ESPEJO)      # aqui ya no esta; en el remoto, si
alli = refs(ENVIO_GIT)
rs = [g(ESPEJO, command='push'), g(ESPEJO, command='push', args='origin'),
      g(ESPEJO, command='push', args='--tags origin')]
check('J16 push sin nombres desde un repo ESPEJO se niega (GIT-048): lo que envia lo decide su '
      'configuracion, y quitaria del remoto lo que aqui ya no esta',
      all(mc.abre(r, 'SR_GIT_PUSH_CONFIG_FMT') for r in rs), [corto(r) for r in rs][:3])
check('J16 ...y en el remoto sigue todo como estaba', refs(ENVIO_GIT) == alli and 'copia' in alli,
      '%s | antes: %s' % (corto(refs(ENVIO_GIT)), corto(alli)))

srv.cierra()

# J17 - las raices en una LETRA DE RED
NETDIR = os.environ.get('DELPHI_MCP_TEST_NETDIR', '').strip()
RED = os.path.join(NETDIR, 'bateria-git-red') if NETDIR else ''
if not NETDIR or not os.path.isdir(NETDIR):
    print('NOTA J17: sin DELPHI_MCP_TEST_NETDIR (una carpeta de una unidad de red conectada) no se '
          'mide con git una raiz en una letra de red; la regla sola, en LspTests.Rutas')
else:
    mc.borra(RED)
    MONO_R = os.path.join(RED, 'mono')              # el repo de OTRO, en la misma unidad
    A_R = os.path.join(MONO_R, 'a')                 # ...con una raiz de la sesion dentro
    DENTRO_R = os.path.join(RED, 'dentro')          # y otra raiz, con un repo que vive entero en ella
    REPO_R = os.path.join(DENTRO_R, 'repo')
    os.makedirs(A_R)
    os.makedirs(os.path.join(REPO_R, 'sub'))
    open(os.path.join(A_R, 'uno.txt'), 'w').write('uno\n')
    open(os.path.join(REPO_R, 'sub', 'f.txt'), 'w').write('f\n')
    git('init', '-q', '-b', 'main', cwd=MONO_R)
    git('add', '.', cwd=MONO_R)
    git('commit', '-qm', 'base', cwd=MONO_R)
    donde = git('rev-parse', '--show-toplevel', cwd=MONO_R)
    check('J17 TESTIGO: en esa unidad git contesta la raiz del repo como UNC, no con la letra '
          '(si no, lo de abajo no mide nada)', donde.startswith('//') and donde.endswith('/mono'), donde)
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': A_R + ';' + DENTRO_R}), nombre='git-red', t=120)
    call = srv.call
    pasos = [('init', g(REPO_R, command='init')),
             ('status', g(REPO_R, command='status', args='--porcelain')),
             ('config', g(REPO_R, command='config', args='user.name', message='Red')),
             ('config', g(REPO_R, command='config', args='user.email', message='red@example.com')),
             ('add', g(REPO_R, command='add', args='.')),
             ('commit', g(REPO_R, command='commit', message='desde la letra de red')),
             ('log', g(REPO_R, command='log', args='--oneline')),
             ('status desde una subcarpeta', g(os.path.join(REPO_R, 'sub'), command='status', args='--porcelain'))]
    mal = ['%s: %s' % (n, corto(r)) for n, r in pasos if mc.fallo(r) or not mc.llego_a_git(r)]
    check('J17 un repo que vive dentro de una raiz declarada con la letra de red: init, status, config, '
          'add, commit y log trabajan, tambien desde una subcarpeta',
          not mal and 'desde la letra de red' in pasos[6][1], mal[:3] or corto(pasos[6][1]))
    # la SALIDA: git escribe la ruta de red (//host/recurso/...), que salia con el
    # nombre de la maquina y en una forma que el agente no puede devolver
    host = donde.split('/')[2].lower()
    unidad = 'srv%s:' % NETDIR[0].lower()
    check('J17 lo que git escribe (init) sale con la unidad virtual y sin el nombre de la maquina',
          unidad in pasos[0][1].lower() and host not in pasos[0][1].lower(), corto(pasos[0][1], 300))
    WT = os.path.join(DENTRO_R, 'wt')
    r = g(REPO_R, command='worktree', args='add', path=WT, ref='HEAD')
    lista = g(REPO_R, command='worktree', args='list')
    listada = [l.split()[0] for l in lista.splitlines() if l.strip() and l.split()[0].rstrip('/').endswith('/wt')]
    check('J17 worktree list ensena el worktree con la unidad virtual, sin el nombre de la maquina',
          not mc.fallo(r) and len(listada) == 1 and listada[0].lower().startswith(unidad)
          and host not in lista.lower(), '%s | %s' % (corto(r), corto(lista, 300)))
    r = g(REPO_R, command='worktree', args='remove', path=listada[0] if listada else WT)
    check('J17 ...y esa ruta, tal como la ensena, se puede devolver: worktree remove la quita',
          bool(listada) and not mc.fallo(r) and not os.path.exists(WT),
          '%s | queda: %s' % (corto(r, 300), os.path.exists(WT)))
    # lo que NO cambia: el repo de otro sigue fuera, y un agente no entra por el UNC
    rs = [g(A_R, command='status'), g(A_R, command='log'), g(A_R, command='add', args='.')]
    check('J17 ...y el repo que vive POR ENCIMA de la raiz, en la misma unidad, sigue negado (GIT-041)',
          all(mc.abre(r, 'SR_GIT_REPO_FUERA_FMT') for r in rs), [corto(r) for r in rs][:3])
    unc = (donde[:-len('/mono')] + '/dentro/repo/sub/f.txt').replace('/', '\\')
    r = call('delphi_read', {'path': unc})
    # la negativa DICE la forma declarada (con el mensaje de la jaula salia ya
    # traducida por el enmascarador, y se contradecia), y esa forma se puede usar
    m = re.search(r'"([^"]+)"', r)
    ofrecida = m.group(1) if m else ''
    r2 = call('delphi_read', {'path': ofrecida}) if ofrecida else '<sin forma ofrecida>'
    check('J17 ...y ese mismo fichero pedido por su ruta de red sigue negado, con su mensaje (GUARD-029), '
          'que dice su forma declarada; y por esa forma se lee',
          mc.abre(r, 'SR_JAIL_FORMA_DE_RED_FMT') and host not in r.lower()
          and ofrecida.lower().startswith(unidad) and not mc.fallo(r2) and '1|f' in r2,
          '%s | %s' % (corto(r, 260), corto(r2)))
    r = call('delphi_read', {'path': (donde[:-len('/mono')] + '/fuera/x.txt').replace('/', '\\')})
    check('J17 ...y una ruta de red de ese mismo recurso que no es de ningun sitio declarado sigue fuera '
          '(GUARD-002), como siempre', mc.abre(r, 'SR_JAIL_FMT'), corto(r, 260))
    srv.cierra()
    # en la unidad de red no se deja nada, tampoco en rojo: no es la carpeta
    # temporal de las baterias (lo que fallo ya esta dicho en el check)
    mc.borra(RED)
if mc.F == 0:
    git('worktree', 'remove', '--force', ENLAZADO, cwd=MONO)
    mc.borra(BASE)
mc.fin('test_git_jaula')
