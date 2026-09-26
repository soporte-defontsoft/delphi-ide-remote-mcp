"""The engine's own DUnitX suite (src/LspUnitTests), run THROUGH the server.

The Python batteries are black-box: a non-Delphi client talks to the exe as
shipped. This is the step below: unit tests of the engine's units (the
encoding detector and its inverses, the designer binary shape and the RTL
round trip, the .dproj hazard scan) written in DUnitX, born through
`delphi_create kind=project-test` (24-sep-2026) and executed here by
`delphi_test run`, so the suite is part of the regression and the tool that
runs tests is measured on a real suite every release.

Usage:  python tests/test_engine_dunitx.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
SRCDIR = os.path.join(REPO, 'src')
SUITE = os.path.join(SRCDIR, 'UnitTests', 'LspUnitTests.dproj')
BASE = mc.carpeta('engine-dunitx')
EXE = mc.copia_exe(BASE)

# The jail is the whole repo, like the real workspace: the suite lives in src/
# and the engine units it links include files from sibling folders (the
# node key .inc under src/DesktopNode), which a src-only jail refuses -
# measured the day this battery was born. AllowTests comes from the
# environment, the way a workspace would declare it in settings.ini.
env = mc.entorno({'DELPHI_MCP_ROOTS': REPO, 'DELPHI_MCP_ALLOW_TESTS': '1'})
srv = mc.Stdio(EXE, env, nombre='eng', t=900)  # compilar la suite: hasta 900 s
call = srv.call
def J(t):
    try: return json.loads(t)
    except Exception: return {}

check('la suite existe en src/', os.path.isfile(SUITE), SUITE)
j = J(call('delphi_test', {'command': 'discover', 'path': SUITE}))
names = [p.get('project', '') for p in j.get('projects', [])]
check('discover la reconoce como DUnitX', any('LspUnitTests' in n for n in names) and
      all(p.get('framework') == 'DUnitX' for p in j.get('projects', []) if 'LspUnitTests' in p.get('project', '')), str(j)[:300])

raw = call('delphi_test', {'command': 'run', 'project': SUITE, 'platform': 'Win64'}, t=900)
j = J(raw)
if not j:
    print('RESPUESTA CRUDA:', raw[:1200])
check('run: compila y corre', j.get('result') in ('pass', 'fail'), str(j)[:500])
check('run: result=pass (0 fallos)', j.get('result') == 'pass' and j.get('failed') == 0, str(j)[:600])
MIN_TESTS = 41  # 14 encodings + 8 designer + 5 dproj on 24-sep-2026; +14 images/frame/capture-out/deletion on 25-sep; only grows
check('run: al menos %d tests, todos pasados' % MIN_TESTS,
      j.get('total', 0) >= MIN_TESTS and j.get('passed') == j.get('total'), str(j)[:300])
check('run: veredicto por numeros, no por exit code', j.get('verdictFrom') == 'counts', str(j)[:200])
check('run: exitCode 0', j.get('exitCode') == 0, str(j)[:200])
if j.get('failures'):
    print('FALLOS:', json.dumps(j.get('failures'), ensure_ascii=False)[:1500])

srv.cierra()  # salida limpia: suelta el exe y la carpeta se puede borrar
mc.borra(BASE)
mc.fin('engine-dunitx battery')
