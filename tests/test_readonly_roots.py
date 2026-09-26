"""E2E battery for ReadOnlyRoots (2026-09-25): REFERENCE projects outside the
jail that a workspace reads as its own and never writes.

David, 2026-09-25: "que un agente trabaje con sus roots pero pueda ver otros
proyectos, solo para aprender como se hacen las cosas" - and "manda
ReadOnlyRoots sobre Roots: si duplican carpetas, readonly".

Two servers: the FIRST owns the reference folder as a root and fabricates a
real console project there with delphi_create (a read-only root cannot be
written by the server under test, by definition). The SECOND is the one under
test: Roots=A, ReadOnlyRoots=B, plus a third folder declared in BOTH lists to
measure the precedence.

Usage:  python tests/test_readonly_roots.py [path-to-DelphiLspMcp.exe]
"""
import atexit, json, subprocess, os, shutil
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
# carpeta propia en vez de mc.carpeta(): la barre borra(), que quita antes los
# junctions y los ficheros de solo lectura del repo git de la referencia
BASE = os.path.join(mc.RAIZ, 'readonly-roots')
def quita_enlaces(base):
    # junctions first, with rmdir (removes the LINK, never its target):
    # shutil.rmtree refuses to enter them and ignore_errors hid the leftovers
    r = subprocess.run(['cmd', '/c', 'dir', '/AL', '/S', '/B', base], capture_output=True, text=True)
    for j in sorted(r.stdout.split('\n'), key=len, reverse=True):
        j = j.strip()
        if j and os.path.isdir(j):
            os.rmdir(j)


def borra(base):
    # read-only files (git objects) are made writable and retried: with
    # ignore_errors they stayed behind and the next run started dirty
    def reintenta(fn, p, exc):
        os.chmod(p, 0o666)
        fn(p)
    quita_enlaces(base)
    if os.path.isdir(base):
        shutil.rmtree(base, onexc=reintenta)


borra(BASE)
# su propia copia del servidor, fuera de toda raiz (antes corria el compilado
# EN SU SITIO: logs y __delphi-temp en la carpeta de build)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
MINE = os.path.join(BASE, 'mio')          # Roots
REF = os.path.join(BASE, 'referencia')    # ReadOnlyRoots
BOTH = os.path.join(BASE, 'ambos')        # in Roots AND ReadOnlyRoots: read-only wins
OUT = os.path.join(BASE, 'fuera')         # neither: the plain jail
for d in (MINE, REF, BOTH, OUT):
    os.makedirs(d, exist_ok=True)
open(os.path.join(OUT, 'Fuera.pas'), 'w').write('unit Fuera;\n\ninterface\n\nimplementation\n\nend.\n')
open(os.path.join(MINE, 'Mio.pas'), 'w').write('unit Mio;\n\ninterface\n\nimplementation\n\nend.\n')
# a reference declared INSIDE a write root: moving or trashing its parent
# would take it along (the hole of 2026-09-25)
NEST = os.path.join(MINE, 'conref', 'RefDentro')
os.makedirs(NEST, exist_ok=True)
open(os.path.join(NEST, 'dentro.txt'), 'w').write('referencia')
open(os.path.join(MINE, 'conref', 'mio.txt'), 'w').write('mio')
# a second write root on ANOTHER drive, when the machine has one (the repo)
OTRA = os.path.join(REPO, 'tests', '__mudanza-otra-unidad')
HAY_OTRA = os.path.splitdrive(REPO)[0].lower() != os.path.splitdrive(BASE)[0].lower()
if HAY_OTRA:
    # tiene que estar en OTRA unidad, asi que vive en el repo: se barre al
    # empezar (lo que dejo una pasada rota) y al salir PASE LO QUE PASE
    borra(OTRA)
    os.makedirs(OTRA)
    atexit.register(borra, OTRA)


def Server(env):
    # el handshake con el que esta bateria se presento siempre
    return mc.Stdio(EXE, mc.entorno(env), nombre='bateria-readonly-roots',
                    protocolo='2025-03-26')


