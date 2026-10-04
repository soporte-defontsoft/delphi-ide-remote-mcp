"""E2E battery - EL identificador (Lsp.Pascal), 4-oct-2026.

A Pascal identifier is a letter of ANY alphabet or _, then letters, digits
or _ (the compiler's rule and the RTL's IsValidIdent): AnadirLineaTexto
written with its n-tilde, lblDireccion with its accent. The RTL's TRegEx
compiles without PCRE_UCP, so \\w, \\b and [A-Za-z] only see ASCII, and the
server wrote its identifiers that way in some sixty regexes and three
character classifiers. Measured that day: 124 units of David's projects
with 6,789 such names. What it broke, and what each check here measures
through the real server:

- rename_symbol: the new name was refused, and the identifier under the
  cursor was a piece of the name;
- INSERT of a method: the name of 'procedure AnadirX' was 'A', so the two
  "already there" looks searched for a routine A and the second insert
  wrote a duplicate;
- a unit with an accented name: refused by add-unit (CFG-038), and its
  entry in the .dpr, rewritten by a move, kept the tail of the old name;
- delphi_search wholeword: a piece of a name followed by an accented
  letter counted as a whole word;
- check-binding: an accented handler was never read;
- what dcc reads as an identifier is wider than "a letter": any non-ASCII
  character of the basic plane (measured: Col\u00b7lecci\u00f3 with its middle
  dot, a euro sign, a no-break space compile; a letter outside the basic
  plane does not), and the first version of the lexicon (\\p{L}) split them;
- and the echo of a rolled-back batch of delphi_edit / delphi_textedit:
  the line re-read from the disk went through the drive mask, so a
  '[^\\s:]' came back as '[^\\srv0:]' and the hint was no anchor. What the
  agent typed is still masked.

Usage:  python tests/test_identificadores.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('identificadores')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='ident', t=300)
call = srv.call


# los de la casa (mcp_cliente): el JSON de una tool, un fichero (vacio si no
# existe) y un build
J = mc.como_json
rd = mc.lee


def build_ok(dproj):
    return mc.build_ok(call, dproj)


ANADIR = 'A\u00f1adirLineaTexto'      # AnadirLineaTexto, con su enye
AGREGAR = 'AgregarL\u00ednea'         # el nombre nuevo, con su i acentuada
TAMANO = 'Tama\u00f1o'
ARBOL = 'U\u00c1rbol'                 # UArbol, con su A acentuada
BOTON = 'Bot\u00f3n'

print('== identificadores battery ==')
PRJ = os.path.join(BASE, 'Ident')
DPR = os.path.join(PRJ, 'Ident.dpr')
DPROJ = os.path.join(PRJ, 'Ident.dproj')
r = call('delphi_create', {'kind': 'project-console', 'name': 'Ident', 'dir': PRJ})
assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r
r = call('delphi_create', {'kind': 'unit', 'name': 'UTexto', 'project': DPR})
assert mc.abre(r, 'SK_CREATE_CREADA_UNIT_LINEAS_FMT'), r
UTEXTO = os.path.join(PRJ, 'UTexto.pas')
open(UTEXTO, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UTexto;

interface

type
  TComunicador = class
  public
    procedure Base;
  end;

function %(a)s(const S: string): string;
function %(t)s(const S: string): Integer;

implementation

procedure TComunicador.Base;
begin
end;

function %(a)s(const S: string): string;
begin
  Result := S + sLineBreak;
end;

function %(t)s(const S: string): Integer;
begin
  Result := Length(%(a)s(S));
end;

end.
""" % {'a': ANADIR, 't': TAMANO})
s = rd(DPR)
open(DPR, 'w', encoding='utf-8-sig', newline='').write(
    s.replace('begin', 'begin\n  Writeln(%s(\'x\'));' % TAMANO, 1))
ok, err = build_ok(DPROJ)
check('fixture: el proyecto con identificadores acentuados COMPILA (dcc los acepta)', ok, err)

# ---- I1 rename_symbol: el nombre nuevo y el de debajo del cursor ----
lineas = rd(UTEXTO).replace('\r\n', '\n').split('\n')
li = next(i for i, l in enumerate(lineas) if l.startswith('function ' + ANADIR))
j = J(call('delphi_rename_symbol', {'path': UTEXTO, 'line': li, 'character': 9 + 3, 'newname': AGREGAR}))
check('I1 rename: el simbolo de debajo del cursor es el nombre ENTERO (con A-Z a mano era un trozo)',
      j.get('symbol') == ANADIR, str(j)[:400])
