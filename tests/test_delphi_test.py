"""E2E battery for v0.59.0-beta - delphi_test: the difference between "it
compiles" and "it works".

Two independent reviews (mine and an agent's, 2026-08-25) named the same gap
as the biggest one left: an agent could write code and never learn whether it
does the right thing. This battery builds a green suite and a red one and
checks the server tells them apart, with numbers.

Usage:  python tests/test_delphi_test.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'dtest')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

def spawn(extra_env=None):
    env = dict(os.environ); env['DELPHI_MCP_ROOTS'] = BASE
    env.pop('DELPHI_MCP_ALLOW_RUN', None)
    env.pop('DELPHI_MCP_ALLOW_TESTS', None)
    if extra_env: env.update(extra_env)
    p = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    q = queue.Queue()
    def rd():
        for line in p.stdout:
            line = line.strip()
            if line: q.put(line)
    threading.Thread(target=rd, daemon=True).start()
    st = {'p': p, 'q': q, 'id': 10}
    send(st, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "dt", "version": "1"}}})
    recv(st, 1)
    send(st, {"jsonrpc": "2.0", "method": "notifications/initialized"})
    return st
def send(st, o): st['p'].stdin.write(json.dumps(o) + '\n'); st['p'].stdin.flush()
def recv(st, r, t=600):
    dl = time.time() + t
    while time.time() < dl:
        try: line = st['q'].get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(st, name, args, t=600):
    st['id'] += 1
    send(st, {"jsonrpc": "2.0", "id": st['id'], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(st, st['id'], t)
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:300])
def J(t):
    try: return json.loads(t)
    except Exception: return {}

A = spawn()                                    # sin permiso de ejecutar
B = spawn({'DELPHI_MCP_ALLOW_TESTS': '1'})     # con el interruptor

# ---- fixtures: una suite verde y una roja, y un proyecto que NO es test ----
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'VerdeTest', 'dir': os.path.join(BASE, 'VerdeTest')})
assert 'CREADO' in r, r
VERDE = os.path.join(BASE, 'VerdeTest', 'VerdeTest.dpr')
open(VERDE, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""program VerdeTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils;

procedure Comprobar(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName);
    ExitCode := 1;
  end;
end;

begin
  Comprobar('suma', 2 + 2 = 4);
  Comprobar('cadena', UpperCase('ab') = 'AB');
  Comprobar('resta', 5 - 3 = 2);
end.
""")
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'RojoTest', 'dir': os.path.join(BASE, 'RojoTest')})
ROJO = os.path.join(BASE, 'RojoTest', 'RojoTest.dpr')
open(ROJO, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""program RojoTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils;

procedure Comprobar(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName);
    ExitCode := 1;
  end;
end;

begin
  Comprobar('esta bien', True);
  Comprobar('esta MAL a proposito', 1 = 2);
end.
""")
call(A, 'delphi_create', {'kind': 'project-console', 'name': 'NormalApp', 'dir': os.path.join(BASE, 'NormalApp')})

# ---- discover ----
j = J(call(A, 'delphi_test', {'command': 'discover', 'path': BASE}))
names = [os.path.basename(p.get('dpr', '')) for p in j.get('projects', [])]
check('discover encuentra las dos suites', 'VerdeTest.dpr' in names and 'RojoTest.dpr' in names, str(j)[:300])
check('discover NO cuenta un proyecto normal', 'NormalApp.dpr' not in names, names)
check('discover dice el framework y el porque', all(p.get('framework') and p.get('why') for p in j.get('projects', [])), str(j)[:250])
j = J(call(A, 'delphi_test', {'command': 'discover', 'path': os.path.join(BASE, 'NormalApp')}))
check('carpeta sin tests: total 0 con explicacion', j.get('total') == 0 and 'test' in (j.get('note') or ''), str(j)[:250])

# ---- el interruptor ----
r = call(A, 'delphi_test', {'command': 'run', 'project': VERDE})
check('sin AllowTests: run RECHAZADO nombrando el interruptor', 'RECHAZADO' in r and 'AllowTests' in r, r[:250])
r = call(A, 'delphi_test', {'command': 'discover', 'path': BASE})
check('sin AllowTests: discover SI funciona', r.startswith('{'), r[:150])

# ---- run verde ----
j = J(call(B, 'delphi_test', {'command': 'run', 'project': VERDE}, t=900))
check('suite verde: result=pass', j.get('result') == 'pass', str(j)[:400])
check('suite verde: 3 de 3', j.get('total') == 3 and j.get('passed') == 3 and j.get('failed') == 0, str(j)[:300])
check('suite verde: veredicto por numeros', j.get('verdictFrom') == 'counts', str(j)[:200])
check('suite verde: dice el binario y la duracion', bool(j.get('binary')) and j.get('durationMs') is not None, str(j)[:250])
check('suite verde: corrio en sandbox', j.get('sandboxed') is True, str(j)[:200])

# ---- run rojo ----
j = J(call(B, 'delphi_test', {'command': 'run', 'project': ROJO}, t=900))
check('suite roja: result=fail', j.get('result') == 'fail', str(j)[:400])
check('suite roja: 1 de 2 y el fallo NOMBRADO', j.get('failed') == 1 and any('MAL' in f for f in j.get('failures', [])), str(j)[:350])
check('suite roja: exitCode distinto de 0', j.get('exitCode') not in (0, None), str(j)[:200])

# ---- contratos ----
r = call(B, 'delphi_test', {'command': 'run', 'project': os.path.join(BASE, 'NormalApp', 'NormalApp.dpr')})
check('un proyecto que no es test: rechazado y explicado', 'RECHAZADO' in r and 'DUnitX' in r, r[:300])
r = call(B, 'delphi_test', {'command': 'run'})
check('run sin project rechazado con pista', 'RECHAZADO' in r and 'discover' in r, r[:200])
r = call(B, 'delphi_test', {'command': 'volar', 'path': BASE})
check('comando invalido', 'discover' in r and 'run' in r, r[:150])
r = call(B, 'delphi_test', {'command': 'run', 'project': 'C:\\Windows\\x.dproj'})
check('fuera de la jaula rechazado', 'RECHAZADO' in r, r[:200])

# una suite que NO compila: se dice, no se ejecuta nada viejo
# ojo: Delphi IGNORA lo que va despues de "end." - hay que romperlo DENTRO
_txt = open(ROJO, encoding='utf-8-sig').read().replace(
    "Comprobar('esta bien', True);", "esto no compila ni de lejos;")
open(ROJO, 'w', encoding='utf-8-sig', newline='').write(_txt)
j = J(call(B, 'delphi_test', {'command': 'run', 'project': ROJO}, t=900))
check('suite que no compila: result=build-failed con los errores',
      j.get('result') == 'build-failed' and bool(j.get('build')), str(j)[:300])

A['p'].kill(); B['p'].kill()
print('\n== delphi_test battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
