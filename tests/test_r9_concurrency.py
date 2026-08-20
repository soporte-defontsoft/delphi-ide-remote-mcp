"""E2E battery for the R9 field finding: CONCURRENT vault writes must not lose
data. Several remote agents sharing one knowledge vault is the server's declared
architecture, so two of them appending to the SAME note at once is normal. Before
the fix the read->backup->write was not serialized: both read the same base and
the last save silently erased the other's addition (each still got an "ANADIDO ...
copia previa" success), and two backups of one note in the same second collided.

This drives the --http host with a burst of simultaneous POSTs and checks that
EVERY reported success actually landed on disk.

Usage:  python tests/test_r9_concurrency.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, subprocess, time, os, sys, tempfile, shutil, threading
import urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
PORT = 4477
URL = 'http://127.0.0.1:%d/mcp' % PORT
TOKEN = 'conc-token'
N = 16  # writers firing at once

VAULT = os.path.join(tempfile.gettempdir(), 'delphi-r9conc-vault-%d' % os.getpid())
WORK = os.path.join(tempfile.gettempdir(), 'delphi-r9conc-work-%d' % os.getpid())
for d in (VAULT, WORK):
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)

def w(rel, text):
    p = os.path.join(VAULT, rel.replace('/', os.sep))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(text.encode('utf-8'))

# minimal governance so the bootstrap is happy, plus the note under attack
w('AGENTS-VAULT.md', '# Reglas\n\n1. Carga perezosa.\n')
w('MEMORY.md', '# MEMORY\n\n- nota de concurrencia\n')
w('conc/base.md', '# Concurrencia\n\nlinea base.\n')

env = dict(os.environ)
# Loopback ONLY. Listening on every interface makes Windows Firewall pop its
# "allow this app?" prompt, and it asks once per program PATH - so a battery
# that runs the exe from a fresh temp folder asks again on every single run.
# The tests only ever talk to 127.0.0.1, so there is nothing to expose.
env['DELPHI_MCP_BIND_IP'] = '127.0.0.1'
env['DELPHI_MCP_TOKEN'] = TOKEN
env['DELPHI_MCP_ROOTS'] = WORK
env['DELPHI_MCP_VAULT_PATH'] = VAULT
env['DELPHI_MCP_VAULT_READONLY'] = '0'
proc = subprocess.Popen([EXE, '--http', str(PORT)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)

P = FCOUNT = 0
def check(name, cond, detail=''):
    global P, FCOUNT
    if cond:
        P += 1; print('PASS -', name)
    else:
        FCOUNT += 1; print('FAIL -', name, '|', str(detail)[:200])

_rid = [100]
_ridlock = threading.Lock()
def next_id():
    with _ridlock:
        _rid[0] += 1
        return _rid[0]

def post(payload):
    req = urllib.request.Request(URL, json.dumps(payload).encode('utf-8'),
        {'Content-Type': 'application/json', 'Accept': 'application/json',
         'Authorization': 'Bearer ' + TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return 'HTTP%d %s' % (e.code, e.read().decode('utf-8', 'replace')[:150])

def tool_text(body):
    try:
        c = json.loads(body)['result'].get('content', [])
        return c[0].get('text', '') if c else ''
    except Exception:
        return body

def call_tool(name, args):
    return tool_text(post({"jsonrpc": "2.0", "id": next_id(),
        "method": "tools/call", "params": {"name": name, "arguments": args}}))

try:
    # initialize once (HTTP is stateless per POST; this just proves auth works)
    init = post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "r9conc", "version": "1"}}})
    check('http: initialize con token', 'delphi-lsp-mcp-service' in init, init[:150])

    # ---- burst 1: N simultaneous appends to the SAME note -------------------
    results = [None] * N
    barrier = threading.Barrier(N)
    def append_worker(i):
        barrier.wait()  # release all at once -> maximum overlap
        results[i] = call_tool('vault_append',
            {"path": "conc/base.md", "content": "MARK-%02d linea concurrente" % i})
    threads = [threading.Thread(target=append_worker, args=(i,)) for i in range(N)]
    for t in threads: t.start()
    for t in threads: t.join()

    ok_reports = sum(1 for r in results if r and 'ANADIDO' in r)
    collisions = sum(1 for r in results if r and ('Cannot create' in r or 'No se puede' in r))
    disk = open(os.path.join(VAULT, 'conc', 'base.md'), encoding='utf-8').read()
    on_disk = sum(1 for i in range(N) if ('MARK-%02d' % i) in disk)

    check('conc-append: los %d writers reportan exito' % N, ok_reports == N,
          '%d/%d ANADIDO' % (ok_reports, N))
    check('conc-append: NINGUNA colision de backup (mismo segundo)', collisions == 0,
          '%d colisiones' % collisions)
    check('conc-append: las %d marcas estan EN DISCO (sin perdida silenciosa)' % N,
          on_disk == N, '%d/%d en disco; faltan %s' % (on_disk, N,
          [i for i in range(N) if ('MARK-%02d' % i) not in disk]))
    check('conc-append: exitos reportados == marcas en disco (sin falso exito)',
          ok_reports == on_disk, 'reportados=%d disco=%d' % (ok_reports, on_disk))

    # ---- burst 2: N simultaneous CREATEs of DISTINCT notes ------------------
    cres = [None] * N
    barrier2 = threading.Barrier(N)
    def create_worker(i):
        barrier2.wait()
        cres[i] = call_tool('vault_create',
            {"path": "conc/n%02d.md" % i, "content": "# nota %02d\n\ncontenido\n" % i})
    threads2 = [threading.Thread(target=create_worker, args=(i,)) for i in range(N)]
    for t in threads2: t.start()
    for t in threads2: t.join()
    created = sum(1 for i in range(N)
                  if os.path.exists(os.path.join(VAULT, 'conc', 'n%02d.md' % i)))
    creport = sum(1 for r in cres if r and 'CREADA' in r)
    check('conc-create: las %d notas distintas existen en disco' % N, created == N,
          '%d/%d creadas' % (created, N))
    check('conc-create: %d exitos reportados (sin choque)' % N, creport == N,
          '%d/%d CREADA' % (creport, N))

    # ---- the empty-note guard still holds under the lock --------------------
    out = call_tool('vault_patch', {"path": "conc/base.md",
        "old_text": open(os.path.join(VAULT, 'conc', 'base.md'), encoding='utf-8').read(),
        "new_text": ""})
    check('lock: patch que vaciaria la nota sigue RECHAZADO',
          'VACIA' in out or 'vacia' in out or 'RECHAZAD' in out, out[:150])
finally:
    proc.kill()

total = P + FCOUNT
print('\n== r9 concurrency battery: %d PASS / %d FAIL ==' % (P, FCOUNT))
sys.exit(1 if FCOUNT else 0)