# ---- 1) the reference project, made for real by a server that OWNS the folder
maker = Server({'DELPHI_MCP_ROOTS': REF + ';' + BOTH})
out = maker.call('delphi_create', {'kind': 'project-console', 'dir': os.path.join(REF, 'Ref'), 'name': 'Ref'})
check('fixture: proyecto de referencia creado', out.startswith('CREADO'), out[:200])
out = maker.call('delphi_create', {'kind': 'unit', 'name': 'URefUtil',
                                   'project': os.path.join(REF, 'Ref', 'Ref.dpr')})
check('fixture: unit de referencia creada', out.startswith('CREADO') or out.startswith('CREADA'), out[:200])
out = maker.call('delphi_create', {'kind': 'project-console', 'dir': os.path.join(BOTH, 'Ambos'), 'name': 'Ambos'})
check('fixture: proyecto en la carpeta doble creado', out.startswith('CREADO'), out[:200])
maker.cierra(0.5)
REF_PAS = os.path.join(REF, 'Ref', 'URefUtil.pas')
REF_DPROJ = os.path.join(REF, 'Ref', 'Ref.dproj')
# the reference is a git repository with one commit: query must work, writes not
REF_GIT = os.path.join(REF, 'Ref')
subprocess.run(['git', 'init', '-q'], cwd=REF_GIT, check=True)
subprocess.run(['git', '-c', 'user.name=bateria', '-c', 'user.email=b@t', 'add', '-A'], cwd=REF_GIT, check=True)
subprocess.run(['git', '-c', 'user.name=bateria', '-c', 'user.email=b@t', 'commit', '-q', '-m', 'ref'], cwd=REF_GIT, check=True)

# ---- 2) the server under test
srv = Server({'DELPHI_MCP_ROOTS': MINE + ';' + BOTH + (';' + OTRA if HAY_OTRA else ''),
              'DELPHI_MCP_READONLY_ROOTS': REF + ';' + BOTH + ';' + NEST})
call = srv.call


def refused_as_reference(out):
    return out.startswith('RECHAZADO') and 'REFERENCIA' in out


# workspace announces them
out = call('delphi_workspace', {})
try:
    d = json.loads(out)
    check('workspace: readOnlyRoots listados', any(r.lower().endswith('referencia') for r in d.get('readOnlyRoots', [])), out[:300])
    check('workspace: nota de referencia', 'reference' in d.get('readOnlyRootsNote', '').lower(), out[:300])
    check('workspace: la referencia NO esta entre los roots', not any(r.lower().endswith('referencia') for r in d.get('roots', [])), out[:300])
except Exception as e:
    check('workspace: parsea', False, '%s | %s' % (e, out[:200]))

# projects: listed, flagged, and the doubled folder walked once
out = call('delphi_projects', {})
try:
    d = json.loads(out)
    items = d.get('projects') or d.get('items') or []
    ref = [p for p in items if p.get('name') == 'Ref']
    amb = [p for p in items if p.get('name') == 'Ambos']
    check('projects: el proyecto de referencia aparece', len(ref) == 1, out[:400])
    check('projects: ...marcado readOnly:true', ref and ref[0].get('readOnly') is True, json.dumps(ref)[:200])
    check('projects: carpeta en Roots Y ReadOnlyRoots: UNA vez y readOnly', len(amb) == 1 and amb[0].get('readOnly') is True, json.dumps(amb)[:200])
except Exception as e:
    check('projects: parsea', False, '%s | %s' % (e, out[:300]))
out = call('delphi_projects', {'root': REF})
check('projects root=referencia: listar es leer, no se rechaza',
      mc.como_json(out).get('total') == 1 and [p.get('name') for p in mc.como_json(out).get('projects', [])] == ['Ref'], out[:200])

# reading works exactly like in the roots
out = call('delphi_read', {'path': REF_PAS})
check('read en la referencia', 'unit URefUtil' in out, out[:200])
out = call('delphi_search', {'root': REF, 'query': 'URefUtil'})
check('search en la referencia', 'URefUtil' in out and not out.startswith('RECHAZADO'), out[:200])
out = call('delphi_list', {'path': os.path.join(REF, 'Ref')})
check('list en la referencia', 'URefUtil.pas' in out, out[:200])
out = call('delphi_symbols', {'path': REF_PAS})
check('symbols (LSP) en la referencia', out.lstrip().startswith('[') and '"name":"interface"' in out and '"selectionRange"' in out, out[:200])
out = call('delphi_fetch', {'path': REF_PAS, 'offset': 0})
check('fetch en la referencia', '"chunkBase64"' in out or '"download"' in out, out[:200])

