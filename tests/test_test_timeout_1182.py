# -*- coding: utf-8 -*-
"""H3 de Hermes (1.18.2, punto 9): con timeoutms=1 (nobuild) delphi_test
contestaba exitCode 0 y la nota TEST-008 afirmaba "That is why exitCode comes
as 1" - un texto fijo que decia un valor que el campo de al lado desmentia. Al
matar el proceso, su codigo es el del proceso muerto, no un veredicto de los
tests: la nota ya no afirma ninguno.

  T1 un run cortado por tiempo: result=timeout y timedOut=true (guarda), con
     un test que DUERME mas que el plazo: el exe de la plantilla tarda ~54 ms,
     y con timeoutms=1 el corte dependia de si acababa antes del primer sondeo
     de 50 ms de RunCore (la intermitencia de run_all del 16 y el 23-oct-2026)
  T2 ...y la nota no afirma un exitCode que el campo contradiga (ROJO en
     produccion: "comes as 1" con exitCode 0)
  T3 un run dado por cortado fue MATADO: su exitCode no es el 0 de uno que
     acabo solo (ROJO hasta la 1.23: con timeoutms=1 el exe de la plantilla
     acababa solo mientras se vaciaba su salida y salia result=timeout con
     exitCode 0, 10 de 10 medidos el 23-oct-2026)

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
        # (revisor de baterias, 18-oct-2026) SIN CHECKS solo sin RAD Studio: con el,
        # un proyecto de test recien creado que no compila o no pasa es ROJO (hoy
        # cambio su plantilla: UsingDelphiRTL, $(DUnitX), los grupos de Debug)
        if mc.catalogo()['SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED'] in r:
            SKIP = 'no hay RAD Studio en esta maquina: %s' % r[:200]
        else:
            check('T0 el proyecto de test que crea delphi_create compila y pasa', False, r[:300])
    else:
        # T3: el exe de la plantilla, rapido, con un plazo que vence antes de que
        # acabe o mientras se vacia su salida: cortado = matado, nunca un 0
        vistos = []
        for _ in range(5):
            r = srv.call('delphi_test', {'command': 'run', 'project': dproj, 'nobuild': True,
                                         'timeoutms': 1}, t=120)
            try:
                j = json.loads(r)
            except Exception:
                j = {}
            vistos.append((j.get('result'), j.get('exitCode')))
        check('T3 un run dado por cortado fue matado: su exitCode no es el 0 de uno que acabo solo',
              all(res in ('pass', 'timeout') for res, _ in vistos) and
              all(code != 0 for res, code in vistos if res == 'timeout'), vistos)
        # T1/T2: un test que duerme 8 s y un plazo de 2 s, sin carrera
        unidad = [f for f in os.listdir(d) if f.lower().endswith('.pas')][0]
        unidad = os.path.join(d, unidad)
        leido = srv.call('delphi_read', {'path': unidad})
        texto = '\n'.join(l.split('|', 1)[1] for l in leido.splitlines() if re.match(r'^\d+\|', l))
        clase = re.search(r'\b(\w+)\s*=\s*class\b', texto).group(1)
        srv.call('delphi_edit', {'path': unidad, 'adduses': 'Winapi.Windows', 'section': 'implementation'})
        r = srv.call('delphi_edit', {'path': unidad, 'insert': 'metodo', 'inclass': clase,
                                     'code': '[Test] procedure Duerme;\nbegin\n  Winapi.Windows.Sleep(8000);\nend;'})
        check('fixture: un test que duerme 8 s', mc.es(r, 'SK_EDIT_ESCRITO_EN_FMT'), r[:300])
        r = srv.call('delphi_build', {'project': dproj}, t=600)
        check('fixture: el proyecto con el test lento compila', '"success":true' in r.replace(' ', ''), r[:300])
        r = srv.call('delphi_test', {'command': 'run', 'project': dproj, 'nobuild': True,
                                     'timeoutms': 2000}, t=120)
        try:
            j = json.loads(r)
        except Exception:
            j = {}
        check('T1 un run cortado por tiempo: result=timeout y timedOut=true',
              j.get('result') == 'timeout' and j.get('timedOut') is True and j.get('exitCode') != 0,
              {k: j.get(k) for k in ('result', 'timedOut', 'exitCode', 'durationMs')} if j else r[:300])
        nota = j.get('timeoutNote', '')
        m = re.search(r'exitCode comes as (\d+)', nota)
        # la nota EXISTE (por su constante): con timeoutNote renombrado, m era None
        # y pasaba siempre
        check('T2 la nota no afirma un exitCode que el campo contradiga',
              mc.es(nota, 'SN_TEST_TIMEOUT_NOTE') and ((m is None) or (int(m.group(1)) == j.get('exitCode'))),
              (j.get('exitCode'), nota[:160]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_test cortado por tiempo 1182 (H3)', sin_checks=SKIP)
