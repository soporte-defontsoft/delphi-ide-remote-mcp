# -*- coding: utf-8 -*-
"""Dos "dentro de" que quedaron por TEXTO (V81, 1.23.1): IncludeFor, la ruta
que se escribe en el .dpr, y RelToRoot comparaban rutas con
.ToLower.StartsWith. Medido el 27-oct: ToLower lleva el signo Kelvin (U+212A) a
'k', y para NTFS P<Kelvin> y Pk son DOS carpetas - el texto se equivoca hacia
DENTRO. add-unit escribia "UKa in 'UKa.pas'" de una unidad que vive en Pk junto
a un .dpr de P<Kelvin>: el build no la encuentra. Las dos funciones las mide
DUnitX (LspTests.RutasOrdinal); esta bateria, el camino entero por la tool.

  K1 add-unit de una unidad de Pk a un proyecto de P<Kelvin>: la entrada lleva su
     carpeta (..\\Pk\\UKa.pas), no 'UKa.pas'
  K2 ...y el proyecto compila (la encuentra)

Uso:  python tests/test_rutas_texto_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('rutas_texto_1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='rutas-texto', t=300)
try:
    call = srv.call
    KELVIN = os.path.join(JAIL, 'PK')
    KA = os.path.join(JAIL, 'Pk')
    r = call('delphi_create', {'kind': 'project-console', 'name': 'Kel', 'dir': KELVIN}, t=120)
    r2 = call('delphi_create', {'kind': 'unit', 'name': 'UKa', 'dir': KA})
    check('preparacion: P<Kelvin> y Pk son dos carpetas, el proyecto en una y la unidad en la otra',
          not mc.fallo(r) and not mc.fallo(r2) and sorted(os.listdir(JAIL)) == sorted(['PK', 'Pk']),
          (r[:200], r2[:200], os.listdir(JAIL)))
    DPR = os.path.join(KELVIN, 'Kel.dpr')
    r = call('delphi_config', {'project': os.path.join(KELVIN, 'Kel.dproj'), 'command': 'add-unit',
                               'path': os.path.join(KA, 'UKa.pas')})
    dpr = open(DPR, 'rb').read()
    check("K1 add-unit de una unidad de Pk a un .dpr de P<Kelvin>: la entrada lleva su carpeta (era 'UKa.pas')",
          not mc.fallo(r) and b"UKa in '..\\Pk\\UKa.pas'" in dpr, (r[:200], dpr[-200:]))
    r = call('delphi_build', {'project': DPR, 'platform': 'Win32', 'config': 'Debug'}, t=240)
    check('K2 ...y el proyecto compila: el compilador la encuentra', '"success":true' in r.replace(' ', ''), r[:500])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('dentro de por texto 1.23.1 (V81)')