# every write is refused, with the reference message, and nothing changes
before = open(REF_PAS, 'rb').read()
out = call('delphi_edit', {'path': REF_PAS, 'old': 'unit URefUtil;', 'new': 'unit URefUtil2;'})
check('edit en la referencia: RECHAZADO como referencia', refused_as_reference(out), out[:200])
out = call('delphi_textedit', {'path': os.path.join(REF, 'nota.txt'), 'create': True, 'content': 'x'})
check('textedit create en la referencia: RECHAZADO', refused_as_reference(out) and not os.path.exists(os.path.join(REF, 'nota.txt')), out[:200])
out = call('delphi_create', {'kind': 'unit', 'dir': os.path.join(REF, 'Ref'), 'name': 'UNueva', 'project': os.path.join(REF, 'Ref', 'Ref.dpr')})
check('create en la referencia: RECHAZADO', refused_as_reference(out), out[:200])
out = call('delphi_move', {'path': REF_PAS, 'dest': os.path.join(REF, 'Ref', 'UOtra.pas')})
check('move en la referencia: RECHAZADO', refused_as_reference(out), out[:200])
# copy only READS its source (David, 2026-09-25): a unit comes in from a
# reference, a whole project does not, and outside everything stays outside
out = call('delphi_move', {'path': REF_PAS, 'dest': os.path.join(MINE, 'UCopia.pas'), 'copy': True})
check('copy DESDE la referencia a mis roots: COPIADO (copiar solo LEE el origen)', out.startswith('COPIADO') and os.path.exists(os.path.join(MINE, 'UCopia.pas')), out[:200])
check('...la copia es mia: cabecera renombrada', os.path.exists(os.path.join(MINE, 'UCopia.pas')) and 'unit UCopia;' in open(os.path.join(MINE, 'UCopia.pas')).read(), out[:200])
out = call('delphi_move', {'path': os.path.join(REF, 'Ref'), 'dest': os.path.join(MINE, 'RefCopia'), 'copy': True})
check('copy del PROYECTO de referencia entero: RECHAZADO (nunca en dos sitios)', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(MINE, 'RefCopia')), out[:200])
out = call('delphi_move', {'path': os.path.join(OUT, 'Fuera.pas'), 'dest': os.path.join(MINE, 'UFuera.pas'), 'copy': True})
check('copy desde FUERA de todo: RECHAZADO (no se puede leer)', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(MINE, 'UFuera.pas')), out[:200])
out = call('delphi_delete', {'path': REF_PAS})
check('delete en la referencia: RECHAZADO', refused_as_reference(out), out[:200])
out = call('delphi_build', {'project': REF_DPROJ})
check('build de la referencia: RECHAZADO (compilar escribe)', refused_as_reference(out), out[:200])
out = call('delphi_designer', {'command': 'to-text', 'path': os.path.join(REF, 'Ref', 'X.dfm')})
check('to-text en la referencia: RECHAZADO o inexistente, nunca escrito', out.startswith('RECHAZADO') or 'no existe' in out, out[:200])
check('la referencia sigue byte a byte', open(REF_PAS, 'rb').read() == before, '')

# precedence: the doubled folder is read-only although it is a root
out = call('delphi_edit', {'path': os.path.join(BOTH, 'Ambos', 'Ambos.dpr'), 'old': 'program Ambos;', 'new': 'program Ambos2;'})
check('carpeta en Roots Y ReadOnlyRoots: escribir RECHAZADO (manda la referencia)', refused_as_reference(out), out[:200])
out = call('delphi_read', {'path': os.path.join(BOTH, 'Ambos', 'Ambos.dpr')})
check('carpeta en Roots Y ReadOnlyRoots: leer OK', 'program Ambos' in out, out[:200])

