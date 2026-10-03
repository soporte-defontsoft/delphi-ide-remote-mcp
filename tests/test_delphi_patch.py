"""End-to-end battery for the delphi_edit / delphi_read MCP tools.

Talks real MCP over stdio to the built server and exercises every safety
gate against throwaway fixtures (never against real project code). Verifies
results at BYTE level: encoding preservation is the whole point.

Usage:  python tests/test_delphi_edit.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('patch')
# su propia copia del servidor (antes corria el compilado EN SU SITIO: sus
# logs y su __delphi-temp caian en la carpeta de build), fuera de la jaula
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
DIR = os.path.join(BASE, 'jail')
os.makedirs(DIR)
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

# v0.98: sin jaula declarada = solo lectura. La jaula es SIEMPRE la de la
# bateria: antes un DELPHI_MCP_ROOTS de quien la lanzaba ganaba (setdefault)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': DIR}), nombre='patch-battery')
assert srv.init, 'no initialize response'
call = srv.call

GESTORIA = 'gestoría'

# --- read ---
out = call('delphi_read', {"path": PAS})
check('read: detecta cp1252+CRLF', 'encoding=cp1252' in out and 'eol=CRLF' in out, out)
check('read: acentos correctos', GESTORIA in out, out)

# --- edit happy path + byte-level verification ---
out = call('delphi_edit', {"path": PAS,
    "old": "  Writeln('%s');" % GESTORIA,
    "new": "  Writeln('%s moderna');" % GESTORIA})
check('edit: escribe', mc.abre(out, 'SK_EDIT_ESCRITO_EN_FMT'), out)
nb = open(PAS, 'rb').read()
check('edit: bytes cp1252 intactos', b'gestor\xeda moderna' in nb, nb[:60])
check('edit: sin BOM, CRLF', not nb.startswith(b'\xef') and b'\r\n' in nb[:20])

# --- rejection gates ---
out = call('delphi_edit', {"path": PAS, "old": "begin\n  X := 1;", "new": "x"})
# Se afirma el CONTRATO, no la redaccion: que rechace y que diga por donde SI
# se puede. La negativa antigua mandaba a "una llamada por linea", consejo que
# caduco dos veces -cuando "edits" acepto bloques y cuando llego "toline"- y
# una bateria pegada a sus palabras habria defendido el consejo caducado.
check('gate: ancla multilinea', mc.rechazado(out) and mc.es(out, 'SR_PATCH_ANCHOR_MULTILINE') and 'edits' in out and
      'toline' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "  Writeln('inventada');", "new": "x"})
check('gate: ancla inexistente', mc.rechazado(out) and mc.es(out, 'SR_ANCLA_NO_ESTA_FMT'), out)
out = call('delphi_edit', {"path": PAS, "old": "  X := 1;", "new": "  X := 2;"})
check('gate: ancla repetida lista lineas', mc.rechazado(out) and mc.es(out, 'SR_EDIT_ANCLA_NO_UNICA_FMT'), out)
out = call('delphi_edit', {"path": PAS, "old": "  X := 1;", "new": "  X := 2;", "atline": 11})
check('edit: atline desempata', mc.abre(out, 'SK_EDIT_ESCRITO_EN_FMT'), out)
out = call('delphi_edit', {"path": PAS, "new": "algo"})
check('gate: reescritura total prohibida', mc.rechazado(out) and mc.es(out, 'SR_EDIT_NEW_SIN_ANCLA'), out)
out = call('delphi_edit', {"path": PAS, "old": "procedure Otro;",
                            "new": "procedure Otro; // marca ✔"})
check('gate: caracter fuera de cp1252 con consejo #$', mc.rechazado(out) and mc.es(out, 'SR_EDIT_CARACTERES_NO_CABEN_FMT') and '#$2714' in out, out)
out = call('delphi_edit', {"path": PAS, "old": "linea con �", "new": "x"})
check('gate: U+FFFD en ancla', mc.rechazado(out) and mc.es(out, 'SR_EDIT_TU_ANCLA_LLEVA_CARACTER'), out)
out = call('delphi_edit', {"path": DFM, "old": "a", "new": "b"})
check('gate: designer binario TPF0', mc.rechazado(out) and mc.es(out, 'SR_EDIT_BINARIO_FIRMA_TPF0_ENVOLTORIO_FMT'), out)
out = call('delphi_edit', {"path": DFM_FF, "old": "a", "new": "b"})
check('gate: designer binario con envoltorio $FF (formato real del IDE)',
      mc.rechazado(out) and mc.es(out, 'SR_EDIT_BINARIO_FIRMA_TPF0_ENVOLTORIO_FMT'), out)
out = call('delphi_edit', {"path": os.path.join(DIR, '__history', 'x.pas'),
                            "old": "a", "new": "b"})
check('gate: __history vetado', mc.rechazado(out) and mc.es(out, 'SR_GUARD_DEAD_IDE'), out)

# --- mojibake warning on new text ---
out = call('delphi_edit', {"path": PAS, "old": "procedure Otro;",
                            "new": "procedure Otro; // gestorÃ³n"})
check('aviso: mojibake en texto nuevo', mc.es(out, 'SN_EDIT_FIRMA_MOJIBAKE_NUEVO'), out)
call('delphi_edit', {"path": PAS,
    "old": "procedure Otro; // gestorÃ³n", "new": "procedure Otro;"})

# --- semantic insert ---
code = "procedure Nueva;\nbegin\n  Writeln('nueva');\nend;"
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global", "code": code})
check('insert: rutina-global', 'INSERT rutina-global' in out and mc.es(out, 'SK_EDIT_ESCRITO_EN_FMT'), out)
txt = open(PAS, 'rb').read().decode('cp1252')
check('insert: colocada antes del end.', txt.rstrip().endswith('end.')
      and 'procedure Nueva;' in txt, txt[-90:])
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global",
                            "code": "procedure Mala;\nbegin\nend"})
check('gate: end sin punto y coma', mc.rechazado(out) and mc.es(out, 'SR_EDIT_BLOQUE_TERMINA_END_SIN'), out)
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global",
                            "code": "x := 1;\nend;"})
check('gate: code sin firma de rutina', mc.rechazado(out) and mc.es(out, 'SR_EDIT_BLOQUE_NO_EMPIEZA_FIRMA_FMT'), out)
out = call('delphi_edit', {"path": PAS, "insert": "rutina-global",
                            "code": "procedure P;\nbegin\nend;\nend."})
check('gate: code con end.', mc.rechazado(out) and mc.es(out, 'SR_EDIT_BLOQUE_TRAE_END_SOLO'), out)

# --- insert metodo: both halves ---
mcode = "procedure Ping;\nbegin\n  // nada\nend;"
out = call('delphi_edit', {"path": PAS, "insert": "metodo", "code": mcode,
                            "inclass": "TCosa"})
check('insert metodo: clase inexistente rechaza', mc.rechazado(out) and mc.es(out, 'SR_EDIT_ENCUENTRO_CLASS_FMT'), out)

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
check('insert metodo: DOS mitades', mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT'), out)
ctx = open(CLS, 'rb').read().decode('cp1252')
check('insert metodo: declaracion en clase',
      '    procedure Ping;' in ctx and ctx.index('procedure Ping;') < ctx.index('implementation'), ctx)
check('insert metodo: implementacion cualificada',
      'procedure TCosa.Ping;' in ctx and ctx.rstrip().endswith('end.'), ctx[-120:])
# la firma con su comentario DELANTE en la misma linea se cualifica igual
# (1.10.0: la firma se busca en la vista del codigo; la clase se ponia con
# '^procedure' sobre el texto y se quedaba sin poner)
out = call('delphi_edit', {"path": CLS, "insert": "metodo",
                           "code": "{ la doc } procedure Pong;\nbegin\nend;",
                           "inclass": "TCosa", "visibility": "public"})
ctx = open(CLS, 'rb').read().decode('cp1252')
check('insert metodo: la firma con su comentario delante, cualificada',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and '{ la doc } procedure TCosa.Pong;' in ctx,
      out[:300] + ' | ' + ctx[-200:])

# --- INSERT metodo: la cabecera entera (1.11.2). Se rechazaba con EDIT-070 un
# bloque con atributos delante ([Test], visto en la VM 13.2) o un 'class
# procedure', y la firma se cortaba en su primer ';': 'virtual;' iba a la
# implementacion (E2070) y la declaracion salia sin el, contestando "las dos
# mitades". Medido con dcc (sonda, 3-oct-2026): en la implementacion un
# atributo compila y la RTTI NO lo ve, y la implementacion sin directivas
# compila con todas; lo que corre de verdad lo mide test_delphi_test.
def _impl(t):
    return t[t.index('implementation'):]
def _decl(t):
    return t[:t.index('implementation')]
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa", "visibility": "public",
                           "code": "[Test]\n[TestCase('a', '1,2')]\nprocedure ConAtrib;\nbegin\nend;"})
ctx = open(CLS, 'rb').read().decode('cp1252')
check('INSERT metodo con atributos: DOS mitades, los atributos encima de la DECLARACION',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and
      "    [Test]\r\n    [TestCase('a', '1,2')]\r\n    procedure ConAtrib;\r\n" in _decl(ctx), out[:300] + ' | ' + ctx)
check('INSERT metodo con atributos: la implementacion SIN ellos (alli la RTTI no los ve)',
      'procedure TCosa.ConAtrib;\r\nbegin\r\nend;' in _impl(ctx) and '[Test' not in _impl(ctx), _impl(ctx))
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa", "visibility": "public",
                           "code": "[Test] procedure EnLinea;\nbegin\nend;"})
ctx = open(CLS, 'rb').read().decode('cp1252')
check('INSERT metodo con el atributo en la MISMA linea que la firma: cada uno a su sitio',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and
      '    [Test]\r\n    procedure EnLinea;\r\n' in _decl(ctx) and
      'procedure TCosa.EnLinea;\r\nbegin\r\nend;' in _impl(ctx) and '[Test]' not in _impl(ctx), out[:300] + ' | ' + ctx)
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa", "visibility": "public",
                           "code": "class function Cuenta: Integer;\nbegin\n  Result := 0;\nend;"})
ctx = open(CLS, 'rb').read().decode('cp1252')
check('INSERT metodo: un class function entra (era EDIT-070) y se cualifica detras de function',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and
      '    class function Cuenta: Integer;\r\n' in _decl(ctx) and
      'class function TCosa.Cuenta: Integer;\r\nbegin' in _impl(ctx), out[:300] + ' | ' + ctx)
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa", "visibility": "public",
                           "code": "procedure Virt(A: Integer); virtual; overload;\nbegin\nend;"})
ctx = open(CLS, 'rb').read().decode('cp1252')
check('INSERT metodo con directivas: TODAS en la declaracion',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and
      '    procedure Virt(A: Integer); virtual; overload;\r\n' in _decl(ctx), out[:300] + ' | ' + ctx)
check('INSERT metodo con directivas: la implementacion sin ninguna (con virtual es E2070)',
      'procedure TCosa.Virt(A: Integer);\r\nbegin\r\nend;' in _impl(ctx) and 'virtual' not in _impl(ctx), _impl(ctx))
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa", "visibility": "public",
                           "code": "function Viejo: string;\n  deprecated 'usa Nuevo; o no';\nbegin\n  Result := '';\nend;"})
ctx = open(CLS, 'rb').read().decode('cp1252')
check('INSERT metodo: una directiva en la linea de abajo, con su cadena (y un ; dentro), entera a la declaracion',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and
      "    function Viejo: string; deprecated 'usa Nuevo; o no';\r\n" in _decl(ctx) and
      "function TCosa.Viejo: string;\r\nbegin\r\n  Result := '';\r\nend;" in _impl(ctx) and 'deprecated' not in _impl(ctx),
      out[:300] + ' | ' + ctx)
CAB = os.path.join(DIR, 'ConCabecera.pas')
open(CAB, 'wb').write(CRLF.join(['unit ConCabecera;', '', 'interface', '', 'type', '  TOtra = class',
                                 '  public', '    procedure SoloDecl;', '  end;', '', 'implementation', '',
                                 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": CAB, "insert": "metodo", "inclass": "TOtra",
                           "code": "[Test]\nprocedure SoloDecl; virtual;\nbegin\nend;"})
_src = open(CAB, 'rb').read().decode('ascii')
check('INSERT metodo con la declaracion YA puesta: solo la implementacion, sin directivas, y AVISA de lo que traia para la declaracion',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_SOLO_IMPL_FMT') and mc.es(out, 'SN_EDIT_CABECERA_NO_ANADIDA_FMT') and
      '|[Test] virtual;|' in out and 'line 8' in out and
      'procedure TOtra.SoloDecl;\r\nbegin\r\nend;' in _src and _src.count('procedure SoloDecl;') == 1,
      out[:500] + ' | ' + _src)
GLO = os.path.join(DIR, 'ConGlobal.pas')
open(GLO, 'wb').write(CRLF.join(['unit ConGlobal;', '', 'interface', '', 'implementation', '',
                                 'end.', '']).encode('ascii'))
_g0 = open(GLO, 'rb').read()
out = call('delphi_edit', {"path": GLO, "insert": "rutina-global",
                           "code": "class procedure Suelta;\nbegin\nend;"})
check('INSERT rutina-global de un class procedure: RECHAZADO nombrando insert=metodo, sin escribir',
      mc.rechazado(out) and mc.es(out, 'SR_EDIT_RUTINA_GLOBAL_DE_CLASE_FMT') and 'metodo' in out and
      open(GLO, 'rb').read() == _g0, out[:300])
out = call('delphi_edit', {"path": GLO, "insert": "rutina-global", "visible": True,
                           "code": "procedure Exporta(A: Integer); stdcall;\nbegin\nend;"})
_src = open(GLO, 'rb').read().decode('ascii')
check('INSERT rutina-global visible con stdcall: la directiva en las DOS mitades (sin ella en el interface, E2037)',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_ANTES_FMT') and
      'procedure Exporta(A: Integer); stdcall;\r\n\r\nimplementation' in _src and
      'procedure Exporta(A: Integer); stdcall;\r\nbegin\r\nend;' in _src, out[:400] + ' | ' + _src)
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa",
                           "code": "[Test]\nbegin\nend;"})
check('INSERT: atributos sin firma detras: EDIT-070 nombrando la linea que debia ser la firma',
      mc.rechazado(out) and mc.es(out, 'SR_EDIT_BLOQUE_NO_EMPIEZA_FIRMA_FMT') and '|begin|' in out, out[:300])
out = call('delphi_edit', {"path": CLS, "insert": "metodo", "inclass": "TCosa",
                           "code": "[Test\nprocedure Roto;\nbegin\nend;"})
check('INSERT: un corchete de atributo que no cierra: EDIT-070 nombrando el atributo',
      mc.rechazado(out) and mc.es(out, 'SR_EDIT_BLOQUE_NO_EMPIEZA_FIRMA_FMT') and '|[Test|' in out, out[:300])

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
check('insert metodo con tipo anidado: DOS mitades', 'BOTH halves' in out and 'Half 2' in out, out)
ctx = open(ANI, 'rb').read().decode('cp1252')
check('insert metodo con tipo anidado: la declaracion cae en public, DESPUES del tipo anidado',
      '    procedure Ping;' in ctx and ctx.index('procedure Ping;') > ctx.index('FLista: TDentro;')
      and ctx.index('procedure Ping;') < ctx.index('implementation'), ctx)

# --- createunit ---
NU = os.path.join(DIR, 'Naciente.pas')
if os.path.exists(NU):
    os.remove(NU)
out = call('delphi_edit', {"path": NU, "createunit": True})
check('createunit: crea', mc.abre(out, 'SK_EDIT_CREADA_UNIT_FMT'), out)
nb2 = open(NU, 'rb').read()
check('createunit: UTF-8 BOM + CRLF + esqueleto',
      nb2.startswith(b'\xef\xbb\xbf') and b'\r\n' in nb2 and b'unit Naciente;' in nb2,
      nb2[:40])
out = call('delphi_edit', {"path": NU, "createunit": True})
check('createunit: jamas sobreescribe', mc.rechazado(out) and mc.es(out, 'SR_EDIT_EXISTE_CREATEUNIT_JAMAS_SOBREESCRIBE_FMT'), out)

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
      mc.es(out, 'SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT') and 'TControlSize' in out and 'Width' in out
      and 'TextSettings' in out and 'HorzAlign' in out
      and 'Leading' in out, out[-900:])
out = call('delphi_edit', {"path": FMX,
    "old": "    Size.X = 100.000000",
    "new": "    Size.Width = 100.000000000000000000"})
check('lint fmx: cubre el fichero ENTERO (los defectos restantes siguen avisando)',
      mc.es(out, 'SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT') and 'does not exist in TLabel' in out, out[-600:])
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
      mc.es(out, 'SK_EDIT_ESCRITO_EN_FMT') and not mc.es(out, 'SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT')
      and not mc.es(out, 'SN_DESIGNER_BINDING_LINT_HEADER'), out[-300:])
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
      mc.es(out, 'SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT') and 'does not exist in TButton' in out
      and 'alClient' in out, out[-600:])

# --- la verificacion ensena LA region editada, no otra igual ---------------
# El eco buscaba la primera linea del texto nuevo DESDE ARRIBA, asi que si esa
# linea era de las que se repiten (un "begin", un "var") el agente comprobaba
# su edicion mirando un trozo de fichero que no era el suyo. Medido el
# 2026-09-20: edicion en la linea 19, eco de la 7.
def eco(t):
    """Las lineas numeradas (N|contenido) que el eco relee del disco: se
    sacan por su forma, no partiendo por la frase que las presenta (el dia
    que se tradujo, el split lo devolvia todo y los checks seguian verdes)."""
    return '\n'.join(re.findall(r'^ *\d+\|.*$', t, re.M))


ECO = os.path.join(DIR, 'UEco.pas')
open(ECO, 'wb').write(
    ('unit UEco;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n'
     'procedure Uno;\r\nbegin\r\nend;\r\n\r\n'
     'procedure Dos;\r\nbegin\r\nend;\r\n\r\n'
     'procedure Tres;\r\nbegin\r\nend;\r\n\r\nend.\r\n').encode('ascii'))
out = call('delphi_edit', {"path": ECO, "old": "procedure Tres;",
                           "new": "begin\r\nend;\r\n\r\nprocedure Marcador;\r\nprocedure Tres;"})
_eco = eco(out)
check('eco: la verificacion ensena la region EDITADA, no el primer "begin"',
      'Marcador' in _eco and 'procedure Uno' not in _eco, _eco[:200] or out[:300])
_nums = [int(l.split('|')[0].strip()) for l in _eco.strip().splitlines() if '|' in l]
check('eco: y esas lineas son las de verdad (>= 14, no las de arriba)',
      bool(_nums) and min(_nums) >= 14, _nums)
out = call('delphi_edit', {"path": ECO, "old": "procedure Dos;",
                           "new": "procedure A;\r\nbegin\r\nend;\r\n\r\n"
                                  "procedure B;\r\nbegin\r\nend;\r\n\r\nprocedure Dos;"})
_eco = eco(out)
check('eco: la ventana cubre TODO lo escrito, no solo las dos primeras lineas',
      'procedure A;' in _eco and 'procedure B;' in _eco and 'procedure Dos;' in _eco,
      _eco[:300] or out[:300])

# --- adduses: la unit entra en el uses de la seccion, la clausula la escribe el motor ---
ADDU = os.path.join(DIR, 'ConUses.pas')
open(ADDU, 'wb').write(CRLF.join([
    'unit ConUses;', '', 'interface', '', 'uses', '  System.Classes;', '',
    'type', '  TX = class end;', '', 'implementation', '', '{$R *.res} // uses (en comentario, no cuenta)', '',
    'end.', '']).encode('cp1252'))
out = call('delphi_edit', {"path": ADDU, "adduses": "System.SysUtils; Modules.API"})
check('adduses: implementation sin uses -> se crea', mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and mc.es(out, 'SN_ADDUSES_CREATED_FMT'), out[:300])
_src = open(ADDU, 'rb').read().decode('cp1252')
check('adduses: clausula nueva bajo implementation, con puntos en los nombres',
      'implementation\r\n\r\nuses\r\n  System.SysUtils, Modules.API;\r\n\r\n{$R' in _src, _src)
check('adduses: la de interface no se toca', 'interface\r\n\r\nuses\r\n  System.Classes;\r\n' in _src, _src)
out = call('delphi_edit', {"path": ADDU, "adduses": "UOtra", "section": "implementation"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('adduses: anade al final de la clausula existente', mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and 'Modules.API,\r\n  UOtra;' in _src, out[:300])
_cl = re.search(r'^uses\s.*?;', out, re.M | re.S)  # la clausula releida: su forma, no la frase que la presenta
check('adduses: el eco trae la clausula releida', bool(_cl) and 'UOtra;' in _cl.group(0), out[:300])
out = call('delphi_edit', {"path": ADDU, "adduses": "System.Classes", "section": "interface"})
check('adduses: idempotente (ya estaba)', mc.abre(out, 'SN_ADDUSES_PRESENT_FMT'), out[:200])
out = call('delphi_edit', {"path": ADDU, "adduses": "UInterfaz;System.Classes", "section": "interface"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('adduses: interface con uses -> anade la que falta y dice cual estaba',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and mc.es(out, 'SN_ADDUSES_SOME_PRESENT_FMT') and 'Already there: System.Classes.' in out
      and 'System.Classes,\r\n  UInterfaz;' in _src, out[:300])
_antes = open(ADDU, 'rb').read()
out = call('delphi_edit', {"path": ADDU, "adduses": "System.Classes"})
check('adduses: ya esta en la OTRA seccion -> no la repite (E2004) y lo dice',
      mc.abre(out, 'SN_ADDUSES_PRESENT_OTHER_FMT') and 'interface' in out and open(ADDU, 'rb').read() == _antes, out[:200])
out = call('delphi_edit', {"path": ADDU, "adduses": "2Mal"})
check('adduses: nombre invalido rechazado', mc.rechazado(out) and mc.es(out, 'SR_ADDUSES_BAD_NAME_FMT'), out[:200])
out = call('delphi_edit', {"path": ADDU, "adduses": "X", "section": "initialization"})
check('adduses: seccion invalida rechazada', mc.rechazado(out) and mc.es(out, 'SR_ADDUSES_BAD_SECTION_FMT'), out[:200])
DPRX = os.path.join(DIR, 'Prog.dpr')
open(DPRX, 'wb').write(b'program Prog;\r\nbegin\r\nend.\r\n')
out = call('delphi_edit', {"path": DPRX, "adduses": "X"})
check('adduses: en un .dpr remite a add-unit', mc.rechazado(out) and mc.es(out, 'SR_ADDUSES_NOT_PAS_FMT') and 'add-unit' in out, out[:200])
check('adduses: cp1252 intacto (sin BOM, CRLF)', not open(ADDU, 'rb').read().startswith(b'\xef\xbb\xbf') and b'\n' not in open(ADDU, 'rb').read().replace(b'\r\n', b''))
# --- removeuses: la inversa ---
out = call('delphi_edit', {"path": ADDU, "removeuses": "UOtra"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('removeuses: quita de implementation y la clausula sigue bien cerrada',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'UOtra' not in _src and 'System.SysUtils,\r\n  Modules.API;\r\n' in _src, out[:300])
out = call('delphi_edit', {"path": ADDU, "removeuses": "UOtra"})
check('removeuses: la que no esta -> nada que escribir', mc.abre(out, 'SN_REMOVEUSES_ABSENT_FMT'), out[:200])
out = call('delphi_edit', {"path": ADDU, "removeuses": "System.Classes;UInterfaz;UNoEsta", "section": "interface"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('removeuses: la clausula vacia se va entera y lo dice',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and mc.es(out, 'SN_REMOVEUSES_SOME_ABSENT_FMT') and 'Not there: UNoEsta.' in out
      and mc.es(out, 'SN_REMOVEUSES_GONE_FMT')
      and 'interface\r\n\r\ntype\r\n' in _src and _src.count('\r\nuses\r\n') == 1, _src)
out = call('delphi_edit', {"path": ADDU, "removeuses": "X", "section": "interface"})
check('removeuses: seccion sin uses lo dice', mc.es(out, 'SN_REMOVEUSES_NO_CLAUSE_FMT'), out[:200])
out = call('delphi_edit', {"path": DPRX, "removeuses": "X"})
check('removeuses: en un .dpr remite a remove-unit', mc.rechazado(out) and mc.es(out, 'SR_REMOVEUSES_NOT_PAS_FMT') and 'remove-unit' in out, out[:200])
# un // detras de la coma es de la entrada de ANTES: quitar la ULTIMA no mete el
# ; en el comentario (medido 27-sep: la clausula quedaba sin cerrar), y quitar una
# del medio no baja el comentario a una linea suya
CMT = os.path.join(DIR, 'ConComentario.pas')
open(CMT, 'wb').write(CRLF.join([
    'unit ConComentario;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA,   // la de antes, con su nota', '  UB,', '  UC,   // otra nota', '  UD;', '',
    'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": CMT, "removeuses": "UD"})
_src = open(CMT, 'rb').read().decode('ascii')
check('removeuses: quitar la ULTIMA deja el ; delante del // de la anterior',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and '  UC;   // otra nota\r\n' in _src, _src)
out = call('delphi_edit', {"path": CMT, "removeuses": "UB"})
_src = open(CMT, 'rb').read().decode('ascii')
check('removeuses: quitar una del medio deja el // en SU linea',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  UA,   // la de antes, con su nota\r\n  UC;   // otra nota\r\n' in _src,
      _src)
# el // que va DETRAS del ; final es de la ultima entrada (1.10.0): anadir otra
# detras no se lo lleva (salia 'Lsp.Texts; // PrefijoSinBarra', medido el
# 2-oct-2026), y quitar la suya no lo pega a la que queda (salia
# '// de UA // de UB' en una linea): se queda en una linea suya
FIN = os.path.join(DIR, 'ConColaFinal.pas')
open(FIN, 'wb').write(CRLF.join([
    'unit ConColaFinal;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA,  // de UA', '  UB;  // de UB', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": FIN, "adduses": "UC"})
_src = open(FIN, 'rb').read().decode('ascii')
check('adduses: el // del ; final se queda con SU entrada, la nueva va detras',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and 'uses\r\n  UA,  // de UA\r\n  UB,  // de UB\r\n  UC;\r\n\r\nend.' in _src,
      _src)
out = call('delphi_edit', {"path": FIN, "removeuses": "UC"})
_src = open(FIN, 'rb').read().decode('ascii')
check('removeuses: quitar la nueva devuelve el ; a su sitio, delante del //',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  UA,  // de UA\r\n  UB;  // de UB\r\n\r\nend.' in _src,
      _src)
out = call('delphi_edit', {"path": FIN, "removeuses": "UB"})
_src = open(FIN, 'rb').read().decode('ascii')
check('removeuses: quitar la del // final no se lo pega a la que queda',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  UA;  // de UA\r\n  // de UB\r\n\r\nend.' in _src,
      _src)
# ...y quitar una del MEDIO no mueve el // final de la ultima: su duena se busca
# por el NOMBRE, porque el texto de una entrada lleva delante el // de la de
# antes (medido el 2-oct-2026: el '// de UC' bajaba a una linea suya)
MED = os.path.join(DIR, 'ConColaMedio.pas')
open(MED, 'wb').write(CRLF.join([
    'unit ConColaMedio;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA, // de UA', '  UB, // de UB', '  UC; // de UC', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": MED, "removeuses": "UB"})
_src = open(MED, 'rb').read().decode('ascii')
check('removeuses: quitar una del medio deja el // final con la ultima',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and '  UC; // de UC\r\n' in _src, _src)
# ...y el // de la quitada, que iba detras de SU coma, no se pega a la de
# antes: se queda en una linea suya (se pegaba a la de antes: 'UA, // de UB',
# medido el 2-oct-2026 con remove-unit, el mismo escritor)
check('removeuses: el // de la quitada del medio se queda en una linea suya',
      'uses\r\n  UA, // de UA\r\n  // de UB\r\n  UC; // de UC\r\n' in _src, _src)
# ...y sin comentario en la de antes: ese de arriba pasaba igual con el
# arreglo quitado (el // de UA se colaba primero y tapaba el caso; lo vio la
# mutacion de la 1.10.0)
MED2 = os.path.join(DIR, 'ConColaMedio2.pas')
open(MED2, 'wb').write(CRLF.join([
    'unit ConColaMedio2;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA,', '  UB, // de UB', '  UC;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": MED2, "removeuses": "UB"})
_src = open(MED2, 'rb').read().decode('ascii')
check('removeuses: el // de la quitada no se pega a la de antes sin comentario',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  UA,\r\n  // de UB\r\n  UC;\r\n' in _src, _src)
# ...pero una DIRECTIVA detras del ; no es de ninguna entrada: se queda detras
# del ; de la clausula, como estaba
DIR2 = os.path.join(DIR, 'ConDirectivaFinal.pas')
open(DIR2, 'wb').write(CRLF.join([
    'unit ConDirectivaFinal;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA; {$WARNINGS ON}', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DIR2, "adduses": "UB"})
_src = open(DIR2, 'rb').read().decode('ascii')
check('adduses: una directiva detras del ; final se queda detras del ; nuevo',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and '  UA,\r\n  UB; {$WARNINGS ON}\r\n' in _src, _src)
# la vecina de una entrada envuelta en directiva: la directiva se queda y la
# vecina conserva UNA sangria (medido en vivo: salia con dos)
IFD = os.path.join(DIR, 'ConIfdef.pas')
open(IFD, 'wb').write(CRLF.join([
    'unit ConIfdef;', '', 'interface', '', 'uses', '  System.Classes,', '  {$IFDEF MSWINDOWS}',
    '  Winapi.Windows,', '  {$ENDIF}', '  System.SysUtils;', '', 'implementation', '', 'end.', '']).encode('cp1252'))
out = call('delphi_edit', {"path": IFD, "removeuses": "Winapi.Windows", "section": "interface"})
_src = open(IFD, 'rb').read().decode('cp1252')
check('removeuses: la directiva se queda y la vecina con una sola sangria',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and '  {$IFDEF MSWINDOWS}\r\n  {$ENDIF}\r\n  System.SysUtils;' in _src, _src)
# la directiva de cierre que va DETRAS de la entrada quitada se queda con la de
# apertura (1.10.0, revisor: se iba el {$ENDIF} con DebugU y el {$IFDEF} quedaba
# abierto hasta el final de la unidad)
DIR3 = os.path.join(DIR, 'ConCierreDetras.pas')
open(DIR3, 'wb').write(CRLF.join([
    'unit ConCierreDetras;', '', 'interface', '', 'implementation', '', 'uses',
    '  A', '  {$IFDEF DEBUG}, DebugU{$ENDIF};', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DIR3, "removeuses": "DebugU"})
_src = open(DIR3, 'rb').read().decode('ascii')
check('removeuses: el {$ENDIF} de detras se queda con su {$IFDEF}',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  A\r\n  {$IFDEF DEBUG}\r\n  {$ENDIF};\r\n' in _src, _src)
# quitar la ULTIMA cuando la de antes va envuelta: la coma de la envuelta se
# queda DENTRO del condicional y el ; detras del {$ENDIF} (1.10.0, revisor: el ;
# caia dentro, en 'DebugU;', y sin DEBUG la clausula quedaba en 'A,' sin cerrar)
DIR4 = os.path.join(DIR, 'ConEnvueltaDelante.pas')
open(DIR4, 'wb').write(CRLF.join([
    'unit ConEnvueltaDelante;', '', 'interface', '', 'implementation', '', 'uses',
    '  A,', '  {$IFDEF DEBUG}', '  DebugU,', '  {$ENDIF}', '  C;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DIR4, "removeuses": "C"})
_src = open(DIR4, 'rb').read().decode('ascii')
check('removeuses: quitar la ultima tras una envuelta deja la coma dentro del condicional',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT')
      and 'uses\r\n  A\r\n  {$IFDEF DEBUG}\r\n  , DebugU\r\n  {$ENDIF};\r\n' in _src, _src)

# --- EL lexico (Lsp.Pascal, 1.10.0): cada caso, medido antes con la sonda del
# lexico el 2-oct-2026 contra el exe de entonces ---
# un // dentro de una llave no es un comentario de linea: la coma caia dentro
# de la llave y adduses acababa en SYS-006 'Index out of bounds (1)'
LLA = os.path.join(DIR, 'ConLlaveUrl.pas')
open(LLA, 'wb').write(CRLF.join([
    'unit ConLlaveUrl;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA {ver https://docwiki};', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": LLA, "adduses": "UB"})
_src = open(LLA, 'rb').read().decode('ascii')
check('adduses: un // dentro de una llave no se lleva la coma',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and 'uses\r\n  UA {ver https://docwiki},\r\n  UB;\r\n' in _src,
      out[:200] + ' | ' + _src)
# INSERT: el // de una cadena no corta la firma (EDIT-071 falso)...
FIR = os.path.join(DIR, 'ConFirmaUrl.pas')
open(FIR, 'wb').write(CRLF.join(['unit ConFirmaUrl;', '', 'interface', '', 'implementation', '',
                                 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": FIR, "insert": "rutina-global",
                           "code": "procedure Abre(const U: string = 'http://x');\nbegin\nend;"})
_src = open(FIR, 'rb').read().decode('ascii')
check('insert: una firma con // en una cadena se cierra en su ;',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_ANTES_FMT') and
      "procedure Abre(const U: string = 'http://x');\r\nbegin\r\nend;\r\n\r\nend." in _src, out[:200])
# ...ni un parentesis dentro de un comentario descuadra la cuenta
FIR2 = os.path.join(DIR, 'ConFirmaNota.pas')
open(FIR2, 'wb').write(CRLF.join(['unit ConFirmaNota;', '', 'interface', '', 'implementation', '',
                                  'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": FIR2, "insert": "rutina-global",
                           "code": "procedure Cuenta(N: Integer { (sic });\nbegin\nend;"})
_src = open(FIR2, 'rb').read().decode('ascii')
check('insert: un parentesis dentro de un comentario de la firma no la deja abierta',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_ANTES_FMT') and
      'procedure Cuenta(N: Integer { (sic });\r\nbegin\r\nend;\r\n\r\nend.' in _src, out[:200] + ' | ' + _src)
# un end. comentado no es la frontera (EDIT-049 falso): la rutina va delante
# del de verdad y el comentario se queda como estaba
FIN2 = os.path.join(DIR, 'ConFinComentado.pas')
open(FIN2, 'wb').write(CRLF.join(['unit ConFinComentado;', '', 'interface', '', 'implementation', '',
                                  '{ lo de antes:', 'end.', '}', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": FIN2, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
_src = open(FIN2, 'rb').read().decode('ascii')
check('insert: un end. comentado no es la frontera de la unit',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_ANTES_FMT') and
      '{ lo de antes:\r\nend.\r\n}\r\n\r\nprocedure P;\r\nbegin\r\nend;\r\n\r\nend.\r\n' in _src,
      out[:200] + ' | ' + _src)
# .dpr: un 'uses ...;' dentro de un comentario no es la clausula: la rutina
# caia DENTRO del comentario y la respuesta decia que estaba colocada
DPRU = os.path.join(DIR, 'ConUsesComentado.dpr')
open(DPRU, 'wb').write(CRLF.join(['program ConUsesComentado;', '', '{$APPTYPE CONSOLE}', '', '{',
                                  'uses antiguos: ninguno;', '}', '', 'uses', '  System.SysUtils;', '',
                                  'begin', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DPRU, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
_src = open(DPRU, 'rb').read().decode('ascii')
check('insert en un .dpr: detras del uses de verdad, no dentro del comentado',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_DPR_FMT') and
      '{\r\nuses antiguos: ninguno;\r\n}\r\n' in _src and
      'uses\r\n  System.SysUtils;\r\n\r\nprocedure P;' in _src, out[:200] + ' | ' + _src)

# --- lo que encontro el revisor de codigo de la 1.10.0, cada caso medido
# antes con una sonda contra el exe de entonces ---
# escribir "detras de una linea" es detras de donde ACABA: un comentario que
# se abre en ella se llevaba dentro la rutina del .dpr...
DPRN = os.path.join(DIR, 'ConUsesNota.dpr')
open(DPRN, 'wb').write(CRLF.join(['program ConUsesNota;', '', '{$APPTYPE CONSOLE}', '', 'uses',
                                  '  System.SysUtils; { las units', '  de arriba }', '',
                                  'begin', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DPRN, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
_src = open(DPRN, 'rb').read().decode('ascii')
check('insert en un .dpr: detras del comentario que se abre en la linea del uses, no dentro',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_DPR_FMT') and
      '  System.SysUtils; { las units\r\n  de arriba }\r\n\r\nprocedure P;' in _src, out[:200] + ' | ' + _src)
# ...y el uses que adduses crea debajo de 'interface { la parte'
INTN = os.path.join(DIR, 'ConInterfazNota.pas')
open(INTN, 'wb').write(CRLF.join(['unit ConInterfazNota;', '', 'interface { la parte', '  publica }', '',
                                  'implementation', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": INTN, "adduses": "System.Classes", "section": "interface"})
_src = open(INTN, 'rb').read().decode('ascii')
check('adduses: la clausula nueva va debajo del comentario de la linea de interface, no dentro',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and
      'interface { la parte\r\n  publica }\r\n\r\nuses\r\n  System.Classes;\r\n\r\nimplementation' in _src,
      out[:200] + ' | ' + _src)
# INSERT metodo con un 'end.' dentro de un comentario: la segunda escritura iba
# sin su linea, el ancla salia doble y se deshacian las dos mitades
MFC = os.path.join(DIR, 'ConMetFinComentado.pas')
open(MFC, 'wb').write(CRLF.join(['unit ConMetFinComentado;', '', 'interface', '', 'type',
                                 '  TCosa = class', '  public', '    procedure Uno;', '  end;', '',
                                 'implementation', '', '{', 'end.', '}', '', 'procedure TCosa.Uno;',
                                 'begin', 'end;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": MFC, "insert": "metodo", "inclass": "TCosa",
                           "code": "procedure Dos;\nbegin\nend;"})
_src = open(MFC, 'rb').read().decode('ascii')
check('insert metodo: un end. comentado no deshace las dos mitades',
      mc.abre(out, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and '    procedure Dos;' in _src and
      '{\r\nend.\r\n}\r\n' in _src and 'procedure TCosa.Dos;\r\nbegin\r\nend;\r\n\r\nend.' in _src,
      out[:300] + ' | ' + _src)
# la cola envuelta, leida por EL lector de directivas: la forma
# parentesis-asterisco y un // detras de la directiva dejaban 'UA, ;' sin DEBUG
for _n, _abre, _cierra in (('ConEnvueltaParen', '(*$IFDEF DEBUG*)', '(*$ENDIF*)'),
                           ('ConEnvueltaNota', '{$IFDEF DEBUG} // solo en depuracion', '{$ENDIF}')):
    _p = os.path.join(DIR, _n + '.pas')
    open(_p, 'wb').write(CRLF.join(['unit %s;' % _n, '', 'interface', '', 'implementation', '', 'uses',
                                    '  A,', '  ' + _abre, '  DebugU,', '  ' + _cierra, '  C;', '',
                                    'end.', '']).encode('ascii'))
    out = call('delphi_edit', {"path": _p, "removeuses": "C"})
    _src = open(_p, 'rb').read().decode('ascii')
    check('removeuses: tras una envuelta en %s, la coma dentro del condicional' % _abre,
          mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT')
          and 'uses\r\n  A\r\n  %s\r\n  , DebugU\r\n  %s;\r\n' % (_abre, _cierra) in _src, _src)
# dos comentarios IGUALES detras de dos comas: cada uno con su duena (el
# segundo se daba a la del primero y bajaba a una linea suya)
DUP = os.path.join(DIR, 'ConTodosIguales.pas')
open(DUP, 'wb').write(CRLF.join(['unit ConTodosIguales;', '', 'interface', '', 'implementation', '', 'uses',
                                 '  UA, // TODO', '  UB, // TODO', '  UC;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DUP, "adduses": "UD"})
_src = open(DUP, 'rb').read().decode('ascii')
check('adduses: dos // iguales detras de dos comas, cada uno en su linea',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and
      'uses\r\n  UA, // TODO\r\n  UB, // TODO\r\n  UC,\r\n  UD;\r\n' in _src, _src)
# el aviso de "posible metodo dentro de otro" mira el CODIGO: una firma dentro
# de un comentario, con una asignacion comentada encima, avisaba
AVI = os.path.join(DIR, 'ConAvisoComentado.pas')
open(AVI, 'wb').write(CRLF.join(['unit ConAvisoComentado;', '', 'interface', '', 'implementation', '',
                                 'procedure Haz;', 'var', '  X, Y: Integer;', 'begin', '  X := 0;',
                                 'end;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": AVI, "old": "  X := 0;",
                           "new": "  X := 1;\n  {\n  Y := 2;\nprocedure Vieja;\n  }"})
check('edit: una firma dentro de un comentario no avisa de un metodo partido',
      mc.abre(out, 'SK_EDIT_ESCRITO_EN_FMT') and not mc.es(out, 'SN_EDIT_POSIBLE_INSERCION_METODO_FMT'), out)
out = call('delphi_edit', {"path": AVI, "old": "  X := 1;", "new": "  X := 2;\nprocedure Suelta;"})
check('edit: ...y una de verdad detras de una asignacion SI avisa (control)',
      mc.es(out, 'SN_EDIT_POSIBLE_INSERCION_METODO_FMT'), out[-300:])

# --- restore: two steps, byte-identical ---
out = call('delphi_edit', {"path": PAS, "restore": True})
check('restore: paso 1 solo avisa', mc.es(out, 'SN_EDIT_RESTAURAR_NADA_HECHO_FMT'), out)
out = call('delphi_edit', {"path": PAS, "restore": True, "confirm": True})
check('restore: paso 2 ejecuta', mc.abre(out, 'SK_EDIT_RESTAURADO_DESDE_FMT'), out)
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
      mc.rechazado(out) and mc.es(out, 'SR_PATCH_OCCURRENCE_DUP_FMT'), out[:220])
check('tanda rechazada: el fichero no se toco',
      open(_occ, encoding='utf-8').read().count("Writeln('x')") == 3, '')
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps([
    {'old': "  Writeln('x');", 'new': "  Writeln('B');", 'occurrence': 2},
    {'old': "  Writeln('x');", 'new': "  Writeln('A');", 'occurrence': 1}])})
_t = open(_occ, encoding='utf-8', newline='').read()
check('tanda de abajo arriba (occurrence 2, luego 1): aplicada en su sitio',
      mc.abre(out, 'SN_PATCH_EDITS_OK_FMT') and "Writeln('A');\r\n  Writeln('B');\r\n  Writeln('x');" in _t, out[:900] + ' | ' + _t[-120:])
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps([
    {'old': "  Writeln('A');", 'new': "  Writeln('A');\r\n  Writeln('A2');"},
    {'old': "  Writeln('x');", 'new': "  Writeln('C');", 'occurrence': 1}])})
_t = open(_occ, encoding='utf-8', newline='').read()
check('tanda: una entrada anade lineas y la siguiente occurrence se arrastra bien',
      mc.abre(out, 'SN_PATCH_EDITS_OK_FMT') and "Writeln('A2');\r\n  Writeln('B');\r\n  Writeln('C');" in _t, out[:900] + ' | ' + _t[-140:])

# 2026-09-25 (hermes): a client that sends "edits" as a REAL JSON array (the
# description says "array", the schema says string) got '' from the vendor
# serializer and the batch was silently ignored; one that encodes it twice
# got "no es array" with nothing about what arrived. Both work now, and
# garbage is refused naming its length and start.
out = call('delphi_edit', {'path': _occ, 'edits': [
    {'old': "  Writeln('C');", 'new': "  Writeln('D');"}]})
_t = open(_occ, encoding='utf-8').read()
check('tanda: "edits" como ARRAY JSON real (no cadena) se aplica',
      mc.abre(out, 'SN_PATCH_EDITS_OK_FMT') and "Writeln('D');" in _t, out[:200])
out = call('delphi_edit', {'path': _occ, 'edits': json.dumps(json.dumps([
    {'old': "  Writeln('D');", 'new': "  Writeln('E');"}]))})
_t = open(_occ, encoding='utf-8').read()
check('tanda: "edits" codificado dos veces (cadena JSON dentro de cadena) se desenvuelve',
      mc.abre(out, 'SN_PATCH_EDITS_OK_FMT') and "Writeln('E');" in _t, out[:200])
out = call('delphi_edit', {'path': _occ, 'edits': '{"old": "x", "new": "y"}'})
check('tanda: "edits" que no es array -> RECHAZADO diciendo cuantos caracteres llegaron y como empieza',
      mc.rechazado(out) and mc.es(out, 'SR_PATCH_EDITS_JSON_FMT') and '24 characters arrived' in out and '{"old": "x"' in out, out[:300])

srv.cierra()
mc.fin('delphi_edit battery')