check('I1b rename: un nombre nuevo con acento es legal (se negaba con RENAME-BAD-IDENT)',
      j.get('applicable') is True and not any(mc.es(b, 'SR_RENAME_BAD_IDENT_FMT') for b in j.get('blockers', [])),
      str(j)[:400])
j = J(call('delphi_rename_symbol', {'path': UTEXTO, 'line': li, 'character': 9 + 3, 'newname': AGREGAR,
                                    'mode': 'apply'}))
u = rd(UTEXTO)
check('I1c rename apply: las tres apariciones cambian y no queda la vieja',
      j.get('applied') is True and u.count(AGREGAR) == 3 and ANADIR not in u, str(j)[:300] + ' | ' + u[:400])
ok, err = build_ok(DPROJ)
check('I1d ...y el proyecto COMPILA', ok, err)

# ---- I2 INSERT de un metodo con acento, dos veces ----
r = call('delphi_edit', {'path': UTEXTO, 'insert': 'metodo', 'inclass': 'TComunicador',
                         'code': 'procedure A\u00f1adirSaludo;\nbegin\nend;'})
u = rd(UTEXTO)
check('I2 insert=metodo con enye: las dos mitades',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure A\u00f1adirSaludo;' in u and
      'procedure TComunicador.A\u00f1adirSaludo;' in u, r[:300])
antes = open(UTEXTO, 'rb').read()
r = call('delphi_edit', {'path': UTEXTO, 'insert': 'metodo', 'inclass': 'TComunicador',
                         'code': 'procedure A\u00f1adirSaludo;\nbegin\nend;'})
check('I2b el segundo INSERT ve que ya esta entero y no escribe (su nombre era "A")',
      mc.rechazado(r) and mc.es(r, 'SR_EDIT_EXISTE_ENTERO_DECLARACION_LINEA_FMT') and
      open(UTEXTO, 'rb').read() == antes, r[:300])
ok, err = build_ok(DPROJ)
check('I2c ...y el proyecto COMPILA', ok, err)

# ---- I3 una unit de nombre acentuado: crear, usar, mover ----
r = call('delphi_create', {'kind': 'unit', 'name': ARBOL, 'project': DPR})
dpr = rd(DPR)
check('I3 create unit acentuada: creada y dada de alta en el .dpr (CFG-038 la negaba)',
      mc.abre(r, 'SK_CREATE_CREADA_UNIT_LINEAS_FMT') and mc.es(r, 'SN_UNIT_ADDED_FMT') and
      "%s in '%s.pas'" % (ARBOL, ARBOL) in dpr, r[:300] + ' | ' + dpr)
r = call('delphi_edit', {'path': UTEXTO, 'adduses': ARBOL, 'section': 'implementation'})
check('I3b adduses de la unit acentuada', mc.abre(r, 'SN_ADDUSES_ADDED_FMT') and ARBOL in rd(UTEXTO), r[:300])
NUEVO = ARBOL + 'Nuevo'
r = call('delphi_move', {'path': os.path.join(PRJ, ARBOL + '.pas'), 'dest': os.path.join(PRJ, NUEVO + '.pas')})
dpr = rd(DPR)
entrada = [l.strip() for l in dpr.split('\n') if NUEVO in l]
check('I3c move: la entrada del .dpr es la nueva entera, sin la cola de la vieja pegada',
      mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and len(entrada) == 1 and
      re.fullmatch(r"%s in '%s\.pas'[,;]" % (NUEVO, NUEVO), entrada[0]) is not None, r[:300] + ' | ' + dpr)
check('I3d move: la cabecera y el uses de quien la usa, renombrados',
      rd(os.path.join(PRJ, NUEVO + '.pas')).lstrip().startswith('unit %s;' % NUEVO) and
      re.search(r'\b%s\b' % NUEVO, rd(UTEXTO)) is not None and
      re.search(r'%s(?!Nuevo)' % ARBOL, rd(UTEXTO)) is None, rd(UTEXTO)[-300:])
