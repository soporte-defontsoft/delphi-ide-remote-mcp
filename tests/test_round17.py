"""E2E battery for v0.78.0-beta - hermes' supplement #1 and #2.

#1 Structured outcomes: a failing call carries structuredContent {ok, code}
   and isError, so a client never has to parse Spanish prefixes. Codes:
   DENIED (policy refusal: jail, guard, ownership), NOT_FOUND (the named
   thing is not there), INVALID_PARAM (the call was wrong), INTERNAL (server
   broke - report it). The jail's anti-probing property survives:
   outside-the-jail refusals use one fixed text whether the target exists or
   not, so both map to DENIED.

   A PROSE SUCCESS PUBLISHES NO structuredContent (fixed 2026-09-20). The
   field is the tool's output for the protocol, so a client that understands
   it SHOWS IT AND HIDES 'content': publishing {"ok": true} there left
   delphi_read, delphi_help and delphi_git status answering literally
   nothing in Claude Code. A JSON answer is its own structuredContent; a
   prose answer has none, and prose failures carry their text inside it.

#2 Real JSON Schema defaults: optional parameters that have a measured
   default now emit it as a schema "default" (typed), instead of prose only.

  R1  prose success: no structuredContent at all, and the text arrives
  R1b JSON success: the JSON IS the structuredContent, with ok:true
  R2  in-jail missing file answers NOT_FOUND + isError
  R3  outside-the-jail answers DENIED whether the target exists or not
  R4  a wrong parameter value answers INVALID_PARAM
  R5  tools/list carries typed defaults (build platform/config, search
      maxresults, config section)

Usage:  python tests/test_round17.py [path-to-DelphiLspMcp.exe]
"""
import json, time, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round17')
EXE = mc.copia_exe(BASE)
open(os.path.join(BASE, 'ok.pas'), 'w').write(
    'unit ok;\ninterface\nimplementation\nend.\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='round17')


def call(tool, args):
    """The FULL MCP result object (content + structuredContent + isError):
    what this battery measures is the envelope, not the text. {} if it
    did not arrive or came back as a JSON-RPC error."""
    return (srv.call_msg(tool, args) or {}).get('result', {})


time.sleep(0.3)

# R1: prose success - NOTHING may hide the answer
r = call('delphi_read', {'path': os.path.join(BASE, 'ok.pas')})
txt = r.get('content', [{}])[0].get('text', '')
check('R1 exito en prosa: sin structuredContent, sin isError, y el texto llega',
      'structuredContent' not in r and 'isError' not in r
      and 'unit ok;' in txt,
      (r.get('structuredContent'), r.get('isError'), txt[:80]))

# R1b: JSON success - the JSON itself is the structuredContent
r = call('delphi_list', {'root': BASE})
sc = r.get('structuredContent', {})
check('R1b exito en JSON: el JSON ES structuredContent, ok true, sin isError',
      sc.get('ok') is True and 'code' not in sc and 'isError' not in r
      and 'files' in sc,
      (list(sc)[:6], r.get('isError')))

# R2: in-jail missing file
r = call('delphi_read', {'path': os.path.join(BASE, 'no-esta.pas')})
sc = r.get('structuredContent', {})
check('R2 no existe (dentro del jail): NOT_FOUND + isError',
      sc.get('ok') is False and sc.get('code') == 'NOT_FOUND' and
      r.get('isError') is True,
      (sc, r.get('content', [{}])[0].get('text', '')[:120]))
check('R2b el fallo en prosa se lleva su texto dentro de structuredContent',
      sc.get('text', '') == r.get('content', [{}])[0].get('text', ''),
      (sc.get('text', '')[:80],))

# R3: outside the jail - existing and non-existing must answer the SAME
r_exist = call('delphi_read', {'path': 'C:\\Windows\\win.ini'})
r_ghost = call('delphi_read', {'path': 'C:\\Windows\\no-such-file-zz.ini'})
sce, scg = r_exist.get('structuredContent', {}), r_ghost.get('structuredContent', {})
te = r_exist.get('content', [{}])[0].get('text', '')
tg = r_ghost.get('content', [{}])[0].get('text', '')
check('R3 fuera del jail: DENIED + isError',
      sce.get('code') == 'DENIED' and r_exist.get('isError') is True, sce)
check('R3 anti-sondeo intacto: mismo code y mismo texto exista o no',
      scg.get('code') == 'DENIED' and
      te.replace('win.ini', 'X') == tg.replace('no-such-file-zz.ini', 'X'),
      (te[:80], tg[:80]))

# R4: wrong parameter value
r = call('delphi_config', {'project': os.path.join(BASE, 'ok.pas'),
                           'command': 'marte'})
sc = r.get('structuredContent', {})
check('R4 parametro invalido: INVALID_PARAM + isError',
      sc.get('ok') is False and sc.get('code') == 'INVALID_PARAM' and
      r.get('isError') is True, sc)

# R5: schema defaults in tools/list
tl = srv.request('tools/list') or {}
tools = {t['name']: t for t in tl.get('result', {}).get('tools', [])}


def prop(tool, name):
    return tools.get(tool, {}).get('inputSchema', {}).get(
        'properties', {}).get(name, {})


check('R5 delphi_build: platform default Win32, config default Debug (tipados)',
      prop('delphi_build', 'platform').get('default') == 'Win32' and
      prop('delphi_build', 'config').get('default') == 'Debug' and
      prop('delphi_build', 'target').get('default') == 'Build',
      {k: prop('delphi_build', k).get('default') for k in ('platform', 'config', 'target')})
check('R5 delphi_build: verbosity default quiet (el contrato del bat de la casa)',
      prop('delphi_build', 'verbosity').get('default') == 'quiet',
      prop('delphi_build', 'verbosity'))
# Y que quiet de VERDAD cuesta menos: mismo proyecto, dos verbosidades.
_pr = call('delphi_create', {'kind': 'project-console', 'name': 'Verb', 'dir': BASE})
_dprojs = [p for p in
           __import__('glob').glob(os.path.join(BASE, '**', 'Verb.dproj'),
                                   recursive=True)]
if _dprojs:
    _q = call('delphi_build', {'project': _dprojs[0], 'platform': 'Win64',
                               'config': 'Debug'})
    _n = call('delphi_build', {'project': _dprojs[0], 'platform': 'Win64',
                               'config': 'Debug', 'verbosity': 'normal'})
    _tq = _q.get('content', [{}])[0].get('text', '')
    _tn = _n.get('content', [{}])[0].get('text', '')
    _jq, _jn = json.loads(_tq), json.loads(_tn)
    check('R5b quiet no manda un warnings vacio (no es "no hay", es "no se pidieron")',
          'warnings' not in _jq and 'warningsNote' in _jq and 'warnings' in _jn,
          (list(_jq)[:8], list(_jn)[:8]))
    # Ojo con lo que se mide: en un proyecto LIMPIO quiet NO es mas corto (la
    # nota pesa mas que la cola vacia). El ahorro esta donde hay ruido; lo que
    # se puede pinar siempre es la FORMA: quiet no trae cola, normal si.
    check('R5b quiet no trae cola de salida y normal si',
          _jq.get('success') is True and _jn.get('success') is True and
          not _jq.get('outputTail') and bool(_jn.get('outputTail')),
          (len(_jq.get('outputTail', '')), len(_jn.get('outputTail', ''))))
else:
    check('R5b verbosity: proyecto de prueba creado', False, _pr)
check('R5 delphi_search: maxresults default 100 como NUMERO',
      prop('delphi_search', 'maxresults').get('default') == 100 and
      not isinstance(prop('delphi_search', 'maxresults').get('default'), str),
      prop('delphi_search', 'maxresults'))
check('R5 delphi_config: section default summary; delphi_test: platform Win64',
      prop('delphi_config', 'section').get('default') == 'summary' and
      prop('delphi_test', 'platform').get('default') == 'Win64',
      (prop('delphi_config', 'section'), prop('delphi_test', 'platform')))

# v0.79 - hermes' blind eval: the two texts that misled small models.
check('R6 build.platform dice que Build local NO usa profile',
      'NOT use profile' in prop('delphi_build', 'platform').get('description', ''),
      prop('delphi_build', 'platform').get('description', '')[:150])
check('R6 fetch.maxbytes ABRE con el aviso de que <=1MB fuerza base64',
      prop('delphi_fetch', 'maxbytes').get('description', '').startswith('OJO'),
      prop('delphi_fetch', 'maxbytes').get('description', '')[:120])

# v0.80 - blind rerun S10: "cap 500" read as a GLOBAL limit. Per page, and
# offset walks the full hit list.
check('R6b search.maxresults dice PER PAGE, no tope global',
      'PER PAGE' in prop('delphi_search', 'maxresults').get('description', ''),
      prop('delphi_search', 'maxresults').get('description', '')[:120])
check('R6b search.offset dice que recorre la lista COMPLETA',
      'FULL hit list' in prop('delphi_search', 'offset').get('description', ''),
      prop('delphi_search', 'offset').get('description', '')[:120])

# R7 (v0.79): package hands the exact next call - a model invented the zip
# name when it was prose (hermes' blind eval).
sub = os.path.join(BASE, 'paquete')
os.makedirs(sub)
open(os.path.join(sub, 'a.txt'), 'w').write('x' * 100)
r = call('delphi_package', {'dir': sub})
body = json.loads(r.get('content', [{}])[0].get('text', '{}'))
nc = body.get('nextCall', {})
check('R7 package devuelve nextCall exacto para delphi_fetch',
      nc.get('tool') == 'delphi_fetch' and
      nc.get('arguments', {}).get('path') == body.get('zip') and
      body.get('zip', '').endswith('-deploy.zip'), body)

srv.mata()
mc.fin('round-17 battery')
