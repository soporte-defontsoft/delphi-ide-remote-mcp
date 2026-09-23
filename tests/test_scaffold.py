"""E2E battery for delphi_create: scaffold projects/forms and BUILD them.

The acid test: a scaffolded project must compile with delphi_build, and a
scaffolded form must leave the project still compiling.

Usage:  python tests/test_scaffold.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, '..', 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'scaffold')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE, exist_ok=True)

env = dict(os.environ)
env.setdefault('DELPHI_MCP_ROOTS', BASE)  # v0.98: sin jaula declarada = solo lectura
env['DELPHI_MCP_ALLOW_RUN'] = '1'  # let the run test reach the "needs roots" path
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
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

# v0.29: a successful build DECLARES the artifact it produced (stateless
# protocol: the agent must not have to hunt the disk for its own output)
out = call('delphi_build', {"project": os.path.join(CDIR, 'HolaConsola.dproj'),
                            "platform": "Win64", "config": "Debug",
                            "target": "Build"}, 600)
try:
    d = json.loads(out)
    outp = d.get('output', '')
    if outp.lower().startswith('srv'):
        outp = outp[3].upper() + outp[4:]
    check('build: resultado declara el artefacto (output)',
          outp.lower().endswith('holaconsola.exe') and os.path.isfile(outp),
          d.get('output', '(sin output)'))
    check('build: outputSize > 0', d.get('outputSize', 0) > 0, out[:200])
    check('build: outputNote guia package+fetch',
          'delphi_package' in d.get('outputNote', ''), out[:200])
except Exception as e:
    check('build: output parsea', False, '%s | %s' % (e, out[:200]))
out = call('delphi_create', {"kind": "project-console", "dir": CDIR, "name": "HolaConsola"})
check('create: jamas sobreescribe', 'RECHAZADO' in out, out)

# v0.98: la bateria declara su jaula (sin jaula ya no hay barra libre sino
# solo lectura), asi que delphi_run del exe recien compilado EJECUTA dentro
# de ella - sandbox de integridad baja y salida capturada, como siempre
out = call('delphi_run', {"path": os.path.join(CDIR, 'Win64', 'Debug', 'HolaConsola.exe')})
check('run: con jaula declarada ejecuta en el sandbox', 'exit=0' in out, out[:150])

# --- runtime package (1.2 candidate, pulled forward on 2026-09-23: Hermes'
# battery 1.2 case 1 could not even start a package by tools) ---
PDIR = os.path.join(BASE, 'PaqueteUno')
PDPK = os.path.join(PDIR, 'PaqueteUno.dpk')
PDPROJ = os.path.join(PDIR, 'PaqueteUno.dproj')
out = call('delphi_create', {"kind": "project-package", "dir": PDIR, "name": "PaqueteUno"})
check('package: CREADO', out.startswith('CREADO') and 'contains' in out, out[:300])
check('package: .dpk + .dproj', os.path.isfile(PDPK) and os.path.isfile(PDPROJ), os.listdir(PDIR) if os.path.isdir(PDIR) else 'sin carpeta')
_k = open(PDPK, 'rb').read().decode('utf-8-sig')
check('package: requires rtl, sin contains', 'requires' in _k and 'rtl;' in _k and 'contains' not in _k, _k)
_x = open(PDPROJ, 'rb').read().decode('utf-8-sig')
check('package: .dproj de paquete (MainSource .dpk, AppType Package, bpl en la carpeta)',
      '<MainSource>PaqueteUno.dpk</MainSource>' in _x and '<AppType>Package</AppType>' in _x and
      '<DCC_BplOutput>' in _x and '<DCC_DcpOutput>' in _x and '<Borland.ProjectType>Package</Borland.ProjectType>' in _x, _x[:400])
out = call('delphi_build', {"project": PDPROJ, "platform": "Win64", "config": "Debug", "target": "Build"}, 600)
try:
    d = json.loads(out)
    check('package: vacio COMPILA a .bpl', d['success'] and d.get('output', '').lower().endswith('paqueteuno.bpl'), out[:250])
    check('package: .dcp en la carpeta del proyecto (no en la publica de Embarcadero)',
          os.path.isfile(os.path.join(PDIR, 'Win64', 'Debug', 'PaqueteUno.dcp')), os.listdir(os.path.join(PDIR, 'Win64', 'Debug')) if os.path.isdir(os.path.join(PDIR, 'Win64', 'Debug')) else 'sin salida')
except Exception as e:
    check('package: build parsea', False, '%s | %s' % (e, out[:200]))
# the first unit OPENS the contains clause
out = call('delphi_create', {"kind": "unit", "name": "UPkgUno", "project": PDPK})
check('package: kind=unit registra en contains', out.startswith('CREADA') and 'ANADIDA' in out, out[:300])
_k = open(PDPK, 'rb').read().decode('utf-8-sig')
check('package: contains estrenada antes de end.', "contains\r\n  UPkgUno in 'UPkgUno.pas';" in _k and _k.index('contains') < _k.index('end.'), _k)
check('package: requires intacta', "requires\r\n  rtl;" in _k, _k)
# a second unit by hand + add-unit, into a subfolder
_sub = os.path.join(PDIR, 'src')
os.makedirs(_sub, exist_ok=True)
_dos = os.path.join(_sub, 'UPkgDos.pas')
open(_dos, 'wb').write('unit UPkgDos;\r\n\r\ninterface\r\n\r\nfunction Dos: Integer;\r\n\r\nimplementation\r\n\r\nfunction Dos: Integer;\r\nbegin\r\n  Result := 2;\r\nend;\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": PDPROJ, "command": "add-unit", "path": _dos})
check('package: add-unit por el .dproj (resuelve al .dpk)', out.startswith('ANADIDA'), out[:300])
_k = open(PDPK, 'rb').read().decode('utf-8-sig')
check('package: contains con dos entradas y coma', "UPkgUno in 'UPkgUno.pas',\r\n  UPkgDos in 'src\\UPkgDos.pas';" in _k, _k)
check('package: DCCReference de las dos', 'Include="UPkgUno.pas"' in open(PDPROJ, 'rb').read().decode('utf-8-sig') and 'Include="src\\UPkgDos.pas"' in open(PDPROJ, 'rb').read().decode('utf-8-sig'), '')
out = call('delphi_config', {"project": PDPROJ, "section": "units"})
try:
    _u = {u['unit'] for u in json.loads(out).get('units', [])}
    check('package: view units lista las dos', _u == {'UPkgUno', 'UPkgDos'}, _u)
except Exception as e:
    check('package: view units parsea', False, '%s | %s' % (e, out[:200]))
ok, err = build_ok(PDPROJ)
check('package: con dos units COMPILA', ok, err)
# a unit that uses another package's units: the IDE lists them and offers
# to add their packages to requires; here the build lists them and
# add-requires writes them (measured 2026-09-23: 25 W1033 and a 4.6 MB BPL
# with the VCL inside, invisible in quiet)
out = call('delphi_create', {"kind": "unit", "name": "UUsaVcl", "project": PDPK, "content":
    "unit UUsaVcl;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Dialogs, Data.DB;\r\n\r\nprocedure Saluda;\r\n\r\nimplementation\r\n\r\nprocedure Saluda;\r\nbegin\r\n  ShowMessage('hola');\r\nend;\r\n\r\nend.\r\n"})
check('package: unit que usa Vcl y Data', out.startswith('CREADA'), out[:200])
out = call('delphi_build', {"project": PDPROJ, "platform": "Win64", "config": "Debug", "target": "Build"}, 600)
try:
    d = json.loads(out)
    check('package: build quiet en verde pero con implicitImports', d['success'] and 'Vcl.Dialogs' in d.get('implicitImports', []), out[:300])
    check('package: requiresSuggested trae vcl y dbrtl (leido de los BPL)', {'vcl', 'dbrtl'} <= set(d.get('requiresSuggested', [])), d.get('requiresSuggested'))
    check('package: requiresNote con la orden add-requires', 'add-requires' in d.get('requiresNote', ''), d.get('requiresNote', '')[:200])
    check('package: en quiet sigue sin warnings[]', 'warnings' not in d, list(d.keys()))
    _sug = ';'.join(d.get('requiresSuggested', []))
    _bpl_gordo = d.get('outputSize', 0)
except Exception as e:
    check('package: build con W1033 parsea', False, '%s | %s' % (e, out[:200])); _sug = 'vcl;dbrtl'; _bpl_gordo = 0
out = call('delphi_config', {"project": PDPROJ, "command": "add-requires", "requires": _sug})
check('package: add-requires ANADIDOS', out.startswith('ANADIDOS'), out[:200])
_k = open(PDPK, 'rb').read().decode('utf-8-sig')
check('package: requires con rtl, vcl y dbrtl, una por linea', "requires\r\n  rtl,\r\n" in _k and 'vcl' in _k.split('contains')[0] and 'dbrtl' in _k.split('contains')[0], _k)
out = call('delphi_config', {"project": PDPROJ, "command": "add-requires", "requires": "vcl"})
check('package: add-requires idempotente', 'ya estaban' in out, out[:200])
out = call('delphi_build', {"project": PDPROJ, "platform": "Win64", "config": "Debug", "target": "Build"}, 600)
try:
    d = json.loads(out)
    check('package: con requires COMPILA sin implicitImports', d['success'] and 'implicitImports' not in d, out[:300])
    check('package: el BPL adelgaza (ya no lleva la VCL dentro)', 0 < d.get('outputSize', 0) < _bpl_gordo, '%s -> %s' % (_bpl_gordo, d.get('outputSize')))
except Exception as e:
    check('package: build con requires parsea', False, '%s | %s' % (e, out[:200]))
out = call('delphi_config', {"project": PDPROJ, "command": "remove-unit", "path": os.path.join(PDIR, 'UUsaVcl.pas')})
check('package: remove-unit de la unit VCL dice contains', out.startswith('QUITADA') and '(contains' in out, out[:200])
out = call('delphi_config', {"project": PDPROJ, "command": "remove-unit", "path": os.path.join(PDIR, 'UPkgUno.pas')})
check('package: remove-unit', out.startswith('QUITADA') or 'quitada' in out.lower(), out[:200])
_k = open(PDPK, 'rb').read().decode('utf-8-sig')
check('package: contains se queda con la otra', "contains\r\n  UPkgDos in 'src\\UPkgDos.pas';" in _k and 'UPkgUno' not in _k, _k)
ok, err = build_ok(PDPROJ)
check('package: tras remove-unit COMPILA', ok, err)
out = call('delphi_create', {"kind": "project-package", "dir": PDIR, "name": "PaqueteUno"})
check('package: jamas sobreescribe', 'RECHAZADO' in out, out)

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