ok, err = build_ok(DPROJ)
check('I3e ...y el proyecto COMPILA', ok, err)
# la MISMA unit escrita con otra caja de su acento (dcc la toma por la misma,
# medido): adduses no la vuelve a anadir (con SameText, solo A-Z, la anadia y
# el build caia con E2004)
r = call('delphi_edit', {'path': UTEXTO, 'adduses': 'U\u00e1RBOLNUEVO', 'section': 'implementation'})
u = rd(UTEXTO)
check('I3f adduses de la misma unit con otra caja del acento: no se duplica',
      u.casefold().count(NUEVO.casefold()) == 1 and not mc.fallo(r), r[:300] + ' | ' + u[-300:])

# ---- I4 delphi_search wholeword ----
j = J(call('delphi_search', {'root': PRJ, 'query': 'Tama', 'wholeword': True}))
check('I4 search wholeword: "Tama" no es una palabra entera dentro de "%s"' % TAMANO,
      j.get('total') == 0, str(j)[:300])
j = J(call('delphi_search', {'root': PRJ, 'query': TAMANO, 'wholeword': True}))
check('I4b ...y el nombre entero si lo es', j.get('total', 0) >= 3, str(j)[:300])
# la mascara de fichero de delphi_search tambien admite letras de cualquier
# alfabeto: ahora hay units acentuadas (se negaba con ^[\w*?.\-]+$)
r = call('delphi_search', {'root': PRJ, 'query': 'unit', 'pattern': ARBOL + '*.pas'})
check('I4c search con una mascara acentuada (%s*.pas)' % ARBOL,
      not mc.fallo(r) and J(r).get('total', 0) >= 1, r[:300])

# ---- I5 check-binding con un manejador acentuado ----
FP = os.path.join(PRJ, 'UBoton.pas')
FD = os.path.join(PRJ, 'UBoton.dfm')
open(FP, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UBoton;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, System.Classes;

type
  TFormBoton = class(TForm)
    btnUno: TButton;
    btnDos: TButton;
    procedure %(b)sClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TFormBoton.%(b)sClick(Sender: TObject);
begin
end;

end.
""" % {'b': BOTON})
open(FD, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""object FormBoton: TFormBoton
  object btnUno: TButton
    OnClick = %(b)sClick
  end
  object btnDos: TButton
    OnClick = %(b)sFalta
  end
end
""" % {'b': BOTON})
d = mc.como_json(call('delphi_designer', {'command': 'check-binding', 'path': FD}))
sin = ' '.join(d.get('eventsWithoutMethod', []))
check('I5 check-binding: el manejador acentuado que no existe se avisa (la linea no se leia)',
      BOTON + 'Falta' in sin, str(d)[:500])
check('I5b ...y el que existe no (su nombre se leia hasta el acento)',
      d.get('form') == 'FormBoton' and BOTON + 'Click' not in sin and
      BOTON + 'Click' not in ' '.join(d.get('eventsWithMethodNotPublished', [])),
      str(d)[:500])

# ---- I6 el eco de una tanda que se deshace ----
L = BASE[0].upper()
TXT = os.path.join(PRJ, 'notas.txt')
open(TXT, 'w', encoding='utf-8', newline='\n').write(
    "R := '[^\\s:]' + '%s:\\datos';\nS := '%s:\\otro';\n" % (L, L))
antes = open(TXT, 'rb').read()
r = call('delphi_textedit', {'path': TXT, 'edits': json.dumps([
    {'fragment': '%s:\\datos' % L, 'new': '%s:\\DATOS' % L, 'atline': 1},
    {'fragment': 'no-esta', 'new': 'x', 'atline': 2}])})
check('I6 tanda con una entrada mala: ROLLBACK y el fichero intacto',
      mc.abre(r, 'SR_PATCH_EDITS_ROLLED_FMT') and open(TXT, 'rb').read() == antes, r[:400])
check('I6b la linea releida del disco viene TAL CUAL y en una linea suya (era "[^\\srv0:]" y la letra virtual)',
      re.search(r"(?m)^\s+1\|R := '\[\^\\s:\]' \+ '%s:\\DATOS';" % L, r) is not None, r[:600])
check('I6c la cita del disco de la entrada que fallo, tambien tal cual',
      "2|S := '%s:\\otro';" % L in r, r[:800])