# git: the QUERY half works on a reference repository, the writing half does not
out = call('delphi_git', {'repo': REF_GIT, 'command': 'status'})
check('git status en la referencia: consulta OK', out.startswith('exit=0') and not out.startswith('RECHAZADO'), out[:200])
out = call('delphi_git', {'repo': REF_GIT, 'command': 'log'})
check('git log en la referencia: consulta OK', out.startswith('exit=0') and out.rstrip().endswith(' ref'), out[:200])
out = call('delphi_git', {'repo': REF_GIT, 'command': 'add', 'args': '-A'})
check('git add en la referencia: RECHAZADO como referencia', refused_as_reference(out), out[:200])
out = call('delphi_git', {'repo': REF_GIT, 'command': 'branch', 'args': 'rama-nueva'})
check('git branch con args en la referencia: RECHAZADO (crea)', refused_as_reference(out), out[:200])

# config: view reads, everything else writes
out = call('delphi_config', {'project': REF_DPROJ, 'command': 'view'})
check('config view en la referencia: OK', mc.como_json(out).get('appType') == 'Console' and 'Ref.dproj' in out, out[:200])
out = call('delphi_config', {'project': REF_DPROJ, 'command': 'set-version', 'version': '9.9.9'})
check('config set-version en la referencia: RECHAZADO', refused_as_reference(out), out[:200])

# rename: preview reads, apply writes
out = call('delphi_rename_symbol', {'path': REF_PAS, 'line': 1, 'character': 6, 'newname': 'UOtra', 'mode': 'apply'})
check('rename apply en la referencia: RECHAZADO', refused_as_reference(out), out[:200])

# folder copies never leak what the session cannot read (25-sep-2026): a
# junction to a REFERENCE project is followed (readable anyway); one to a
# folder outside everything is not, and the answer says so. The same for
# the safety copy a move takes into the trash.
CE = os.path.join(MINE, 'conenlaces')
os.makedirs(CE, exist_ok=True)
open(os.path.join(CE, 'propio.txt'), 'w').write('mio')
# a folder of the reference WITHOUT a project (with one, the copy is refused
# first: a project never lives in two places)
os.makedirs(os.path.join(REF, 'docs'), exist_ok=True)
open(os.path.join(REF, 'docs', 'nota.txt'), 'w').write('de la casa')
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(CE, 'aRef'), os.path.join(REF, 'docs')], capture_output=True)
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(CE, 'aFuera'), OUT], capture_output=True)
check('fixture: dos junctions (a la referencia y a fuera)', os.path.isdir(os.path.join(CE, 'aRef')) and os.path.isdir(os.path.join(CE, 'aFuera')), CE)
out = call('delphi_move', {'path': CE, 'dest': os.path.join(MINE, 'copia'), 'copy': True})
check('copy: COPIADO', out.startswith('COPIADO'), out[:200])
check('copy: lo propio se copia', os.path.exists(os.path.join(MINE, 'copia', 'propio.txt')), out[:200])
check('copy: el junction a la REFERENCIA se sigue (se podia leer)', os.path.exists(os.path.join(MINE, 'copia', 'aRef', 'nota.txt')), out[:300])
check('copy: el junction a FUERA no se sigue: nada de fuera entra', not os.path.exists(os.path.join(MINE, 'copia', 'aFuera')), out[:300])
check('copy: la respuesta dice que enlace no se siguio', 'NO seguidos' in out and 'aFuera' in out, out[:400])
out = call('delphi_move', {'path': CE, 'dest': os.path.join(MINE, 'movida')})
fuga = [os.path.join(r, f) for r, d, fs in os.walk(os.path.join(MINE, '__delphi-patch')) for f in fs if f.startswith('Fuera')]
check('move: la copia de seguridad en la papelera tampoco se trae lo de fuera', out.startswith('MOVIDO') and not fuga, str(fuga)[:200] + ' ' + out[:200])
# the hole of v0.16..v1.3.0: TDirectory.Move walked the junctions, brought
# what was behind them into the jail and DELETED it from its place
check('move: lo de detras del junction a FUERA sigue en su sitio', os.path.exists(os.path.join(OUT, 'Fuera.pas')), os.listdir(OUT))
check('move: lo de detras del junction a la REFERENCIA sigue en su sitio', os.path.exists(os.path.join(REF, 'docs', 'nota.txt')), os.listdir(os.path.join(REF, 'docs')))
check('move: los junctions viajan como ENLACES', os.path.isjunction(os.path.join(MINE, 'movida', 'aFuera')) and os.path.isjunction(os.path.join(MINE, 'movida', 'aRef')), os.listdir(os.path.join(MINE, 'movida')))
check('move: la referencia sigue siendo un repo entero', os.path.isdir(os.path.join(REF_GIT, '.git', 'objects')) and os.path.exists(REF_PAS), '')
for j in (os.path.join(MINE, 'movida', 'aRef'), os.path.join(MINE, 'movida', 'aFuera')):
    if os.path.isdir(j):
        os.rmdir(j)  # quita el junction, nunca lo de detras

