# -*- coding: utf-8 -*-
"""A11 de la 1.23: LA subida por carpetas. Buscar hacia arriba el proyecto de
una unidad estaba escrito tres veces con tres topes: el motor (BuscaDproj) subia
8 carpetas y delete/move (SubeCarpetas) y la mudanza 12. Una unidad a 10 niveles
de su proyecto era del proyecto para delete y de ninguno para el motor:
diagnostics contestaba que no tenia ajustes (LSP-035). Ahora sube Ancestros con
UN tope, NIVELES_DE_SUBIDA (12 carpetas, la de partida incluida).

  S1 diagnostics de una unidad a 10 carpetas de su proyecto la analiza con sus
     ajustes, no LSP-035 (ROJO hasta la 1.23: el motor subia 8)
  S2 (guarda) una unidad a 3 carpetas, igual
  S3 (guarda) a 13 carpetas, fuera del tope: LSP-035 - el tope es uno y se cumple
  S4 (guarda) delete de la unidad a 10: la nota nombra el .dpr que la lista, el
     mismo proyecto que ven las demas tools (desde V19 el borrado no lo toca; antes
     la quitaba del .dpr)

Uso:  python tests/test_subida_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_subida_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
PROY = os.path.join(JAIL, 'P')
DPROJ = os.path.join(PROY, 'P.dproj')
DPR = os.path.join(PROY, 'P.dpr')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-subida', t=300)


def unidad(nombre, subcarpetas):
    """Una unidad del proyecto en a\\b\\... (tantas carpetas como se pidan)."""
    sub = '\\'.join(chr(ord('a') + k) for k in range(subcarpetas))
    r = srv.call('delphi_create', {'kind': 'unit', 'name': nombre, 'project': DPROJ, 'dir': sub}, t=120)
    check('fixture: %s a %d carpetas del proyecto' % (nombre, subcarpetas + 1),
          os.path.exists(os.path.join(PROY, sub, nombre + '.pas')),
          r[:300])
    return os.path.join(PROY, sub, nombre + '.pas')


def diagnostics(ruta):
    t = srv.call('delphi_diagnostics', {'path': ruta}, t=240)
    if mc.como_json(t).get('status') == 'in-progress':  # el primer lint de un motor frio
        t = srv.call('delphi_diagnostics', {'path': ruta}, t=240)
    return t


try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': PROY}, t=120)
    check('fixture: el proyecto P', os.path.exists(DPROJ), r[:300])
    honda = unidad('UHonda', 9)    # su carpeta + 9 = el .dproj en la carpeta 10
    corta = unidad('UCorta', 2)    # en la carpeta 3
    fuera = unidad('UFuera', 12)   # en la carpeta 13: por encima del tope

    t = diagnostics(honda)
    check('S1 diagnostics de una unidad a 10 carpetas de su proyecto la analiza con sus ajustes, no LSP-035',
          not mc.es(t, 'SR_LSP_LINT_SIN_AJUSTES_FMT'), t[:300])
    t = diagnostics(corta)
    check('S2 (guarda) una unidad a 3 carpetas, igual', not mc.es(t, 'SR_LSP_LINT_SIN_AJUSTES_FMT'), t[:300])
    t = diagnostics(fuera)
    check('S3 (guarda) a 13 carpetas, fuera del tope: LSP-035 (el tope es uno y se cumple)',
          mc.es(t, 'SR_LSP_LINT_SIN_AJUSTES_FMT'), t[:300])

    antes = open(DPR, encoding='utf-8-sig').read()
    r = srv.call('delphi_delete', {'path': honda}, t=120)
    despues = open(DPR, encoding='utf-8-sig').read()
    check('S4 (guarda) delete de la unidad a 10: la nota nombra el .dpr, que no se toca',
          'UHonda' in antes and despues == antes and not os.path.exists(honda) and
          mc.es(r, 'SN_REFERENCIAS_A_LO_BORRADO_FMT') and 'P.dpr (' in r, r[-500:])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('la subida por carpetas, A11 de la 1.23')
