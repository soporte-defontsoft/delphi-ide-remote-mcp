# -*- coding: utf-8 -*-
"""La carpeta que nombra quien llama y que no es una, una regla (W1, A17 de la 1.23).

delphi_list, delphi_projects y delphi_package toman una CARPETA. Con un fichero:
list decia LIST-002 nombrandose a si misma, package decia el mismo LIST-002 con
el nombre de list, y projects contestaba PROJ-003, "no existe... no hay nada
alli", de un fichero que estaba alli (medido contra r1222ai). Ahora las tres
pasan por Mcp.Tools.Workspace.CarpetaQueNoEs.

  H1 delphi_projects con un fichero: LIST-002 con su nombre (ROJO hasta la 1.23:
     PROJ-003)
  H2 delphi_package con un fichero: LIST-002 con SU nombre (ROJO hasta la 1.23:
     nombraba a delphi_list)
  H3 (guarda) delphi_list con un fichero: LIST-002 con el suyo
  H4 (guarda) lo que no existe sigue siendo lo de cada una: list y package
     WS-008, projects PROJ-003

Uso:  python tests/test_hermanas_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_hermanas_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
FICH = os.path.join(JAIL, 'Proyecto.dproj')
open(FICH, 'w', encoding='utf-8').write('<Project/>\n')
NADA = os.path.join(JAIL, 'no-existe')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def es_fichero(r, tool):
    return 'LIST-002' in r and ('%s walks folders' % tool) in r


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-hermanas', t=120)
try:
    r1 = srv.call('delphi_projects', {'root': FICH})
    check('H1 delphi_projects con un fichero: LIST-002 con su nombre, no "no existe"',
          es_fichero(r1, 'delphi_projects') and not mc.es(r1, 'SR_PROJECTS_NO_ROOT_FMT'), r1[:300])
    r2 = srv.call('delphi_package', {'dir': FICH})
    check('H2 delphi_package con un fichero: LIST-002 con SU nombre',
          es_fichero(r2, 'delphi_package') and 'delphi_list' not in r2, r2[:300])
    r3 = srv.call('delphi_list', {'root': FICH})
    check('H3 (guarda) delphi_list con un fichero: LIST-002 con el suyo', es_fichero(r3, 'delphi_list'), r3[:300])
    r4 = [srv.call('delphi_list', {'root': NADA}), srv.call('delphi_package', {'dir': NADA}),
          srv.call('delphi_projects', {'root': NADA})]
    check('H4 (guarda) lo que no existe: list y package WS-008, projects PROJ-003',
          'WS-008' in r4[0] and 'WS-008' in r4[1] and 'PROJ-003' in r4[2], [r[:120] for r in r4])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('la carpeta que no es una, W1 de A17 de la 1.23')
