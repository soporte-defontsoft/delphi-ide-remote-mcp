"""E2E battery for v0.51.0-beta - delphi_changeset: multi-file transactions.

Acceptance criteria (external review 2026-08-24, adopted):
  - a batch where operation N fails leaves ZERO net changes (byte-exact);
  - a file changed externally between preview and commit refuses the batch;
  - encodings survive (CP1252 + CRLF untouched in unedited regions);
  - commit without a clean preview is blocked.

Usage:  python tests/test_changeset.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'changeset')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

env = dict(os.environ); env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def reader():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=reader, daemon=True).start()
rid = [10]
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=120):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(name, args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(rid[0])
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "cs", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:300])
def sha(p): return hashlib.sha256(open(p, 'rb').read()).hexdigest()
def cs(args):
    r = call('delphi_changeset', args)
    return r
def begin():
    r = cs({'command': 'begin'})
    if 'CHANGESET ' not in r:
        print('BEGIN FALLO:', r[:300])
        sys.exit(2)
    return r.split('CHANGESET ')[1].split(' ')[0]

# ---- fixtures: CP1252 + CRLF file with accents, and friends ----
A_PATH = os.path.join(BASE, 'UnoAcentos.pas')
A_BYTES = ('unit UnoAcentos;\r\n\r\ninterface\r\n\r\n// gesti\xf3n de acci\xf3n\r\n'
           'const C1 = 1;\r\nconst C2 = 2;\r\n\r\nimplementation\r\n\r\nend.\r\n').encode('cp1252')
open(A_PATH, 'wb').write(A_BYTES)
B_PATH = os.path.join(BASE, 'Dos.txt')
open(B_PATH, 'w', encoding='utf-8', newline='\n').write('linea uno\nlinea dos\nlinea tres\n')

# ---- 1. happy path: edit + create + move + delete, all-or-all ----
cid = begin()
check('begin devuelve id', bool(cid), cid)
r = cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': A_PATH,
        'old': 'const C1 = 1;', 'new': 'const C1 = 111;'})
check('stage edit', 'STAGED edit' in r, r[:150])
r = cs({'command': 'stage', 'id': cid, 'kind': 'create', 'path': os.path.join(BASE, 'Nuevo.md'),
        'content': '# nuevo\n'})
check('stage create', 'STAGED create' in r, r[:150])
r = cs({'command': 'stage', 'id': cid, 'kind': 'move', 'path': B_PATH,
        'dest': os.path.join(BASE, 'DosMovido.txt')})
check('stage move', 'STAGED move' in r, r[:150])
r = cs({'command': 'preview', 'id': cid})
j = json.loads(r)
check('preview limpio', j.get('unresolved') == 0 and j.get('files') == 4, r[:300])
r = cs({'command': 'commit', 'id': cid})
check('commit completo', 'COMMIT COMPLETO' in r, r[:200])
disk = open(A_PATH, 'rb').read()
check('edit aplicado con encoding intacto', b'C1 = 111' in disk and b'gesti\xf3n' in disk and b'\r\n' in disk, disk[:80])
check('create aplicado', os.path.exists(os.path.join(BASE, 'Nuevo.md')))
check('move aplicado', os.path.exists(os.path.join(BASE, 'DosMovido.txt')) and not os.path.exists(B_PATH))

# ---- 2. batch of 10 where op 7 fails -> ZERO net changes ----
files = []
for i in range(10):
    p = os.path.join(BASE, 'lote%d.txt' % i)
    open(p, 'wb').write(('valor %d\r\nancla %d\r\n' % (i, i)).encode('utf-8'))
    files.append(p)
before = {p: sha(p) for p in files}
cid = begin()
for i in range(10):
    if i == 6:
        # two edits on the same file: the second's anchor is the line the
        # first one REMOVES -> resolves at preview, fails at apply
        cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': files[i],
            'old': 'ancla %d' % i, 'new': 'ancla cambiada'})
        cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': files[i],
            'old': 'ancla %d' % i, 'new': 'no llegara'})
    else:
        cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': files[i],
            'old': 'valor %d' % i, 'new': 'valor %d cambiado' % i})
r = cs({'command': 'preview', 'id': cid})
j = json.loads(r)
check('preview del lote resuelve (la trampa es en apply)', j.get('unresolved') == 0, r[:300])
r = cs({'command': 'commit', 'id': cid})
check('commit falla y hace ROLLBACK COMPLETO', 'ROLLBACK COMPLETO' in r, r[:250])
after = {p: sha(p) for p in files}
check('CERO cambios netos tras el rollback (byte a byte)', before == after,
      [p for p in files if before[p] != after[p]])

# ---- 3. FILE_CHANGED entre preview y commit ----
cid = begin()
cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': files[0],
    'old': 'valor 0', 'new': 'valor tocado'})
cs({'command': 'preview', 'id': cid})
open(files[0], 'ab').write(b'linea externa\r\n')  # somebody else writes
h = sha(files[0])
r = cs({'command': 'commit', 'id': cid})
check('commit rechazado por FILE_CHANGED', 'FILE_CHANGED' in r, r[:250])
check('y no ha tocado nada', sha(files[0]) == h)

# ---- 4. commit sin preview limpio bloqueado ----
cid = begin()
cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': files[1],
    'old': 'no existe esta ancla', 'new': 'x'})
r = cs({'command': 'preview', 'id': cid})
j = json.loads(r)
check('preview marca la ancla ausente', j.get('unresolved') == 1, r[:250])
r = cs({'command': 'commit', 'id': cid})
check('commit bloqueado sin preview limpio', 'RECHAZADO' in r and 'preview' in r.lower(), r[:200])
cs({'command': 'rollback', 'id': cid})

# ---- 6. fricciones de campo (report hermes 2026-08-24) ----
# F1: el commit debe decir el NUMERO REAL de operaciones (era 0 por leer un
# changeset ya liberado por el diccionario que lo posee)
f1 = os.path.join(BASE, 'f1.txt')
open(f1, 'wb').write(b'uno\r\ndos\r\ntres\r\ncuatro\r\n')
cid = begin()
for n, w in ((1, 'uno'), (2, 'dos'), (3, 'tres')):
    cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': f1,
        'old': w, 'new': w + ' cambiado'})
cs({'command': 'preview', 'id': cid})
r = cs({'command': 'commit', 'id': cid})
check('F1: el commit cuenta las operaciones reales (3, no 0)', '3 operaciones' in r, r[:200])
check('F1: y los cambios estan en disco', open(f1, 'rb').read().count(b'cambiado') == 3, open(f1, 'rb').read())

# F2: delete-line borra una linea EN BLANCO (que no tiene ancla usable)
f2 = os.path.join(BASE, 'f2.txt')
open(f2, 'wb').write(b'alfa\r\n\r\nbeta\r\n')
cid = begin()
r = cs({'command': 'stage', 'id': cid, 'kind': 'delete-line', 'path': f2, 'atline': 2})
check('F2: stage delete-line', 'STAGED delete-line' in r, r[:150])
cs({'command': 'preview', 'id': cid})
r = cs({'command': 'commit', 'id': cid})
check('F2: la linea en blanco desaparece', open(f2, 'rb').read() == b'alfa\r\nbeta\r\n', open(f2, 'rb').read())
cid = begin()
r = cs({'command': 'stage', 'id': cid, 'kind': 'delete-line', 'path': f2})
check('F2: delete-line sin atline rechazado con el motivo', 'RECHAZADO' in r and 'atline' in r, r[:200])
cs({'command': 'rollback', 'id': cid})

# F3: las atline se rebasan contra lo que hicieron las ops anteriores
f3 = os.path.join(BASE, 'f3.txt')
open(f3, 'wb').write(b'L1\r\nL2\r\nL3\r\nL4\r\n')
cid = begin()
# op 1 mete DOS lineas donde habia una -> L3 pasa de la linea 3 a la 4
cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': f3, 'old': 'L1',
    'new': 'L1a\nL1b'})
# op 2 fija la linea 3 (la de L3 en el fichero ORIGINAL, que el preview ve)
cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': f3, 'old': 'L3',
    'new': 'L3 cambiada', 'atline': 3})
r = cs({'command': 'preview', 'id': cid})
j = json.loads(r)
check('F3: preview limpio', j.get('unresolved') == 0, r[:250])
r = cs({'command': 'commit', 'id': cid})
check('F3: commit aplica las dos (atline rebasada, no ROLLBACK)', 'COMMIT COMPLETO' in r and '2 operaciones' in r, r[:250])
disk = open(f3, 'rb').read()
check('F3: resultado correcto en disco', b'L1a' in disk and b'L1b' in disk and b'L3 cambiada' in disk, disk)

# ---- 5. jaula y contratos ----
cid = begin()
r = cs({'command': 'stage', 'id': cid, 'kind': 'edit', 'path': 'C:\\Windows\\win.ini', 'old': 'x', 'new': 'y'})
check('stage fuera de la jaula rechazado', 'RECHAZADO' in r, r[:150])
r = cs({'command': 'stage', 'id': cid, 'kind': 'explotar', 'path': files[2]})
check('kind invalido', 'RECHAZADO' in r, r[:120])
r = cs({'command': 'commit', 'id': 'noexiste'})
check('id desconocido', 'RECHAZADO' in r, r[:120])
r = cs({'command': 'commit', 'id': cid})
check('commit de changeset vacio rechazado', 'RECHAZADO' in r, r[:150])
r = cs({'command': 'rollback', 'id': cid})
check('rollback descarta', 'descartado' in r, r[:120])
r = cs({'command': 'status'})
check('status responde JSON', r.startswith('{'), r[:120])

proc.kill()
print('\n== changeset battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
