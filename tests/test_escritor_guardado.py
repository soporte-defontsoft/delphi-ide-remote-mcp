"""E2E battery for the guarded writer (2026-09-25, audit of every write).

The audit found writes that passed a gate on the ARGUMENT and then wrote
something ELSE. Each check here plants that "something else" outside what the
session may write and asserts it comes out untouched:

  H1  renaming a unit rewrote every file its .dpr lists - including one
      OUTSIDE the roots (measured live against 1.3.1: rewritten, plus a
      __delphi-patch folder created next to it).
  B   a junction inside a root pointing to a reference declared INSIDE the
      root, or to a ReadOnlyPaths folder, made it writable (the gate compared
      the text path).
  C   fetching a capture-shaped .png deleted it, with only the READ gate
      (a reference that holds one lost it on reading).
  S   the "sdk" argument of delphi_build reached the cmd.exe line unquoted.
  D   delphi_designer to-text/to-binary was in no read-only list.

Usage:  python tests/test_escritor_guardado.py [path-to-DelphiLspMcp.exe]
"""
import json, os, shutil, stat, subprocess, sys, tempfile, threading, queue, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'escritor-guardado')


def quita_enlaces(base):
    # junctions first, with rmdir (removes the LINK, never its target)
    r = subprocess.run(['cmd', '/c', 'dir', '/AL', '/S', '/B', base], capture_output=True, text=True)
    for j in sorted(r.stdout.split('\n'), key=len, reverse=True):
        j = j.strip()
        if j and os.path.isdir(j):
            os.rmdir(j)


def borra(base):
    def reintenta(fn, p, exc):
        os.chmod(p, stat.S_IWRITE)
        fn(p)
    quita_enlaces(base)
    if os.path.isdir(base):
        shutil.rmtree(base, onexc=reintenta)


borra(BASE)
MINE = os.path.join(BASE, 'mio')                       # Roots
OUT = os.path.join(BASE, 'fuera')                      # outside everything
REF = os.path.join(BASE, 'referencia')                 # ReadOnlyRoots, outside
NEST = os.path.join(MINE, 'refdentro')                 # ReadOnlyRoots, INSIDE the root
ROP = os.path.join(MINE, 'vendor')                     # ReadOnlyPaths, inside the root
for d in (MINE, OUT, REF, NEST, ROP):
    os.makedirs(d, exist_ok=True)
open(os.path.join(NEST, 'n.txt'), 'w').write('referencia de dentro')
open(os.path.join(ROP, 'v.txt'), 'w').write('vendor')

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
        e = {k: v for k, v in os.environ.items() if not k.startswith('DELPHI_MCP_')}
        e.update(env)
        self.proc = subprocess.Popen([EXE], env=e, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, encoding='utf-8',
                                     errors='replace', bufsize=1)
        self.q = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()
        self.n = 0
        self.send({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize', 'params': {
            'protocolVersion': '2025-03-26', 'capabilities': {},
            'clientInfo': {'name': 'bateria-escritor-guardado', 'version': '1'}}})
        self.recv(0)
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def _reader(self):
        for line in self.proc.stdout:
            self.q.put(line)

    def send(self, o):
        self.proc.stdin.write(json.dumps(o) + '\n')
        self.proc.stdin.flush()

    def recv(self, rid, t=180):
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

    def call(self, name, args, t=180):
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


srv = Server({'DELPHI_MCP_ROOTS': MINE, 'DELPHI_MCP_READONLY_ROOTS': REF + ';' + NEST,
              'DELPHI_MCP_READONLY_PATHS': ROP})
call = srv.call

# ---- H1: renaming a unit does not rewrite a listed file it may not write
APP = os.path.join(MINE, 'App')
out = call('delphi_create', {'kind': 'project-console', 'dir': APP, 'name': 'App'})
check('fixture: proyecto', out.startswith('CREADO'), out[:200])
out = call('delphi_create', {'kind': 'unit', 'name': 'UOld', 'project': os.path.join(APP, 'App.dpr')})
check('fixture: unit UOld', out.startswith('CREAD'), out[:200])
SHARED = os.path.join(OUT, 'Shared.pas')
open(SHARED, 'w').write('unit Shared;\n\ninterface\n\n// usa UOld para algo\n\nimplementation\n\nend.\n')
REFSH = os.path.join(REF, 'RefShared.pas')
open(REFSH, 'w').write('unit RefShared;\n\ninterface\n\n// tambien nombra UOld\n\nimplementation\n\nend.\n')
antes_out, antes_ref = open(SHARED, 'rb').read(), open(REFSH, 'rb').read()
dpr = open(os.path.join(APP, 'App.dpr'), encoding='utf-8-sig').read()
linea = [l for l in dpr.split('\n') if 'UOld in' in l][0].rstrip('\r')
nueva = (linea[:-1] + ",\n  Shared in '..\\..\\fuera\\Shared.pas',\n"
         "  RefShared in '..\\..\\referencia\\RefShared.pas'" + linea[-1])
