# -*- coding: utf-8 -*-
"""1.29 (WATCH del 6-nov): delphi_search y delphi_list sin pattern miraban las fuentes, los designers y los
.dproj/.groupproj, y no el manifiesto de despliegue del IDE (.deployproj), el otro fichero del proyecto: una
busqueda de un RemoteDir escaneaba 2 de los 3 ficheros de un proyecto y no lo encontraba (medido).

  D1 delphi_search sin pattern encuentra un texto del .deployproj. ROJO contra 6fd7d045
  D2 delphi_list sin pattern lo lista. ROJO contra 6fd7d045
  D3 control: un .txt sigue fuera del conjunto por defecto

Uso:  python tests/test_search_deployproj_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('search_deployproj_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='search-dp', t=60)
try:
    P = os.path.join(JAIL, 'Dep')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Dep', 'dir': P})
    with open(os.path.join(P, 'Dep.deployproj'), 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
                '    <ItemGroup Condition="\'$(Platform)\'==\'Win64\'">\n'
                '        <DeployFile Include="Win64\\Debug\\Dep.exe" Condition="\'$(Config)\'==\'Debug\'">\n'
                '            <RemoteDir>MarcaRemota129\\</RemoteDir>\n'
                '        </DeployFile>\n    </ItemGroup>\n</Project>\n')
    open(os.path.join(P, 'notas.txt'), 'w', encoding='ascii').write('MarcaRemota129 en un txt\n')
    j = mc.como_json(srv.call('delphi_search', {'root': P, 'query': 'MarcaRemota129'})) or {}
    ficheros = [fi.get('name') for d in j.get('folders', []) for fi in d.get('files', [])]
    check('D1 delphi_search sin pattern encuentra el RemoteDir del .deployproj. ROJO contra 6fd7d045',
          'Dep.deployproj' in ficheros, (ficheros, str(j)[:200]))
    check('D3 control: el .txt sigue fuera del conjunto por defecto', 'notas.txt' not in ficheros, ficheros)
    r = srv.call('delphi_list', {'root': P})
    check('D2 delphi_list sin pattern lista el .deployproj. ROJO contra 6fd7d045', 'Dep.deployproj' in r, r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('el .deployproj en el conjunto por defecto de search y list (1.29)')
