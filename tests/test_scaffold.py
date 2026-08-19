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

# run the freshly built console exe (needs roots configured -> restart not
# needed: this battery runs unrestricted, so delphi_run must REFUSE)
out = call('delphi_run', {"path": os.path.join(CDIR, 'Win64', 'Debug', 'HolaConsola.exe')})
check('run: sin jaula configurada rechaza', out.startswith('error:') and 'roots' in out.lower(), out[:150])

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

# --- package the deploy and verify the zip ---
import zipfile
out = call('delphi_package', {"dir": os.path.join(VDIR, 'Win64', 'Debug')})
try:
    d = json.loads(out)
    zp = d['zip']
    # since v0.12 server paths travel with virtual drive units (srvX: = X:)
    if zp.lower().startswith('srv'):
        zp = zp[3].upper() + zp[4:]
    names = zipfile.ZipFile(zp).namelist()
    check('package: zip creado con el exe', 'HolaVcl.exe' in names, names)
    check('package: sin dcu dentro', not any(n.endswith('.dcu') for n in names), names)
except Exception:
    check('package: parsea', False, out[:200])

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

# --- B0: createunit accepts DOTTED namespace unit names ---
out = call('delphi_edit', {"path": os.path.join(VDIR, 'Lsp.BuildRunner.pas'),
                           "createunit": True})
check('createunit: nombre dotted (Lsp.BuildRunner) aceptado',
      out.startswith('CREADA') and 'Lsp.BuildRunner' in out, out[:150])

# --- M1: whole unit content in ONE call (create-with-content) + eol ---
uc = ("unit Mi.Unidad.Nueva;\n\ninterface\n\nfunction Saluda: string;\n\n"
      "implementation\n\nfunction Saluda: string;\nbegin\n"
      "  Result := '¡hola gestoría!';\nend;\n\nend.")
up = os.path.join(VDIR, 'Mi.Unidad.Nueva.pas')
out = call('delphi_edit', {"path": up, "createunit": True, "content": uc})
check('createunit: unit COMPLETA en una llamada', out.startswith('CREADA'), out[:200])
raw = open(up, 'rb').read()
check('createunit content: UTF-8 con BOM y CRLF (sin LF sueltos)',
      raw[:3] == b'\xef\xbb\xbf' and raw.count(b'\n') == raw.count(b'\r\n'),
      repr(raw[:40]))
check('createunit content: acentos intactos',
      '¡hola gestoría!' in raw.decode('utf-8-sig'), raw[-120:])
out = call('delphi_textedit', {"path": os.path.join(VDIR, 'unix.md'),
                               "create": True, "content": "a\nb\n", "eol": "lf"})
check('textedit: eol=lf produce LF puro',
      b'\r' not in open(os.path.join(VDIR, 'unix.md'), 'rb').read(), out[:120])

# --- B1: old given + new="" blanks the line (no Access Violation) ---
bp = os.path.join(VDIR, 'BlankMe.pas')
call('delphi_edit', {"path": bp, "createunit": True})
out = call('delphi_edit', {"path": bp, "old": "interface", "new": ""})
check('edit: new="" blanquea la linea sin AccessViolation',
      'BLANQUEADA la linea' in out and 'AccessViolation' not in out, out[:150])

# --- scaffold ships a basic .gitignore (remote agent may edit it later) ---
gi = os.path.join(VDIR, '.gitignore')
check('gitignore: creado por el scaffold', os.path.exists(gi)
      and '__delphi-patch/' in open(gi).read(), gi)

# --- BOM audit false positive: accents into a UTF8-BOM unit must NOT warn ---
out = call('delphi_edit', {"path": os.path.join(VDIR, 'UMain.pas'),
    "insert": "metodo", "inclass": "TFormMain", "visibility": "public",
    "code": "function Saludar: string;\r\nbegin\r\n  Result := '¡Bienvenida, gestoría!';\r\nend;"})
check('edit: acentos en fichero utf8-bom SIN falso positivo',
      'ESCRITO' in out and 'FUERA DE CUADRO' not in out, out[:300])
body = open(os.path.join(VDIR, 'UMain.pas'), 'rb').read().decode('utf-8-sig')
check('edit: literal con acentos intacto en disco',
      '¡Bienvenida, gestoría!' in body, body[-200:])

# --- stale-buffer fix: the LSP must see edits made AFTER its didOpen ---
out = call('delphi_symbols', {"path": os.path.join(VDIR, 'UMain.pas')}, 300)
check('lsp: symbols inicial (didOpen)', 'TFormMain' in out, out[:150])
out = call('delphi_edit', {"path": os.path.join(VDIR, 'UMain.pas'),
    "insert": "metodo", "inclass": "TFormMain", "visibility": "public",
    "code": "procedure Despedir;\r\nbegin\r\n  Caption := 'adios';\r\nend;"})
check('lsp: insert posterior al didOpen', 'ESCRITO' in out, out[:200])
out = call('delphi_symbols', {"path": os.path.join(VDIR, 'UMain.pas')}, 300)
check('lsp: symbols VE el metodo nuevo (buffer refrescado, no rancio)',
      'Despedir' in out, out[:300])

print()
print('== scaffold battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
