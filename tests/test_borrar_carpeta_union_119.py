# -*- coding: utf-8 -*-
"""delphi_delete de una CARPETA con una junction dentro (2h de la 1.18.4): una
GUARDA. Al borrar una carpeta, las units de dentro se quitan de sus proyectos
(los de fuera de la carpeta), y esa lista se hace con GetFiles(soAllDirectories),
que CRUZA una junction. La teoria era que una union dentro de la carpeta a una
carpeta hermana con una unit haria que la unit se quitara de su proyecto sin
borrarse (la union se quita como enlace; lo de detras no se toca). MEDIDO el
14-oct-2026 contra df060cc: NO pasa, el .dpr sigue listando la unit. El codigo
no se toca sin una causa medida; esta bateria vigila que siga asi.

  B1 la unit detras de la union sigue en el disco y la union se fue
  B2 el .dpr del proyecto de fuera SIGUE listando la unit

Uso:  python tests/test_borrar_carpeta_union_119.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('borrar_carpeta_union_119')
JAIL = os.path.join(BASE, 'jail')
LIB = os.path.join(JAIL, 'Lib')
PROY = os.path.join(JAIL, 'P')
TMP = os.path.join(JAIL, 'Tmp')
for d in (LIB, PROY, TMP):
    os.makedirs(d)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def dpr_lista(unidad):
    return unidad in open(os.path.join(PROY, 'P.dpr'), encoding='utf-8-sig', errors='replace').read()


s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='borrar-union', t=180)
try:
    r = s.call('delphi_create', {'kind': 'project-console', 'dir': PROY, 'name': 'P'}, t=120)
    check('fixture proyecto P', not mc.fallo(r), r[:200])
    U = os.path.join(LIB, 'ULib.pas')
    open(U, 'w', encoding='utf-8-sig').write(
        'unit ULib;\ninterface\nprocedure Saludo;\nimplementation\n'
        'procedure Saludo; begin end;\nend.\n')
    r = s.call('delphi_config', {'command': 'add-unit', 'project': os.path.join(PROY, 'P.dproj'), 'path': U})
    check('fixture ULib registrada en P', not mc.fallo(r) and dpr_lista('ULib'), r[:200])
    ENLACE = os.path.join(TMP, 'enlace')
    check('fixture junction Tmp\\enlace -> Lib', mc.junction(ENLACE, LIB))
    r = s.call('delphi_delete', {'path': TMP})
    check('delete de Tmp va', not mc.fallo(r), r[:300])
    check('B1 la unit detras de la union sigue en el disco y la union se fue',
          os.path.isfile(U) and not os.path.lexists(ENLACE), (os.path.isfile(U), os.path.lexists(ENLACE)))
    check('B2 el .dpr de P SIGUE listando ULib (la unit no se ha borrado)', dpr_lista('ULib'), r[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('borrar carpeta con union 1.19.0')