out = call('delphi_edit', {'path': os.path.join(APP, 'App.dpr'), 'old': linea, 'new': nueva})
check('fixture: el .dpr lista un fichero de FUERA y uno de la REFERENCIA', out.startswith('ESCRITO'), out[:200])
out = call('delphi_move', {'path': os.path.join(APP, 'UOld.pas'), 'dest': os.path.join(APP, 'UNew.pas')})
check('H1 rename: MOVIDO', out.startswith('MOVIDO'), out[:300])
check('H1 el fichero de FUERA sigue byte a byte', open(SHARED, 'rb').read() == antes_out, open(SHARED).read()[:120])
check('H1 ...y sin __delphi-patch creado fuera', os.listdir(OUT) == ['Shared.pas'], os.listdir(OUT))
check('H1 el fichero de la REFERENCIA sigue byte a byte', open(REFSH, 'rb').read() == antes_ref, open(REFSH).read()[:120])
check('H1 la respuesta dice cuales NO se reescribieron', 'NO reescritos' in out and 'Shared.pas' in out and 'RefShared.pas' in out, out[-400:])
check('H1 lo propio SI se reescribe (el .dpr nombra UNew)', 'UNew' in open(os.path.join(APP, 'App.dpr'), encoding='utf-8-sig').read(), '')

# ---- B: a junction inside the root does not make a read-only place writable
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(MINE, 'aNest'), NEST], capture_output=True)
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(MINE, 'aVendor'), ROP], capture_output=True)
check('fixture: junctions a la referencia de dentro y al vendor',
      os.path.isjunction(os.path.join(MINE, 'aNest')) and os.path.isjunction(os.path.join(MINE, 'aVendor')), '')
out = call('delphi_textedit', {'path': os.path.join(MINE, 'aNest', 'nuevo.txt'), 'create': True, 'content': 'x'})
check('B escribir por el junction a la REFERENCIA de dentro: RECHAZADO', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(NEST, 'nuevo.txt')), out[:200])
out = call('delphi_textedit', {'path': os.path.join(MINE, 'aVendor', 'nuevo.txt'), 'create': True, 'content': 'x'})
check('B escribir por el junction al VENDOR (ReadOnlyPaths): RECHAZADO', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(ROP, 'nuevo.txt')), out[:200])
out = call('delphi_read', {'path': os.path.join(MINE, 'aNest', 'n.txt')})
check('B leer por el junction a la referencia sigue OK', 'referencia de dentro' in out, out[:200])

# ---- C: consuming a capture = deleting: never with only the read gate
CAPD = os.path.join(REF, 'x', '__delphi-temp', 'desktop')
os.makedirs(CAPD, exist_ok=True)
CAP = os.path.join(CAPD, 'captura.png')
open(CAP, 'wb').write(b'\x89PNG\r\n\x1a\n' + b'0' * 64)
out = call('delphi_fetch', {'path': CAP, 'offset': 0})
check('C fetch de una captura en la REFERENCIA: se sirve', '"chunkBase64"' in out or '"download"' in out, out[:200])
check('C ...y NO se borra (solo se podia leer)', os.path.exists(CAP), out[:300])

# ---- S: sdk is a file NAME, never a path or a metacharacter
out = call('delphi_build', {'project': os.path.join(APP, 'App.dproj'), 'platform': 'Linux64', 'sdk': 'x&y.sdk'})
check('S sdk con metacaracter: RECHAZADO por la puerta', out.startswith('RECHAZADO') and 'sdk' in out, out[:200])
out = call('delphi_build', {'project': os.path.join(APP, 'App.dproj'), 'platform': 'Linux64', 'sdk': os.path.join(MINE, 'a.sdk')})
check('S sdk con carpeta: RECHAZADO', out.startswith('RECHAZADO'), out[:200])

# ---- X: a folder is never copied or moved into itself (it used to recurse)
CASA = os.path.join(MINE, 'casa')
os.makedirs(os.path.join(CASA, 'sub'), exist_ok=True)
open(os.path.join(CASA, 'c.txt'), 'w').write('c')
out = call('delphi_move', {'path': CASA, 'dest': os.path.join(CASA, 'sub', 'copia'), 'copy': True})
check('X copy dentro de si misma: RECHAZADO', out.startswith('RECHAZADO') and 'dentro de si misma' in out, out[:200])
check('X ...y no ha creado nada', not os.path.exists(os.path.join(CASA, 'sub', 'copia')), os.listdir(os.path.join(CASA, 'sub')))
out = call('delphi_move', {'path': CASA, 'dest': os.path.join(CASA, 'sub', 'movida')})
check('X move dentro de si misma: RECHAZADO con el motivo', out.startswith('RECHAZADO') and 'dentro de si misma' in out, out[:200])

