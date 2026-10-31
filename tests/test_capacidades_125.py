# -*- coding: utf-8 -*-
"""Las capacidades de la 1.25, una por una, de punta a punta por el protocolo.

V39: delphi_docs search pagina como las demas listas.
V44: delphi_search con contexto alrededor de cada acierto y con ficheros que se dejan fuera, por el
mismo juez de mascaras que el paseo.

Usage:  python tests/test_capacidades_125.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('capacidades-125')
EXE = mc.copia_exe(BASE)
RAIZ = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ)
with open(os.path.join(RAIZ, 'UNo.pas'), 'w', newline='') as f:
    f.write('unit UNo;\r\n// uno\r\n// dos\r\n// AGUJA\r\n// cuatro\r\n// cinco\r\nend.\r\n')
with open(os.path.join(RAIZ, 'UDos_test.pas'), 'w', newline='') as f:
    f.write('unit UDos_test;\r\n// AGUJA\r\nend.\r\n')
with open(os.path.join(RAIZ, 'Vieja.pas'), 'w', newline='') as f:
    f.write('unit Vieja;\r\n// AGUJA\r\nend.\r\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='capacidades')
call = srv.call


def hits(d):
    return {x['name']: x['hits'] for g in d.get('folders', []) for x in g['files']}


try:
    # V39 - delphi_docs search
    t = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'limit': 3})
    if mc.es(t, 'SR_DOCS_SIN_AYUDA_FMT'):
        print('NOTA: sin ayuda instalada: V39 no se mide aqui')
    else:
        a = json.loads(t)
        check('V39 search da su pagina: total, shown, hasMore y nextOffset',
              a.get('shown') == 3 and a.get('hasMore') is True and a.get('nextOffset') == 3 and a.get('total', 0) > 3, t[:300])
        t2 = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'limit': 3, 'offset': a.get('nextOffset', 3)})
        b = json.loads(t2) if t2.startswith('{') else {}
        ids_a, ids_b = [r['id'] for r in a.get('results', [])], [r['id'] for r in b.get('results', [])]
        check('V39 la pagina siguiente trae otras, sin repetir', len(ids_b) == 3 and not set(ids_a) & set(ids_b), t2[:300])
        check('V39 y dice su offset', b.get('offset') == 3, t2[:200])
        t3 = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'offset': 100000})
        c = json.loads(t3) if t3.startswith('{') else {}
        check('V39 un offset mas alla del final: lista vacia, hasMore false', c.get('results') == [] and c.get('hasMore') is False, t3[:200])
        t4 = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'limit': 99})
        check('V39 limit sigue con su tope de 25', json.loads(t4).get('shown', 0) <= 25, t4[:200])

    # V44 - delphi_search: contexto
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'context': 2}))
    h = hits(d).get('UNo.pas', [{}])[0]
    check('V44 context: las dos de antes y las dos de despues, tal cual',
          h.get('before') == ['// uno', '// dos'] and h.get('after') == ['// cuatro', '// cinco'] and h.get('text') == '// AGUJA', d)
    check('V44 y el acierto sigue en su sitio', h.get('line') == 4 and h.get('line0') == 3, h)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'unit UNo', 'context': 3}))
    h = hits(d)['UNo.pas'][0]
    check('V44 context en la primera linea: before vacio', h.get('before') == [] and len(h.get('after', [])) == 3, h)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'context': 500}))
    check('V44 context tiene su tope', len(hits(d)['UNo.pas'][0].get('before', [])) == 3, d)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA'}))
    check('V44 sin context, ni before ni after', 'before' not in hits(d)['UNo.pas'][0] and 'after' not in hits(d)['UNo.pas'][0], d)

    # V44 - delphi_search: exclude
    d = json.loads(call('delphi_search', {'root': RAIZ, 'query': 'AGUJA'}))
    check('V44 sin exclude, los tres', sorted(hits(d)) == ['UDos_test.pas', 'UNo.pas', 'Vieja.pas'], d)
    d = json.loads(call('delphi_search', {'root': RAIZ, 'query': 'AGUJA', 'exclude': '*_test.pas;Vie*.pas'}))
    check('V44 exclude deja fuera lo suyo y lo cuenta', sorted(hits(d)) == ['UNo.pas'] and d.get('excluded') == 2 and d.get('filesScanned') == 1, d)
    t = call('delphi_search', {'root': RAIZ, 'query': 'AGUJA', 'exclude': '..\\*.pas'})
    check('V44 exclude que no es una mascara: su negativa', mc.es(t, 'SR_WS_PATTERN_DEBE_SER_MASCARA'), t[:200])
    t = call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'exclude': '*.pas'})
    check('V44 exclude con UN fichero por raiz: SEARCH-010', mc.es(t, 'SR_SEARCH_EXCLUDE_CON_FICHERO_FMT'), t[:200])
    d = json.loads(call('delphi_search', {'root': RAIZ, 'query': 'AGUJA', 'exclude': '*.pas', 'pattern': '*.pas'}))
    check('V44 todo fuera: no dice que la mascara no casa', d.get('excluded') == 3 and 'maskNote' not in d, d)
finally:
    srv.mata()

mc.borra(BASE)
mc.fin('capacidades 1.25 battery')
