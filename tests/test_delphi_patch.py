"""End-to-end battery for the delphi_edit / delphi_read MCP tools.

Talks real MCP over stdio to the built server and exercises every safety
gate against throwaway fixtures (never against real project code). Verifies
results at BYTE level: encoding preservation is the whole point.

Usage:  python tests/test_delphi_edit.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, subprocess, threading, queue, time, os, sys, tempfile

EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), '..', 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

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

_env = dict(os.environ)
_env.setdefault('DELPHI_MCP_ROOTS', DIR)  # v0.98: sin jaula declarada = solo lectura
proc = subprocess.Popen([EXE], env=_env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
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
# Se afirma el CONTRATO, no la redaccion: que rechace y que diga por donde SI
# se puede. La negativa antigua mandaba a "una llamada por linea", consejo que
# caduco dos veces -cuando "edits" acepto bloques y cuando llego "toline"- y
# una bateria pegada a sus palabras habria defendido el consejo caducado.
check('gate: ancla multilinea', 'RECHAZADO' in out and 'edits' in out and
      'toline' in out, out)
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

# --- insert metodo con un TIPO ANIDADO en la clase (medido 2026-09-22 en
# Lsp.Client: el primer 'end;' era el del tipo anidado y la declaracion caia
# DENTRO de el, y la seccion 'public' pedida "no existia") ---
ANI = os.path.join(DIR, 'ConAnidado.pas')
with open(ANI, 'wb') as f:
    f.write(CRLF.join([
        'unit ConAnidado;', '',
        'interface', '',
        'type',
        '  TFuera = class',
        '  private type',
        '    TDentro = class',
        '      Valor: Integer;',
        '      constructor Create;',
        '    end;',
        '  private',
        '    FLista: TDentro;',
        '  public',
        '    procedure Existente;',
        '  end;', '',
        'implementation', '',
        'constructor TFuera.TDentro.Create;',
        'begin',
        'end;', '',
        'procedure TFuera.Existente;',
        'begin',
        'end;', '',
        'end.', '']).encode('cp1252'))
out = call('delphi_edit', {"path": ANI, "insert": "metodo", "code": mcode,
                            "inclass": "TFuera", "visibility": "public"})
check('insert metodo con tipo anidado: DOS mitades', 'DOS mitades' in out and 'Mitad 2' in out, out)
ctx = open(ANI, 'rb').read().decode('cp1252')
check('insert metodo con tipo anidado: la declaracion cae en public, DESPUES del tipo anidado',
      '    procedure Ping;' in ctx and ctx.index('procedure Ping;') > ctx.index('FLista: TDentro;')
      and ctx.index('procedure Ping;') < ctx.index('implementation'), ctx)

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

# --- la verificacion ensena LA region editada, no otra igual ---------------
# El eco buscaba la primera linea del texto nuevo DESDE ARRIBA, asi que si esa
# linea era de las que se repiten (un "begin", un "var") el agente comprobaba
# su edicion mirando un trozo de fichero que no era el suyo. Medido el
# 2026-09-20: edicion en la linea 19, eco de la 7.
ECO = os.path.join(DIR, 'UEco.pas')
open(ECO, 'wb').write(
    ('unit UEco;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n'
     'procedure Uno;\r\nbegin\r\nend;\r\n\r\n'
     'procedure Dos;\r\nbegin\r\nend;\r\n\r\n'
     'procedure Tres;\r\nbegin\r\nend;\r\n\r\nend.\r\n').encode('ascii'))
out = call('delphi_edit', {"path": ECO, "old": "procedure Tres;",
                           "new": "begin\r\nend;\r\n\r\nprocedure Marcador;\r\nprocedure Tres;"})
_eco = out.split('lineas resultantes leidas del disco:')[-1]
check('eco: la verificacion ensena la region EDITADA, no el primer "begin"',
      'Marcador' in _eco and 'procedure Uno' not in _eco, _eco[:200])
_nums = [int(l.split('|')[0].strip()) for l in _eco.strip().splitlines() if '|' in l]
check('eco: y esas lineas son las de verdad (>= 14, no las de arriba)',
      bool(_nums) and min(_nums) >= 14, _nums)
out = call('delphi_edit', {"path": ECO, "old": "procedure Dos;",
                           "new": "procedure A;\r\nbegin\r\nend;\r\n\r\n"
                                  "procedure B;\r\nbegin\r\nend;\r\n\r\nprocedure Dos;"})
_eco = out.split('lineas resultantes leidas del disco:')[-1]
check('eco: la ventana cubre TODO lo escrito, no solo las dos primeras lineas',
      'procedure A;' in _eco and 'procedure B;' in _eco and 'procedure Dos;' in _eco,
      _eco[:300])

# --- adduses: la unit entra en el uses de la seccion, la clausula la escribe el motor ---
ADDU = os.path.join(DIR, 'ConUses.pas')
open(ADDU, 'wb').write(CRLF.join([
    'unit ConUses;', '', 'interface', '', 'uses', '  System.Classes;', '',
    'type', '  TX = class end;', '', 'implementation', '', '{$R *.res} // uses (en comentario, no cuenta)', '',
    'end.', '']).encode('cp1252'))
out = call('delphi_edit', {"path": ADDU, "adduses": "System.SysUtils; Modules.API"})
check('adduses: implementation sin uses -> se crea', out.startswith('ANADIDAS') and 'creada' in out, out[:300])
_src = open(ADDU, 'rb').read().decode('cp1252')
check('adduses: clausula nueva bajo implementation, con puntos en los nombres',
      'implementation\r\n\r\nuses\r\n  System.SysUtils, Modules.API;\r\n\r\n{$R' in _src, _src)
check('adduses: la de interface no se toca', 'interface\r\n\r\nuses\r\n  System.Classes;\r\n' in _src, _src)
out = call('delphi_edit', {"path": ADDU, "adduses": "UOtra", "section": "implementation"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('adduses: anade al final de la clausula existente', out.startswith('ANADIDAS') and 'Modules.API,\r\n  UOtra;' in _src, out[:300])
check('adduses: el eco trae la clausula releida', 'UOtra;' in out.split('releida del disco')[-1], out[:300])
out = call('delphi_edit', {"path": ADDU, "adduses": "System.Classes", "section": "interface"})
check('adduses: idempotente (ya estaba)', out.startswith('Ya estaba'), out[:200])
out = call('delphi_edit', {"path": ADDU, "adduses": "UInterfaz;System.Classes", "section": "interface"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('adduses: interface con uses -> anade la que falta y dice cual estaba',
      out.startswith('ANADIDAS') and 'Ya estaban: System.Classes' in out and 'System.Classes,\r\n  UInterfaz;' in _src, out[:300])
_antes = open(ADDU, 'rb').read()
out = call('delphi_edit', {"path": ADDU, "adduses": "System.Classes"})
check('adduses: ya esta en la OTRA seccion -> no la repite (E2004) y lo dice',
      out.startswith('Nada que escribir') and 'interface' in out and open(ADDU, 'rb').read() == _antes, out[:200])
out = call('delphi_edit', {"path": ADDU, "adduses": "2Mal"})
check('adduses: nombre invalido rechazado', out.startswith('RECHAZADO'), out[:200])
out = call('delphi_edit', {"path": ADDU, "adduses": "X", "section": "initialization"})
check('adduses: seccion invalida rechazada', out.startswith('RECHAZADO'), out[:200])
DPRX = os.path.join(DIR, 'Prog.dpr')
open(DPRX, 'wb').write(b'program Prog;\r\nbegin\r\nend.\r\n')
out = call('delphi_edit', {"path": DPRX, "adduses": "X"})
check('adduses: en un .dpr remite a add-unit', out.startswith('RECHAZADO') and 'add-unit' in out, out[:200])
check('adduses: cp1252 intacto (sin BOM, CRLF)', not open(ADDU, 'rb').read().startswith(b'\xef\xbb\xbf') and b'\n' not in open(ADDU, 'rb').read().replace(b'\r\n', b''))
# --- removeuses: la inversa ---
out = call('delphi_edit', {"path": ADDU, "removeuses": "UOtra"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('removeuses: quita de implementation y la clausula sigue bien cerrada',
      out.startswith('QUITADAS') and 'UOtra' not in _src and 'System.SysUtils,\r\n  Modules.API;\r\n' in _src, out[:300])
out = call('delphi_edit', {"path": ADDU, "removeuses": "UOtra"})
check('removeuses: la que no esta -> nada que escribir', out.startswith('No estaba'), out[:200])
out = call('delphi_edit', {"path": ADDU, "removeuses": "System.Classes;UInterfaz;UNoEsta", "section": "interface"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('removeuses: la clausula vacia se va entera y lo dice',
      out.startswith('QUITADAS') and 'No estaban: UNoEsta' in out and 'se ha quitado entera' in out
      and 'interface\r\n\r\ntype\r\n' in _src and _src.count('\r\nuses\r\n') == 1, _src)
out = call('delphi_edit', {"path": ADDU, "removeuses": "X", "section": "interface"})
check('removeuses: seccion sin uses lo dice', 'no tiene uses' in out, out[:200])
out = call('delphi_edit', {"path": DPRX, "removeuses": "X"})
check('removeuses: en un .dpr remite a remove-unit', out.startswith('RECHAZADO') and 'remove-unit' in out, out[:200])
# la vecina de una entrada envuelta en directiva: la directiva se queda y la
# vecina conserva UNA sangria (medido en vivo: salia con dos)
IFD = os.path.join(DIR, 'ConIfdef.pas')
open(IFD, 'wb').write(CRLF.join([
    'unit ConIfdef;', '', 'interface', '', 'uses', '  System.Classes,', '  {$IFDEF MSWINDOWS}',
    '  Winapi.Windows,', '  {$ENDIF}', '  System.SysUtils;', '', 'implementation', '', 'end.', '']).encode('cp1252'))
out = call('delphi_edit', {"path": IFD, "removeuses": "Winapi.Windows", "section": "interface"})
_src = open(IFD, 'rb').read().decode('cp1252')
check('removeuses: la directiva se queda y la vecina con una sola sangria',
      out.startswith('QUITADAS') and '  {$IFDEF MSWINDOWS}\r\n  {$ENDIF}\r\n  System.SysUtils;' in _src, _src)

# --- restore: two steps, byte-identical ---
out = call('delphi_edit', {"path": PAS, "restore": True})
check('restore: paso 1 solo avisa', 'NO he hecho nada' in out and 'SE PERDERAN' in out, out)
out = call('delphi_edit', {"path": PAS, "restore": True, "confirm": True})
check('restore: paso 2 ejecuta', out.startswith('RESTAURADO'), out)
check('restore: bytes identicos al original', open(PAS, 'rb').read() == ORIG)

print()
# ---- occurrence inside a batch counts on the file BEFORE the batch: two
# entries resolving to the same line are refused at the gate (2026-09-24,
# found using the server as an agent: "occurrence 1" twice, expecting the
# second to be the next one, died mid-batch with a message that explained
# nothing). Bottom-up numbering (2 then 1) and top-down (1 then 2) both work.
_occ = os.path.join(DIR, 'UOcc.pas')
open(_occ, 'w', encoding='utf-8', newline='').write(  # newline='': el texto ya lleva CRLF, sin traducir
    "unit UOcc;\r\n\r\ninterface\r\n\r\nprocedure Hazlo;\r\n\r\nimplementation\r\n\r\n"
    "procedure Hazlo;\r\nbegin\r\n  Writeln('x');\r\n  Writeln('x');\r\n  Writeln('x');\r\nend;\r\n\r\nend.\r\n")
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps([
    {'old': "  Writeln('x');", 'new': "  Writeln('A');", 'occurrence': 1},
    {'old': "  Writeln('x');", 'new': "  Writeln('B');", 'occurrence': 1}])})
check('tanda: dos entradas a la MISMA linea (occurrence 1 y 1) -> RECHAZADO en la puerta',
      'RECHAZADO' in out and 'MISMA linea' in out and 'ANTES de la tanda' in out, out[:220])
check('tanda rechazada: el fichero no se toco',
      open(_occ, encoding='utf-8').read().count("Writeln('x')") == 3, '')
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps([
    {'old': "  Writeln('x');", 'new': "  Writeln('B');", 'occurrence': 2},
    {'old': "  Writeln('x');", 'new': "  Writeln('A');", 'occurrence': 1}])})
_t = open(_occ, encoding='utf-8', newline='').read()
check('tanda de abajo arriba (occurrence 2, luego 1): aplicada en su sitio',
      out.startswith('APLICADAS') and "Writeln('A');\r\n  Writeln('B');\r\n  Writeln('x');" in _t, out[:900] + ' | ' + _t[-120:])
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps([
    {'old': "  Writeln('A');", 'new': "  Writeln('A');\r\n  Writeln('A2');"},
    {'old': "  Writeln('x');", 'new': "  Writeln('C');", 'occurrence': 1}])})
_t = open(_occ, encoding='utf-8', newline='').read()
check('tanda: una entrada anade lineas y la siguiente occurrence se arrastra bien',
      out.startswith('APLICADAS') and "Writeln('A2');\r\n  Writeln('B');\r\n  Writeln('C');" in _t, out[:900] + ' | ' + _t[-140:])

# 2026-09-25 (hermes): a client that sends "edits" as a REAL JSON array (the
# description says "array", the schema says string) got '' from the vendor
# serializer and the batch was silently ignored; one that encodes it twice
# got "no es array" with nothing about what arrived. Both work now, and
# garbage is refused naming its length and start.
out = call('delphi_edit', {'path': _occ, 'edits': [
    {'old': "  Writeln('C');", 'new': "  Writeln('D');"}]})
_t = open(_occ, encoding='utf-8').read()
check('tanda: "edits" como ARRAY JSON real (no cadena) se aplica',
      out.startswith('APLICADAS') and "Writeln('D');" in _t, out[:200])
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps(json.dumps([
    {'old': "  Writeln('D');", 'new': "  Writeln('E');"}]))})
_t = open(_occ, encoding='utf-8').read()
check('tanda: "edits" codificado dos veces (cadena JSON dentro de cadena) se desenvuelve',
      out.startswith('APLICADAS') and "Writeln('E');" in _t, out[:200])
out = call('delphi_edit', {'path': _occ, 'edits': '{"old": "x", "new": "y"}'})
check('tanda: "edits" que no es array -> RECHAZADO diciendo cuantos caracteres llegaron y como empieza',
      out.startswith('RECHAZADO') and 'Han llegado 24 caracteres' in out and '{"old": "x"' in out, out[:300])

print('== delphi_edit battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
