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

# --- mojibake en el texto nuevo ---
# (en un CP1252 con otros acentos el fichero se sigue leyendo como CP1252 -
# como lo leen el IDE y dcc -: se escribe, y se avisa)
out = call('delphi_edit', {"path": PAS, "old": "procedure Otro;",
                            "new": "procedure Otro; // gestorÃ³n"})
check('aviso: mojibake en texto nuevo', mc.es(out, 'SN_EDIT_FIRMA_MOJIBAKE_NUEVO'), out)
call('delphi_edit', {"path": PAS,
    "old": "procedure Otro; // gestorÃ³n", "new": "procedure Otro;"})
# ...y en un UTF-8 tambien
U8N = os.path.join(DIR, 'MojiNuevo.pas')
open(U8N, 'wb').write("unit MojiNuevo;\r\n\r\ninterface\r\n\r\nconst\r\n  A = 'Ca\u00f1a';\r\n\r\n"
                      "implementation\r\n\r\nend.\r\n".encode('utf-8'))
out = call('delphi_edit', {"path": U8N, "old": "  A = 'Ca\u00f1a';", "new": "  A = 'gestor\u00c3\u00b3n';"})
check('aviso: mojibake en texto nuevo (en un UTF-8, que se sigue leyendo igual)',
      mc.es(out, 'SN_EDIT_FIRMA_MOJIBAKE_NUEVO'), out)
# ...y el de una lectura Latin-1 (la E acentuada mayuscula leida asi es
# U+00C3 U+0089): con el byte CP1252 del codificador solo, dejo de verse
# (revisor propio, 9-oct-2026). En un fichero UTF-8: en uno CP1252 un U+0089
# ni siquiera se escribe
U8M = os.path.join(DIR, 'MojiU8.pas')
open(U8M, 'wb').write("unit MojiU8;\r\n\r\ninterface\r\n\r\nconst\r\n  A = 'Ca\u00f1a';\r\n\r\n"
                      "implementation\r\n\r\nend.\r\n".encode('utf-8'))
out = call('delphi_edit', {"path": U8M, "old": "  A = 'Ca\u00f1a';", "new": "  A = 'CAF\u00c3\u0089';"})
check('aviso: mojibake de una lectura Latin-1 (U+00C3 U+0089 por la E acentuada mayuscula)',
      mc.es(out, 'SN_EDIT_FIRMA_MOJIBAKE_NUEVO'), out)

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
# Las tablas del disenador, listas ANTES: una edicion no las espera (lo
# escribe y dice DSGN-052, sin validar) y estos checks miden los avisos de la
# validacion. Solo pasaban si otra bateria habia dejado la cache caliente: al
# subir GENERACION_TABLAS (4-oct-2026) los tres de abajo salieron rojos
for _fw, _r in mc.espera_tablas(call):
    # (un INTERNAL -DSGN-050/053/054, el fallo recordado del generador- o un
    # timeout tampoco es "lista": mc.fallo los cuenta, rechazado no)
    check('tablas del disenador listas antes del lint (%s)' % _fw,
          not mc.tiene(_r, 'DSGN-051') and not mc.fallo(_r), _r[:300])
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
      mc.es(out, 'SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT') and '"HorzAlignment" does not exist' in out, out[-600:])
# (Font.Size en un TLabel de FMX ya no avisa: FMX lo sigue cargando por
# TTextPropLoader, un DefineProperties que la tabla generada conoce; lo que
# prueba el fichero ENTERO es el aviso de la linea 7, que esta edicion no toca)
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
      and not mc.es(out, 'SN_DESIGNER_BINDING_LINT_HEADER')
      # y SI se valido: sin tabla la edicion dice DSGN-052 y tampoco avisa
      and not mc.tiene(out, 'DSGN-052'), out[-300:])
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
# la clausula que escribio el motor es COMPACTA (dos en una linea): se respeta
# su forma (3.13 de la 1.18.0; antes se rehacia una por linea)
check('adduses: anade al final de la clausula existente', mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and 'System.SysUtils, Modules.API, UOtra;' in _src, out[:300])
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
# en un .dpr, unidades de BIBLIOTECA (11.6, David 10-oct-2026: el muro de
# SondaOrdenFmx - FMX.Edit al uses de un .dpr no tenia tool)
out = call('delphi_edit', {"path": DPRX, "adduses": "System.SysUtils"})
_src = open(DPRX, 'rb').read().decode('ascii')
check('adduses en un .dpr sin uses: lo estrena tras la cabecera',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and mc.es(out, 'SN_ADDUSES_CREADA_PROGRAMA') and
      _src == 'program Prog;\r\n\r\nuses\r\n  System.SysUtils;\r\nbegin\r\nend.\r\n', out[:300] + ' | ' + _src)
out = call('delphi_edit', {"path": DPRX, "adduses": "System.Classes;System.SysUtils"})
_src = open(DPRX, 'rb').read().decode('ascii')
check('adduses en un .dpr con uses: entra la que falta y dice la que ya estaba',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and mc.es(out, 'SN_ADDUSES_SOME_PRESENT_FMT') and
      'uses\r\n  System.SysUtils,\r\n  System.Classes;\r\n' in _src, out[:300] + ' | ' + _src)
open(os.path.join(DIR, 'UDelProg.pas'), 'wb').write(b'unit UDelProg;\r\ninterface\r\nimplementation\r\nend.\r\n')
_antes = open(DPRX, 'rb').read()
out = call('delphi_edit', {"path": DPRX, "adduses": "UDelProg"})
check('adduses en un .dpr: una unidad DEL PROYECTO (su .pas al lado) remite a add-unit y no escribe',
      mc.rechazado(out) and mc.es(out, 'SR_ADDUSES_UNIDAD_DEL_PROYECTO_FMT') and 'add-unit' in out
      and open(DPRX, 'rb').read() == _antes, out[:300])
DPKX = os.path.join(DIR, 'Paq.dpk')
open(DPKX, 'wb').write(b'package Paq;\r\nrequires\r\n  rtl;\r\nend.\r\n')
out = call('delphi_edit', {"path": DPKX, "adduses": "System.SysUtils"})
check('adduses en un .dpk: remite a add-unit / add-requires', mc.rechazado(out) and mc.es(out, 'SR_ADDUSES_NOT_PAS_FMT')
      and 'add-requires' in out, out[:200])
