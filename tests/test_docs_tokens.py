"""E2E battery for v1.13.0 - what an agent pays in tokens (the token reviewer
of 4-oct-2026: ~27K fixed per session, tools/list 26.9K of it).

  T1  tools/list stays under its budget: 100.000 characters (105.592 with the
      1.12.1). Raising it is a decision, not an accident.
  T2  the fields of an "edits" entry - read from EDIT-012, the list the engine
      itself checks (Lsp.Patch.CAMPOS_DE_UNA_EDICION) - are ALL named in the
      long description (delphi_edit) and in the short one (delphi_textedit).
      The copy of 2026-09-20 drifted; the short one exists since 1.13.0.
  T3  delphi_search groups the hits by file: the path once per file.
  T4  delphi_read of a clean file says "audit=clean accents=N", without the
      six counters; of a file with mixed line endings, the counters.
  T5  delphi_edit's echo of a clean file: ONE audit line, no before/after;
      of a file with mixed line endings, before and after.
  T6  the backup path goes once: the second edit of the day says "already
      existed" without the path.
  T7  LIST-009 is one line.
  T8  delphi_symbols of a FOLDER stops at its size cap and NAMES what is left
      out (LSP-034); a small folder has no notShown.
  T9  delphi_symbols mode=full: no selectionRange equal to its range, no
      empty children, no empty detail.

Usage:  python tests/test_docs_tokens.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('docs_tokens')
EXE = mc.copia_exe(BASE)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='tokens', t=180)
call = srv.call

TOOLS = srv.request('tools/list', {})['result']['tools']
TAM = len(json.dumps(TOOLS, ensure_ascii=False))
check('T1 tools/list por debajo de su presupuesto (100.000 caracteres)', TAM < 100000, TAM)


def prop(tool, p):
    t = next((x for x in TOOLS if x['name'] == tool), {})
    return t.get('inputSchema', {}).get('properties', {}).get(p, {}).get('description', '')


# T2: los campos, de la boca del motor
TXT = os.path.join(BASE, 'campos.txt')
open(TXT, 'w', encoding='utf-8', newline='\n').write('uno\ndos\n')
r = call('delphi_textedit', {'path': TXT, 'edits': json.dumps([{'zzz': '1'}])})
m = re.search(r'fields of an edit are: (.+?) \(all', r)
campos = [c.strip() for c in m.group(1).split(',')] if m else []
check('T2 EDIT-012 dice los campos de una entrada', len(campos) >= 7, r[:300])
for tool in ('delphi_edit', 'delphi_textedit'):
    d = prop(tool, 'edits')
    faltan = [c for c in campos if not re.search(r'\b%s\b' % re.escape(c), d)]
    check('T2 %s.edits nombra todos los campos' % tool, campos and not faltan, faltan)

# T3: la ruta, una vez por fichero
PAS = os.path.join(BASE, 'Agujas.pas')
open(PAS, 'w', encoding='utf-8', newline='\r\n').write(
    'unit Agujas;\ninterface\nconst A1 = 1; // aguja\nconst A2 = 2; // aguja\n'
    'implementation\nend.\n')
r = call('delphi_search', {'root': BASE, 'query': '// aguja'})
j = mc.como_json(r)
fs = j.get('files', [])
check('T3 search agrupa por fichero: un grupo con sus dos aciertos y la ruta una vez',
      j.get('total') == 2 and len(fs) == 1 and len(fs[0].get('hits', [])) == 2 and
      all('path' not in h for h in fs[0]['hits']) and r.count('Agujas.pas') == 1, r[:400])

# T4: la cabecera de una lectura
r = call('delphi_read', {'path': PAS})
check('T4 read de un fichero limpio: audit=clean, sin los contadores',
      'audit=clean accents=0' in r.splitlines()[0] and 'loneLF=' not in r, r.splitlines()[0])
MIX = os.path.join(BASE, 'Mezcla.pas')
open(MIX, 'wb').write(b'unit Mezcla;\r\ninterface\nimplementation\r\nend.\r\n')
r = call('delphi_read', {'path': MIX})
check('T4 read de uno con saltos mezclados: los contadores enteros',
      'loneLF=1' in r.splitlines()[0] and 'audit=clean' not in r, r.splitlines()[0])

# T5 y T6: el eco de una escritura
r = call('delphi_edit', {'path': PAS, 'old': 'interface', 'new': 'interface // uno'})
check('T5 edit de un fichero limpio: una linea de auditoria, sin antes/despues',
      'audit=clean' in r and 'before:' not in r and 'after:' not in r, r[:400])
check('T6 la primera edicion del dia dice donde quedo la copia',
      '__delphi-patch' in r and 'already existed' not in r, r[:400])
r = call('delphi_edit', {'path': PAS, 'old': 'interface // uno', 'new': 'interface // dos'})
check('T6 la segunda dice que ya existia, sin repetir la ruta',
      'already existed (the first one of today stays)' in r and '__delphi-patch' not in r, r[:400])
r = call('delphi_edit', {'path': MIX, 'old': 'implementation', 'new': 'implementation // x'})
check('T5 edit de uno con saltos mezclados: antes y despues, con los contadores',
      'before:' in r and 'after:' in r and 'loneLF=' in r, r[:400])

# T7
r = call('delphi_list', {'root': BASE})
nota = mc.como_json(r).get('maskNote', '')
check('T7 LIST-009 en una linea', 'LIST-009' in nota and len(nota) < 90, nota)

# T8: el resumen de una carpeta, por tamano
GRANDE = os.path.join(BASE, 'grande')
os.makedirs(GRANDE)
for i in range(12):
    open(os.path.join(GRANDE, 'U%02d.pas' % i), 'w', encoding='utf-8', newline='\r\n').write(
        'unit U%02d;\ninterface\nconst\n' % i +
        ''.join('  CONSTANTE_LARGA_NUMERO_%03d = %d;\n' % (k, k) for k in range(60)) +
        'implementation\nend.\n')
j = mc.como_json(call('delphi_symbols', {'path': GRANDE}))
fuera = j.get('notShown', [])
check('T8 una carpeta grande se corta por tamano y NOMBRA lo que falta (LSP-034)',
      j.get('total') == 12 and fuera and len(j.get('units', [])) + len(fuera) == 12 and
      all(f.endswith('.pas') and ':' not in f for f in fuera) and
      'LSP-034' in j.get('notShownNote', ''), json.dumps(j)[:300])
PEQUE = os.path.join(BASE, 'peque')
os.makedirs(PEQUE)
open(os.path.join(PEQUE, 'P.pas'), 'w').write('unit P;\ninterface\nconst X = 1;\nimplementation\nend.\n')
j = mc.como_json(call('delphi_symbols', {'path': PEQUE}))
check('T8 una carpeta pequena entra entera, sin notShown',
      j.get('total') == 1 and 'notShown' not in j and 'notShownNote' not in j, json.dumps(j)[:300])

# T9: el arbol entero, sin lo que el motor repite
r = call('delphi_symbols', {'path': PAS, 'mode': 'full'}, 120)
check('T9 mode=full: con rangos, sin selectionRange repetido ni children/detail vacios',
      r.lstrip().startswith('[') and '"range"' in r and 'selectionRange' not in r and
      '"children":[]' not in r and '"detail":""' not in r, r[:300])

srv.cierra()
mc.borra(BASE)
mc.fin('docs-tokens battery')
