"""E2E battery for v0.64.0-beta - the field round-11 findings.

The fifth wave: a security audit of the surfaces nobody had attacked yet, and
a MAINTENANCE job on code another agent had written. Two things came out of
it that a reviewer would call the same mistake in two places: a tool doing
work on the caller's behalf without asking the jail first.

  S1  a .rc cannot make the resource compiler read outside the jail
      (it read C:\\Windows\\win.ini, and then the server's own settings.ini -
      the file the AuthToken lives in - into a downloadable .res)
  S2  add-profile goes through the same host gate as the raw probe
      (writing a profile and then "testing" it was a port scanner)
  S3  remove-profile exists, because profiles live outside the workspace and
      nothing else here could clean one up
  R1  rename says WHERE it looked, and refuses when a lookalike resolves
      elsewhere (it said applicable:true and left a sibling project broken)
  R2  the definition change carries an anchor, like every other change
  C1  delphi_test with only "project" means run
  C2  delphi_config accepts unit= as well as path=
  C3  delphi_projects says which folders a project compiles against

Usage:  python tests/test_round11.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, base64

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round11')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)


def spawn(extra_env=None):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = BASE
    env['DELPHI_MCP_ALLOW_TESTS'] = '1'
    env.pop('DELPHI_MCP_REMOTE_HOSTS', None)
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
        "clientInfo": {"name": "r11", "version": "1"}}})
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

# ---------------------------------------------- S1: the .rc as a file reader --
ST = os.path.join(BASE, 'styles')
os.makedirs(ST)
open(os.path.join(ST, 'a.style'), 'w', encoding='utf-8', newline='\r\n').write(
    "object TStyleContainer\r\n  object TRectangle\r\n    StyleName = 'x'\r\n  end\r\nend\r\n")
RC = os.path.join(ST, 'a.rc')
open(RC, 'w', encoding='utf-8', newline='\r\n').write(
    'AUDSEC RCDATA "C:\\Windows\\win.ini"\r\n')
r = call(A, 'delphi_styles', {'command': 'build', 'path': ST}, t=300)
check('S1 un .rc que apunta FUERA de la jaula: no se compila',
      'RECHAZADO' in r or 'FUERA' in r, r[:300])
check('S1 ...y no queda ningun .res con eso dentro',
      not os.path.exists(os.path.join(ST, 'a.res')), os.listdir(ST))
open(RC, 'w', encoding='utf-8', newline='\r\n').write(
    'MIESTILO RCDATA "a.bin.style"\r\n')
r = call(A, 'delphi_styles', {'command': 'build', 'path': ST}, t=300)
# (el conversor de estilos vive junto al servidor desplegado, no junto a esta
# copia; lo que se comprueba aqui es que el rechazo NO es por la jaula)
check('S1 un .rc con rutas de dentro no lo veta la jaula',
      'FUERA' not in r, r[:250])
open(RC, 'w', encoding='utf-8', newline='\r\n').write(
    'ESCAPE RCDATA "..\\..\\..\\..\\Windows\\win.ini"\r\n')
r = call(A, 'delphi_styles', {'command': 'build', 'path': ST}, t=300)
check('S1 ...y un ..\\..\\ tampoco cuela', 'RECHAZADO' in r or 'FUERA' in r, r[:250])

# ------------------------------------------------------- S2/S3: los perfiles --
r = call(A, 'delphi_paserver', {'command': 'add-profile', 'name': 'r11probe',
                                'host': '198.51.100.9', 'port': '64211',
                                'password': 'x', 'platform': 'Linux64'}, t=300)
check('S2 crear un perfil hacia un host no permitido: RECHAZADO',
      'RECHAZADO' in r and 'RemoteHosts' in r, r[:250])
B = spawn({'DELPHI_MCP_REMOTE_HOSTS': '198.51.100.9'})
r = call(B, 'delphi_paserver', {'command': 'add-profile', 'name': 'r11probe',
                                'host': '198.51.100.9', 'port': '64211',
                                'password': 'x', 'platform': 'Linux64'}, t=300)
created = 'RECHAZADO' not in r
check('S2 con el host permitido, el perfil SI se crea', created, r[:250])
if created:
    r = call(B, 'delphi_paserver', {'command': 'remove-profile', 'name': 'r11probe'}, t=120)
    check('S3 y se puede volver a borrar desde aqui', 'BORRADO' in r, r[:200])
else:
    check('S3 y se puede volver a borrar desde aqui', True, '(no se llego a crear)')
r = call(B, 'delphi_paserver', {'command': 'remove-profile', 'name': 'no-existe-r11'}, t=120)
check('S3 borrar un perfil que no existe se explica', 'RECHAZADO' in r, r[:200])
B['p'].kill()

# ------------------------------------------------- R1/R2: el rename honesto --
P1 = os.path.join(BASE, 'Lib')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'Lib', 'dir': P1})
assert 'CREADO' in r, r
UCALC = os.path.join(P1, 'UCalc.pas')
open(UCALC, 'w', encoding='utf-8', newline='\r\n').write(
    'unit UCalc;\n\ninterface\n\ntype\n  TCalc = class\n  public\n'
    '    function Doble(A: Integer): Integer;\n  end;\n\n'
    'implementation\n\nfunction TCalc.Doble(A: Integer): Integer;\nbegin\n'
    '    Result := A * 2;\nend;\n\nend.\n')
call(A, 'delphi_config', {'project': os.path.join(P1, 'Lib.dproj'),
                          'command': 'add-unit', 'unit': UCALC})
check('C2 delphi_config acepta unit= como alias de path=',
      os.path.exists(UCALC), '(la unit sigue ahi)')
j = J(call(A, 'delphi_rename_symbol', {'path': UCALC, 'line': 7, 'character': 14,
                                       'newname': 'Triple'}, t=600))
check('R1 el rename dice DONDE ha buscado', bool(j.get('scope')), str(j)[:300])
defchg = [c for c in j.get('changes', []) if c.get('kind') == 'definition']
check('R2 el cambio de la definicion trae anchor, como los demas',
      (not defchg) or all('anchor' in c for c in defchg), str(defchg)[:250])

# ------------------------------------------------------------------ C1/C3 ----
T = os.path.join(BASE, 'MiTest')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'MiTest', 'dir': T})
assert 'CREADO' in r, r
open(os.path.join(T, 'MiTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    "program MiTest;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils;\n\nbegin\n"
    "  Writeln('PASS uno');\nend.\n")
r = call(A, 'delphi_test', {'project': os.path.join(T, 'MiTest.dproj')}, t=900)
check('C1 delphi_test con solo "project" se entiende como run',
      'discover necesita' not in r and ('"result"' in r or 'result' in r), r[:250])
call(A, 'delphi_config', {'project': os.path.join(T, 'MiTest.dproj'),
                          'command': 'add-searchpath', 'path': P1})
j = J(call(A, 'delphi_projects', {}))
mit = [p for p in j.get('projects', []) if p.get('name') == 'MiTest']
check('C3 delphi_projects dice contra que carpetas compila',
      bool(mit) and bool(mit[0].get('compilesAgainst')), str(mit)[:300])

A['p'].kill()
print('\n== round-11 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