check('adduses: cp1252 intacto (sin BOM, CRLF)', not open(ADDU, 'rb').read().startswith(b'\xef\xbb\xbf') and b'\n' not in open(ADDU, 'rb').read().replace(b'\r\n', b''))
# --- una clausula COMPACTA se edita en su sitio (3.13 de la 1.18.0): adduses y
# removeuses la rehacian una por linea, un diff de cuarenta lineas por una unit
# (medido el 9-oct-2026 en UTrayMain) ---
COMP = os.path.join(DIR, 'Compacta.pas')
open(COMP, 'wb').write(CRLF.join([
    'unit Compacta;', '', 'interface', '', 'uses',
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,',
    '  System.StrUtils, System.JSON,', '  Vcl.Forms, Vcl.Dialogs;', '',
    'implementation', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": COMP, "removeuses": "System.Classes;Vcl.Forms", "section": "interface"})
_src = open(COMP, 'rb').read().decode('ascii')
check('removeuses en una clausula compacta: sale solo lo suyo, el resto en su sitio',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and
      'uses\r\n  Winapi.Windows, Winapi.Messages, System.SysUtils,\r\n  System.StrUtils, System.JSON,\r\n'
      '  Vcl.Dialogs;\r\n' in _src, _src)
out = call('delphi_edit', {"path": COMP, "adduses": "System.IOUtils", "section": "interface"})
_src = open(COMP, 'rb').read().decode('ascii')
check('adduses en una clausula compacta: entra detras de la ultima, en su linea',
      mc.abre(out, 'SN_ADDUSES_ADDED_FMT') and '\r\n  Vcl.Dialogs, System.IOUtils;\r\n' in _src, _src)
out = call('delphi_edit', {"path": COMP, "adduses": "Una.Unidad.Con.Un.Nombre.Muy.Largo.Para.Pasar.De.Ochenta",
                           "section": "interface"})
_src = open(COMP, 'rb').read().decode('ascii')
check('...y la que no cabe en 80 columnas, en una linea nueva con su sangria',
      'Vcl.Dialogs, System.IOUtils,\r\n  Una.Unidad.Con.Un.Nombre.Muy.Largo.Para.Pasar.De.Ochenta;\r\n' in _src, _src)
out = call('delphi_edit', {"path": COMP, "removeuses": "System.StrUtils;System.JSON", "section": "interface"})
_src = open(COMP, 'rb').read().decode('ascii')
check('removeuses: la linea que se queda vacia se va con ellas',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and
      'System.SysUtils,\r\n  Vcl.Dialogs, System.IOUtils,\r\n' in _src, _src)
# --- removeuses: la inversa ---
out = call('delphi_edit', {"path": ADDU, "removeuses": "UOtra"})
_src = open(ADDU, 'rb').read().decode('cp1252')
check('removeuses: quita de implementation y la clausula sigue bien cerrada',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'UOtra' not in _src and 'System.SysUtils, Modules.API;\r\n' in _src, out[:300])
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
check('removeuses: quitar la del // final se lo lleva (11.3) y no lo pega a la que queda',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  UA;  // de UA\r\n\r\nend.' in _src
      and '// de UB' not in _src, _src)
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
# ...y el // de la quitada, que iba detras de SU coma, se va con ella (11.3,
# David 10-oct-2026); antes se quedaba en una linea suya, huerfano dentro del
# uses, y antes aun se pegaba a la de antes ('UA, // de UB', 2-oct-2026)
check('removeuses: el // de la quitada del medio se va con ella (11.3)',
      'uses\r\n  UA, // de UA\r\n  UC; // de UC\r\n' in _src and '// de UB' not in _src, _src)
# ...y sin comentario en la de antes: ese de arriba pasaba igual con el
# arreglo quitado (el // de UA se colaba primero y tapaba el caso; lo vio la
# mutacion de la 1.10.0)
MED2 = os.path.join(DIR, 'ConColaMedio2.pas')
open(MED2, 'wb').write(CRLF.join([
    'unit ConColaMedio2;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA,', '  UB, // de UB', '  UC;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": MED2, "removeuses": "UB"})
_src = open(MED2, 'rb').read().decode('ascii')
check('removeuses: el // de la quitada se va con ella tambien sin comentario en la de antes (11.3)',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and 'uses\r\n  UA,\r\n  UC;\r\n' in _src
      and '// de UB' not in _src, _src)
# (guarda) el de una linea PROPIA encima de la quitada se queda: no es de su linea
PROP = os.path.join(DIR, 'ConNotaPropia.pas')
open(PROP, 'wb').write(CRLF.join([
    'unit ConNotaPropia;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA,', '  // nota propia', '  UB,', '  UC;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": PROP, "removeuses": "UB"})
_src = open(PROP, 'rb').read().decode('ascii')
check('removeuses: (guarda) el // de una linea propia encima de la quitada se queda',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and '// nota propia' in _src and 'UB' not in _src, _src)
# y con las dos cosas en la quitada: su nota de linea propia (que viaja pegada a la
# siguiente, EntriesWithout) se queda y el // de su linea se va
DOS = os.path.join(DIR, 'ConDosNotas.pas')
open(DOS, 'wb').write(CRLF.join([
    'unit ConDosNotas;', '', 'interface', '', 'implementation', '', 'uses',
    '  UA,', '  // nota propia', '  UB, // de UB', '  UC;', '', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DOS, "removeuses": "UB"})
_src = open(DOS, 'rb').read().decode('ascii')
check('removeuses: la nota de linea propia de la quitada se queda y el // de su linea se va (11.3)',
      mc.abre(out, 'SN_REMOVEUSES_REMOVED_FMT') and '// nota propia' in _src and 'UC;' in _src
      and '// de UB' not in _src and 'UB,' not in _src, _src)
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
# .dpr SIN uses y con la cabecera partida en dos lineas: EL lector de la cabecera
# (Lsp.Pascal.CabeceraDeFuente) la encuentra; la regla de antes la queria en una
# sola linea acabada en ';' y negaba (inventario del 10-oct-2026)
DPRC = os.path.join(DIR, 'CabeceraPartida.dpr')
open(DPRC, 'wb').write(CRLF.join(['program', '  CabeceraPartida;', '', '{$APPTYPE CONSOLE}', '',
                                  'begin', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": DPRC, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
_src = open(DPRC, 'rb').read().decode('ascii')
check('insert en un .dpr sin uses y con la cabecera en dos lineas: detras de la cabecera',
      mc.abre(out, 'SK_EDIT_INSERT_RUTINA_DPR_FMT') and
      _src.index('  CabeceraPartida;') < _src.index('procedure P;') < _src.index('begin\r\nend.'),
      out[:200] + ' | ' + _src)
# y el de UNA linea ('program P; begin end.') se sigue negando: detras de la
# linea de la cabecera la rutina caeria tras el end. (revision del diff propio)
DPRL = os.path.join(DIR, 'UnaLinea.dpr')
open(DPRL, 'wb').write(b'program UnaLinea; begin end.\r\n')
out = call('delphi_edit', {"path": DPRL, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
check('insert en un .dpr de una sola linea: se niega y no escribe',
      mc.abre(out, 'SR_EDIT_ENCUENTRO_FINAL_CABECERA_USES') and
      open(DPRL, 'rb').read() == b'program UnaLinea; begin end.\r\n', out[:200])
# --- EL end. (Lsp.Pascal.EndsConPunto), como lo lee dcc: la palabra, blancos
# (tambien saltos) y el punto. Contado "solo en su linea", una edicion que dejaba
# 'begin end.' en una linea - y compila - salia con EDIT-085 BROKEN STRUCTURE y la
# orden de deshacer (sonda en vivo del 10-oct-2026)
DPRE = os.path.join(DIR, 'EndJunto.dpr')
open(DPRE, 'wb').write(b'program EndJunto;\r\n\r\nbegin\r\nend.\r\n')
out = call('delphi_edit', {"path": DPRE, "old": "end.", "new": "Writeln('x'); end."})
check('end.: una sentencia delante del end. en su linea no es BROKEN STRUCTURE',
      not mc.rechazado(out) and not mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_END_FMT') and
      not mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_ULTIMA') and
      open(DPRE, 'rb').read() == b"program EndJunto;\r\n\r\nbegin\r\nWriteln('x'); end.\r\n", out[:300])
# y una tanda de BLOQUE que se lleva el end. avisa: el bloque no preguntaba por la
# estructura y la tanda solo la juzgaba si una entrada de una linea habia avisado
DPRB = os.path.join(DIR, 'EndBloque.dpr')
open(DPRB, 'wb').write(b'program EndBloque;\r\n\r\nbegin\r\nend.\r\n')
out = call('delphi_edit', {"path": DPRB, "edits": [{"old": "begin\nend.", "new": "begin"}]})
check('end.: una tanda de bloque que quita el end. avisa de BROKEN STRUCTURE',
      mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_END_FMT'), out[:300])
# la frontera del insert en una unit: un 'end' con su '.' en la linea de abajo
# compila (medido con delphi_build), y la rutina va delante del end; se negaba
PASE = os.path.join(DIR, 'UEndPartido.pas')
open(PASE, 'wb').write(CRLF.join(['unit UEndPartido;', '', 'interface', '', 'implementation', '',
                                  'end', '.', '']).encode('ascii'))
out = call('delphi_edit', {"path": PASE, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
_src = open(PASE, 'rb').read().decode('ascii')
check('end.: insert en una unit con el punto del end en la linea de abajo: delante del end',
      'INSERT rutina-global' in out and mc.es(out, 'SK_EDIT_ESCRITO_EN_FMT') and
      not mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_END_FMT') and
      _src.index('implementation') < _src.index('procedure P;') < _src.rindex('end\r\n.'),
      out[:300] + ' | ' + _src)
# ...y con codigo delante del end. en su linea ('end; end.') se sigue negando:
# delante de esa linea la rutina caeria dentro de la de arriba
PASP = os.path.join(DIR, 'UEndPegado.pas')
_pegado = CRLF.join(['unit UEndPegado;', '', 'interface', '', 'implementation', '',
                     'procedure A;', 'begin', 'end; end.', '']).encode('ascii')
open(PASP, 'wb').write(_pegado)
out = call('delphi_edit', {"path": PASP, "insert": "rutina-global", "code": "procedure P;\nbegin\nend;"})
check('end.: insert con codigo delante del end. en su linea: se niega y no escribe',
      mc.es(out, 'SR_EDIT_ENCUENTRO_FRONTERA_FINAL_UNIT') and open(PASP, 'rb').read() == _pegado,
      out[:200])
# y un bloque que trae un end. que NO va solo en su linea se niega: pasaba, y el
# fichero quedaba con dos sin que la auditoria lo viese
PASB = os.path.join(DIR, 'UBloqueEnd.pas')
_bloque = CRLF.join(['unit UBloqueEnd;', '', 'interface', '', 'implementation', '', 'end.', '']).encode('ascii')
open(PASB, 'wb').write(_bloque)
out = call('delphi_edit', {"path": PASB, "insert": "rutina-global",
                            "code": "procedure Q;\nbegin\n  if True then Exit; end.\nend;"})
check('end.: un bloque con un end. a media linea se niega y no escribe',
      mc.rechazado(out) and mc.es(out, 'SR_EDIT_BLOQUE_TRAE_END_SOLO') and
      open(PASB, 'rb').read() == _bloque, out[:200])
# la auditoria es RELATIVA (revisor 8, M1): lo que ya estaba detras del end. final
# (notas sin comentar, que el compilador no lee) no avisa mientras no cambie;
# daba EDIT-086 "Restore ... and STOP" en cada edicion y en una tanda que no
# escribia nada (y restore devuelve la primera copia del dia)
PASN = os.path.join(DIR, 'UNotas.pas')
_notas = CRLF.join(['unit UNotas;', '', 'interface', '', 'implementation', '', 'end.',
                    'Historial: v1', '']).encode('ascii')
open(PASN, 'wb').write(_notas)
out = call('delphi_edit', {"path": PASN, "edits": [{"old": "interface", "new": "interface"}]})
check('end.: una tanda que no escribe nada en un fichero con notas tras el end. no avisa',
      not mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_ULTIMA') and not mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_END_FMT')
      and open(PASN, 'rb').read() == _notas, out[:300])
out = call('delphi_edit', {"path": PASN, "old": "interface", "new": "interface\n// una nota"})
check('end.: ...ni una edicion de otra parte del fichero',
      'WRITTEN' in out and not mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_ULTIMA'), out[:300])
out = call('delphi_edit', {"path": PASN, "old": "Historial: v1", "new": "Historial: v1\nprocedure Perdida;"})
check('end.: (guarda) lo que se escribe DETRAS del end. si avisa (EDIT-086)',
      mc.es(out, 'SN_EDIT_ESTRUCTURA_ROTA_ULTIMA'), out[:300])
# la frontera del insert en una unit con 'begin ... end.' como inicializacion es
# su begin, por EL lector (TLectorPas: donde acaban las declaraciones); la rutina
# caia DENTRO del bloque (revisor 8, M2; medido: E2070)
PASI = os.path.join(DIR, 'UIniBegin.pas')
open(PASI, 'wb').write(CRLF.join(['unit UIniBegin;', '', 'interface', '', 'implementation', '',
                                  'var', '  X: Integer;', '', 'begin', '  X := 1;', 'end.', '']).encode('ascii'))
out = call('delphi_edit', {"path": PASI, "insert": "rutina-global", "code": "procedure Nueva;\nbegin\n  X := 2;\nend;"})
_src = open(PASI, 'rb').read().decode('ascii')
_p = [_src.find(s) for s in ('X: Integer;', 'procedure Nueva;', 'begin\r\n  X := 1;\r\nend.')]
check('insert en una unit con begin..end. de inicializacion: delante de su begin',
      mc.es(out, 'SK_EDIT_ESCRITO_EN_FMT') and -1 not in _p and _p[0] < _p[1] < _p[2],
      out[:300] + ' | ' + _src)
# 'unit A . B;' compila y es A.B (medido con dcc): el nombre de la cabecera sin los
# blancos de alrededor del punto; create lo negaba (CREATE-019) y move no la veia
PASD = os.path.join(DIR, 'UPunto.Dos.pas')
out = call('delphi_edit', {"path": PASD, "createunit": True,
                            "content": "unit UPunto . Dos;\n\ninterface\n\nimplementation\n\nend.\n"})
check('cabecera "unit UPunto . Dos;": create la toma (es UPunto.Dos, como la lee dcc)',
      os.path.exists(PASD) and not mc.rechazado(out), out[:300])
if os.path.exists(PASD):
    out = call('delphi_move', {"path": PASD, "dest": os.path.join(DIR, 'UTres.pas')})
    _src = open(os.path.join(DIR, 'UTres.pas'), 'rb').read().decode('utf-8-sig') if os.path.exists(os.path.join(DIR, 'UTres.pas')) else ''
    check('...y move la reescribe ENTERA, con sus blancos: "unit UTres;"',
          mc.es(out, 'SN_MOVE_CABECERA_REESCRITA_FMT') and _src.startswith('unit UTres;') and 'Dos' not in _src,
          out[:300] + ' | ' + _src[:80])

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

# 2026-10-06 (revision): LA sangria que el ancla deja fuera, una regla para
# las dos tools (Lsp.Patch.SangraComoLaLinea). delphi_edit la ponia delante
# de la PRIMERA linea de new SIEMPRE: con new ya sangrado salia doble (medido:
# 4 + 4 = 8 espacios), y las demas lineas de new se quedaban sin ella.
_san = os.path.join(DIR, 'Sangria.pas')
open(_san, 'w', encoding='utf-8', newline='').write(CRLF.join([
    'unit Sangria;', '', 'interface', '', 'implementation', '',
    'procedure P;', 'begin', '    Foo := 1;', 'end;', '', 'end.', '']))
call('delphi_edit', {'path': _san, 'old': 'Foo := 1;', 'new': '    Foo := 2;'})
_t = open(_san, encoding='utf-8', newline='').read()
check('sangria: ancla sin ella y new YA sangrado -> se respeta, no se duplica',
      '\r\n    Foo := 2;\r\n' in _t, repr(_t[-60:]))
call('delphi_edit', {'path': _san, 'old': 'Foo := 2;', 'new': 'Foo := 3;'})
_t = open(_san, encoding='utf-8', newline='').read()
check('sangria: ancla y new sin ella -> new toma la de la linea',
      '\r\n    Foo := 3;\r\n' in _t, repr(_t[-60:]))
call('delphi_edit', {'path': _san, 'old': 'Foo := 3;', 'new': 'Foo := 4;\nBar := 5;'})
_t = open(_san, encoding='utf-8', newline='').read()
check('sangria: new de varias lineas sin ella -> TODAS toman la de la linea, no solo la primera',
      '\r\n    Foo := 4;\r\n    Bar := 5;\r\n' in _t, repr(_t[-60:]))
# la gemela, con la MISMA regla, en una linea sangrada de un .txt
_txt = os.path.join(DIR, 'sangria.txt')
open(_txt, 'w', encoding='utf-8', newline='').write('lista\r\n    - uno\r\nfin\r\n')
call('delphi_textedit', {'path': _txt, 'old': '- uno', 'new': '    - dos'})
call('delphi_textedit', {'path': _txt, 'old': '- dos', 'new': '- tres\n- cuatro'})
_t = open(_txt, encoding='utf-8', newline='').read()
check('sangria: delphi_textedit sigue la misma regla (no duplica, y en todas las lineas)',
      _t == 'lista\r\n    - tres\r\n    - cuatro\r\nfin\r\n', repr(_t))

# 4.1 de la 1.18.0 (David, 9-oct-2026): un fuente SOLO ASCII no tiene
# codificacion que respetar: el primer caracter no ASCII elige la que dcc lee
# bien - CP1252 si cabe, si no UTF-8 CON BOM -, como el IDE al guardar
# (medido por David: 'Accion' acentuado -> 0xF3 sin BOM, sin preguntar;
# Omega con su letra griega -> pregunta y, con si, EF BB BF + CE A9). Se
# escribia UTF-8 SIN BOM, y dcc lo compila como ANSI (AcciÃ³n).
def _ascii(nombre):
    p = os.path.join(DIR, nombre)
    b = (b"unit %s;\r\n\r\ninterface\r\n\r\nconst\r\n  Texto = 'Accion';\r\n\r\n"
         b"implementation\r\n\r\nend.\r\n" % nombre[:-4].encode())
    open(p, 'wb').write(b)
    return p, b
# todo el fichero byte a byte: lo no tocado sigue igual y el BOM, solo si toca
_a1, _o = _ascii('UAscii1.pas')
call('delphi_edit', {'path': _a1, 'old': "  Texto = 'Accion';", 'new': "  Texto = 'Acción';"})
_b = open(_a1, 'rb').read()
check('ASCII + un acento que cabe en CP1252: CP1252 crudo y sin BOM, como el IDE (0xF3)',
      _b == _o.replace(b"'Accion'", b"'Acci\xf3n'"), _b[:80])
_a2, _o = _ascii('UAscii2.pas')
_out = call('delphi_edit', {'path': _a2, 'old': "  Texto = 'Accion';", 'new': "  Texto = 'OmegaΩ';"})
_b = open(_a2, 'rb').read()
check('ASCII + un caracter que NO cabe en CP1252: UTF-8 CON BOM, como el IDE (EF BB BF + CE A9)',
      _b == b'\xef\xbb\xbf' + _o.replace(b"'Accion'", b"'Omega\xce\xa9'"), _b[:80])
check('...y lo dice: EDIT-080 nombra la codificacion que ha escrito (utf8-bom)',
      mc.es(_out, 'SN_EDIT_ERA_ASCII_PURO_FMT') and 'utf8-bom' in _out, _out[-600:])
# la regla vive en los DOS escritores (DoEdit y PatchSaveText): un bloque va
# por el segundo, y un insert y un changeset por el primero
_a3, _o = _ascii('UAscii3.pas')
call('delphi_edit', {'path': _a3, 'edits': json.dumps([{'old': "const\n  Texto = 'Accion';",
                                                      'new': "const\n  Texto = 'OmegaΩ';"}])})
_b = open(_a3, 'rb').read()
check('...un ancla de BLOQUE (PatchSaveText): UTF-8 con BOM igual',
      _b == b'\xef\xbb\xbf' + _o.replace(b"'Accion'", b"'Omega\xce\xa9'"), _b[:80])
_a4, _o = _ascii('UAscii4.pas')
call('delphi_edit', {'path': _a4, 'insert': 'rutina-global',
                     'code': "procedure Hola;\nbegin\n  Writeln('Acción');\nend;"})
_b = open(_a4, 'rb').read()
check('...un insert con un acento que cabe: CP1252 sin BOM',
      not _b.startswith(b'\xef\xbb\xbf') and b"Writeln('Acci\xf3n');" in _b and b'\xc3' not in _b, _b[-120:])
_a5, _o = _ascii('UAscii5.pas')
_r = call('delphi_changeset', {'command': 'begin'})
_cid = mc.id_changeset(_r)
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'edit', 'path': _a5,
                          'old': "  Texto = 'Accion';", 'new': "  Texto = 'OmegaΩ';"})
call('delphi_changeset', {'command': 'preview', 'id': _cid})  # el commit pide un preview limpio
_r = call('delphi_changeset', {'command': 'commit', 'id': _cid})
_b = open(_a5, 'rb').read()
check('...un changeset: UTF-8 con BOM igual',
      _b == b'\xef\xbb\xbf' + _o.replace(b"'Accion'", b"'Omega\xce\xa9'"), (_r[:200], _b[:80]))
# un texto cuyos bytes CP1252 se leerian como UTF-8 (una A con tilde y un
# superindice tres; una E acentuada y una comilla tipografica): el IDE y el
# detector leerian el fichero como UTF-8, con otros caracteres. Un fuente sin
# codificacion va entonces en UTF-8 con BOM, que no es ambiguo (revisor propio
# de la 4.1); antes salia CP1252 y se releia distinto
for _nom, _txt, _como in (('UAscii6.pas', 'Acci\u00c3\u00b3n', 'mojibake (A tilde + superindice tres)'),
                          ('UAscii7.pas', 'CAF\u00c9\u201d', 'una E acentuada y una comilla tipografica')):
    _p, _o = _ascii(_nom)
    _out = call('delphi_edit', {'path': _p, 'old': "  Texto = 'Accion';", 'new': "  Texto = '%s';" % _txt})
    check('...un ASCII con %s, cuyos bytes CP1252 se leerian como UTF-8: UTF-8 con BOM' % _como,
          open(_p, 'rb').read() == b'\xef\xbb\xbf' + _o.replace(b"'Accion'", ("'%s'" % _txt).encode('utf-8')),
          (_out[:300], open(_p, 'rb').read()[:60]))
# una tanda que pone una Omega y la quita: el fichero era ASCII al empezar y lo
# es al acabar; heredaba el BOM de en medio (revisor propio de la 4.1, medido)
_a9, _o = _ascii('UAscii9.pas')
_out = call('delphi_edit', {'path': _a9, 'edits': json.dumps([
    {'old': "  Texto = 'Accion';", 'new': "  Texto = '\u03a9';"}, {'old': "  Texto = '\u03a9';", 'new': "  Texto = 'y';"}])})
check('...una tanda que pone una Omega y la quita deja el fichero ASCII sin BOM (heredaba el de en medio)',
      open(_a9, 'rb').read() == _o.replace(b"'Accion'", b"'y'"), (_out[:300], open(_a9, 'rb').read()[:40]))
_a8, _o = _ascii('UAscii8.pas')
call('delphi_edit', {'path': _a8, 'old': "  Texto = 'Accion';", 'new': "  Texto = '\u201cCAF\u00c9\u201d';"})
check('...con la comilla de apertura ya no es UTF-8 valido: CP1252, como el IDE',
      open(_a8, 'rb').read() == _o.replace(b"'Accion'", b"'\x93CAF\xc9\x94'"), open(_a8, 'rb').read()[:80])
_u8 = os.path.join(DIR, 'UYaUtf8.pas')
open(_u8, 'wb').write("unit UYaUtf8;\r\n\r\ninterface\r\n\r\nconst\r\n  A = 'Ca\u00f1a';\r\n  B = 'x';\r\n\r\n"
                      "implementation\r\n\r\nend.\r\n".encode('utf-8'))
call('delphi_edit', {'path': _u8, 'old': "  B = 'x';", 'new': "  B = 'Acci\u00f3n';"})
_b = open(_u8, 'rb').read()
check('...uno que YA tiene su codificacion (UTF-8 sin BOM con acentos) la conserva: ni BOM ni CP1252',
      _b.startswith(b'unit') and "B = 'Acci\u00f3n';".encode('utf-8') in _b, _b[:120])
_md = os.path.join(DIR, 'leeme_ascii.md')
open(_md, 'wb').write(b'# titulo\r\nnada\r\n')
_out = call('delphi_textedit', {'path': _md, 'old': 'nada', 'new': 'Omega\u03a9'})
# lo que no lee dcc sigue la preferencia del IDE para un ASCII: con UTF-8
# se escribe UTF-8 SIN BOM; con ANSI la Omega no cabe y se niega - y entonces
# esto no mide la regla (un fichero sin tocar tampoco tiene BOM)
_IDE_PREFIERE_UTF8 = not mc.rechazado(_out)
if mc.rechazado(_out):
    print('NOTA: la regla del .md no se mide: el IDE de esta maquina prefiere ANSI y la Omega se niega')
else:
    check('...y un fichero que no lee dcc (un .md) no entra en la regla: UTF-8 sin BOM, sin ganar uno',
          open(_md, 'rb').read() == b'# titulo\r\nOmega\xce\xa9\r\n', open(_md, 'rb').read()[:40])

# UTF-32 (4.1 de la 1.18.0): el IDE lo ofrece al guardar un .pas (LE y BE) y
# el motor lo leia como UTF-16 LE (FF FE 00 00 empieza por FF FE) y el BE como
# binario. dcc no lo compila (F2438, medido), pero un fichero asi se lee y se
# edita con SUS bytes: lo no tocado igual byte a byte, y el BOM con el.
for _be, _nom, _enc, _codec, _bom in ((False, 'U32LE.pas', 'utf32-le', 'utf-32-le', b'\xff\xfe\x00\x00'),
                                      (True, 'U32BE.pas', 'utf32-be', 'utf-32-be', b'\x00\x00\xfe\xff')):
    _p = os.path.join(DIR, _nom)
    _s = ("unit %s;\r\n\r\ninterface\r\n\r\nconst\r\n  A = 'Caña \U0001F600';\r\n  B = 'x';\r\n\r\n"
          "implementation\r\n\r\nend.\r\n" % _nom[:-4])
    open(_p, 'wb').write(_bom + _s.encode(_codec))
    _out = call('delphi_read', {'path': _p})
    check('%s: delphi_read la reconoce por su BOM (encoding=%s, eol=CRLF) y la decodifica, fuera del plano basico tambien' % (_enc, _enc),
          'encoding=%s' % _enc in _out and 'eol=CRLF' in _out and "A = 'Caña \U0001F600';" in _out, _out[:300])
    _out = call('delphi_search', {'root': _p, 'query': 'Caña'})
    check('%s: delphi_search la lee (no es binario)' % _enc, '"total":1' in _out, _out[:300])
    _out = call('delphi_edit', {'path': _p, 'old': "  B = 'x';", 'new': "  B = 'Acción';"})
    _b = open(_p, 'rb').read()
    check('%s: delphi_edit escribe con SU codificacion, BOM incluido, y lo no tocado byte a byte' % _enc,
          _b == _bom + _s.replace("B = 'x'", "B = 'Acción'").encode(_codec), (_out[:300], _b[:40]))
_t32 = os.path.join(DIR, 'notas32.txt')
open(_t32, 'wb').write(b'\xff\xfe\x00\x00' + 'uno\r\ndos ñ\r\n'.encode('utf-32-le'))
_out = call('delphi_textedit', {'path': _t32, 'old': 'uno', 'new': 'tres'})
check('utf32-le: delphi_textedit tambien (la misma pareja detector/escritor)',
      open(_t32, 'rb').read() == b'\xff\xfe\x00\x00' + 'tres\r\ndos ñ\r\n'.encode('utf-32-le'), _out[:300])

# ...y un .inc tambien: dcc lee cada uno con SU BOM, aunque lo incluya un .pas
# sin BOM (medido en Sonda32 el 9-oct-2026)
_inc = os.path.join(DIR, 'UAscii.inc')
open(_inc, 'wb').write(b"Texto = 'Accion';\r\n")
call('delphi_edit', {'path': _inc, 'old': "Texto = 'Accion';", 'new': "Texto = 'OmegaΩ';"})
check('...un .inc ASCII con un caracter que no cabe en CP1252: UTF-8 con BOM, como un .pas',
      open(_inc, 'rb').read() == b"\xef\xbb\xbfTexto = 'Omega\xce\xa9';\r\n", open(_inc, 'rb').read())

# LA REGLA DE IDA Y VUELTA (David, 9-oct-2026), en los DOS escritores: lo que no
# vuelve igual por su codificacion no se reescribe - cambiaria bytes que nadie
# toco. Se lee (avisando, READ-007) y NINGUN escritor lo toca: delphi_edit,
# delphi_textedit, delphi_changeset (EDIT-038 era solo de la entrada de
# delphi_edit, y ninguna bateria lo miraba)
def _intacto_tras(nombre, ruta, orig, salida, codigo='SR_EDIT_BYTES_NO_VUELVEN_FMT'):
    check('ida y vuelta: %s se niega (EDIT-038) y no toca un byte' % nombre,
          mc.es(salida, codigo) and open(ruta, 'rb').read() == orig, (salida[:300], open(ruta, 'rb').read()[:60]))
# (1) BOM de UTF-8 y el cuerpo en CP1252: la lectura REVENTABA (SYS-006) y la
# busqueda tambien (medido en produccion)
_roto = os.path.join(DIR, 'UBomRoto.pas')
_ROTO = b"\xef\xbb\xbfunit UBomRoto;\r\n\r\ninterface\r\n\r\nconst\r\n  S = 'gesti\xf3n';\r\n  T = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n"
open(_roto, 'wb').write(_ROTO)
_out = call('delphi_read', {'path': _roto})
check('ida y vuelta: un BOM de UTF-8 con el cuerpo roto se LEE (no SYS-006) y lo dice (READ-007)',
      mc.es(_out, 'SN_READ_BYTES_NO_VUELVEN_FMT') and 'T = 1;' in _out and not mc.fallo(_out), _out[:300])
_out = call('delphi_search', {'root': _roto, 'query': 'T = 1'})
check('ida y vuelta: ...y se BUSCA (no SYS-006)', '"total":1' in _out, _out[:300])
_intacto_tras('delphi_edit en un BOM de UTF-8 con el cuerpo roto', _roto, _ROTO,
              call('delphi_edit', {'path': _roto, 'old': '  T = 1;', 'new': '  T = 2;'}))
_rotot = os.path.join(DIR, 'roto.txt')
_ROTOT = b'\xef\xbb\xbfuno\r\ngesti\xf3n\r\n'
open(_rotot, 'wb').write(_ROTOT)
_intacto_tras('delphi_textedit en un BOM de UTF-8 con el cuerpo roto', _rotot, _ROTOT,
              call('delphi_textedit', {'path': _rotot, 'old': 'uno', 'new': 'dos'}))
_r = call('delphi_changeset', {'command': 'begin'})
_cid = mc.id_changeset(_r)
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'edit', 'path': _roto,
                          'old': '  T = 1;', 'new': '  T = 3;'})
# (el ensayo del preview pasa por el escritor: la negativa sale YA en el
# preview, y el commit queda bloqueado)
_intacto_tras('delphi_changeset (su preview) en un BOM de UTF-8 con el cuerpo roto', _roto, _ROTO,
              call('delphi_changeset', {'command': 'preview', 'id': _cid}))
_r = call('delphi_changeset', {'command': 'commit', 'id': _cid})
check('ida y vuelta: ...y su commit se niega sin tocar un byte',
      mc.rechazado(_r) and open(_roto, 'rb').read() == _ROTO, _r[:300])
# (2) un UTF-32 mal formado (le sobran dos bytes al final)
_u32m = os.path.join(DIR, 'U32Mal.pas')
_U32M = b'\xff\xfe\x00\x00' + "unit U32Mal;\r\n  T = 1;\r\nend.\r\n".encode('utf-32-le') + b'\x41\x00'
open(_u32m, 'wb').write(_U32M)
_out = call('delphi_read', {'path': _u32m})
check('ida y vuelta: un UTF-32 mal formado se lee y lo dice (READ-007)',
      mc.es(_out, 'SN_READ_BYTES_NO_VUELVEN_FMT') and 'encoding=utf32-le' in _out, _out[:300])
_intacto_tras('delphi_edit en un UTF-32 mal formado', _u32m, _U32M,
              call('delphi_edit', {'path': _u32m, 'old': '  T = 1;', 'new': '  T = 2;'}))
# (3) un CP1252 cuyos UNICOS bytes altos parecen una forma larga de UTF-8 (E0
# 80 80, prohibida por RFC 3629): se detectaba UTF-8 y su lectura reventaba
_larga = os.path.join(DIR, 'ULarga.pas')
_LARGA = b"unit ULarga;\r\n\r\ninterface\r\n\r\nconst\r\n  S = '\xe0\x80\x80';\r\n  T = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n"
open(_larga, 'wb').write(_LARGA)
_out = call('delphi_read', {'path': _larga})
check('UTF-8 estricto: E0 80 80 no es UTF-8 (RFC 3629): se lee como cp1252',
      'encoding=cp1252' in _out and "S = 'à€€';" in _out, _out[:300])
call('delphi_edit', {'path': _larga, 'old': '  T = 1;', 'new': '  T = 2;'})
check('...y se edita con sus mismos bytes',
      open(_larga, 'rb').read() == _LARGA.replace(b'T = 1;', b'T = 2;'), open(_larga, 'rb').read()[:80])
# (4) el OTRO escritor (PatchSaveText: un ancla de bloque) sobre el fichero roto
_intacto_tras('un ancla de BLOQUE en un BOM de UTF-8 con el cuerpo roto', _roto, _ROTO,
              call('delphi_edit', {'path': _roto, 'edits': json.dumps(
                  [{'old': '  T = 1;\n\nimplementation', 'new': '  T = 2;\n\nimplementation'}])}))
# (5) ...y lo que lo cura: restore copia BYTES, y su vista previa lee el
# fichero roto sin reventar
_cura = os.path.join(DIR, 'UCura.pas')
_BUENO = b"unit UCura;\r\n\r\ninterface\r\n\r\nconst\r\n  S = 'gesti\xf3n';\r\n  T = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n"
open(_cura, 'wb').write(_BUENO)
call('delphi_edit', {'path': _cura, 'old': '  T = 1;', 'new': '  T = 2;'})  # su copia del dia: la buena
open(_cura, 'wb').write(b'\xef\xbb\xbf' + _BUENO)  # alguien le pone un BOM de UTF-8: cuerpo roto
_out = call('delphi_edit', {'path': _cura, 'restore': True})
_out2 = call('delphi_edit', {'path': _cura, 'restore': True, 'confirm': True})
check('ida y vuelta: restore, que copia bytes, cura un fichero roto (y su vista previa no revienta)',
      not mc.fallo(_out) and not mc.fallo(_out2) and open(_cura, 'rb').read() == _BUENO, (_out[:200], _out2[:200]))
# (6) un U+FFFD que esta DE VERDAD en el fichero (EF BF BD en un UTF-8 valido)
# no es un byte roto: vuelve igual y se edita
_fffd = os.path.join(DIR, 'UFffd.pas')
_FF = (b'\xef\xbb\xbf' + "unit UFffd;\r\n\r\ninterface\r\n\r\nconst\r\n  S = 'a\ufffdb \u00f1';\r\n  T = 1;\r\n\r\n"
       "implementation\r\n\r\nend.\r\n".encode('utf-8'))
open(_fffd, 'wb').write(_FF)
_out = call('delphi_edit', {'path': _fffd, 'old': '  T = 1;', 'new': '  T = 2;'})
check('ida y vuelta: un U+FFFD legitimo (EF BF BD en un UTF-8 valido) vuelve igual: se edita, byte a byte',
      open(_fffd, 'rb').read() == _FF.replace(b'T = 1;', b'T = 2;'), (_out[:300], open(_fffd, 'rb').read()[:60]))
# (7) READ-007 nombra la primera linea que no cuadra y, en un UTF-8, como seria
# en la otra lectura: el agente ve las dos y lo arregla en el IDE (David)
_CAT = mc.catalogo()
_out = call('delphi_read', {'path': _roto})
check('ida y vuelta: READ-007 nombra la primera linea que no cuadra y como se leeria en cp1252 (gestión)',
      _CAT['SF_READ_PRIMERA_NO_CUADRA_FMT'].split('%s')[0] in _out and
      (_CAT['SF_READ_OTRA_LECTURA_FMT'] % ('cp1252', '')).rstrip() in _out and
      "S = 'gesti\u00f3n';" in _out, _out[:600])
# (8) acentos UTF-8 validos y una secuencia prohibida (un sustituto en CESU-8)
# no son UTF-8: el juez de la RTL dice que no, y el IDE y dcc lo leen en ANSI.
# El servidor tambien (David: "si hay juez lo seguimos"; una regla propia de
# "UTF-8 danado" dejaba sin editar un CP1252 legitimo con comillas tipograficas)
_dan = os.path.join(DIR, 'UDanado.pas')
_DAN = (b"unit UDanado;\r\n\r\ninterface\r\n\r\nconst\r\n  S = 'gesti\xc3\xb3n';\r\n  R = '\xed\xa0\xbd\xed\xb8\x80';\r\n"
        b"  T = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n")
open(_dan, 'wb').write(_DAN)
_out = call('delphi_read', {'path': _dan})
check('UTF-8 mezclado con una secuencia prohibida: se lee como cp1252, como el IDE y dcc',
      'encoding=cp1252' in _out and not mc.es(_out, 'SN_READ_BYTES_NO_VUELVEN_FMT'), _out[:400])
call('delphi_edit', {'path': _dan, 'old': '  T = 1;', 'new': "  T = 'Acci\u00f3n';"})
check('...y se edita en cp1252, con sus mismos bytes',
      open(_dan, 'rb').read() == _DAN.replace(b'T = 1;', b"T = 'Acci\xf3n';"), open(_dan, 'rb').read()[:80])
# (9) un UTF-16 con un byte suelto al final: delphi_edit lo reescribia SIN el
# byte (la RTL lo dejaba fuera callado). Se lee con U+FFFD y nadie lo reescribe
_u16 = os.path.join(DIR, 'U16Impar.pas')
_U16 = b'\xff\xfe' + "unit U16Impar;\r\n  T = 1;\r\nend.\r\n".encode('utf-16-le') + b'\x41'
open(_u16, 'wb').write(_U16)
_out = call('delphi_read', {'path': _u16})
check('UTF-16 con un byte suelto al final: se lee, el byte sale U+FFFD y READ-007 lo dice',
      mc.es(_out, 'SN_READ_BYTES_NO_VUELVEN_FMT') and '\ufffd' in _out, _out[:300])
_intacto_tras('delphi_edit en un UTF-16 con un byte suelto (lo reescribia sin el)', _u16, _U16,
              call('delphi_edit', {'path': _u16, 'old': '  T = 1;', 'new': '  T = 2;'}))
# (10) un changeset que BORRA un fichero roto y lo CREA de nuevo: el ensayo del
# create miraba el viejo (EDIT-038 falso en el preview, que bloqueaba el commit)
_x = os.path.join(DIR, 'URecrea.pas')
open(_x, 'wb').write(_ROTO.replace(b'UBomRoto', b'URecrea'))
_cid = mc.id_changeset(call('delphi_changeset', {'command': 'begin'}))
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'delete', 'path': _x})
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'create', 'path': _x,
                          'content': 'unit URecrea;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'})
_pv = call('delphi_changeset', {'command': 'preview', 'id': _cid})
_r = call('delphi_changeset', {'command': 'commit', 'id': _cid})
_b = open(_x, 'rb').read()
def _sin_pendientes(pv):
    try:
        return json.loads(pv).get('unresolved') == 0
    except ValueError:
        return False
check('ida y vuelta: delete + create de un fichero roto: el preview no niega el create (es NUEVO) y el commit lo deja nuevo',
      _sin_pendientes(_pv) and b'unit URecrea;' in _b and b'gesti' not in _b, (_pv[:300], _r[:300], _b[:60]))

# el origen de la llamada se ancla de nuevo si la ruta cambia de contenido por
# otro camino (revisor propio de la 4.1, medido): un changeset que editaba P, lo
# borraba, movia a P un fichero en UTF-8 con BOM y lo editaba otra vez dejaba P
# en CP1252 - transcodificaba un fichero que SI tenia codificacion
_pm, _qm = os.path.join(DIR, 'UMovP.pas'), os.path.join(DIR, 'UMovQ.pas')
open(_pm, 'wb').write(b"unit UMovP;\r\n\r\ninterface\r\n\r\nconst\r\n  X = 1;\r\n  T = 1;\r\n\r\nimplementation\r\n\r\nend.\r\n")
_QM = b'\xef\xbb\xbf' + ("unit UMovP;\r\n\r\ninterface\r\n\r\nconst\r\n  S = 'gesti\u00f3n';\r\n  T = 1;\r\n\r\n"
                         "implementation\r\n\r\nend.\r\n").encode('utf-8')
open(_qm, 'wb').write(_QM)
_cid = mc.id_changeset(call('delphi_changeset', {'command': 'begin'}))
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'edit', 'path': _pm, 'old': '  X = 1;', 'new': '  X = 2;'})
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'delete', 'path': _pm})
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'move', 'path': _qm, 'dest': _pm})
call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'edit', 'path': _pm, 'old': '  T = 1;', 'new': '  T = 2;'})
_pv = call('delphi_changeset', {'command': 'preview', 'id': _cid})
_r = call('delphi_changeset', {'command': 'commit', 'id': _cid})
check('origen: edit P / delete P / move Q->P / edit P deja en P la codificacion de Q (UTF-8 con BOM), no CP1252',
      open(_pm, 'rb').read() == _QM.replace(b'T = 1;', b'T = 2;'), (_pv[:200], _r[:300], open(_pm, 'rb').read()[:60]))
# ...y conserva CUAL tenia: una tanda que quita el unico acento de un CP1252 y
# pone otro lo dejaba en UTF-8 sin BOM (la preferencia del IDE para lo que ya
# parecia ASCII) segun el orden (revisor propio de la 4.1, medido; tambien 1.17)
_ua = os.path.join(DIR, 'UUnAcento.pas')
_UA = b"unit UUnAcento;\r\n\r\ninterface\r\n\r\nconst\r\n  A = '\xe9';\r\n  B = 'x';\r\n\r\nimplementation\r\n\r\nend.\r\n"
open(_ua, 'wb').write(_UA)
_out = call('delphi_edit', {'path': _ua, 'edits': json.dumps([
    {'old': "  A = '\u00e9';", 'new': "  A = 'e';"}, {'old': "  B = 'x';", 'new': "  B = 'Descripci\u00f3n';"}])})
if not _IDE_PREFIERE_UTF8:
    print('NOTA: el check del unico acento no distingue aqui: con el IDE en ANSI el codigo viejo tambien daba '
          'CP1252 (lo mide LspTests.Encodings.EncAlEscribirConservaLaCodificacionDelOrigen)')
check('origen: una tanda que quita el unico acento y pone otro deja el fichero en CP1252 (acababa en UTF-8 sin BOM)',
      open(_ua, 'rb').read() == _UA.replace(b"'\xe9'", b"'e'").replace(b"'x'", b"'Descripci\xf3n'"),
      (_out[:300], open(_ua, 'rb').read()[:80]))

# EDIT-080 solo cuando el fichero NO tenia codificacion: un UTF-8 con BOM y
# solo ASCII ya tiene una (Measure no cuenta el BOM y decia "era ASCII puro")
_bomasc = os.path.join(DIR, 'UBomAscii.pas')
_BA = b"\xef\xbb\xbfunit UBomAscii;\r\n\r\ninterface\r\n\r\nconst\r\n  T = 'x';\r\n\r\nimplementation\r\n\r\nend.\r\n"
open(_bomasc, 'wb').write(_BA)
_out = call('delphi_edit', {'path': _bomasc, 'old': "  T = 'x';", 'new': "  T = 'Acci\u00f3n';"})
check('EDIT-080: un UTF-8 con BOM y solo ASCII ya tenia codificacion: la conserva y no dice "era ASCII puro"',
      not mc.es(_out, 'SN_EDIT_ERA_ASCII_PURO_FMT') and
      open(_bomasc, 'rb').read() == _BA.replace(b"'x'", "'Acci\u00f3n'".encode('utf-8')), _out[-400:])

# el primer caracter no ASCII lo decide la LLAMADA, no cada escritura (revisor
# propio de la 4.1, medido el 9-oct-2026): una tanda con la vocal acentuada y
# luego la Omega se negaba -la primera entrada fijaba CP1252- y al reves salia
# en UTF-8 con BOM; el preview de un changeset decia que si y su commit que no
def _ascii2(nombre):
    p = os.path.join(DIR, nombre)
    b = (b"unit %s;\r\n\r\ninterface\r\n\r\nconst\r\n  A = 'Accion';\r\n  B = 'x';\r\n\r\n"
         b"implementation\r\n\r\nend.\r\n" % nombre[:-4].encode())
    open(p, 'wb').write(b)
    return p, b
_EA = {'old': "  A = 'Accion';", 'new': "  A = 'Acci\u00f3n';"}
_EO = {'old': "  B = 'x';", 'new': "  B = '\u03a9';"}
def _final(b0):
    return b'\xef\xbb\xbf' + b0.replace(b"'Accion'", "'Acci\u00f3n'".encode('utf-8')).replace(
        b"'x'", "'\u03a9'".encode('utf-8'))
for _nom, _eds, _como in (('UOrdAO.pas', [_EA, _EO], 'la vocal y luego la Omega'),
                          ('UOrdOA.pas', [_EO, _EA], 'la Omega y luego la vocal')):
    _p, _o = _ascii2(_nom)
    _out = call('delphi_edit', {'path': _p, 'edits': json.dumps(_eds)})
    check('el primer caracter no ASCII lo decide la LLAMADA: una tanda con %s acaba en UTF-8 con BOM' % _como,
          open(_p, 'rb').read() == _final(_o), (_out[:300], open(_p, 'rb').read()[:60]))
    check('...sin la falsa alarma de acentos (EDIT-081) cuando la tanda pasa de CP1252 a UTF-8 con BOM (%s)' % _como,
          not mc.es(_out, 'SN_EDIT_ACENTOS_FUERA_CUADRO_FMT'), _out[-500:])
    _p, _o = _ascii2('Cs' + _nom)
    _cid = mc.id_changeset(call('delphi_changeset', {'command': 'begin'}))
    for _e in _eds:
        call('delphi_changeset', {'command': 'stage', 'id': _cid, 'kind': 'edit', 'path': _p,
                                  'old': _e['old'], 'new': _e['new']})
    call('delphi_changeset', {'command': 'preview', 'id': _cid})
    _r = call('delphi_changeset', {'command': 'commit', 'id': _cid})
    check('...y un changeset con %s: el commit hace lo que dijo su preview (UTF-8 con BOM)' % _como,
          open(_p, 'rb').read() == _final(_o), (_r[:300], open(_p, 'rb').read()[:60]))

# (r5 de la 1.18.0, regla 5 de David) un FUENTE en UTF-8 sin BOM con acentos se
# lee y se escribe como UTF-8 (sus bytes), y al LEERLO READ-008 dice que dcc lo
# compilara como ANSI y que la salida es guardarlo en el IDE (le pone el BOM).
# Con BOM, solo ASCII, o un form (que sin BOM se lee en ANSI, como dcc), no
_out = call('delphi_read', {'path': _u8})
check('READ-008: un fuente UTF-8 sin BOM con acentos lo dice al leerlo (dcc lo compila como ANSI)',
      mc.es(_out, 'SN_READ_UTF8_SIN_BOM_FMT') and 'encoding=utf8 ' in _out, _out[:500])
# ...tambien con el acento SOLO en la ruta de una directiva: dcc la lee en ANSI
# (revisor de la tanda rapida, TR-B1: la vista sin directivas no lo veia)
_dir8 = os.path.join(DIR, 'UDirect8.pas')
open(_dir8, 'wb').write(("unit UDirect8;\r\n\r\ninterface\r\n\r\n{$I ..\\Caf\u00e9\\x.inc}\r\n\r\n"
                         "implementation\r\n\r\nend.\r\n").encode('utf-8'))
_out = call('delphi_read', {'path': _dir8})
check('...y con el acento solo en la ruta de un {$I} (dcc lee la directiva en ANSI)',
      mc.es(_out, 'SN_READ_UTF8_SIN_BOM_FMT'), _out[:300])
_out = call('delphi_edit', {'path': _u8, 'old': "  A = 'Ca\u00f1a';", 'new': "  A = 'Ca\u00f1as';"})
check('...y escribirlo no le toca la codificacion (sigue UTF-8 sin BOM)',
      open(_u8, 'rb').read().startswith(b'unit') and
      "A = 'Ca\u00f1as';".encode('utf-8') in open(_u8, 'rb').read(), _out[-600:])
_r8 = {'UConBom8.pas': b'\xef\xbb\xbf' + "unit UConBom8;\r\n\r\ninterface\r\n\r\nconst\r\n  A = 'Ca\u00f1a';\r\n\r\n"
                       "implementation\r\n\r\nend.\r\n".encode('utf-8'),
       'UAsciiR8.pas': b"unit UAsciiR8;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n",
       'FUtf8Sin.dfm': "object F: TForm\r\n  Caption = 'Ca\u00f1a'\r\nend\r\n".encode('utf-8'),
       # los acentos SOLO en comentarios: dcc no los mete en el programa (r5-L8)
       'UComent8.pas': "unit UComent8;\r\n\r\n// A\u00f1o con e\u00f1e\r\n{ y aqu\u00ed }\r\ninterface\r\n\r\n"
                       "implementation\r\n\r\nend.\r\n".encode('utf-8')}
for _nom, _bytes in _r8.items():
    open(os.path.join(DIR, _nom), 'wb').write(_bytes)
    _out = call('delphi_read', {'path': os.path.join(DIR, _nom)})
    check('...READ-008 no sale en %s (con BOM, solo ASCII, acentos solo en comentarios o un form)' % _nom,
          not mc.rechazado(_out) and not mc.es(_out, 'SN_READ_UTF8_SIN_BOM_FMT'), _out[:300])

# --- P3-L9 de la 1.18.0: borrar una linea EN BLANCO. No tiene texto que copiar
# como ancla (EDIT-056 pedia "old" con la linea, y una vacia no se puede dar: el
# rodeo era un bloque de tres lineas). delete + atline SIN old la borra si ESA
# linea esta en blanco - lo que casa con un ancla vacia, la regla del motor -;
# si tiene texto, EDIT-123 citandola, y EDIT-124 si no existe. Igual en la tanda
# y en delphi_textedit, la gemela. Contra el binario de antes: EDIT-056/TEXT-003.
_bl = os.path.join(DIR, 'UBlanca.pas')
_blsrc = b'unit UBlanca;\r\n\r\ninterface\r\n\r\n \t\r\nimplementation\r\n\r\nend.\r\n'
open(_bl, 'wb').write(_blsrc)
_out = call('delphi_edit', {'path': _bl, 'delete': True, 'atline': 5})
check('P3-L9: delete + atline sin old borra la linea EN BLANCO (blancos y tabuladores cuentan como blanca)',
      open(_bl, 'rb').read() == b'unit UBlanca;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n', _out[:400])
_antes = open(_bl, 'rb').read()
_out = call('delphi_edit', {'path': _bl, 'delete': True, 'atline': 3})
check('...una linea CON texto no se borra sin old: EDIT-123 la cita y no se escribe nada',
      mc.abre(_out, 'SR_EDIT_LINEA_NO_EN_BLANCO_FMT') and 'interface' in _out and
      open(_bl, 'rb').read() == _antes, _out[:400])
_out = call('delphi_edit', {'path': _bl, 'delete': True, 'atline': 40})
check('...una linea que no existe: EDIT-124', mc.abre(_out, 'SR_EDIT_LINEA_EN_BLANCO_NO_EXISTE_FMT') and
      open(_bl, 'rb').read() == _antes, _out[:300])
_out = call('delphi_edit', {'path': _bl, 'delete': True})
check('...sin old y sin atline sigue siendo EDIT-056 (que linea, no se adivina)',
      mc.abre(_out, 'SR_EDIT_DELETE_TRUE_NECESITA_OLD') and open(_bl, 'rb').read() == _antes, _out[:300])
_out = call('delphi_edit', {'path': _bl, 'edits': json.dumps([{'delete': True, 'atline': 2}])})
check('...y en una tanda (la entrada sin old con delete y atline)',
      open(_bl, 'rb').read() == b'unit UBlanca;\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n', _out[:400])
# 8.11: "edits" se publica como ARRAY de objetos (el cliente que valida contra el
# esquema rechazaba el array antes de llamar, Hermes 8-oct) y un array REAL se
# aplica; el texto con el JSON dentro se sigue aceptando (arriba, json.dumps)
_out = call('delphi_edit', {'path': _bl, 'edits': [{'delete': True, 'atline': 3}]})
# (GUARDA: el binder acepta un array desde el 25-sep; lo que 8.11 cambia - el
# esquema - lo miden los dos checks de abajo)
check('8.11: edits como array JSON real se aplica (guarda)',
      open(_bl, 'rb').read() == b'unit UBlanca;\r\ninterface\r\nimplementation\r\n\r\nend.\r\n', _out[:400])
_tl = srv.request('tools/list', {})['result']['tools']
for _t in ('delphi_edit', 'delphi_textedit'):
    _props = next(x for x in _tl if x['name'] == _t)['inputSchema']['properties']
    check('8.11: %s.edits se publica como array de objetos' % _t,
          _props['edits'].get('type') == 'array' and _props['edits'].get('items', {}).get('type') == 'object',
          _props['edits'])
    check('...y su "new" sigue siendo texto (solo lo marcado con [JsonComoTexto])',
          _props['new'].get('type') == 'string', _props['new'])
_tx = os.path.join(DIR, 'blanca.txt')
open(_tx, 'wb').write(b'uno\r\n\r\ndos\r\n')
_out = call('delphi_textedit', {'path': _tx, 'delete': True, 'atline': 2})
check('P3-L9 en delphi_textedit: delete + atline sin old borra la linea en blanco',
      open(_tx, 'rb').read() == b'uno\r\ndos\r\n', _out[:300])
open(_tx, 'wb').write(b'uno\r\n\r\ndos\r\n')
_out = call('delphi_textedit', {'path': _tx, 'delete': True, 'atline': 1})
check('...y una con texto: EDIT-123, la misma negativa que delphi_edit',
      mc.abre(_out, 'SR_EDIT_LINEA_NO_EN_BLANCO_FMT') and open(_tx, 'rb').read() == b'uno\r\n\r\ndos\r\n', _out[:300])
_out = call('delphi_textedit', {'path': _tx, 'delete': True})
check('...sin old ni atline: TEXT-003', mc.abre(_out, 'SR_TEXT_DELETE_TRUE_NECESITA_OLD'), _out[:300])
_out = call('delphi_textedit', {'path': _tx, 'old': '   ', 'new': 'x'})
check('...y un ancla de solo blancos es EDIT-060, como en delphi_edit (casaba con la linea en blanco y la reescribia)',
      mc.abre(_out, 'SR_EDIT_ANCLA_ESTA_VACIA_SOLO') and open(_tx, 'rb').read() == b'uno\r\n\r\ndos\r\n', _out[:300])
_out = call('delphi_textedit', {'path': _tx, 'edits': json.dumps([{'delete': True, 'atline': 2}])})
check('...y en una tanda de delphi_textedit', open(_tx, 'rb').read() == b'uno\r\ndos\r\n', _out[:300])

# --- EDIT-091 mira lo que TOCA lo escrito en el fichero que queda, no solo el
# texto nuevo: una linea escrita en MEDIO de un comentario de llaves de varias
# lineas con un {$I} citado (o una llave) no avisaba - la llave que lo abre
# estaba en otra linea (medido el 9-oct-2026 en la suelta y en la tanda; dcc dio
# E2029). Un comentario anidado LEJOS de lo escrito no avisa (sin ruido).
def _llaves(nombre):
    p = os.path.join(DIR, nombre)
    open(p, 'wb').write(b'unit ' + nombre[:-4].encode() + b';\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n'
                        b'{ Un comentario de llaves\r\n  de varias lineas: la linea del medio\r\n'
                        b'  se edita aparte. }\r\nprocedure P;\r\nbegin\r\nend;\r\n\r\n'
                        b'{ uno viejo {con otra} lejos }\r\n\r\nend.\r\n')
    return p
_p = _llaves('ULlaves1.pas')
_out = call('delphi_edit', {'path': _p, 'old': '  de varias lineas: la linea del medio',
                            'new': '  de varias lineas: la ruta de un {$I x.inc} del medio'})
check('EDIT-091: una linea escrita en medio de un comentario de llaves de varias lineas, con un {$I} dentro',
      mc.es(_out, 'SN_AVISO_LLAVE_ANIDADA_FMT') and 'line 7 ' in _out and 'line 14 ' not in _out, _out[-700:])
_p = _llaves('ULlaves2.pas')
_out = call('delphi_edit', {'path': _p, 'edits': json.dumps([{'old': '  se edita aparte. }',
                                                             'new': '  se edita {aparte} en tanda. }'}])})
check('...y en una tanda, con una llave dentro', mc.es(_out, 'SN_AVISO_LLAVE_ANIDADA_FMT') and
      'line 7 ' in _out and 'line 14 ' not in _out, _out[-700:])
_p = _llaves('ULlaves3.pas')
_out = call('delphi_edit', {'path': _p, 'old': '  de varias lineas: la linea del medio',
                            'new': '  de varias lineas: sin llaves aqui'})
check('...sin llave nueva no avisa, ni del anidado de lejos', not mc.fallo(_out) and
      not mc.es(_out, 'SN_AVISO_LLAVE_ANIDADA_FMT'), _out[-500:])
_p4 = os.path.join(DIR, 'ULlaves4.pas')
open(_p4, 'wb').write(b'unit ULlaves4;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n{ primero\r\n  sigue }\r\n'
                      b'{ segundo }\r\n\r\nend.\r\n')
_out = call('delphi_edit', {'path': _p4, 'old': '  sigue }', 'delete': True})
check('...y borrar la linea que cerraba un comentario deja el de debajo DENTRO: lo avisa',
      mc.es(_out, 'SN_AVISO_LLAVE_ANIDADA_FMT') and 'line 7 ' in _out, _out[-500:])

# lo del revisor de la noche (10-oct): M-3 un rango sin old (delete + atline +
# toline) borraba desde una linea en blanco lo que hubiera, sin ancla de texto:
# EDIT-125 en las dos tools; B-3 occurrence sin old en una tanda decia "aparece
# 0 veces": EDIT-126; B-1 borrar la linea pegada a un comentario anidado VIEJO
# (que no abarca la juntura) avisaba EDIT-091 de algo que no se toco
_m3 = os.path.join(DIR, 'URango.pas')
_m3src = b'unit URango;\r\n\r\ninterface\r\n\r\nconst A = 1;\r\nconst B = 2;\r\n\r\nimplementation\r\n\r\nend.\r\n'
open(_m3, 'wb').write(_m3src)
_out = call('delphi_edit', {'path': _m3, 'delete': True, 'atline': 4, 'toline': 6})
check('M-3: delete + atline + toline sin old es EDIT-125 y no se borra nada',
      mc.abre(_out, 'SR_EDIT_RANGO_SIN_OLD') and open(_m3, 'rb').read() == _m3src, _out[:300])
_tx3 = os.path.join(DIR, 'rango.txt')
open(_tx3, 'wb').write(b'uno\r\n\r\ndos\r\ntres\r\n')
_out = call('delphi_textedit', {'path': _tx3, 'delete': True, 'atline': 2, 'toline': 4})
check('...y en delphi_textedit', mc.abre(_out, 'SR_EDIT_RANGO_SIN_OLD') and
      open(_tx3, 'rb').read() == b'uno\r\n\r\ndos\r\ntres\r\n', _out[:300])
_out = call('delphi_edit', {'path': _m3, 'edits': json.dumps([{'delete': True, 'occurrence': 1}])})
check('B-3: occurrence sin old en una tanda es EDIT-126 (no "aparece 0 veces")',
      mc.es(_out, 'SR_PATCH_OCURRENCIA_SIN_TEXTO_FMT') and open(_m3, 'rb').read() == _m3src, _out[:300])
_b1 = os.path.join(DIR, 'UJuntura.pas')
open(_b1, 'wb').write(b'unit UJuntura;\r\n\r\ninterface\r\n\r\n{ ver {enlace }\r\nconst A = 1;\r\nconst B = 2;\r\n'
                      b'\r\nimplementation\r\n\r\nend.\r\n')
_out = call('delphi_edit', {'path': _b1, 'old': 'const A = 1;', 'delete': True})
check('B-1: borrar la linea pegada a un comentario anidado viejo no avisa EDIT-091',
      not mc.fallo(_out) and not mc.es(_out, 'SN_AVISO_LLAVE_ANIDADA_FMT'), _out[-400:])

srv.cierra()
mc.fin('delphi_edit battery')
