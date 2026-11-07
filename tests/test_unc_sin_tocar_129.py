# -*- coding: utf-8 -*-
"""P1 y P2 del revisor del paisaje de la 1.29: un UNC que nombra un .dproj del agente (su search path) no se
toca en disco antes de negarlo. La puerta de leer de varios lugares resolvia el UNC (RealPath) al preguntar a
los lugares del IDE, del vault y de la biblioteca, y delphi_projects miraba si la carpeta existia antes de la
jaula: los dos conectaban por SMB, con la cuenta del servicio, con el host que el agente pusiera. Medido el
7-nov-2026 contra produccion con \\\\192.0.2.1\\s (TEST-NET, no existe): 21 s delphi_projects y 23 s
delphi_diagnostics, frente a 0,02 y 2 s con una ruta local que no existe. La medida es el reloj: el intento SMB
contra una direccion que no contesta tarda lo que tarda Windows en rendirse; sin intento, nada.

Uso: python tests/test_unc_sin_tocar_129.py [ruta-al-exe]
"""
import os, sys, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('unc_sin_tocar_129')
JAIL = os.path.join(BASE, 'jail')
# un host DISTINTO por tool: Windows recuerda un host que no contesto, y la segunda tool contra el mismo salia
# rapida tambien con el fallo (medido: diagnostics paso con el build de antes tras los 21 s de projects)
for d, v in (('unc1', '\\\\192.0.2.1\\s'), ('unc2', '\\\\192.0.2.2\\s'), ('local', 'D:\\NoExisteNada129\\s')):
    os.makedirs(os.path.join(JAIL, d))
    with open(os.path.join(JAIL, d, 'P.dproj'), 'w', newline='\r\n') as f:
        f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n  <PropertyGroup>\n'
                '    <MainSource>P.dpr</MainSource>\n    <DCC_UnitSearchPath>%s</DCC_UnitSearchPath>\n'
                '  </PropertyGroup>\n</Project>\n' % v)
    with open(os.path.join(JAIL, d, 'P.dpr'), 'w', newline='\r\n') as f:
        f.write('program P;\nbegin\nend.\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=sys.argv[1] if len(sys.argv) > 1 else None)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='unc129', t=120)
TOPE = 8.0  # sin intento SMB, menos de un segundo (el motor, la primera vez, un par)
try:
    for tool, unc, args in (('delphi_projects', 'unc1', lambda d: {'root': os.path.join(JAIL, d)}),
                            ('delphi_diagnostics', 'unc2', lambda d: {'path': os.path.join(JAIL, d, 'P.dpr')})):
        tiempos = {}
        r = ''
        for d in ('local', unc):
            t0 = time.time()
            r = srv.call(tool, args(d), 120)
            tiempos['unc' if d == unc else d] = time.time() - t0
        check('%s con un UNC en el search path del .dproj: no conecta antes de negar (%.1f s, local %.1f s)'
              % (tool, tiempos['unc'], tiempos['local']), tiempos['unc'] < TOPE, r[:200])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('UNC sin tocar el disco 1.29 (P1, P2)')
