# -*- coding: utf-8 -*-
"""Lo que confundio a Hermes en la validacion de la 1.18.0, contestado desde
el servidor (1.18.1, 10-oct-2026). Solo textos: lo que cada negativa le dice
al agente que haga despues.

  A1  delphi_report read con un nombre que no tiene la forma de un informe
      ('..', una ruta, un nombre suelto, dos carpetas): REPORT-012 lo dice,
      sin buscar nada (antes REPORT-008, "no esta").
  A2  control: un nombre CON la forma que no esta sigue siendo REPORT-008.
  A3  delphi_git init sobre una carpeta que no existe: GIT-026 con la pista
      GIT-064 (init no la crea; como crearla), y no se crea.
  A4  control: otro comando en esa carpeta es GIT-026 sin la pista de init.
  A5  removeuses sin section con el uses solo en interface: USES-016 y la
      pista USES-024 con section=interface; con ella, se quita.
  A6  el mismo caso con clausula: USES-017 (ninguna esta) y USES-018 (una de
      dos), y la pista nombra solo la que esta en la otra seccion; tambien
      al reves (section=interface con la unit en implementation).
  A7  control: una unit que no esta en ninguna seccion, USES-017 sin pista.
  A8  delphi_test con un comando que no existe: TEST-014 repite lo recibido y
      dice lo que toma cada comando; sin nada, TEST-015 dice que una llamada
      sin command es un discover y como se corre.

Uso:  python tests/test_ayudas_1181.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ayudas1181')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ayudas1181', t=300)


def unidad(nombre, de_interface, de_implementation):
    """Una unit con las uses que se le den (vacia = sin clausula)."""
    ruta = os.path.join(JAIL, nombre + '.pas')
    lineas = ['unit %s;' % nombre, '', 'interface', '']
    if de_interface:
        lineas += ['uses', '  %s;' % ', '.join(de_interface), '']
    lineas += ['implementation', '']
    if de_implementation:
        lineas += ['uses', '  %s;' % ', '.join(de_implementation), '']
    lineas += ['end.', '']
    with open(ruta, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('\n'.join(lineas))
    return ruta


try:
    # ---- A1-A2: delphi_report read ----
    malos = ['..\\..\\etc\\passwd', 'settings.ini', 'hermes\\sub\\20261010-000000-bug-x.md',
             os.path.join(JAIL, '20261010-000000-bug-x.md')]
    rs = [srv.call('delphi_report', {'command': 'read', 'name': n}) for n in malos]
    check('A1 read con un nombre que no tiene la forma de un informe: REPORT-012 lo dice, en los %d' % len(malos),
          all(mc.abre(r, 'SR_REPORT_NOMBRE_FMT') and mc.rechazado(r) for r in rs),
          ' | '.join(r[:160] for r in rs))
    r = srv.call('delphi_report', {'command': 'read', 'name': 'hermes\\20261010-000000-bug-no-esta.md'})
    check('A2 control: un nombre CON la forma que no esta sigue siendo REPORT-008',
          mc.abre(r, 'SR_REPORT_NO_ESTA_FMT'), r[:200])

    # ---- A3-A4: delphi_git init ----
    falta = os.path.join(JAIL, 'nuevo-repo')
    r = srv.call('delphi_git', {'command': 'init', 'repo': falta})
    check('A3 init en una carpeta que no existe: GIT-026 con la pista GIT-064, y no se crea',
          mc.abre(r, 'SR_GIT_DIR_NOT_FOUND_FMT') and mc.es(r, 'SN_GIT_INIT_NO_CREA')
          and not os.path.exists(falta), r[:300])
    r = srv.call('delphi_git', {'command': 'status', 'repo': falta})
    check('A4 control: status en esa carpeta es GIT-026 sin la pista de init',
          mc.abre(r, 'SR_GIT_DIR_NOT_FOUND_FMT') and not mc.es(r, 'SN_GIT_INIT_NO_CREA'), r[:300])

    # ---- A5-A7: removeuses ----
    u1 = unidad('USoloIntf', ['System.SysUtils', 'System.Classes'], [])
    r = srv.call('delphi_edit', {'path': u1, 'removeuses': 'System.Classes'})
    check('A5 removeuses sin section, uses solo en interface: USES-016 y la pista USES-024 con section=interface',
          mc.abre(r, 'SN_REMOVEUSES_NO_CLAUSE_FMT') and mc.es(r, 'SN_REMOVEUSES_EN_LA_OTRA_FMT')
          and 'System.Classes is in the interface uses: pass section=interface' in r, r[:300])
    r = srv.call('delphi_edit', {'path': u1, 'removeuses': 'System.Classes', 'section': 'interface'})
    check('A5 ...y con section=interface se quita',
          mc.abre(r, 'SN_REMOVEUSES_REMOVED_FMT') and 'Classes' not in open(u1, encoding='utf-8').read(), r[:300])

    u2 = unidad('UDos', ['System.SysUtils', 'System.Classes'], ['System.Math', 'System.IOUtils'])
    r = srv.call('delphi_edit', {'path': u2, 'removeuses': 'System.Classes'})
    check('A6 con clausula en implementation y la unit en interface: USES-017 y la pista',
          mc.abre(r, 'SN_REMOVEUSES_ABSENT_FMT') and mc.es(r, 'SN_REMOVEUSES_EN_LA_OTRA_FMT')
          and 'pass section=interface' in r, r[:300])
    r = srv.call('delphi_edit', {'path': u2, 'removeuses': 'System.Math;System.SysUtils'})
    check('A6 ...una de dos: quita System.Math y la pista nombra solo System.SysUtils (USES-018)',
          mc.abre(r, 'SN_REMOVEUSES_REMOVED_FMT') and mc.es(r, 'SN_REMOVEUSES_SOME_ABSENT_FMT')
          and 'System.SysUtils is in the interface uses' in r and 'System.Math is in' not in r
          and 'System.Math' not in open(u2, encoding='utf-8').read(), r[:400])
    r = srv.call('delphi_edit', {'path': u2, 'removeuses': 'System.IOUtils', 'section': 'interface'})
    check('A6 ...y al reves: section=interface con la unit en implementation, la pista dice section=implementation',
          mc.abre(r, 'SN_REMOVEUSES_ABSENT_FMT')
          and 'System.IOUtils is in the implementation uses: pass section=implementation' in r, r[:300])
    r = srv.call('delphi_edit', {'path': u2, 'removeuses': 'Vcl.Forms'})
    check('A7 control: una unit que no esta en ninguna seccion, USES-017 sin pista',
          mc.abre(r, 'SN_REMOVEUSES_ABSENT_FMT') and not mc.es(r, 'SN_REMOVEUSES_EN_LA_OTRA_FMT'), r[:300])

    # ---- A8: delphi_test ----
    r = srv.call('delphi_test', {'command': 'list'})
    check('A8 delphi_test con un comando que no existe: TEST-014 repite "list" y dice lo que toma cada uno',
          mc.abre(r, 'SR_TEST_CMD_FMT') and '"list"' in r and 'with path' in r and 'with project' in r, r[:300])
    r = srv.call('delphi_test', {})
    check('A8 ...y sin nada: TEST-015 dice que una llamada sin command es un discover, y como se corre',
          mc.abre(r, 'SR_TEST_NEED_PATH') and 'no command is a discover' in r and 'command=run' in r, r[:300])
finally:
    srv.mata()

try:
    mc.fin('ayudas 1181 battery')  # sys.exit: la carpeta se borra en el finally
finally:
    mc.borra(BASE)
