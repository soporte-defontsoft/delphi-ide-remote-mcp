"""E2E battery for 1.20 - the double send (Hermes, 13-oct; measured 16-oct).

A JSON answer travels twice: as text and as structuredContent. The spec asks
the text to be the serialized structuredContent (the backwards-compatible
copy), and a client that follows it drops one of the two: Hermes 0.22.2 does
(_content_dual_emits_structured), comparing them as parsed JSON. Ours were
never equal: the vendor (MCPServer.ToolsManager) added "ok" to
structuredContent only, so EVERY JSON answer reached Hermes twice (measured
on 16-oct: structuredContent = text + `,"ok":true`).

  D1  every JSON answer: its text parses to EXACTLY its structuredContent
      (Hermes' own rule), across the tools that answer JSON.
  D2  the text is still the tool's own text: what the vendor adds goes at the
      end of the object, and an accent reaches both channels intact. (The
      tools' own serializer writes it as \\u00E9 in the text - measured on
      16-oct, not this battery's business.)
  D3  a prose answer still has no structuredContent.
  D4  a prose refusal keeps isError and its {text, ok:false, code}.

Usage:  python tests/test_doble_envio_120.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('doble_envio_120')
EXE = mc.copia_exe(BASE)
JAULA = os.path.join(BASE, 'jaula')
os.makedirs(JAULA)
PAS = os.path.join(JAULA, 'UProbe.pas')
open(PAS, 'w', encoding='utf-8', newline='\r\n').write(
    'unit UProbe;\ninterface\nconst Aguja = 1; // Café con acento\nimplementation\nend.\n')
TXT = os.path.join(JAULA, 'notas.txt')
open(TXT, 'w', encoding='utf-8').write('uno\ndos\n')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAULA}), nombre='doble-envio', t=240)


def partes(nombre, args):
    res = (srv.call_msg(nombre, args) or {}).get('result') or {}
    textos = [b.get('text', '') for b in res.get('content', []) if b.get('type') == 'text']
    return res, textos, res.get('structuredContent')


def igual(textos, sc):
    for t in textos:
        try:
            if json.loads(t) == sc:
                return True
        except ValueError:
            pass
    return False


# D1: las que contestan JSON, la copia igual
JSON = [
    ('delphi_workspace', {}),
    ('delphi_installs', {}),
    ('delphi_help', {'command': 'tool', 'name': 'git'}),
    ('delphi_list', {'root': JAULA}),
    ('delphi_search', {'root': JAULA, 'query': 'Aguja'}),
    ('delphi_search', {'root': JAULA, 'query': 'NoEstaEnNingunSitio'}),
    ('delphi_symbols', {'path': JAULA}),
    ('delphi_projects', {'root': JAULA}),
    ('delphi_report', {'command': 'list'}),
    ('delphi_fetch', {'path': TXT}),
    ('delphi_paserver', {}),
    ('delphi_docs', {'query': 'TStringList'}),
]
for nombre, args in JSON:
    res, textos, sc = partes(nombre, args)
    check('D1 %s %s: el texto ES su structuredContent (la regla de Hermes)' % (nombre, sorted(args)),
          sc is not None and not res.get('isError') and igual(textos, sc),
          'struct=%s texto=%s' % (json.dumps(sc, ensure_ascii=False)[-80:] if sc else None,
                                  (textos[0] if textos else '')[-80:]))

# D2: el texto de la tool, con lo del vendor al final y sin reserializar
res, textos, sc = partes('delphi_search', {'root': JAULA, 'query': 'Aguja'})
t = textos[0] if textos else ''
hits = [h.get('text', '') for f in mc.ficheros(t) for h in f.get('hits', [])]
check('D2 el acento del fuente llega intacto por los dos canales',
      hits == ['const Aguja = 1; // Café con acento'] and
      'Café con acento' in json.dumps(sc, ensure_ascii=False), t[:300])
check('D2 lo que anade el vendor va al final del objeto, nada mas', t.rstrip().endswith(',"ok":true}'), t[-60:])

# D3: la prosa sigue sin structuredContent
for nombre, args in (('delphi_read', {'path': PAS}), ('delphi_help', {'command': 'tasks'})):
    res, textos, sc = partes(nombre, args)
    check('D3 %s contesta prosa, sin structuredContent' % nombre,
          sc is None and textos and not textos[0].lstrip().startswith('{'), json.dumps(res)[:200])

# D4: una negativa en prosa, como siempre
res, textos, sc = partes('delphi_read', {'path': os.path.join(JAULA, 'NoExiste.pas')})
check('D4 una negativa en prosa: isError y {text, ok:false, code}',
      res.get('isError') is True and isinstance(sc, dict) and sc.get('ok') is False and sc.get('code') and
      sc.get('text') == (textos[0] if textos else None), json.dumps(res, ensure_ascii=False)[:300])

srv.cierra()
mc.borra(BASE)
mc.fin('doble-envio battery')