check('I6d lo que tecleo el agente (el fragmento, no la linea del disco) sale enmascarado',
      ('OK: ' + mc.virtual('%s:\\datos' % L) + '  ->') in r and ('OK: %s:' % L) not in r, r[:600])

# ---- I7 la PUERTA rechaza los controles sin citar rutas ni raices ----
# una ruta con un salto y '1|' dentro hacia que el filtro de las tools de eco
# tomara su segunda linea por una cita del disco: las raices del servidor
# salian con su letra real (revision del 4-oct-2026; tambien en la 1.12.1)
for _p in ('a\n1|', 'a\nb  ->  1|'):
    r = call('delphi_read', {'path': _p})
    check('I7 la negativa de la puerta con %r no cita ninguna raiz' % _p,
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_CONTROL_EN_RUTA_FMT')
          and mc.virtual(BASE) not in r and BASE not in r, r[:400])

# ---- I8 la cabecera que ABRE una clase (PATRON_ABRE_CLASE) ----
# insert=metodo tomaba la primera 'TFoo = class': una declaracion adelantada,
# y escribia la declaracion DENTRO de un metodo del implementation (medido el
# 4-oct-2026: E2070, y la tool decia "las dos mitades")
r = call('delphi_create', {'kind': 'unit', 'name': 'UAdelantada', 'project': DPR})
UADE = os.path.join(PRJ, 'UAdelantada.pas')
open(UADE, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UAdelantada;

interface

type
  TFoo = class;
  TFooClass = class of TFoo;
  TBar = class
  public
    procedure B;
  end;
  TFoo = class
  public
    procedure F;
  end;

implementation

procedure TBar.B;
begin
end;

procedure TFoo.F;
begin
end;

end.
""")
r = call('delphi_edit', {'path': UADE, 'insert': 'metodo', 'inclass': 'TFoo', 'code': 'procedure Nuevo;\nbegin\nend;'})
u = rd(UADE)
clase = u[u.index('  TFoo = class\r\n'):u.index('implementation')]
check('I8 insert=metodo con una declaracion adelantada: la declaracion va en la clase de verdad',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure Nuevo;' in clase and
      'procedure TFoo.Nuevo;' in u and u.count('procedure Nuevo;') == 1, r[:300] + ' | ' + u)
ok, err = build_ok(DPROJ)
check('I8b ...y el proyecto COMPILA', ok, err)
# una clase SIN cuerpo no tiene donde poner el metodo: se dice (se escribia
# dentro de un metodo de la clase siguiente, E2070; medido el 4-oct-2026)
_txt = rd(UADE)  # leido ANTES: open(..., 'w') trunca el fichero
open(UADE, 'w', encoding='utf-8-sig', newline='').write(
    _txt.replace('  TBar = class\r\n', '  EMio = class(TObject);\r\n  TBar = class\r\n', 1))
antes = open(UADE, 'rb').read()
r = call('delphi_edit', {'path': UADE, 'insert': 'metodo', 'inclass': 'EMio', 'code': 'procedure Otro;\nbegin\nend;'})
check('I8c insert=metodo en una clase sin cuerpo: rechazado y nada escrito',
      mc.rechazado(r) and mc.es(r, 'SR_EDIT_CLASE_SIN_CUERPO_FMT') and open(UADE, 'rb').read() == antes, r[:300])

# ---- I9 un nombre que ACABA en un acento, junto a otro que lo contiene ----
# el '\b' viejo casaba dentro de Caf\u00e9x (la e acentuada no es \w) y no en Caf\u00e9:
# el rename cambiaba el que no era
CAFE = 'Caf\u00e9'
r = call('delphi_create', {'kind': 'unit', 'name': 'UCafe', 'project': DPR})
UCAFE = os.path.join(PRJ, 'UCafe.pas')
open(UCAFE, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UCafe;

interface

function %(c)s: Integer;
function %(c)sx: Integer;
function Ambos: Integer;

implementation

function %(c)s: Integer;
begin
  Result := 1;
end;

function %(c)sx: Integer;
begin
  Result := 2;
end;

function Ambos: Integer;
begin
  Result := %(c)sx + %(c)s;
end;

end.
""" % {'c': CAFE})
lineas = rd(UCAFE).replace('\r\n', '\n').split('\n')
li = lineas.index('function %s: Integer;' % CAFE)
j = J(call('delphi_rename_symbol', {'path': UCAFE, 'line': li, 'character': 9, 'newname': 'T\u00e9',
                                    'mode': 'apply'}))
