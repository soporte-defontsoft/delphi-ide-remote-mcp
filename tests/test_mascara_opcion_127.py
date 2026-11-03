# -*- coding: utf-8 -*-
r"""A8 de la 1.27: una unidad pegada a una opcion de una linea de ordenes sale enmascarada.

Medido el 3-nov-2026 en produccion: la linea de dcc64 de un delphi_build verbosity=verbose lleva
-LEC:\..., -LNC:\..., -NBC:\... y -NHC:\... sin comillas (las carpetas de .bpl, .dcp y .hpp de la
instalacion), y salian con la letra REAL: el barrido de las letras del enmascarador solo empezaba una
unidad detras de algo que no fuera letra ni cifra, y la C: va detras de la E. Las rutas de red ya
tenian esa regla (una opcion pegada, -U\\nas\lib); ahora es UNA (Lsp.Lugares.OpcionPegada) para las
dos y para la casa. Lo fino (JSON, la casa pegada, los controles) lo mide LspTests.Rutas.

  M1 build verbose de una consola Win64: compila (premisa)
  M2 la linea de dcc64 trae -LE, -LN, -NB y -NH con una ruta pegada (premisa: lo medido existe)
  M3 ninguna de esas opciones lleva pegada una unidad REAL, todas srvX: (ROJA contra la 1.26.1)

Uso:  python tests/test_mascara_opcion_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('mascara-opcion-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='mascara-opcion-127', t=600)

try:
    D = os.path.join(JAIL, 'cons')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Cons', 'dir': D})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    rb = srv.call('delphi_build', {'project': os.path.join(D, 'Cons.dproj'), 'platform': 'Win64',
                                   'config': 'Release', 'verbosity': 'verbose'}, 600)
    j = mc.como_json(rb)
    check('M1 build verbose de una consola Win64: compila', j.get('success') is True, rb[:300])
    cola = j.get('outputTail', '')
    pegadas = re.findall(r' -(LE|LN|NB|NH)(\S{2,4})', cola)
    check('M2 la linea de dcc64 trae -LE, -LN, -NB y -NH con una ruta pegada',
          {p[0] for p in pegadas} == {'LE', 'LN', 'NB', 'NH'}, str(pegadas)[:300])
    reales = re.findall(r' -(?:LE|LN|NB|NH)[A-Za-z]:[\\/]', cola)
    check('M3 ninguna lleva pegada una unidad REAL: todas srvX:',
          pegadas and not reales and all(p[1].startswith('srv') for p in pegadas),
          str(reales or pegadas)[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('una unidad pegada a una opcion de una linea de ordenes 1.27 (A8)')