# ---- P: a project never lives in two places - a loose project file neither
out = call('delphi_move', {'path': os.path.join(APP, 'App.dproj'), 'dest': os.path.join(MINE, 'Otra.dproj'), 'copy': True})
check('P copy de un .dproj SUELTO: RECHAZADO', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(MINE, 'Otra.dproj')), out[:200])
SOLODPR = os.path.join(MINE, 'solodpr')
os.makedirs(SOLODPR, exist_ok=True)
open(os.path.join(SOLODPR, 'P.dpr'), 'w').write('program P;\nbegin\nend.\n')
out = call('delphi_move', {'path': SOLODPR, 'dest': os.path.join(MINE, 'solodpr2'), 'copy': True})
check('P copy de una carpeta con solo un .dpr: RECHAZADO', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(MINE, 'solodpr2')), out[:200])
out = call('delphi_move', {'path': os.path.join(APP, 'UNew.pas'), 'dest': os.path.join(MINE, 'UCopia.pas'), 'copy': True})
check('P una unit suelta SI se copia', out.startswith('COPIADO'), out[:200])

# ---- CS: a changeset asks the gate again when it applies (up to 30 min later)
CS = os.path.join(MINE, 'cs')
os.makedirs(CS, exist_ok=True)
open(os.path.join(CS, 'f.txt'), 'w').write('igual')
os.makedirs(os.path.join(OUT, 'cs'), exist_ok=True)
open(os.path.join(OUT, 'cs', 'f.txt'), 'w').write('igual')
out = call('delphi_changeset', {'command': 'begin'})
cid = out.split()[1] if out.startswith('CHANGESET') else ''
check('CS begin', cid != '', out[:200])
out = call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'delete', 'path': os.path.join(CS, 'f.txt')})
out = call('delphi_changeset', {'command': 'preview', 'id': cid})
check('CS preview', not out.startswith('RECHAZADO'), out[:200])
# between preview and commit the folder becomes a junction to OUTSIDE (same bytes behind it)
os.rename(CS, CS + '-aparte')
subprocess.run(['cmd', '/c', 'mklink', '/J', CS, os.path.join(OUT, 'cs')], capture_output=True)
out = call('delphi_changeset', {'command': 'commit', 'id': cid})
check('CS commit a traves de un camino que dejo de ser escribible: no borra', os.path.exists(os.path.join(OUT, 'cs', 'f.txt')), out[:300])
check('CS ...y lo dice (deshecho)', 'f.txt' in out or 'RECHAZADO' in out or 'deshech' in out.lower(), out[:300])
os.rmdir(CS)
os.rename(CS + '-aparte', CS)

# ---- W: the file walker (search, list, projects, the package zip) follows a
# link only when what is behind it can be READ, and a cycle of links ends
os.makedirs(os.path.join(OUT, 'secretos'), exist_ok=True)
open(os.path.join(OUT, 'secretos', 'Secreto.pas'), 'w').write('unit Secreto;\n// MARCA_FUERA_DE_TODO\nend.\n')
os.makedirs(os.path.join(REF, 'libro'), exist_ok=True)
open(os.path.join(REF, 'libro', 'Libro.pas'), 'w').write('unit Libro;\n// MARCA_DE_LA_REFERENCIA\nend.\n')
BUS = os.path.join(MINE, 'busca')
os.makedirs(os.path.join(BUS, 'bucle'), exist_ok=True)
open(os.path.join(BUS, 'Propio.pas'), 'w').write('unit Propio;\n// MARCA_PROPIA\nend.\n')
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(BUS, 'aFuera'), os.path.join(OUT, 'secretos')], capture_output=True)
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(BUS, 'aRef'), os.path.join(REF, 'libro')], capture_output=True)
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(BUS, 'bucle', 'aPadre'), BUS], capture_output=True)
check('fixture: tres junctions (fuera, referencia, ciclo)', all(os.path.isjunction(p) for p in (
    os.path.join(BUS, 'aFuera'), os.path.join(BUS, 'aRef'), os.path.join(BUS, 'bucle', 'aPadre'))), '')
