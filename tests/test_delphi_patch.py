"""End-to-end battery for the delphi_edit / delphi_read MCP tools.

Talks real MCP over stdio to the built server and exercises every safety
gate against throwaway fixtures (never against real project code). Verifies
results at BYTE level: encoding preservation is the whole point.

Usage:  python tests/test_delphi_edit.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, subprocess, threading, queue, time, os, sys, tempfile

EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), '..', 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

DIR = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'patch')
os.makedirs(DIR, exist_ok=True)
PAS = os.path.join(DIR, 'Dummy.pas')
DFM = os.path.join(DIR, 'Bin.dfm')
# The REAL on-disk binary form (IDE / convert.exe, measured 2026-08-21):
# a 16-bit resource wrapper - $FF, word len, UPPERCASED name, NUL, size,
# then the TPF0 stream. TPF0 is NOT at offset 0 in this shape.
DFM_FF = os.path.join(DIR, 'BinRes.dfm')

CRLF = '\r\n'
SRC = CRLF.join([
    'unit Dummy;', '',
    'interface', '',
    'procedure Saludar;', '',
    'implementation', '',
    'procedure Saludar;',
    'begin',
    '  X := 1;',
    "  Writeln('gestoría');",   # gestoría — CP1252 high byte
    'end;', '',
    'procedure Otro;',
    'begin',
    '  X := 1;',
    'end;', '',
    'end.', ''])

with open(PAS, 'wb') as f:
    f.write(SRC.encode('cp1252'))
with open(DFM, 'wb') as f:
    f.write(b'TPF0' + b'binarydata')
with open(DFM_FF, 'wb') as f:
    f.write(b'\xff\x0a\x00TFORMX\x00\x30\x10\x86\x03\x00\x00TPF0binarydata')
ORIG = open(PAS, 'rb').read()

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

def recv(r, t=60):
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

def call(name, args, t=60):
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
    "clientInfo": {"name": "patch-battery", "version": "1"}}})
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
        print('FAIL -', name, '|', str(detail)[:170])

GESTORIA = 'gestoría'

# --- read ---
out = call('delphi_read', {"path": PAS})
check('read: detecta cp1252+CRLF', 'encoding=cp1252' in out and 'finales=CRLF' in out, out)
check('read: acentos correctos', GESTORIA in out, out)

# --- edit happy path + byte-level verification ---
out = call('delphi_edit', {"path": PAS,
    "old": "  Writeln('%s');" % GESTORIA,
    "new": "  Writeln('%s moderna');" % GESTORIA})
check('edit: escribe', out.startswith('ESCRITO'), out)
nb = open(PAS, 'rb').read()
check('edit: bytes cp1252 intactos', b'gestor\xeda moderna' in nb, nb[:60])
check('edit: sin BOM, CRLF', not nb.startswith(b'\xef') and b'\r\n' in nb[:20])

# --- rejection gates ---
out = call('delphi_edit', {"path": PAS, "old": "begin\n  X := 1;", "new": "x"})
check('gate: ancla multilinea', 'RECHAZADO' in out and 'mas de una linea' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "  Writeln('inventada');", "new": "x"})
check('gate: ancla inexistente', 'RECHAZADO' in out and 'no aparece' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "  X := 1;", "new": "  X := 2;"})
check('gate: ancla repetida lista lineas', 'RECHAZADO' in out and 'veces' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "  X := 1;", "new": "  X := 2;", "atline": 11})
check('edit: atline desempata', out.startswith('ESCRITO'), out)
out = call('delphi_edit', {"path": PAS, "new": "algo"})
check('gate: reescritura total prohibida', 'RECHAZADO' in out and 'NUNCA reescribe' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "procedure Otro;",
                            "new": "procedure Otro; // marca ✔"})
check('gate: caracter fuera de cp1252 con consejo #$', 'RECHAZADO' in out and '#$2714' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "linea con �", "new": "x"})
check('gate: U+FFFD en ancla', 'RECHAZADO' in out and 'U+FFFD' in out, out)
out = call('delphi_edit', {"path": DFM, "old": "a", "new": "b"})
check('gate: designer binario TPF0', 'RECHAZADO' in out and 'TPF0' in out, out)
out = call('delphi_edit', {"path": DFM_FF, "old": "a", "new": "b"})
check('gate: designer binario con envoltorio $FF (formato real del IDE)',
      'RECHAZADO' in out and 'BINARIO' in out, out)
out = call('delphi_edit', {"path": os.path.join(DIR, '__history', 'x.pas'),
                            "old": "a", "new": "b"})
check('gate: __history vetado', 'RECHAZADO' in out and '__history' in out, out)

# --- mojibake warning on new text ---
out = call('delphi_edit', {"path": PAS, "old": "procedure Otro;",
                            "new": "procedure Otro; // gestorÃ³n"})
check('aviso: mojibake en texto nuevo', 'MOJIBAKE' in out, out)
call('delphi_edit', {"path": PAS,
    "old": "procedure Otro; // gestorÃ³n", "new": "procedure Otro;"})

# --- semantic insert ---
code = "procedure Nueva;\nbegin\n  Writeln('nueva');\nend;"
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global", "code": code})
check('insert: rutina-global', 'INSERT rutina-global' in out and 'ESCRITO' in out, out)
txt = open(PAS, 'rb').read().decode('cp1252')
check('insert: colocada antes del end.', txt.rstrip().endswith('end.')
      and 'procedure Nueva;' in txt, txt[-90:])
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global",
                            "code": "procedure Mala;\nbegin\nend"})
check('gate: end sin punto y coma', 'RECHAZADO' in out and 'punto y coma' in out, out)
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global",
                            "code": "x := 1;\nend;"})
check('gate: code sin firma de rutina', 'RECHAZADO' in out and 'firma' in out, out)
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global",
                            "code": "procedure P;\nbegin\nend;\nend."})
check('gate: code con end.', 'RECHAZADO' in out and "end." in out, out)

# --- insert metodo: both halves ---
mcode = "procedure Ping;\nbegin\n  // nada\nend;"
out = call('delphi_edit', {"path": PAS, "insert": "metodo", "code": mcode,
                            "inclass": "TCosa"})
check('insert metodo: clase inexistente rechaza', 'RECHAZADO' in out, out)

CLS = os.path.join(DIR, 'ConClase.pas')
with open(CLS, 'wb') as f:
    f.write(CRLF.join([
        'unit ConClase;', '',
        'interface', '',
        'type',
        '  TCosa = class',
        '  private',
        '    FValor: Integer;',
        '  public',
        '    procedure Existente;',
        '  end;', '',
        'implementation', '',
        'procedure TCosa.Existente;',
        'begin',
        'end;', '',
        'end.', '']).encode('cp1252'))
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "code": mcode,
                            "inclass": "TCosa", "visibility": "public"})
check('insert metodo: DOS mitades', 'DOS mitades' in out and 'Mitad 2' in out, out)
ctx = open(CLS, 'rb').read().decode('cp1252')
check('insert metodo: declaracion en clase',
      '    procedure Ping;' in ctx and ctx.index('procedure Ping;') < ctx.index('implementation'), ctx)
check('insert metodo: implementacion cualificada',
      'procedure TCosa.Ping;' in ctx and ctx.rstrip().endswith('end.'), ctx[-120:])

# --- createunit ---
NU = os.path.join(DIR, 'Naciente.pas')
if os.path.exists(NU):
    os.remove(NU)
out = call('delphi_edit', {"path": NU, "createunit": True})
check('createunit: crea', out.startswith('CREADA'), out)
nb2 = open(NU, 'rb').read()
check('createunit: UTF-8 BOM + CRLF + esqueleto',
      nb2.startswith(b'\xef\xbb\xbf') and b'\r\n' in nb2 and b'unit Naciente;' in nb2,
      nb2[:40])
out = call('delphi_edit', {"path": NU, "createunit": True})
check('createunit: jamas sobreescribe', 'RECHAZADO' in out and 'YA EXISTE' in out, out)

# --- designer lint: known cross-framework property mistakes warn at edit
# time (field, Fase 3: they crash the app at form-load, silently on Android;
# the build only checks the text grammar and packages them without a word) ---
FMX = os.path.join(DIR, 'Lint.fmx')
with open(FMX, 'wb') as f:
    f.write(('object FormMain: TFormMain\r\n'
             "  Caption = 'FormMain'\r\n"
             '  object Lbl: TLabel\r\n'
             '    Position.X = 10.000000000000000000\r\n'
             '  end\r\n'
             'end\r\n').encode('ascii'))
out = call('delphi_edit', {"path": FMX,
    "old": "    Position.X = 10.000000000000000000",
    "new": "    Position.X = 10.000000000000000000\r\n"
           "    Size.X = 100.000000\r\n"
           "    Font.Size = 24.000000\r\n"
           "    TextSettings.HorzAlignment = Center\r\n"
           "    TextSettings.HorzAlign = taCenter"})
check('lint fmx: defectos resueltos contra las tablas GENERADAS del framework',
      'AVISO DESIGNER' in out and 'TControlSize' in out and 'Width' in out
      and 'TextSettings' in out and 'HorzAlign' in out
      and 'Leading' in out and 'CRASHEA' in out, out[-900:])
out = call('delphi_edit', {"path": FMX,
    "old": "    Size.X = 100.000000",
    "new": "    Size.Width = 100.000000000000000000"})
check('lint fmx: cubre el fichero ENTERO (los defectos restantes siguen avisando)',
      'AVISO DESIGNER' in out and 'no existe en TLabel' in out, out[-600:])
FMX2 = os.path.join(DIR, 'Limpio.fmx')
with open(FMX2, 'wb') as f:
    f.write(('object FormMain: TFormMain\r\n'
             "  Caption = 'FormMain'\r\n"
             '  object Btn: TButton\r\n'
             '    Position.X = 20.000000000000000000\r\n'
             "    Text = 'Salir'\r\n"
             '  end\r\n'
             'end\r\n').encode('ascii'))
out = call('delphi_edit', {"path": FMX2,
    "old": "    Text = 'Salir'", "new": "    Text = 'Cerrar'"})
check('lint fmx: un designer LIMPIO no genera aviso',
      'ESCRITO' in out and 'AVISO DESIGNER' not in out, out[-300:])
VDFM = os.path.join(DIR, 'LintV.dfm')
with open(VDFM, 'wb') as f:
    f.write(('object Form1: TForm1\r\n'
             "  Caption = 'Form1'\r\n"
             '  object Boton1: TButton\r\n'
             '    Left = 8\r\n'
             '  end\r\n'
             'end\r\n').encode('ascii'))
out = call('delphi_edit', {"path": VDFM,
    "old": "    Left = 8",
    "new": "    Left = 8\r\n    Position.X = 20.000000\r\n    Align = Client"})
check('lint dfm: FMX-ismos avisados en el sentido inverso',
      'AVISO DESIGNER' in out and 'no existe en TButton' in out
      and 'alClient' in out, out[-600:])

# --- restore: two steps, byte-identical ---
out = call('delphi_edit', {"path": PAS, "restore": True})
check('restore: paso 1 solo avisa', 'NO he hecho nada' in out and 'SE PERDERAN' in out, out)
out = call('delphi_edit', {"path": PAS, "restore": True, "confirm": True})
check('restore: paso 2 ejecuta', out.startswith('RESTAURADO'), out)
check('restore: bytes identicos al original', open(PAS, 'rb').read() == ORIG)

print()
print('== delphi_edit battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
