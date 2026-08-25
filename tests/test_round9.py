"""E2E battery for v0.62.0-beta - the field round-9 findings.

Three more agents worked the 0.60 server through nothing but MCP on
2026-08-25 (security, contracts, and a real programming job) and came back
with another forty. This battery is the ones that became code.

  R1  git refuses an explicit remote URL unless the operator allowed the host
  R3  a delete that did not delete says so instead of claiming success
  B1  git merge takes a branch name (or --abort), never options
  B2  a test killed by the timeout is told apart from one that fails
  B3  diagnostics on a non-Delphi file refuses instead of looping forever
  B4  a read range that runs backwards is refused, not answered empty
  F1  an upload offset that lands mid-file is refused (it truncated the tail)
  F2  changeset preview re-validates the plan instead of trusting the stage
  F3  a second quarantined upload does not overwrite the first
  F4  a changeset id is a capability: status shows only its public half
  F6  ANY drive letter is masked, and a UNC host never travels
  M3  a project file is refused at stage, not at commit
  P3  rename answers 1-based lines (and line0 alongside)
  P4  git's own list of commands is complete
  P7  delphi_projects on a root that is not there is an error
  P8  symbols on a file that is not Delphi says so
  C1  create kind=unit says it needs "project", not "dir"
  C2  delphi_list accepts path= as well as root=
  C3  delphi_test says which platform it builds and runs
  C7  delete's answer does not contradict itself
  F11 a report kind nobody knows is announced, not silently refiled
  F12 components says when it ignores "filter"

Usage:  python tests/test_round9.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, base64

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round9')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)


def spawn(extra_env=None):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = BASE
    env.pop('DELPHI_MCP_GIT_REMOTES', None)
    env['DELPHI_MCP_ALLOW_TESTS'] = '1'
    if extra_env:
        env.update(extra_env)
    p = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    q = queue.Queue()

    def rd():
        for line in p.stdout:
            line = line.strip()
            if line:
                q.put(line)
    threading.Thread(target=rd, daemon=True).start()
    st = {'p': p, 'q': q, 'id': 10}
    send(st, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "r9", "version": "1"}}})
    recv(st, 1)
    send(st, {"jsonrpc": "2.0", "method": "notifications/initialized"})
    return st


def send(st, o):
    st['p'].stdin.write(json.dumps(o) + '\n')
    st['p'].stdin.flush()


def recv(st, r, t=900):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = st['q'].get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None


def call(st, name, args, t=900):
    st['id'] += 1
    send(st, {"jsonrpc": "2.0", "id": st['id'], "method": "tools/call",
              "params": {"name": name, "arguments": args}})
    r = recv(st, st['id'], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:300]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'


P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:300])


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


A = spawn()

# ------------------------------------------------------------ R1: git URLs --
REPOD = os.path.join(BASE, 'repo')
os.makedirs(REPOD)
call(A, 'delphi_git', {'repo': REPOD, 'command': 'init'})
r = call(A, 'delphi_git', {'repo': REPOD, 'command': 'fetch', 'args': 'http://127.0.0.1:3131/mcp'})
check('R1 una URL explicita a localhost: RECHAZADA sin conectar',
      'RECHAZADO' in r and 'GitRemotes' in r, r[:250])
r = call(A, 'delphi_git', {'repo': REPOD, 'command': 'fetch', 'args': 'https://198.51.100.7/evil.git'})
check('R1 ...y a un host cualquiera tambien', 'RECHAZADO' in r, r[:200])
r = call(A, 'delphi_git', {'repo': os.path.join(BASE, 'clon'), 'command': 'clone',
                           'message': 'https://198.51.100.7/evil.git'})
check('R1 clone con URL no permitida: RECHAZADO', 'RECHAZADO' in r, r[:200])
r = call(A, 'delphi_git', {'repo': REPOD, 'command': 'push', 'args': 'origin main'})
check('R1 un remoto POR NOMBRE sigue permitido (no es una URL)',
      'RECHAZADO' not in r, r[:200])

B = spawn({'DELPHI_MCP_GIT_REMOTES': 'example.com'})
r = call(B, 'delphi_git', {'repo': REPOD, 'command': 'fetch', 'args': 'https://otro.example.org/x.git'})
check('R1 host fuera de la lista del operador: RECHAZADO nombrando la lista',
      'RECHAZADO' in r and 'example.com' in r, r[:250])
r = call(B, 'delphi_git', {'repo': REPOD, 'command': 'fetch', 'args': 'https://example.com/x.git'})
check('R1 el host permitido SI pasa la puerta (falle luego lo que falle)',
      'RECHAZADO' not in r, r[:200])
B['p'].kill()

# --------------------------------------------------------------- B1: merge --
r = call(A, 'delphi_git', {'repo': REPOD, 'command': 'merge', 'args': '--no-ff otra'})
check('B1 merge con opciones: RECHAZADO (rompia el --ff-only)',
      'RECHAZADO' in r and 'ff-only' in r, r[:250])
r = call(A, 'delphi_git', {'repo': REPOD, 'command': 'merge', 'args': '--abort'})
check('B1 merge --abort SI se acepta (la salida del merge a medias)',
      'RECHAZADO' not in r, r[:200])

# ------------------------------------------------------------- P4: comandos --
r = call(A, 'delphi_git', {'repo': REPOD, 'command': 'switchh'})
check('P4 el error enumera TODOS los comandos, switch/merge/stash incluidos',
      'switch' in r and 'merge' in r and 'stash' in r, r[:250])

# ---------------------------------------------------------- F1/F3: upload ---
U = os.path.join(BASE, 'sub')
os.makedirs(U)
V = os.path.join(U, 'v.txt')
open(V, 'wb').write(b'hello auditor3')
j = J(call(A, 'delphi_upload', {'path': V, 'chunkbase64': base64.b64encode(b'XYZ').decode(),
                                'offset': 5}))
check('F1 offset dentro del fichero: RECHAZADO y el fichero INTACTO',
      open(V, 'rb').read() == b'hello auditor3', (str(j)[:200], open(V, 'rb').read()))
j = J(call(A, 'delphi_upload', {'path': V, 'chunkbase64': base64.b64encode(b'!').decode(),
                                'offset': 14}))
check('F1 offset == tamano (append) SI vale', j.get('size') == 15, str(j)[:200])

BAD = os.path.join(U, 'b.bin')
call(A, 'delphi_upload', {'path': BAD, 'chunkbase64': base64.b64encode(b'AAA').decode(),
                          'offset': 0, 'sha256': '0' * 64})
call(A, 'delphi_upload', {'path': BAD, 'chunkbase64': base64.b64encode(b'BBB').decode(),
                          'offset': 0, 'sha256': '0' * 64})
import glob
q_backups = glob.glob(os.path.join(U, '__delphi-patch', '*', '*.corrupto'))
check('F3 la segunda cuarentena no pisa a la primera sin copia',
      open(BAD + '.corrupto', 'rb').read() == b'BBB' and len(q_backups) >= 1,
      (open(BAD + '.corrupto', 'rb').read(), q_backups))

# ----------------------------------------------------------------- R3: rm ---
D = os.path.join(BASE, 'paraborrar')
os.makedirs(os.path.join(D, 'dentro'))
open(os.path.join(D, 'dentro', 'f.txt'), 'w').write('x')
r = call(A, 'delphi_delete', {'path': D})
check('R3 borrar una carpeta la quita DE VERDAD, y solo entonces dice BORRADO',
      ('BORRADO' in r) == (not os.path.isdir(D)), (r[:150], os.path.isdir(D)))

# ------------------------------------------------------- F2/F4/M3 changeset --
CS = os.path.join(BASE, 'tanda')
os.makedirs(CS)
X = os.path.join(CS, 'X.txt')
open(X, 'w').write('uno\n')
r = call(A, 'delphi_changeset', {'command': 'begin'})
CID = [w for w in r.replace('.', ' ').split() if w.count('-') >= 2][0]
check('F4 el id lleva un secreto (no es solo hora-contador)', len(CID.split('-')) >= 3, CID)
st = J(call(A, 'delphi_changeset', {'command': 'status'}))
ids = [c.get('id') for c in st.get('changesets', [])]
check('F4 status NO ensena el id completo de nadie',
      all(i != CID for i in ids) and any('...' in (i or '') for i in ids), ids)
call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'delete', 'path': X})
call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'create', 'path': X,
                             'content': 'dos\n'})
call(A, 'delphi_changeset', {'command': 'unstage', 'id': CID, 'n': 1})
r = call(A, 'delphi_changeset', {'command': 'preview', 'id': CID})
check('F2 preview VUELVE a validar el plan tras un unstage',
      'RECHAZADO' in r and 'ya existe' in r, r[:250])
call(A, 'delphi_changeset', {'command': 'rollback', 'id': CID})

r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'Proy', 'dir': os.path.join(BASE, 'Proy')})
assert 'CREADO' in r, r
r = call(A, 'delphi_changeset', {'command': 'begin'})
CID2 = [w for w in r.replace('.', ' ').split() if w.count('-') >= 2][0]
r = call(A, 'delphi_changeset', {'command': 'stage', 'id': CID2, 'kind': 'edit',
                                 'path': os.path.join(BASE, 'Proy', 'Proy.dproj'),
                                 'old': '<Platform>Win32</Platform>', 'new': 'x'})
check('M3 un .dproj se rechaza EN EL STAGE, no en el commit',
      'RECHAZADO' in r and 'delphi_config' in r, r[:250])
call(A, 'delphi_changeset', {'command': 'rollback', 'id': CID2})

# ------------------------------------------------------------- B4/P8/B3 ----
PAS = os.path.join(BASE, 'Proy', 'UAlgo.pas')
open(PAS, 'w', encoding='utf-8').write('unit UAlgo;\r\ninterface\r\nimplementation\r\nend.\r\n')
r = call(A, 'delphi_read', {'path': PAS, 'fromline': 4, 'toline': 2})
check('B4 rango al reves: RECHAZADO en vez de cuerpo vacio',
      'RECHAZADO' in r and 'reves' in r, r[:200])
TXT = os.path.join(BASE, 'notas.txt')
open(TXT, 'w', encoding='utf-8').write('esto no es pascal\n')
r = call(A, 'delphi_symbols', {'path': TXT})
check('P8 symbols sobre algo que no es Delphi: lo dice, no devuelve []',
      'RECHAZADO' in r and '.pas' in r, r[:200])
r = call(A, 'delphi_diagnostics', {'path': TXT}, t=120)
check('B3 diagnostics sobre algo que no es Delphi: RECHAZADO, sin bucle',
      'RECHAZADO' in r and 'in-progress' not in r, r[:200])

# ------------------------------------------------------------------- C1/C2 --
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'USuelta', 'dir': BASE})
check('C1 kind=unit sin project: dice exactamente lo que falta',
      'RECHAZADO' in r and 'project' in r and 'dir' in r, r[:250])
j = J(call(A, 'delphi_list', {'path': os.path.join(BASE, 'Proy')}))
check('C2 delphi_list acepta path= igual que root=', j.get('total', 0) >= 1, str(j)[:200])

# --------------------------------------------------------------------- P7 ---
r = call(A, 'delphi_projects', {'root': os.path.join(BASE, 'no-existe-esto')})
check('P7 un root inexistente es un ERROR, no "0 proyectos"',
      'error' in r.lower() and 'no existe' in r, r[:200])

# ----------------------------------------------------------------- C3/B2 ----
TDIR = os.path.join(BASE, 'MiTest')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'MiTest', 'dir': TDIR})
assert 'CREADO' in r, r
open(os.path.join(TDIR, 'MiTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    "program MiTest;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils;\n\n"
    "begin\n  Writeln('PASS uno');\n  Sleep(120000);\nend.\n")
j = J(call(A, 'delphi_test', {'command': 'discover', 'path': TDIR}))
check('C3 discover dice EN QUE plataforma se ejecutara y donde puede escribir',
      'Win64' in (j.get('runsOn') or '') and
      'escribir' in (j.get('runsOn') or '').lower(), str(j)[:400])
check('M4 ...y que formato de salida se cuenta',
      any('PASS' in (p.get('countsFormat') or '') for p in j.get('projects', [])), str(j)[:400])
j = J(call(A, 'delphi_test', {'command': 'run', 'project': os.path.join(TDIR, 'MiTest.dproj'),
                              'timeoutms': 3000}, t=900))
check('B2 un test cortado por tiempo se DISTINGUE de uno que falla',
      j.get('result') == 'timeout' and j.get('timedOut') is True, str(j)[:400])
check('B2 ...y explica por que no hay salida', 'buffer' in (j.get('timeoutNote') or ''), str(j)[:300])
check('C3 el resultado dice la plataforma que corrio', j.get('platform') == 'Win64', str(j)[:250])
r = call(A, 'delphi_test', {'command': 'run', 'project': os.path.join(TDIR, 'MiTest.dproj'),
                            'config': 'Inventada'}, t=900)
check('F3(test) una config que no existe: RECHAZADA nombrando las que hay',
      'RECHAZADO' in r and 'Debug' in r, r[:250])

# --------------------------------------------------------------------- F6 ---
# El enmascarado ya no es una lista blanca C/D... y al generalizarlo se comio
# un separador de ruta normal (en JSON un "\" viaja como "\\", que es
# exactamente la forma de una UNC). Las dos cosas, fijadas aqui.
jw = J(call(A, 'delphi_list', {'root': os.path.join(BASE, 'Proy')}))
paths = [f.get('path', '') for f in jw.get('files', [])]
check('F6 una ruta normal NO se rompe al enmascarar (srvhost fantasma)',
      paths and all('srvhost' not in p for p in paths), paths[:2])
check('F6 ...y sigue viajando virtualizada',
      paths and all(p.lower().startswith('srv') for p in paths), paths[:2])

# ------------------------------------------------------------ C7/F11/F12 ----
UNIT = os.path.join(BASE, 'Proy', 'UBorrar.pas')
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'UBorrar',
                              'project': os.path.join(BASE, 'Proy', 'Proy.dproj')})
r = call(A, 'delphi_delete', {'path': UNIT})
check('C7 el mensaje de borrado no se contradice a si mismo',
      'BORRADO' in r and 'sigue en disco' not in r, r[:300])
r = call(A, 'delphi_report', {'kind': 'invento', 'title': 'x', 'message': 'y', 'agent': 'r9'})
check('F11 un kind inventado se archiva como bug PERO se dice',
      'no es un kind' in r, r[:250])
r = call(A, 'delphi_components', {'platform': 'Win64', 'filter': 'algo'})
check('F12 components avisa de que ha ignorado el filter',
      'IGNORADO' in r or 'ignorado' in r.lower(), r[:250])

A['p'].kill()
print('\n== round-9 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
