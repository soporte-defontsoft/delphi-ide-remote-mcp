# -*- coding: utf-8 -*-
"""H5-02 de Hermes (1.19.2, medido el 15-oct): delphi_delete de una unidad que
lista un .dpr de una carpeta HERMANA (app\\P.dpr lista '..\\scratch\\UDef.pas')
contestaba FILE-002 "no .dpr listed it" y dejaba el .dpr colgando de la unidad
borrada (proyecto roto hasta editarlo a mano). El buscador de "que proyectos
listan esta unidad" (ProjectsUsingUnit, el de delete y move) solo SUBIA por las
carpetas; el de los paquetes (WorkspacePackagesWithUnit) ya miraba ademas las
subcarpetas inmediatas de cada nivel. Ahora los dos recorren los mismos sitios.

  D1 delete de scratch\\UDef.pas: FILE-035 nombra app\\P.dpr   (ROJO en produccion: FILE-002)
  D2 ...y el .dpr ya no lista UDef                            (ROJO)
  D3 una unidad dos niveles abajo (lib\\core\\UDeep.pas): igual (ROJO)
  M1 move scratch\\UMov.pas -> scratch\\UMov2.pas: FILE-035     (ROJO)
  M2 ...y el .dpr apunta a UMov2                              (ROJO)
  C1 control: una unidad junto al .dpr sigue saliendo de el

Uso:  python tests/test_delete_proyecto_lateral_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('delete_proyecto_lateral_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def dpr_texto(ruta):
    return io.open(ruta, encoding='utf-8-sig').read()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='delete-lateral', t=300)
try:
    app = os.path.join(JAIL, 'app')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': app}, t=120)
    dpr = os.path.join(app, 'P.dpr')
    scratch = os.path.join(JAIL, 'scratch')
    core = os.path.join(JAIL, 'lib', 'core')
    for nombre, carpeta in (('UDef', scratch), ('UMov', scratch), ('UDeep', core), ('UJunto', app)):
        srv.call('delphi_create', {'kind': 'unit', 'name': nombre, 'dir': carpeta}, t=120)
        r = srv.call('delphi_config', {'command': 'add-unit', 'project': dpr,
                                       'path': os.path.join(carpeta, nombre + '.pas')}, t=120)
        assert 'CFG-041' in r, r
    assert "UDef in '..\\scratch\\UDef.pas'" in dpr_texto(dpr), dpr_texto(dpr)

    r = srv.call('delphi_delete', {'path': os.path.join(scratch, 'UDef.pas')}, t=120)
    check('D1 delete de una unidad listada por el .dpr de una carpeta HERMANA: FILE-035 nombra P.dpr',
          'FILE-035' in r and 'P.dpr' in r and not mc.es(r, 'SN_FILE_PROJECTS_NONE'), r[:500])
    check('D2 ...y el .dpr ya no lista UDef', 'UDef' not in dpr_texto(dpr), dpr_texto(dpr))

    r = srv.call('delphi_delete', {'path': os.path.join(core, 'UDeep.pas')}, t=120)
    check('D3 una unidad dos niveles abajo (lib\\core), listada por app\\P.dpr: FILE-035 y fuera del .dpr',
          'FILE-035' in r and 'UDeep' not in dpr_texto(dpr), r[:500])

    r = srv.call('delphi_move', {'path': os.path.join(scratch, 'UMov.pas'), 'dest': os.path.join(scratch, 'UMov2.pas')},
                 t=120)
    check('M1 move de una unidad listada por el .dpr hermano: FILE-035', 'FILE-035' in r and not mc.es(r, 'SN_FILE_PROJECTS_NONE'), r)
    check('M2 ...y el .dpr apunta a UMov2', "UMov2 in '..\\scratch\\UMov2.pas'" in dpr_texto(dpr)
          and "UMov in '..\\scratch\\UMov.pas'" not in dpr_texto(dpr), dpr_texto(dpr))

    r = srv.call('delphi_delete', {'path': os.path.join(app, 'UJunto.pas')}, t=120)
    check('C1 control: la unidad junto al .dpr sale de el', 'FILE-035' in r and 'UJunto' not in dpr_texto(dpr), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delete/move: el .dpr de una carpeta hermana (H5-02 de la 1.19.2)')
