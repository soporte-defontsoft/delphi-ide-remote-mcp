# -*- coding: utf-8 -*-
"""1.29 (I8-4 de la 1.21.2): un trozo con comodin (* o ?) de lo que lee el build se negaba, pero como BUILD-050
"OUTSIDE what a build here may read", aunque la carpeta fuera del proyecto: la puerta lo negaba por su anomalia
(GUARD-024) y el mensaje contaba otra cosa. msbuild expande un comodin de un Include a ficheros que nadie nombro,
y lo que lee el build se juzga fichero a fichero: se niega con su propio codigo, BUILD-071, que lo dice.

  W1 <DCCReference Include="sub\\*.pas"/> dentro del proyecto -> BUILD-071 (comodin). ROJO contra 1a549076: BUILD-050
  W2 control: una DCCReference de fuera de la jaula sigue siendo BUILD-050

Uso:  python tests/test_build_comodin_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('build_comodin_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(FUERA)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='comodin', t=300)


def con_referencia(dproj, include):
    t = open(dproj, encoding='utf-8-sig', newline='').read()
    ancla = '<DelphiCompile Include="$(MainSource)">'
    assert ancla in t, dproj
    t = t.replace(ancla, '<DCCReference Include="%s"/>\r\n        %s' % (include, ancla), 1)
    with open(dproj, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(t)


try:
    P = os.path.join(JAIL, 'Com')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Com', 'dir': P})
    os.makedirs(os.path.join(P, 'sub'))
    open(os.path.join(P, 'sub', 'UA.pas'), 'w', encoding='ascii').write(
        'unit UA;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
    DPROJ = os.path.join(P, 'Com.dproj')
    con_referencia(DPROJ, 'sub\\*.pas')
    r = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64'}, 300)
    check('W1 una DCCReference con comodin dentro del proyecto: BUILD-071, no "OUTSIDE". ROJO contra 1a549076',
          mc.abre(r, 'SR_BUILD_LECTURA_COMODIN_FMT') and not mc.abre(r, 'SR_BUILD_LECTURA_FUERA_FMT'), r[:300])

    P2 = os.path.join(JAIL, 'Fue')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fue', 'dir': P2})
    open(os.path.join(FUERA, 'UF.pas'), 'w', encoding='ascii').write(
        'unit UF;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
    DPROJ2 = os.path.join(P2, 'Fue.dproj')
    con_referencia(DPROJ2, os.path.join(FUERA, 'UF.pas'))
    r = srv.call('delphi_build', {'project': DPROJ2, 'platform': 'Win64'}, 300)
    check('W2 control: una DCCReference de fuera sigue siendo BUILD-050', mc.abre(r, 'SR_BUILD_LECTURA_FUERA_FMT'),
          r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('un comodin en lo que lee el build (1.29)')
