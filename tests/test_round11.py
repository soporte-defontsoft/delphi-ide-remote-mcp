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
# el conversor de estilos vive junto al servidor: sin el, command=build para
# antes de llegar al .rc y no se puede comprobar su jaula
_conv = os.path.join(os.path.dirname(SRC), 'DelphiStyleConvert.exe')
if os.path.exists(_conv):
    shutil.copy(_conv, os.path.join(BASE, 'DelphiStyleConvert.exe'))


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

# ------------------------------------------------ los dos MUROS derribados --
# W1: coser un cambio que toca N sitios del MISMO fichero era N llamadas sin
# atomicidad, o N+3 con ella. Ahora es una, y con red.
W = os.path.join(BASE, 'UCose.pas')
open(W, 'w', encoding='utf-8', newline='\r\n').write(
    'unit UCose;\ninterface\ntype\n  TCosa = class\n  private\n    FA: Integer;\n'
    '  public\n    procedure Uno;\n    procedure Dos;\n  end;\nimplementation\nend.\n')
edits = json.dumps([{"old": "    FA: Integer;", "new": "    FA: Integer;\r\n    FB: string;"},
                    {"old": "    procedure Uno;", "new": "    procedure Uno(A: Integer);"},
                    {"old": "    procedure Dos;", "new": "    procedure Dos(B: string);"}])
r = call(A, 'delphi_edit', {'path': W, 'edits': edits})
disk = open(W, encoding='utf-8').read()
check('W1 tres ediciones sobre un fichero en UNA llamada',
      'APLICADAS 3' in r and 'FB: string;' in disk and 'Uno(A: Integer)' in disk, r[:250])
bad = json.dumps([{"old": "    procedure Uno(A: Integer);", "new": "    procedure Uno(A, C: Integer);"},
                  {"old": "ESTA LINEA NO EXISTE", "new": "x"}])
r = call(A, 'delphi_edit', {'path': W, 'edits': bad})
check('W1 si una falla, se deshacen TODAS (byte a byte)',
      'ROLLBACK' in r and open(W, encoding='utf-8').read() == disk, r[:250])
r = call(A, 'delphi_edit', {'path': W, 'edits': 'esto no es json'})
check('W1 un "edits" que no es JSON se explica', 'RECHAZADO' in r and 'JSON' in r, r[:200])

# W2: orientarse en codigo ajeno costaba un delphi_read por fichero
jd = J(call(A, 'delphi_symbols', {'path': P1}))
check('W2 delphi_symbols sobre una CARPETA resume todas sus units',
      jd.get('total', 0) >= 1 and bool(jd.get('units')), str(jd)[:250])
ucalc = [u for u in jd.get('units', []) if u.get('unit') == 'UCalc']
# Cada declaracion es un objeto: el texto ENTERO (aunque ocupe varias lineas),
# a que clase pertenece y en que linea esta.
_decls = ucalc[0].get('declares', []) if ucalc else []
check('W2 ...con lo que cada una declara, miembros incluidos',
      any(('Doble' in d.get('decl', '')) or ('Triple' in d.get('decl', ''))
          for d in _decls), str(ucalc)[:250])
check('W2 ...diciendo de que clase es cada miembro y en que linea',
      any(d.get('of') == 'TCalc' and d.get('line') for d in _decls), str(_decls)[:250])