u = rd(UCAFE)
check('I9 rename de un nombre que acaba en acento: cambia el suyo y deja %sx' % CAFE,
      j.get('applied') is True and u.count(CAFE + 'x') == 3 and 'Result := %sx + T\u00e9;' % CAFE in u and
      'function T\u00e9: Integer;' in u, str(j)[:300] + ' | ' + u[-300:])
ok, err = build_ok(DPROJ)
check('I9b ...y el proyecto COMPILA', ok, err)

# ---- I10 el nombre de una unit NUEVA: la regla entera (Lsp.Scaffold) ----
# createunit solo miraba que fuera un identificador: Begin.pas pasaba
r = call('delphi_edit', {'path': os.path.join(PRJ, 'Begin.pas'), 'createunit': True})
check('I10 createunit de una unit que se llama como una palabra reservada: rechazado',
      mc.rechazado(r) and mc.es(r, 'SR_CREATE_RESERVED_FMT') and not os.path.exists(os.path.join(PRJ, 'Begin.pas')),
      r[:300])

# ---- I11 el resumen de una carpeta: lo de detras de una adelantada no es suyo ----
DIG = os.path.join(BASE, 'Dig')
os.makedirs(DIG, exist_ok=True)
open(os.path.join(DIG, 'UDig.pas'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    'unit UDig;\n\ninterface\n\ntype\n  TCosa = class;\n  TProc = procedure of object;\n'
    '  TCosa = class\n  public\n    procedure Hola;\n  end;\n\nimplementation\n\n'
    'procedure TCosa.Hola;\nbegin\nend;\n\nend.\n')
d = mc.como_json(call('delphi_symbols', {'path': DIG}))
decl = {x.get('decl'): x.get('of', '') for u_ in d.get('units', []) for x in u_.get('declares', [])}
check('I11 symbols de carpeta: un tipo detras de una adelantada no sale como de esa clase',
      decl.get('TProc = procedure of object;', 'falta') == '' and decl.get('procedure Hola;') == 'TCosa', str(decl)[:400])

# ---- I12 lo que dcc lee como identificador: tambien el punto volado ----
# medido el 4-oct-2026: dcc compila Col\u00b7lecci\u00f3 (y cualquier
# caracter no ASCII del plano basico); la regla \p{L} lo partia en dos
COL = 'Col\u00b7lecci\u00f3'
r = call('delphi_create', {'kind': 'unit', 'name': 'UPunto', 'project': DPR})
UPUNTO = os.path.join(PRJ, 'UPunto.pas')
open(UPUNTO, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UPunto;

interface

function Coleccion: Integer;
function Usa: Integer;

implementation

function Coleccion: Integer;
begin
  Result := 1;
end;

function Usa: Integer;
begin
  Result := Coleccion + 1;
end;

end.
""")
lineas = rd(UPUNTO).replace('\r\n', '\n').split('\n')
li = lineas.index('function Coleccion: Integer;')
j = J(call('delphi_rename_symbol', {'path': UPUNTO, 'line': li, 'character': 10, 'newname': COL,
                                    'mode': 'apply'}))
u = rd(UPUNTO)
check('I12 rename a un nombre con el punto volado: aceptado y aplicado (dcc lo compila)',
      j.get('applied') is True and u.count(COL) == 3, str(j)[:300] + ' | ' + u[-200:])
ok, err = build_ok(DPROJ)
check('I12b ...y el proyecto COMPILA', ok, err)
# (en su propio fichero: medido que, en el UPunto del rename, el check pasaba
# tambien con la regla vieja si el rename no habia escrito el nombre)
open(os.path.join(PRJ, 'Punto.txt'), 'w', encoding='utf-8').write('x := %s;\n' % COL)
j = J(call('delphi_search', {'root': PRJ, 'query': 'Col', 'wholeword': True, 'pattern': 'Punto.txt'}))
check('I12c search wholeword: "Col" no es una palabra entera dentro de %s' % COL,
      j.get('total') == 0, str(j)[:300])

srv.cierra()
mc.fin('identificadores battery')
