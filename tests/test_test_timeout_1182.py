# -*- coding: utf-8 -*-
"""H3 de Hermes (1.18.2, punto 9): con timeoutms=1 (nobuild) delphi_test
contestaba exitCode 0 y la nota TEST-008 afirmaba "That is why exitCode comes
as 1" - un texto fijo que decia un valor que el campo de al lado desmentia. Al
matar el proceso, su codigo es el del proceso muerto, no un veredicto de los
tests: la nota ya no afirma ninguno.

  T1 un run cortado por tiempo: result=timeout y timedOut=true (guarda)
  T2 ...y la nota no afirma un exitCode que el campo contradiga (ROJO en
     produccion: "comes as 1" con exitCode 0)

Uso:  python tests/test_test_timeout_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_timeout_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
SKIP = None

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1'}),
               nombre='test-timeout', t=600)
try:
    d = os.path.join(JAIL, 'CortaTests')
    srv.call('delphi_create', {'kind': 'project-test', 'name': 'CortaTests', 'dir': d})
    dproj = os.path.join(d, 'CortaTests.dproj')
    r = srv.call('delphi_test', {'command': 'run', 'project': dproj}, t=600)
    if '"result":"pass"' not in r.replace(' ', ''):
        SKIP = 'el proyecto de test no compilo o no paso: %s' % r[:200]
    else:
        r = srv.call('delphi_test', {'command': 'run', 'project': dproj, 'nobuild': True,
                                     'timeoutms': 1}, t=120)
        try:
            j = json.loads(r)
        except Exception:
            j = {}
        check('T1 un run cortado por tiempo: result=timeout y timedOut=true',
              j.get('result') == 'timeout' and j.get('timedOut') is True, r[:300])
        nota = j.get('timeoutNote', '')
        m = re.search(r'exitCode comes as (\d+)', nota)
        check('T2 la nota no afirma un exitCode que el campo contradiga',
              (m is None) or (int(m.group(1)) == j.get('exitCode')),
              (j.get('exitCode'), nota[:160]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_test cortado por tiempo 1182 (H3)', sin_checks=SKIP)
