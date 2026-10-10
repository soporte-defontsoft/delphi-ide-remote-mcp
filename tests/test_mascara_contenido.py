"""E2E battery - el CONTENIDO de un fichero no se enmascara (4-oct-2026).

The server's drive letters travel as virtual units (srvd:), and the outbound
filter rewrites them in every textual result - except the CONTENT of a
file, which must reach the agent verbatim: an anchor copied from it has to
match the disk. delphi_read, delphi_search and the echo of delphi_edit were
exempt; the tools below masked the content too, so a line 'R := 'C:\\datos';'
came back as 'srvc:\\datos' and an anchor copied from it never matched:

  M1  delphi_symbols of a folder: the declarations (decl, uses) verbatim,
      the paths masked
  M2  delphi_symbols of a file (mode=full): the declarations verbatim
  M3  delphi_hover: the code block verbatim, the link masked
  M4  delphi_references: the line of each use (text, anchor) verbatim, the
      paths masked
  M5  delphi_rename_symbol preview: the line of each change verbatim
  M6  delphi_changeset: the real line of a staged fragment that is not on
      its line (EDIT-007, CitaDeLinea) verbatim, the path masked (the
      changeset is not an echo tool: the whole refusal was masked)

And the filter no longer guesses by the shape of a line: only the citations
the tool composed in THAT call (Lsp.Mascara.CitaDeLinea) pass (the unit test
LaFilaDeUnaTandaDejaElDiscoComoEsta measures the line that only looks like
one). Every check was seen red against the 1.12.1 exe.

And the way IN (B-9, 10-oct-2026): what is written INSIDE a file is content
(the [Contenido] mark) and the entry gate does not expand its virtual unit;
value / props / state of delphi_designer are the declared exception - the
designer expands the TEXT of each value, because a path literal in a form
has to work at run time (it was a list of names, PARAMS_CON_CONTENIDO):

  M7   delphi_textedit: a new that starts with the virtual unit, verbatim
  M8   vault_patch: old_text / new_text verbatim (expanded: old_text did not
       match its note)
  M9   delphi_report: body, the alias of message, verbatim (it was expanded
       while message was not)
  M10  delphi_designer set: a quoted value, a value inside props and a bare
       one land in the .dfm as the REAL path (quoted or in props it landed
       as srvX:)

M8, M9, M10 and M10b were seen red against 112a311; M7 and M10c against a
mutant without the mark of textedit's new and without the designer's
expansion.

Usage:  python tests/test_mascara_contenido.py [path-to-DelphiLspMcp.exe]
"""
import os
import re
import glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('mascara_contenido')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# un vault, fuera de la jaula como siempre (M8)
VAULT = mc.carpeta('mascara_contenido_vault')
open(os.path.join(VAULT, 'AGENTS-VAULT.md'), 'w', encoding='utf-8').write('# Reglas\n')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_VAULT_PATH': VAULT,
                                'DELPHI_MCP_VAULT_READONLY': '0'}), nombre='mascara', t=300)
call = srv.call
J = mc.como_json
REAL = BASE[0].upper() + ':\\'           # la letra REAL de la raiz de la bateria
VIRTUAL = mc.virtual(BASE[0].upper() + ':') + '\\'

print('== mascara-contenido battery ==')
PRJ = os.path.join(BASE, 'P')
DPR = os.path.join(PRJ, 'P.dpr')
r = call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': PRJ})
assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r
call('delphi_create', {'kind': 'unit', 'name': 'URuta', 'project': DPR})
U = os.path.join(PRJ, 'URuta.pas')
LINEA_RUTA = "  RUTA = '" + REAL + "datos';"
SRC = ("unit URuta;\n\ninterface\n\nconst\n" + LINEA_RUTA + "\n\nfunction Lee: string;\n\n"
       "implementation\n\nfunction Lee: string;\nbegin\n  Result := RUTA + '" + REAL + "otro';\nend;\n\nend.\n")
open(U, 'w', encoding='utf-8-sig', newline='\r\n').write(SRC)
ok, err = mc.build_ok(call, os.path.join(PRJ, 'P.dproj'))
assert ok, err
lineas = SRC.split('\n')
L_RUTA = lineas.index(LINEA_RUTA)
L_USO = next(i for i, l in enumerate(lineas) if 'Result := RUTA' in l)


def ruta_enmascarada(t):
    """las rutas de la respuesta van con la unidad virtual, y la del proyecto
    no sale con la letra real"""
    return VIRTUAL in t and (BASE + '\\') not in t and BASE.replace('\\', '\\\\') not in t


# ---- M1 / M2: symbols ----
r = call('delphi_symbols', {'path': PRJ})
d = J(r)
decls = [x.get('decl', '') for u in mc.ficheros(d, 'units') for x in u.get('declares', [])]
check('M1 symbols de carpeta: la declaracion TAL CUAL (con la letra real) y las rutas enmascaradas',
      ("RUTA = '" + REAL + "datos';") in decls and ruta_enmascarada(r), str(decls)[:300] + ' | ' + r[:300])
r = call('delphi_symbols', {'path': U, 'mode': 'full'})
check('M2 symbols de un fichero (full): la declaracion TAL CUAL',
      ("RUTA = '" + REAL.replace('\\', '\\\\') + "datos';") in r and VIRTUAL.replace('\\', '\\\\') + 'datos' not in r,
      r[:400])

# ---- M3: hover ----
r = call('delphi_hover', {'path': U, 'line': L_RUTA, 'character': 4})
codigo = r[r.find('```'):r.rfind('```')] if '```' in r else ''
check('M3 hover: el bloque de codigo TAL CUAL, el enlace enmascarado',
      (REAL + 'datos') in codigo and (VIRTUAL + 'datos') not in r and
      re.search(r'file:///%s%%3A' % BASE[0], r, re.I) is None, r[:400])

