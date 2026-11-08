# -*- coding: utf-8 -*-
"""1.29 (A17, medido al medir A1): un proyecto que pasa a library por las tools -un project-console con la cabecera
cambiada; hasta la 1.29 delphi_create no tenia libreria, hoy kind=project-library: test_project_library_129- se
queda sin GenDll, y dcc deja la DLL con nombre de ejecutable
(MideLib.exe; medido el 7-nov-2026). delphi_build lo dice junto al binario (BUILD-072) y como se arregla.

  L1 cabecera library sin GenDll: el build deja MideLib.exe y lo dice. ROJO contra 4891b190
  L2 ...con GenDll=true, lo que dice la nota: deja MideLib.dll y ya no lo dice
  L3 control: un programa de consola sin tocar no lleva la nota

Uso:  python tests/test_libreria_sin_gendll_129.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('libreria_sin_gendll_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='libgendll', t=120)


def crea(nombre):
    d = os.path.join(JAIL, nombre)
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    check('preparacion: %s creado' % nombre, not mc.fallo(r), r[:300])
    return os.path.join(d, nombre + '.dproj'), os.path.join(d, nombre + '.dpr')


def build(dproj):
    return mc.como_json(srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug',
                                                  'target': 'Build'}, 600))


try:
    LIB, LIBDPR = crea('MideLib')
    r = srv.call('delphi_edit', {'path': LIBDPR, 'edits': [{'old': 'program MideLib;', 'new': 'library MideLib;'},
                                                           {'old': '{$APPTYPE CONSOLE}', 'delete': True}]})
    check('preparacion: la cabecera es library', not mc.fallo(r) and 'library MideLib;' in mc.lee(LIBDPR), r[:300])
    j = build(LIB)
    check('L1 library sin GenDll: deja MideLib.exe y lo dice (BUILD-072). ROJO contra 4891b190',
          j.get('success') is True and j.get('output', '').lower().endswith('midelib.exe') and
          mc.abre(j.get('outputNote', ''), 'SN_BUILD_LIBRERIA_SIN_GENDLL_FMT'), json.dumps(j)[:600])
    r = srv.call('delphi_config', {'command': 'set-property', 'project': LIB, 'name': 'GenDll', 'value': 'true'})
    check('preparacion: GenDll=true', not mc.fallo(r), r[:300])
    j = build(LIB)
    check('L2 con GenDll=true deja MideLib.dll y ya no lo dice',
          j.get('success') is True and j.get('output', '').lower().endswith('midelib.dll') and
          not mc.es(json.dumps(j), 'SN_BUILD_LIBRERIA_SIN_GENDLL_FMT'), json.dumps(j)[:600])
    CON, _ = crea('MideCon')
    j = build(CON)
    check('L3 control: una consola sin tocar no lleva la nota',
          j.get('success') is True and j.get('output', '').lower().endswith('midecon.exe') and 'outputNote' not in j,
          json.dumps(j)[:600])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('libreria sin GenDll (1.29, A17)')
