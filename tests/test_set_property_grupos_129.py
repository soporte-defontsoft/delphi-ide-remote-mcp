# -*- coding: utf-8 -*-
"""1.29 (A15, medido al medir la escala de la preview): delphi_config set-property sin platform ni config escribe
el grupo base, como el IDE con "All configurations - All platforms", y contestaba "SET ... for all platforms"
aunque los grupos de cada configuracion y plataforma ponen la misma propiedad y, para sus builds, ganan: el build
de Win64 Release seguia leyendo PerMonitorV2 (medido con get-property). El IDE tampoco toca esos grupos; la
respuesta tiene que decirlo.

  G1 set-property AppDPIAwarenessMode sin build en un proyecto VCL nuevo (sus grupos lo ponen): la respuesta dice
     que otros grupos lo ponen y ganan. ROJO contra 6fd7d045
  G2 ...y es verdad: get-property del build de Win64 Release sigue dando el valor de su grupo
  G3 control: con platform y config no sale esa nota

Uso:  python tests/test_set_property_grupos_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('set_property_grupos_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='setprop', t=60)
# el trozo fijo de la nota, del catalogo (no escrito a mano)
OTROS = mc.trozo_de_formato('SF_CFG_PROPERTY_OTROS_GRUPOS_FMT', 0).strip()
try:
    P = os.path.join(JAIL, 'Dpi')
    srv.call('delphi_create', {'kind': 'project-vcl', 'name': 'Dpi', 'dir': P})
    DPROJ = os.path.join(P, 'Dpi.dproj')
    antes = srv.call('delphi_config', {'command': 'get-property', 'project': DPROJ, 'name': 'AppDPIAwarenessMode',
                                       'platform': 'Win64', 'config': 'Release'})
    check('preparacion: el proyecto nuevo pone AppDPIAwarenessMode en sus grupos', 'PerMonitorV2' in antes, antes[:300])
    r = srv.call('delphi_config', {'command': 'set-property', 'project': DPROJ, 'name': 'AppDPIAwarenessMode',
                                   'value': 'none'})
    check('G1 sin build: la respuesta dice que otros grupos lo ponen y ganan para sus builds. ROJO contra 6fd7d045',
          OTROS in r, r[:400])
    g = srv.call('delphi_config', {'command': 'get-property', 'project': DPROJ, 'name': 'AppDPIAwarenessMode',
                                   'platform': 'Win64', 'config': 'Release'})
    check('G2 ...y es verdad: Win64 Release sigue leyendo PerMonitorV2', '= PerMonitorV2' in g, g[:300])
    r = srv.call('delphi_config', {'command': 'set-property', 'project': DPROJ, 'name': 'AppDPIAwarenessMode',
                                   'value': 'none', 'platform': 'Win64', 'config': 'Release'})
    check('G3 control: con platform y config no sale esa nota', OTROS not in r,
          r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('set-property sin build y los grupos que lo pisan (1.29)')
