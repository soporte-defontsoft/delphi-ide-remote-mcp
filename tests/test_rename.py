"""E2E battery - delphi_rename_symbol (preview and apply since 1.0.17), and
since 1.7.8 the engine's freshness across files: a unit edited on disk is
refreshed in the engine before any question, from whichever file it comes.

The adopted rule as tests: applicable=true ONLY with zero unverified
references, no designer hits, no string-literal hits, no collision, and a
definition inside the workspace. Everything else = applicable=false with
the reasons, and NOTHING written.

Usage:  python tests/test_rename.py [path-to-DelphiLspMcp.exe]
"""
import json, os, hashlib
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('rename')
EXE = mc.copia_exe(BASE)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='rn', t=300)
call = srv.call
def J(t):
    try: return json.loads(t)
    except Exception: return {}
def sha_all():
    out = {}
    for root, _, fs in os.walk(BASE):
        for f in fs:
            p = os.path.join(root, f)
            if p.endswith(('.pas', '.dpr', '.dfm')):
                out[p] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    return out

# ---- fixture project ----
PRJ = os.path.join(BASE, 'Ren')
r = call('delphi_create', {'kind': 'project-console', 'name': 'Ren', 'dir': PRJ})
assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r
call('delphi_create', {'kind': 'unit', 'name': 'UCalc', 'project': os.path.join(PRJ, 'Ren.dpr')})
UCALC = os.path.join(PRJ, 'UCalc.pas')
open(UCALC, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UCalc;

interface

function Doble(A: Integer): Integer;
function ConCadena(A: Integer): Integer;
function Existente(A: Integer): Integer;

implementation

function Doble(A: Integer): Integer;
begin
  { it's what Doble's for }
  Result := A * 2;
end;

function ConCadena(A: Integer): Integer;
begin
  // la cadena menciona la funcion por nombre, como un FindComponent
  if 'llama a ConCadena' <> '' then;
  Result := A;
end;

function Existente(A: Integer): Integer;
begin
  Result := Doble(A) + 1;
end;

end.
""")
DPR = os.path.join(PRJ, 'Ren.dpr')
s = open(DPR, encoding='utf-8-sig').read()
open(DPR, 'w', encoding='utf-8-sig', newline='').write(s.replace('begin', 'begin\n  Writeln(Doble(3));', 1))

BEFORE = sha_all()

# UCalc 0-based: line 4 'function Doble(...)' -> col 9
# 1. happy path: applicable
r = call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Duplica'})
j = J(r)
check('preview aplicable (Doble -> Duplica)', j.get('applicable') is True, r[:400])
check('ocurrencias >= 2 y ficheros >= 2', j.get('occurrences', 0) >= 2 and j.get('files', 0) >= 2, r[:300])
check('changes con path/line/text', bool(j.get('changes')) and all('path' in c and 'line' in c for c in j.get('changes', [])), str(j.get('changes'))[:250])
# field 2026-08-25: 'changes' omitia la CABECERA DE LA IMPLEMENTACION (la
# linea que el propio campo definition señala), y un agente que aplicara solo
# lo listado rompia la unit (E2065 Unsatisfied forward declaration)
_def = j.get('definition') or {}
_chg = j.get('changes') or []
check('changes INCLUYE la linea de la definicion',
      any(c.get('line') == _def.get('line') and c.get('path') == _def.get('path') for c in _chg),
      'definition=%s changes=%s' % (_def, [(c.get('path','')[-20:], c.get('line')) for c in _chg]))
check('cero sin confirmar', j.get('unverified') == 0, r[:200])
# el '{ it''s what Doble''s for }' del fixture: las comillas de dentro de un
# comentario no abren una cadena (1.10.0, el lexico de la casa; antes "'s
# what Doble'" contaba como un literal que lo nombraba y bloqueaba)
check('un apostrofo dentro de un comentario no es un literal que bloquee',
      not any(mc.es(b, 'SR_RENAME_STRINGS_FMT') for b in j.get('blockers', [])), str(j.get('blockers'))[:300])

# 2. invalid ident / reserved
r = call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': '9mal'})
j = J(r)
# y es un FALLO (INVALID_PARAM en "error"): salia como un exito con blockers
check('identificador invalido bloquea', j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_BAD_IDENT_FMT') for b in j.get('blockers', [])) and mc.resultado(r) == 'INVALID_PARAM', str(j)[:250])
r = call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'begin'})
j = J(r)
check('palabra reservada bloquea', j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_RESERVED_FMT') for b in j.get('blockers', [])) and mc.resultado(r) == 'INVALID_PARAM', str(j)[:250])

# 3. string literal hit: renaming ConCadena
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 5, 'character': 9, 'newname': 'OtraCosa'}))
check('mencion en literal de cadena bloquea', j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_STRINGS_FMT') for b in j.get('blockers', [])), str(j)[:400])

# 4. collision: rename Doble -> Existente (word already there)
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Existente'}))
check('colision con nombre existente bloquea', j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_COLLISION_FMT') for b in j.get('blockers', [])), str(j)[:300])

# 5. designer hit: a dfm mentioning the identifier
DFM = os.path.join(PRJ, 'UCalc.dfm')
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(
    "object F: TF\n  OnClick = Doble\nend\n")
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Duplica'}))
check('mencion en designer bloquea', j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_DESIGNER_FMT') for b in j.get('blockers', [])), str(j)[:400])
os.remove(DFM)

# 6. RTL symbol refused (definition outside the jail): IntToStr usage
s = open(UCALC, encoding='utf-8-sig').read().replace(
    'uses', 'uses', 1)
open(UCALC, 'w', encoding='utf-8-sig', newline='').write(s.replace(
    "function Existente(A: Integer): Integer;\nbegin\n  Result := Doble(A) + 1;",
    "function Existente(A: Integer): Integer;\nbegin\n  Result := Doble(A) + Length(System.SysUtils.IntToStr(A));", 1).replace(
    "implementation", "implementation\n\nuses System.SysUtils;", 1))
# find IntToStr position dynamically
lines = open(UCALC, encoding='utf-8-sig').read().replace('\r\n', '\n').split('\n')
li = next(i for i, l in enumerate(lines) if 'IntToStr' in l)
co = lines[li].index('IntToStr') + 2
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': li, 'character': co, 'newname': 'MiIntToStr'}))
check('simbolo de la RTL bloqueado (definicion fuera del workspace)',
      j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_LIBRARY') for b in j.get('blockers', [])), str(j)[:400])

# 7. mode=apply on a NON applicable rename: nothing written (ConCadena has a
# string-literal hit). Until 1.0.17 apply was refused outright.
MID = sha_all()
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 5, 'character': 9, 'newname': 'OtraCosa', 'mode': 'apply'}))
check('apply sobre un rename NO aplicable: applied=false y los blockers',
      j.get('applied') is False and j.get('applicable') is False and j.get('blockers'), str(j)[:300])
check('...y no escribio NADA', sha_all() == MID, 'algo cambio en el disco')
# note: fixture edits in step 6 changed UCalc deliberately; verify the TOOL wrote nothing so far
AFTER = sha_all()
tool_touched = [p for p in BEFORE if p in AFTER and BEFORE[p] != AFTER[p] and 'UCalc.pas' not in p]
check('la tool no escribio NADA hasta aqui (solo el fixture cambio a proposito)', not tool_touched, tool_touched)

# 8. mode=apply on an applicable rename: Doble -> Duplica lands in BOTH files
# (UCalc.pas: declaration, implementation header, a call; Ren.dpr: a call),
# through the changeset engine, and the project still builds.
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Duplica', 'mode': 'apply'}))
check('apply aplicable: applied=true con el commit del changeset',
      j.get('applied') is True and mc.abre(j.get('commit', ''), 'SN_CHANGESET_COMMITTED_FMT'), str(j)[:400])
check('apply: una edicion por linea tocada (4: decl, impl, uso, dpr)', j.get('editsApplied') == 4, j.get('editsApplied'))
import re as _re
uc = open(UCALC, encoding='utf-8-sig').read(); dp = open(DPR, encoding='utf-8-sig').read()
check('apply: Doble ya no existe como palabra en UCalc.pas ni en Ren.dpr',
      not _re.search(r'Doble', uc) and not _re.search(r'Doble', dp), (uc[:200], dp[:200]))
check('apply: Duplica esta en la declaracion, la implementacion y los dos usos',
      uc.count('Duplica') == 3 and dp.count('Duplica') == 1, (uc.count('Duplica'), dp.count('Duplica')))
check('apply: la copia previa esta en __delphi-patch',
      os.path.isdir(os.path.join(PRJ, '__delphi-patch')), os.listdir(PRJ))
r = call('delphi_build', {'project': os.path.join(PRJ, 'Ren.dproj')}, t=600)
check('apply: el proyecto COMPILA despues del rename', '"success":true' in r.replace(' ', ''), r[:300])
# the note says to rebuild, and the answer never floods: changes is capped in the answer
check('apply: la nota manda recompilar', 'delphi_build' in j.get('note', ''), j.get('note'))

# 9. La unidad cambia en DISCO mientras el motor la tiene abierta y se
# pregunta desde OTRO fichero (Hermes, 2026-09-30, RENAME-017). El motor no
# vuelve a mirar el disco de un documento abierto, y el servidor solo le
# mandaba el fichero por el que se preguntaba: medido, definition desde el
# .dpr contestaba la linea VIEJA mientras nadie preguntara DENTRO de la
# unidad (25 s, sin tope), y el preview resolvia el destino con la unidad
# vieja y validaba las ocurrencias con la nueva: negado como parecido, y
# aplicable al segundo intento sin tocar nada. Hoy el servidor pone al dia
# TODOS los documentos abiertos de ese motor antes de contestar.
# Primero UNA pregunta dentro de UCalc: la deja abierta en el motor CON el
# texto de despues del rename del punto 8 (segundo revisor de la 1.7.8: sin
# esto el motor la tenia con 'Doble', y el mutante fallaba por 'Duplica sin
# declarar', no por la linea vieja que se quiere medir). Luego una linea mas
# encima de la implementacion de Duplica, escrita a pelo, y se pregunta SOLO
# desde el .dpr.
def lineas(p):
    return open(p, encoding='utf-8-sig').read().replace('\r\n', '\n').split('\n')
ls_uc = lineas(UCALC)
decl = next(i for i, l in enumerate(ls_uc) if l.startswith('function Duplica('))
impl0 = [i for i, l in enumerate(ls_uc) if l.startswith('function Duplica(')][1]
j = J(call('delphi_definition', {'path': UCALC, 'line': decl, 'character': 11}))
check('UCalc abierta en el motor y al dia (definition dentro de ella, decl -> impl)',
      ((j.get('range') or {}).get('start') or {}).get('line') == impl0, (str(j)[:200], impl0))
# la edicion a pelo: una linea mas encima de la implementacion, la FIRMA con un
# parametro mas (S3: hover desde el .dpr) y una llamada mas en el .dpr (S4:
# references desde el .dpr)
uc = open(UCALC, encoding='utf-8-sig').read()
open(UCALC, 'w', encoding='utf-8-sig', newline='').write(uc.replace(
    'implementation\n', 'implementation\n// una linea mas: la implementacion baja una\n', 1).replace(
    'function Duplica(A: Integer): Integer;', 'function Duplica(A: Integer; B: Integer = 0): Integer;'))
dp = open(DPR, encoding='utf-8-sig').read()
open(DPR, 'w', encoding='utf-8-sig', newline='').write(dp.replace(
    'Writeln(Duplica(3));', 'Writeln(Duplica(3));\n  Writeln(Duplica(4));', 1))
ls_uc, ls_dp = lineas(UCALC), lineas(DPR)
impl = [i for i, l in enumerate(ls_uc) if l.startswith('function Duplica(')][1]
ld = next(i for i, l in enumerate(ls_dp) if 'Duplica(3)' in l)
cd = ls_dp[ld].index('Duplica') + 2
# El ORDEN importa (segundo revisor de la 1.7.9): hover y definition desde el
# .dpr no abren UCalc, asi que son las que miden el refresco; el preview la
# refresca el solo al validar sus candidatos, y lo que venga detras ya la
# encuentra al dia sin necesidad del arreglo. Por eso hover va LO PRIMERO, y
# references, que va detras del preview, solo cuenta.
h = call('delphi_hover', {'path': DPR, 'line': ld, 'character': cd})
check('unidad editada en disco: hover desde el .dpr, la PRIMERA pregunta, ve la firma de HOY (B: Integer)',
      'B: Integer' in h, h[:200])
j = J(call('delphi_definition', {'path': DPR, 'line': ld, 'character': cd}))
check('unidad editada en disco: definition desde el .dpr contesta la linea de HOY, no la que tenia el motor',
      ((j.get('range') or {}).get('start') or {}).get('line') == impl and str(j.get('path', '')).endswith('UCalc.pas'),
      (str(j)[:200], impl))
j = J(call('delphi_rename_symbol', {'path': DPR, 'line': ld, 'character': cd, 'newname': 'Triplica'}))
check('unidad editada en disco: el PRIMER preview desde el .dpr es aplicable (era RENAME-017 hasta la 1.7.7)',
      j.get('applicable') is True and not j.get('blockers') and (j.get('definition') or {}).get('line') == impl + 1,
      str(j)[:400])
j = J(call('delphi_references', {'path': DPR, 'line': ld, 'character': cd}))
check('references desde el .dpr cuenta las cinco (decl, impl, Existente y las dos llamadas del .dpr)',
      len(j.get('confirmed') or []) == 5 and not j.get('unverified'), str(j)[:300])

# 10. El motor del LINTER cruza unidades igual: con UCalc abierta en el (un
# diagnostics), una funcion NUEVA en UCalc y su llamada en el .dpr, escritas
# a pelo, y el diagnostics del .dpr no puede inventarse un E2003 con la
# UCalc que el linter tenia.
d0 = J(call('delphi_diagnostics', {'path': UCALC}, t=120))
check('linter: UCalc limpia antes de tocar nada', d0.get('errors') == 0, str(d0)[:200])
uc = open(UCALC, encoding='utf-8-sig').read()
uc = uc.replace('function ConCadena(A: Integer): Integer;\n',
                'function ConCadena(A: Integer): Integer;\nfunction Cuadruple(A: Integer): Integer;\n', 1)
uc = uc.replace('\nend.', '\nfunction Cuadruple(A: Integer): Integer;\nbegin\n  Result := A * 4;\nend;\n\nend.', 1)
open(UCALC, 'w', encoding='utf-8-sig', newline='').write(uc)
dp = open(DPR, encoding='utf-8-sig').read()
open(DPR, 'w', encoding='utf-8-sig', newline='').write(dp.replace(
    'Writeln(Duplica(3));', 'Writeln(Duplica(3));\n  Writeln(Cuadruple(3));', 1))
d1 = J(call('delphi_diagnostics', {'path': DPR}, t=120))
check('linter: el .dpr que llama a una funcion RECIEN escrita en UCalc no da E2003 (la UCalc del linter era la vieja)',
      d1.get('errors') == 0, str(d1)[:300])
# y el control: una llamada a algo que NO existe en ninguna parte si da UN
# error, o sea que el linter del .dpr mira de verdad a traves de las unidades
dp = open(DPR, encoding='utf-8-sig').read()
open(DPR, 'w', encoding='utf-8-sig', newline='').write(dp.replace(
    'Writeln(Cuadruple(3));', 'Writeln(Cuadruple(3));\n  Writeln(Quintuple(3));', 1))
d2 = J(call('delphi_diagnostics', {'path': DPR}, t=120))
check('linter (control): una funcion que no existe si da exactamente un E2003',
      d2.get('errors') == 1 and 'E2003' in str(d2.get('diagnostics')), str(d2)[:300])

# 11. FANTASMA: la unidad se BORRA del disco con el motor teniendola abierta
# (lo esta desde el punto 9). Hasta la 1.7.8 definition, hover y references
# desde el .dpr seguian apuntando a UCalc.pas:N, un fichero que no existia
# (medido 30-sep-2026). Hoy el refresco la cierra (didClose): el motor no
# tiene nada ahi; y si el fichero vuelve con otro texto, se abre de nuevo y
# contesta la linea de hoy.
def linea_de(j):
    return ((j.get('range') or {}).get('start') or {}).get('line')
def impl_hoy():
    ls = lineas(UCALC)
    return (next(i for i, l in enumerate(ls) if l.startswith('function Duplica(')),
            [i for i, l in enumerate(ls) if l.startswith('function Duplica(')][1])
# La precondicion y el control, medidos y no heredados de los puntos 9 y 10
# (segundo revisor de la 1.7.9): una pregunta DENTRO de UCalc la deja abierta
# en el motor, y desde el .dpr la pregunta SI resuelve hacia ella. Sin esto,
# un null despues de borrarla no dice nada.
decl, impl = impl_hoy()
j1 = J(call('delphi_definition', {'path': UCALC, 'line': decl, 'character': 11}))
j2 = J(call('delphi_definition', {'path': DPR, 'line': ld, 'character': cd}))
check('fantasma (control): antes de borrarla, UCalc abierta en el motor y definition desde el .dpr apunta a ella',
      linea_de(j1) == impl and linea_de(j2) == impl and str(j2.get('path', '')).endswith('UCalc.pas'),
      (str(j1)[:120], str(j2)[:120], impl))
uc_bytes = open(UCALC, 'rb').read()
os.remove(UCALC)
r = call('delphi_definition', {'path': DPR, 'line': ld, 'character': cd})
check('fantasma: borrada UCalc.pas, definition desde el .dpr contesta LSP-029 (no un fichero que no existe, ni otro fallo)',
      mc.abre(r, 'SN_LSP_NULL_NOTE'), r[:200])
r = call('delphi_references', {'path': DPR, 'line': ld, 'character': cd})
check('fantasma: y references desde el .dpr, LSP-003', mc.abre(r, 'SR_REFS_NO_DEFINITION_FMT'), r[:200])
vuelta = uc_bytes.replace(b'implementation\n', b'implementation\n// vuelta\n', 1)
assert vuelta != uc_bytes, 'la vuelta tiene que traer otro texto'
open(UCALC, 'wb').write(vuelta)
decl, impl = impl_hoy()
j = J(call('delphi_definition', {'path': DPR, 'line': ld, 'character': cd}))
check('fantasma: el fichero vuelve con otro texto y definition desde el .dpr da la linea de HOY',
      linea_de(j) == impl and str(j.get('path', '')).endswith('UCalc.pas'), (str(j)[:200], impl))
# reabierta (una pregunta dentro: el documento vuelve a nacer en la version 1)
# y editada otra vez: el motor tiene que aceptar ese cambio tras reabrir
j = J(call('delphi_definition', {'path': UCALC, 'line': decl, 'character': 11}))
open(UCALC, 'wb').write(vuelta.replace(b'// vuelta\n', b'// vuelta\n// y otra\n', 1))
decl2, impl2 = impl_hoy()
j2 = J(call('delphi_definition', {'path': DPR, 'line': ld, 'character': cd}))
check('fantasma: reabierta y editada otra vez, definition desde el .dpr da la linea de HOY',
      linea_de(j) == impl and impl2 == impl + 1 and linea_de(j2) == impl2, (str(j)[:120], str(j2)[:120], impl2))

# 12. Los comentarios no son el simbolo (revisor de codigo de la 1.10.0,
# medido con una sonda; la regla del rename de una unit: solo el codigo, David
# 2-oct-2026): el nombre NUEVO escrito solo en un comentario no es una
# colision, el '// see Foo' de la linea de una llamada no se renombra, un
# 'X.Foo' de un comentario no hace cualificada la cabecera, y la columna del
# cuerpo para ir a la declaracion se busca en su codigo (con '{ el cuerpo }'
# delante caia dentro del comentario). Los dos ultimos son GUARDAS: DelphiLSP
# contesta la declaracion desde cualquier columna de la cabecera, tambien
# con '{ TCosa }' delante (medido contra el exe de antes), y el aviso de
# cabecera cualificada solo sale cuando la definicion no vino entre las
# referencias, que aqui viene (verdes sin su arreglo en la mutacion)
COM = os.path.join(BASE, 'Com')
call('delphi_create', {'kind': 'project-console', 'name': 'PCom', 'dir': COM})
call('delphi_create', {'kind': 'unit', 'name': 'UCom', 'project': os.path.join(COM, 'PCom.dpr'),
                       'content': 'unit UCom;\r\n\r\ninterface\r\n\r\nprocedure Foo(A: Integer);\r\n\r\n'
                                  'implementation\r\n\r\n{ el cuerpo } procedure Foo(A: Integer); // no es X.Foo\r\n'
                                  'begin\r\nend;\r\n\r\n'
                                  'procedure Usa;\r\nbegin\r\n  Foo(1); // see Foo\r\n'
                                  '  // Bar es el nombre que tendra\r\nend;\r\n\r\nend.\r\n'})
UCOM = os.path.join(COM, 'UCom.pas')
j = J(call('delphi_definition', {'path': UCOM, 'line': 14, 'character': 3, 'kind': 'declaration'}))
check('declaration desde una llamada: llega a la de la interfaz aunque el cuerpo lleve un comentario delante',
      linea_de(j) == 4, str(j)[:300])
j = J(call('delphi_rename_symbol', {'path': UCOM, 'line': 4, 'character': 10, 'newname': 'Bar'}))
check('un X.Foo dentro de un comentario no hace cualificada la cabecera',
      not any(mc.es(w, 'SN_RENAME_QUALIFIED_FMT') for w in j.get('warnings', [])), str(j.get('warnings'))[:300])
check('el nombre nuevo escrito solo en un comentario no es una colision',
      j.get('applicable') is True and not any(mc.es(b, 'SR_RENAME_COLLISION_FMT') for b in j.get('blockers', [])),
      str(j)[:400])
j = J(call('delphi_rename_symbol', {'path': UCOM, 'line': 4, 'character': 10, 'newname': 'Bar', 'mode': 'apply'}))
uc = open(UCOM, encoding='utf-8-sig').read()
check('apply: el comentario de la linea de una llamada se queda como estaba',
      j.get('applied') is True and '  Bar(1); // see Foo\n' in uc.replace('\r\n', '\n')
      and uc.count('Bar(A: Integer);') == 2, uc)

srv.mata()
mc.fin('rename battery')
