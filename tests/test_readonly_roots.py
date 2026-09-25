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
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'readonly-roots')
shutil.rmtree(BASE, ignore_errors=True)
MINE = os.path.join(BASE, 'mio')          # Roots
REF = os.path.join(BASE, 'referencia')    # ReadOnlyRoots
BOTH = os.path.join(BASE, 'ambos')        # in Roots AND ReadOnlyRoots: read-only wins
OUT = os.path.join(BASE, 'fuera')         # neither: the plain jail
for d in (MINE, REF, BOTH, OUT):
    os.makedirs(d, exist_ok=True)
open(os.path.join(OUT, 'Fuera.pas'), 'w').write('unit Fuera;\n\ninterface\n\nimplementation\n\nend.\n')
open(os.path.join(MINE, 'Mio.pas'), 'w').write('unit Mio;\n\ninterface\n\nimplementation\n\nend.\n')

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        print('  FAIL', name, '--', str(detail)[:300])


class Server:
    def __init__(self, env):
        e = dict(os.environ)
        e.update(env)
        self.proc = subprocess.Popen([EXE], env=e, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, encoding='utf-8',
                                     errors='replace', bufsize=1)
        self.q = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()
        self.n = 0
        self.send({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize', 'params': {
            'protocolVersion': '2025-03-26', 'capabilities': {},
            'clientInfo': {'name': 'bateria-readonly-roots', 'version': '1'}}})
        self.recv(0)
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def _reader(self):
        for line in self.proc.stdout:
            self.q.put(line)

    def send(self, o):
        self.proc.stdin.write(json.dumps(o) + '\n')
        self.proc.stdin.flush()

    def recv(self, rid, t=120):
        end = time.time() + t
        while time.time() < end:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == rid:
                return m
        return {'error': 'timeout'}

    def call(self, name, args, t=120):
        self.n += 1
        self.send({'jsonrpc': '2.0', 'id': self.n, 'method': 'tools/call',
                   'params': {'name': name, 'arguments': args}})
        r = self.recv(self.n, t)
        if 'error' in r:
            return 'MCPERROR: ' + json.dumps(r['error'])
        c = r['result'].get('content', [])
        return c[0].get('text', '') if c else '(no content)'

    def kill(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        time.sleep(0.5)
        self.proc.kill()


# ---- 1) the reference project, made for real by a server that OWNS the folder
maker = Server({'DELPHI_MCP_ROOTS': REF + ';' + BOTH})
out = maker.call('delphi_create', {'kind': 'project-console', 'dir': os.path.join(REF, 'Ref'), 'name': 'Ref'})
check('fixture: proyecto de referencia creado', out.startswith('CREADO'), out[:200])
out = maker.call('delphi_create', {'kind': 'unit', 'name': 'URefUtil',
                                   'project': os.path.join(REF, 'Ref', 'Ref.dpr')})
check('fixture: unit de referencia creada', out.startswith('CREADO') or out.startswith('CREADA'), out[:200])
out = maker.call('delphi_create', {'kind': 'project-console', 'dir': os.path.join(BOTH, 'Ambos'), 'name': 'Ambos'})
check('fixture: proyecto en la carpeta doble creado', out.startswith('CREADO'), out[:200])
maker.kill()
REF_PAS = os.path.join(REF, 'Ref', 'URefUtil.pas')
REF_DPROJ = os.path.join(REF, 'Ref', 'Ref.dproj')
# the reference is a git repository with one commit: query must work, writes not
REF_GIT = os.path.join(REF, 'Ref')
subprocess.run(['git', 'init', '-q'], cwd=REF_GIT, check=True)
subprocess.run(['git', '-c', 'user.name=bateria', '-c', 'user.email=b@t', 'add', '-A'], cwd=REF_GIT, check=True)
subprocess.run(['git', '-c', 'user.name=bateria', '-c', 'user.email=b@t', 'commit', '-q', '-m', 'ref'], cwd=REF_GIT, check=True)

# ---- 2) the server under test
srv = Server({'DELPHI_MCP_ROOTS': MINE + ';' + BOTH, 'DELPHI_MCP_READONLY_ROOTS': REF + ';' + BOTH})
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
check('projects root=referencia: listar es leer, no se rechaza', not out.startswith('RECHAZADO') and 'Ref' in out, out[:200])

# reading works exactly like in the roots
out = call('delphi_read', {'path': REF_PAS})
check('read en la referencia', 'unit URefUtil' in out, out[:200])
out = call('delphi_search', {'root': REF, 'query': 'URefUtil'})
check('search en la referencia', 'URefUtil' in out and not out.startswith('RECHAZADO'), out[:200])
out = call('delphi_list', {'path': os.path.join(REF, 'Ref')})
check('list en la referencia', 'URefUtil.pas' in out, out[:200])
out = call('delphi_symbols', {'path': REF_PAS})
check('symbols (LSP) en la referencia', not out.startswith('RECHAZADO') and 'MCPERROR' not in out, out[:200])
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
out = call('delphi_move', {'path': REF_PAS, 'dest': os.path.join(MINE, 'UCopia.pas'), 'copy': True})
check('copy DESDE la referencia a mis roots: RECHAZADO (el origen tambien pasa la puerta)', out.startswith('RECHAZADO'), out[:200])
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
check('git log en la referencia: consulta OK', 'ref' in out and not out.startswith('RECHAZADO'), out[:200])
out = call('delphi_git', {'repo': REF_GIT, 'command': 'add', 'args': '-A'})
check('git add en la referencia: RECHAZADO como referencia', refused_as_reference(out), out[:200])
out = call('delphi_git', {'repo': REF_GIT, 'command': 'branch', 'args': 'rama-nueva'})
check('git branch con args en la referencia: RECHAZADO (crea)', refused_as_reference(out), out[:200])

# config: view reads, everything else writes
out = call('delphi_config', {'project': REF_DPROJ, 'command': 'view'})
check('config view en la referencia: OK', not out.startswith('RECHAZADO') and 'platform' in out.lower(), out[:200])
out = call('delphi_config', {'project': REF_DPROJ, 'command': 'set-version', 'version': '9.9.9'})
check('config set-version en la referencia: RECHAZADO', refused_as_reference(out), out[:200])

# rename: preview reads, apply writes
out = call('delphi_rename_symbol', {'path': REF_PAS, 'line': 1, 'character': 6, 'newname': 'UOtra', 'mode': 'apply'})
check('rename apply en la referencia: RECHAZADO', refused_as_reference(out), out[:200])

# my own roots still work, and outside is still outside
out = call('delphi_edit', {'path': os.path.join(MINE, 'Mio.pas'), 'old': 'unit Mio;', 'new': 'unit Mio; // mio'})
check('mis roots: escribir sigue OK', out.startswith('ESCRITO'), out[:200])
out = call('delphi_read', {'path': os.path.join(OUT, 'Fuera.pas')})
check('fuera de todo: sigue vetado', out.startswith('RECHAZADO') and 'FUERA' in out, out[:200])

srv.kill()
shutil.rmtree(BASE, ignore_errors=True)
print()
print('== readonly-roots battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