# ---- M4: references ----
d = J(call('delphi_references', {'path': U, 'line': L_USO, 'character': lineas[L_USO].index('RUTA') + 1}))
conf = mc.aciertos(d, 'confirmed')
textos = [c.get('text', '') for c in conf]  # la linea tal cual (1.15.0: text, sin anchor)
check('M4 references: la linea de cada uso TAL CUAL (un ancla) y las rutas enmascaradas',
      LINEA_RUTA in textos and all(VIRTUAL in c.get('path', '') for c in conf) and conf,
      str(d)[:500])

# ---- M5: rename preview ----
d = J(call('delphi_rename_symbol', {'path': U, 'line': L_RUTA, 'character': 3, 'newname': 'RUTA2'}))
chg = mc.aciertos(d, 'changes')
anclas = [c.get('text', '') for c in chg]
check('M5 rename preview: la linea de cada cambio TAL CUAL',
      LINEA_RUTA in anclas and all(VIRTUAL in c.get('path', '') for c in chg) and chg,
      str(d)[:500])

# ---- M6: la pista de changeset ----
cs = call('delphi_changeset', {'command': 'begin'})
cid = re.search(r'CHANGESET (\S+) opened', cs).group(1)
# un fragmento se resuelve al apilarlo: si no esta en su linea, la negativa
# cita la linea real (el preview de un 'old' que no casa solo dice NOT FOUND)
r = call('delphi_changeset', {'command': 'stage', 'id': cid, 'kind': 'edit', 'path': U,
                              'fragment': 'no-esta', 'new': 'x', 'atline': L_RUTA + 1})
check('M6 changeset: la linea real de la negativa TAL CUAL y la ruta enmascarada',
      mc.rechazado(r) and re.search(r'(?m)^\s+%d\|%s$' % (L_RUTA + 1, re.escape(LINEA_RUTA)), r) is not None and
      BASE not in r, r[:600])
call('delphi_changeset', {'command': 'rollback', 'id': cid})

# ---- M7..M10: la ENTRADA (B-9) ----
TXT = os.path.join(PRJ, 'notas.txt')
open(TXT, 'w', encoding='utf-8', newline='\n').write('uno\n')
r = call('delphi_textedit', {'path': TXT, 'old': 'uno', 'new': VIRTUAL + 'datos'})
t = open(TXT, encoding='utf-8').read()
check('M7 textedit: un new que empieza por la unidad virtual se escribe TAL CUAL (es contenido)',
      (VIRTUAL + 'datos') in t and (REAL + 'datos') not in t, r[:200] + ' | ' + t)

NOTA = os.path.join(VAULT, 'nota.md')
open(NOTA, 'w', encoding='utf-8', newline='\n').write('# Nota\n\nruta: ' + VIRTUAL + 'vieja\n')
r = call('vault_patch', {'path': 'nota.md', 'old_text': VIRTUAL + 'vieja', 'new_text': VIRTUAL + 'nueva'})
t = open(NOTA, encoding='utf-8').read()
check('M8 vault_patch: old_text y new_text con la unidad virtual casan con la nota y se escriben TAL CUAL',
      ('ruta: ' + VIRTUAL + 'nueva') in t, r[:300] + ' | ' + t)

r = call('delphi_report', {'body': VIRTUAL + 'por el apodo', 'title': 'b9'})
informes = [open(f, encoding='utf-8', errors='replace').read()
            for f in glob.glob(os.path.join(os.path.dirname(EXE), 'reports', '**', '*.md'), recursive=True)]
check('M9 report: body, el apodo de message, es contenido: su unidad virtual se guarda TAL CUAL',
      any((VIRTUAL + 'por el apodo') in i for i in informes), r[:200] + ' | ' + str(informes)[:300])

DFM = os.path.join(PRJ, 'UHint.dfm')
open(os.path.join(PRJ, 'UHint.pas'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    'unit UHint;\n\ninterface\n\nuses\n  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;\n\n'
    'type\n  TFormHint = class(TForm)\n    Button1: TButton;\n  end;\n\nvar\n  FormHint: TFormHint;\n\n'
    'implementation\n\n{$R *.dfm}\n\nend.\n')
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(
    "object FormHint: TFormHint\n  Left = 0\n  Top = 0\n  Caption = 'Hint'\n  ClientHeight = 120\n"
    "  ClientWidth = 240\n  TextHeight = 15\n  object Button1: TButton\n    Left = 16\n    Top = 16\n"
    "    Width = 120\n    Height = 25\n    Caption = 'Button1'\n    TabOrder = 0\n  end\nend\n")


def dfm():
    return open(DFM, encoding='utf-8', errors='replace').read()


r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'Button1', 'prop': 'Hint',
                             'value': "'" + VIRTUAL + "pista.txt'"})
check("M10 designer set value='srvX:...' entre comillas: el .dfm lleva la ruta REAL (la excepcion declarada)",
      ("Hint = '" + REAL + "pista.txt'") in dfm(), r[:300] + ' | ' + dfm())
r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'Button1',
                             'props': "Hint='" + VIRTUAL + "otra.txt';Caption=Boton"})
check('M10b ...y dentro de props, valor a valor',
      ("Hint = '" + REAL + "otra.txt'") in dfm() and "Caption = 'Boton'" in dfm(), r[:300] + ' | ' + dfm())
r = call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'Button1', 'prop': 'Hint',
                             'value': VIRTUAL + 'tercera.txt'})
check('M10c ...y sin comillas, como antes (ya no la expande la puerta: la expande el disenador)',
      ("Hint = '" + REAL + "tercera.txt'") in dfm(), r[:300] + ' | ' + dfm())

srv.cierra()
mc.fin('mascara-contenido battery')