# a folder that HOLDS a reference is refused whole; what is mine next to it is not
out = call('delphi_delete', {'path': os.path.join(MINE, 'conref')})
check('delete de la carpeta que CONTIENE una referencia: RECHAZADO', out.startswith('RECHAZADO') and 'contiene' in out, out[:300])
out = call('delphi_move', {'path': os.path.join(MINE, 'conref'), 'dest': os.path.join(MINE, 'conref2')})
check('move de la carpeta que CONTIENE una referencia: RECHAZADO', out.startswith('RECHAZADO') and 'contiene' in out, out[:300])
check('...y la referencia de dentro sigue en su sitio', os.path.exists(os.path.join(NEST, 'dentro.txt')) and not os.path.exists(os.path.join(MINE, 'conref2')), '')
check('...sin copias en la papelera de un move rechazado', not os.path.exists(os.path.join(MINE, '__delphi-patch')) or not any('conref' in f for r, d, fs in os.walk(os.path.join(MINE, '__delphi-patch')) for f in d + fs), '')
out = call('delphi_delete', {'path': os.path.join(MINE, 'conref', 'mio.txt')})
check('lo mio de al lado de la referencia SI se borra', out.startswith('BORRADO'), out[:200])

# a folder moves only as a rename: to another drive it is refused whole
if HAY_OTRA:
    VIA = os.path.join(MINE, 'viajera')
    os.makedirs(VIA, exist_ok=True)
    open(os.path.join(VIA, 'v.txt'), 'w').write('v')
    out = call('delphi_move', {'path': VIA, 'dest': os.path.join(OTRA, 'viajera')})
    check('move de carpeta a OTRA unidad: RECHAZADO con el camino (copy + delete)', out.startswith('RECHAZADO') and 'unidades distintas' in out and 'copy=true' in out, out[:300])
    check('...y no se ha movido ni copiado nada', os.path.exists(os.path.join(VIA, 'v.txt')) and not os.path.exists(os.path.join(OTRA, 'viajera')), '')
    out = call('delphi_move', {'path': VIA, 'dest': os.path.join(OTRA, 'viajera'), 'copy': True})
    check('copy=true a otra unidad: COPIADO (el camino legitimo)', out.startswith('COPIADO') and os.path.exists(os.path.join(OTRA, 'viajera', 'v.txt')), out[:200])
else:
    print('  (sin otra unidad en esta maquina: el rechazo entre unidades no se mide)')

# my own roots still work, and outside is still outside
out = call('delphi_edit', {'path': os.path.join(MINE, 'Mio.pas'), 'old': 'unit Mio;', 'new': 'unit Mio; // mio'})
check('mis roots: escribir sigue OK', out.startswith('ESCRITO'), out[:200])
out = call('delphi_read', {'path': os.path.join(OUT, 'Fuera.pas')})
check('fuera de todo: sigue vetado', out.startswith('RECHAZADO') and 'FUERA' in out, out[:200])

srv.cierra(0.5)
srv.p.wait(10)  # su exe esta en BASE: muerto del todo antes de barrerla
borra(BASE)
mc.fin('readonly-roots battery')
