"""E2E battery for v0.46.1-beta - parameter aliases at the gate, delphi_search over ONE file,
delphi_list brace refusal, log flushed per line.

Usage:  python tests/test_v0461.py [path-to-DelphiLspMcp.exe]
"""
import json, os, time, uuid
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('v0461')
EXE = mc.copia_exe(BASE)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='v0461-battery', t=300)
call = srv.call

# --- fixtures
open(os.path.join(BASE, 'Big.dproj'), 'w', encoding='utf-8').write(
    '<Project>\n' + '  <Line/>\n' * 600 + '  <DCC_UnitSearchPath>..\\Lib</DCC_UnitSearchPath>\n' + '  <Line/>\n' * 600 + '</Project>\n')
open(os.path.join(BASE, 'U1.pas'), 'w', encoding='utf-8').write('unit U1;\ninterface\nimplementation\nend.\n')
open(os.path.join(BASE, 'U1.dfm'), 'w', encoding='utf-8').write('object F: TF\nend\n')

# --- delphi_search over ONE file
r = call('delphi_search', {'root': os.path.join(BASE, 'Big.dproj'), 'query': 'DCC_UnitSearchPath'})
try: j = json.loads(r)
except Exception: j = {}
check('search root=file: one hit at the right line', j.get('total') == 1 and j['hits'][0]['line'] == 602, r[:300])
check('search root=file: filesScanned = 1', j.get('filesScanned') == 1, r[:200])
r = call('delphi_search', {'root': os.path.join(BASE, 'Nope.dproj'), 'query': 'x'})
check('search root=missing file: error', 'not found' in r, r)
# alias: text -> query
r = call('delphi_search', {'root': BASE, 'text': 'DCC_UnitSearchPath'})
try: j = json.loads(r)
except Exception: j = {}
check('search alias text->query', j.get('total') == 1, r[:200])

# --- delphi_list
r = call('delphi_list', {'root': BASE, 'pattern': '*.{pas,dfm}'})
check('list: braces refused with hint', 'RECHAZADO' in r and ';' in r, r[:200])
r = call('delphi_list', {'root': BASE, 'pattern': '*.pas;*.dfm'})
try: j = json.loads(r)
except Exception: j = {}
check('list: ";" list works', j.get('total') == 2, r[:200])
r = call('delphi_list', {'root': BASE, 'filter': '*.pas'})
try: j = json.loads(r)
except Exception: j = {}
check('list alias filter->pattern', j.get('total') == 1 and j['files'][0]['path'].endswith('U1.pas'), r[:200])
r = call('delphi_list', {'root': BASE, 'filter': '*.pas', 'pattern': '*.dfm'})
try: j = json.loads(r)
except Exception: j = {}
check('alias never overrides the real name', j.get('total') == 1 and j['files'][0]['path'].endswith('U1.dfm'), r[:200])

# --- delphi_read aliases
r = call('delphi_read', {'path': os.path.join(BASE, 'Big.dproj'), 'startline': 602, 'endline': 602})
check('read alias startline/endline', 'DCC_UnitSearchPath' in r and 'Unknown parameter' not in r, r[:200])

# --- delphi_components alias
r = call('delphi_components', {'query': 'zzz-no-such-package'})
check('components alias query->filter', 'Unknown parameter' not in r and 'zzz-no-such-package' in r, r[:200])

# --- log flushed per line (the tray never closes the writer)
r = call('delphi_workspace', {})
# the real card (its roots list): a refusal text also says "roots"
check('workspace ok', isinstance(mc.como_json(r).get('roots'), list), r[:100])
# Until 1.5.0 the terminal (stdio) wrote no log at all and this check was a
# permanent SKIP. Now ONE sink (Lsp.LogSink) serves the three hosts: it
# appends logs\actual.log next to the exe every half second, while the
# server lives. The last call carries a marker of its own, so what is found
# on disk is THAT call and not an earlier line that happens to match.
MARCA = 'marca-del-log-' + uuid.uuid4().hex[:12]
call('delphi_search', {'root': BASE, 'query': MARCA})
VIVO = os.path.join(BASE, 'logs', 'actual.log')
txt = ''
for _ in range(50):  # up to 5 s: the sink appends every half second
    if os.path.isfile(VIVO):
        txt = open(VIVO, encoding='utf-8', errors='ignore').read()
        if MARCA in txt:
            break
    time.sleep(0.1)
check('log flushed per line (last call already on disk)', MARCA in txt,
      '%s | %s' % (VIVO, os.listdir(BASE)))

srv.mata()
mc.fin('v0.46.1 battery')