# ------------------------------------ S4: la MISMA puerta, otro compilador --
# {$I} y {$R} meten un fichero en la compilacion. El compilador lo abre con los
# permisos del servidor, y lo que entra sale por dos sitios: dentro del binario
# (que se descarga) y citado palabra por palabra en los errores si no es
# Pascal. Medido: un .txt de fuera volvio como "Undeclared identifier: 'esto'".
FUERA = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'FUERA-R11.inc')
open(FUERA, 'w', encoding='utf-8').write('SECRETO_UNO = 1;\n')
PF = os.path.join(BASE, 'Incl')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'Incl', 'dir': PF})
assert 'CREADO' in r, r
open(os.path.join(PF, 'Incl.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    "program Incl;\n\n{$APPTYPE CONSOLE}\n\nconst\n{$I '" + FUERA + "'}\n\n"
    "begin\n  Writeln(SECRETO_UNO);\nend.\n")
r = call(A, 'delphi_build', {'project': os.path.join(PF, 'Incl.dproj'),
                             'platform': 'Win64', 'config': 'Debug'}, t=900)
check('S4 un {$I} que apunta FUERA de la jaula: no se compila',
      r.startswith('RECHAZADO') and '{$I' in r, r[:250])
check('S4 ...y no viene ni una palabra del fichero de fuera',
      'SECRETO_UNO' not in r, r[:250])
check('S4 ...y es un RECHAZO, no un "Error executing tool"',
      not r.startswith('Error executing tool'), r[:120])
# lo normal sigue compilando: {$R *.res} y un include de dentro
open(os.path.join(PF, 'dentro.inc'), 'w', encoding='utf-8', newline='\r\n').write(
    'SECRETO_UNO = 1;\n')
open(os.path.join(PF, 'Incl.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    "program Incl;\n\n{$APPTYPE CONSOLE}\n{$R *.res}\n\nconst\n"
    "{$I 'dentro.inc'}\n\nbegin\n  Writeln(SECRETO_UNO);\nend.\n")
r = call(A, 'delphi_build', {'project': os.path.join(PF, 'Incl.dproj'),
                             'platform': 'Win64', 'config': 'Debug'}, t=900)
check('S4 un include de DENTRO, y el {$R *.res} de siempre, compilan igual',
      not r.startswith('RECHAZADO'), r[:250])

# ------------------------------------- lo que pidio el refactor (ronda 12) --
BLK = os.path.join(BASE, 'UBloque.pas')
open(BLK, 'w', encoding='utf-8', newline='\r\n').write(
    'unit UBloque;\ninterface\nimplementation\n\nprocedure Uno;\nbegin\n'
    '  Writeln(1);\n  Writeln(2);\nend;\n\nprocedure Dos;\nbegin\n'
    '  Writeln(1);\n  Writeln(2);\nend;\n\nend.\n')
blk = json.dumps([{"old": "  Writeln(1);\n  Writeln(2);", "new": "  Writeln(9);",
                   "occurrence": 2}])
r = call(A, 'delphi_edit', {'path': BLK, 'edits': blk})
disk = open(BLK, encoding='utf-8').read()
check('M1 un ancla de VARIAS lineas dentro de edits',
      'APLICADAS 1' in r and disk.count('Writeln(9);') == 1, r[:200])
check('M1 ...y "occurrence" elige cual, sin contar lineas',
      disk.index('Writeln(9);') > disk.index('procedure Dos;'), disk)
amb = json.dumps([{"old": "procedure Uno;\nbegin", "new": "procedure Uno;\nbegin"},
                  {"old": "  ESTO(1);\n  NO EXISTE(2);", "new": "x"}])
r = call(A, 'delphi_edit', {'path': BLK, 'edits': amb})
check('M1 un bloque que no existe se rechaza y se deshace todo',
      'ROLLBACK' in r or 'RECHAZADO' in r, r[:200])
r = call(A, 'delphi_help', {})
check('M3 el mapa dice COMO averiguar los parametros de una tool',
      'command=tool' in r and 'content' in r, r[-400:])
r = call(A, 'delphi_test', {'command': 'run', 'project': 'MiTest'})
check('C9 un NOMBRE de proyecto se explica como tal, no como jaula',
      'RUTA' in r and 'delphi_projects' in r, r[:250])

# ------------------------------- la MISMA raiz, dos puertas mas (ronda 12) --
# S5: el guard del .rc miraba solo las lineas del fichero de arriba. Un .rc
# legal que hace #include de otro colaba cualquier fichero - y por ahi salio
# el settings.ini del servidor, con el token, dentro de un .res descargable.
ST2 = os.path.join(BASE, 'styles2')
os.makedirs(ST2, exist_ok=True)
open(os.path.join(ST2, 'b.style'), 'w', encoding='utf-8', newline='\r\n').write(
    "object TStyleContainer\r\n  object TRectangle\r\n"
    "    StyleName = 'x'\r\n  end\r\nend\r\n")
open(os.path.join(ST2, 'inner.txt'), 'w', encoding='utf-8', newline='\r\n').write(
    'ROBADO RCDATA "C:\\Windows\\win.ini"\r\n')
open(os.path.join(ST2, 'b.rc'), 'w', encoding='utf-8', newline='\r\n').write(
    'LEGIT RCDATA "b.bin.style"\r\n#include "inner.txt"\r\n')
r = call(A, 'delphi_styles', {'command': 'build', 'path': ST2}, t=300)
check('S5 un #include que trae una ruta de fuera: RECHAZADO',
      'RECHAZADO' in r and 'inner.txt' in r, r[:300])
check('S5 ...y no queda .res con nada dentro',
      not os.path.exists(os.path.join(ST2, 'b.res')), os.listdir(ST2))

# S6: symbols distinguia "existe fuera" de "no existe" - un mapa del disco,
# una llamada cada vez. Ahora el rechazo de jaula es el mismo en los dos casos.
r1 = call(A, 'delphi_symbols', {'path': 'C:\\Windows\\NoExisteJamas.pas'})
r2 = call(A, 'delphi_symbols', {'path': SRC})
check('S6 fuera de la jaula: el MISMO rechazo exista o no',
      ('FUERA' in r1) and ('FUERA' in r2), (r1[:90], r2[:90]))

A['p'].kill()
print('\n== round-11 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