t0 = time.time()
out = call('delphi_search', {'root': BUS, 'query': 'MARCA_'})
check('W search termina pese al ciclo', time.time() - t0 < 60 and not out.startswith('MCPERROR'), out[:200])
check('W search encuentra lo propio', 'MARCA_PROPIA' in out, out[:300])
check('W search encuentra lo de la referencia (se puede leer)', 'MARCA_DE_LA_REFERENCIA' in out, out[:300])
check('W search NO ve lo de fuera por el junction', 'MARCA_FUERA_DE_TODO' not in out, out[:300])
out = call('delphi_package', {'dir': BUS, 'outfile': os.path.join(MINE, 'paquete.zip')})
import zipfile
nombres = zipfile.ZipFile(os.path.join(MINE, 'paquete.zip')).namelist() if os.path.exists(os.path.join(MINE, 'paquete.zip')) else []
check('W package: el zip existe', bool(nombres), out[:200])
check('W package: NO empaqueta lo de fuera', not any('Secreto' in n for n in nombres), nombres)

# ---- M: writers ask the DESTINATION gate (jail + dead folders)
out = call('delphi_package', {'dir': BUS, 'outfile': os.path.join(MINE, '__delphi-temp', 'p.zip')})
check('M package con outfile en una carpeta muerta: RECHAZADO', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(MINE, '__delphi-temp', 'p.zip')), out[:200])
HIST = os.path.join(MINE, '__history')
os.makedirs(HIST, exist_ok=True)
open(os.path.join(HIST, 'UVieja.pas'), 'w').write('unit UVieja;\n\ninterface\n\nimplementation\n\nend.\n')
antes_h = open(os.path.join(HIST, 'UVieja.pas'), 'rb').read()
out = call('delphi_edit', {'path': os.path.join(HIST, 'UVieja.pas'), 'adduses': 'SysUtils'})
check('M adduses en __history: RECHAZADO', out.startswith('RECHAZADO') and open(os.path.join(HIST, 'UVieja.pas'), 'rb').read() == antes_h, out[:200])
out = call('delphi_changeset', {'command': 'begin'})
cid = out.split()[1] if out.startswith('CHANGESET') else ''
out = call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'create', 'path': os.path.join(MINE, '__delphi-patch', 'colado.txt'), 'content': 'x'})
check('M changeset create dentro de la papelera: RECHAZADO al preparar', out.startswith('RECHAZADO'), out[:200])
call('delphi_changeset', {'command': 'rollback', 'id': cid})
srv.kill()

# ---- D: read-only mode (local stdio with no roots) never rewrites a form
DFM = os.path.join(MINE, 'Form1.dfm')
open(DFM, 'w').write('object Form1: TForm1\n  Caption = \'x\'\nend\n')
antes_dfm = open(DFM, 'rb').read()
ro = Server({})
out = ro.call('delphi_designer', {'command': 'to-binary', 'path': DFM})
check('D solo lectura: to-binary RECHAZADO', out.startswith('RECHAZADO'), out[:200])
out = ro.call('delphi_designer', {'command': 'tobinary', 'path': DFM})
check('D solo lectura: el alias tobinary tambien', out.startswith('RECHAZADO'), out[:200])
check('D el .dfm sigue byte a byte', open(DFM, 'rb').read() == antes_dfm, '')
out = ro.call('delphi_designer', {'command': 'tree', 'path': DFM})
check('D solo lectura: tree (lee) sigue OK', not out.startswith('RECHAZADO') and 'Form1' in out, out[:200])
ro.kill()

# ---- V: a link inside the vault does not take a note outside it
VAULT = os.path.join(BASE, 'vault')
os.makedirs(VAULT, exist_ok=True)
open(os.path.join(VAULT, 'MEMORY.md'), 'w').write('# MEMORY\n')
os.makedirs(os.path.join(OUT, 'vfuera'), exist_ok=True)
subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(VAULT, 'aFuera'), os.path.join(OUT, 'vfuera')], capture_output=True)
vs = Server({'DELPHI_MCP_ROOTS': MINE, 'DELPHI_MCP_VAULT_PATH': VAULT, 'DELPHI_MCP_VAULT_READONLY': '0'})
out = vs.call('vault_create', {'path': 'aFuera/colada.md', 'content': '# x\n'})
check('V vault_create por un junction a fuera: RECHAZADO', out.startswith('RECHAZADO') and not os.path.exists(os.path.join(OUT, 'vfuera', 'colada.md')), out[:200])
out = vs.call('vault_create', {'path': 'propia.md', 'content': '# propia\n'})
check('V una nota normal SI se crea', os.path.exists(os.path.join(VAULT, 'propia.md')), out[:200])
vs.kill()

borra(BASE)
print()
print('== escritor-guardado battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
