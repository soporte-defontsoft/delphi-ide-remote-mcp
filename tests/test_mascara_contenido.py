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
the tool composed in THAT call (Lsp.Guard.CitaDeLinea) pass (the unit test
LaFilaDeUnaTandaDejaElDiscoComoEsta measures the line that only looks like
one). Every check was seen red against the 1.12.1 exe.

Usage:  python tests/test_mascara_contenido.py [path-to-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('mascara_contenido')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='mascara', t=300)
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
decls = [x.get('decl', '') for u in d.get('units', []) for x in u.get('declares', [])]
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
textos = [c.get('anchor', '') for c in d.get('confirmed', [])]
check('M4 references: la linea de cada uso TAL CUAL (un ancla) y las rutas enmascaradas',
      LINEA_RUTA in textos and all(VIRTUAL in c.get('path', '') for c in d.get('confirmed', [])) and d.get('confirmed'),
      str(d)[:500])

# ---- M5: rename preview ----
d = J(call('delphi_rename_symbol', {'path': U, 'line': L_RUTA, 'character': 3, 'newname': 'RUTA2'}))
anclas = [c.get('anchor', '') for c in d.get('changes', [])]
check('M5 rename preview: la linea de cada cambio TAL CUAL',
      LINEA_RUTA in anclas and all(VIRTUAL in c.get('path', '') for c in d.get('changes', [])) and d.get('changes'),
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

srv.cierra()
mc.fin('mascara-contenido battery')
