"""E2E battery for delphi_create: scaffold projects/forms and BUILD them.

The acid test: a scaffolded project must compile with delphi_build, and a
scaffolded form must leave the project still compiling.

Usage:  python tests/test_scaffold.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, '..', 'src', 'Win64', 'Debug', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-scaffold-tests')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE, exist_ok=True)

proc = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()

def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)

threading.Thread(target=reader, daemon=True).start()
rid = [10]

def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()

def recv(r, t=300):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = q.get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None

def call(name, args, t=300):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:150]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "scaffold-battery", "version": "1"}}})
assert recv(1, 20), 'no initialize response'
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:200])

def build_ok(dproj):
    out = call('delphi_build', {"project": dproj, "platform": "Win64",
                                "config": "Debug", "target": "Build"}, 600)
    try:
        d = json.loads(out)
        return d['success'], json.dumps(d['errors'])[:180]
    except Exception:
        return False, out[:180]

# --- console project ---
CDIR = os.path.join(BASE, 'HolaConsola')
out = call('delphi_create', {"kind": "project-console", "dir": CDIR, "name": "HolaConsola"})
check('create: proyecto console', out.startswith('CREADO'), out)
ok, err = build_ok(os.path.join(CDIR, 'HolaConsola.dproj'))
check('build: proyecto console COMPILA', ok, err)
out = call('delphi_create', {"kind": "project-console", "dir": CDIR, "name": "HolaConsola"})
check('create: jamas sobreescribe', 'RECHAZADO' in out, out)

# --- VCL project + extra form ---
VDIR = os.path.join(BASE, 'HolaVcl')
out = call('delphi_create', {"kind": "project-vcl", "dir": VDIR, "name": "HolaVcl"})
check('create: proyecto VCL', out.startswith('CREADO'), out)
ok, err = build_ok(os.path.join(VDIR, 'HolaVcl.dproj'))
check('build: proyecto VCL COMPILA', ok, err)

out = call('delphi_create', {"kind": "form-vcl", "name": "UClientes",
                             "project": os.path.join(VDIR, 'HolaVcl.dpr')})
check('create: form VCL + alta en dpr', out.startswith('CREADO'), out)
dpr = open(os.path.join(VDIR, 'HolaVcl.dpr'), 'rb').read().decode('utf-8-sig')
check('form: registrado en uses y CreateForm',
      "UClientes in 'UClientes.pas'" in dpr and 'TFormUClientes' in dpr, dpr[-300:])
ok, err = build_ok(os.path.join(VDIR, 'HolaVcl.dproj'))
check('build: VCL con form nuevo COMPILA', ok, err)

# --- new unit in a NEW subfolder of an existing project ---
out = call('delphi_edit', {"path": os.path.join(VDIR, 'nucleo', 'UUtilidades.pas'),
                           "createunit": True})
check('createunit: en subcarpeta NUEVA', out.startswith('CREADA')
      and os.path.exists(os.path.join(VDIR, 'nucleo', 'UUtilidades.pas')), out)

# --- FMX project ---
FDIR = os.path.join(BASE, 'HolaFmx')
out = call('delphi_create', {"kind": "project-fmx", "dir": FDIR, "name": "HolaFmx"})
check('create: proyecto FMX', out.startswith('CREADO'), out)
ok, err = build_ok(os.path.join(FDIR, 'HolaFmx.dproj'))
check('build: proyecto FMX COMPILA', ok, err)

print()
print('== scaffold battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
