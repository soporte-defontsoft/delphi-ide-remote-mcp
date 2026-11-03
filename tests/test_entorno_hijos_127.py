# -*- coding: utf-8 -*-
r"""Colaterales de A1 de la 1.27: lo que el servidor lanza no hereda su configuracion del entorno.

EntornoSinConfiguracion (Lsp.Sandbox) es el bloque de entorno sin las DELPHI_MCP_*: en modo consola
alli pueden ir el token (DELPHI_MCP_TOKEN, DELPHI_MCP_READONLY_TOKEN) y los ajustes del servidor. Lo
usaban msbuild, git y los contenedores; paclient, adb y su demonio, reg.exe y el motor DelphiLSP
heredaban el entorno ENTERO (CreateProcessConHandles con entorno nil, medido en el fuente el
3-nov-2026; el servicio no tiene DELPHI_MCP_* en su entorno, asi que en produccion no llegaba nada).
Ahora un entorno sin dar es ese bloque: lo da EntornoDelHijo (Lsp.Sandbox), y lo preguntan los cuatro que
lanzan (RunCore y RunDetached de Lsp.BuildRunner, el motor en Lsp.Transport.Process, el contenedor);
Lsp.ProcessLaunch no puede llevarla (la enlaza McpRunJob). Esta bateria mide RunCore (paclient); la fila
"un lanzamiento sin EntornoDelHijo" de test_paisaje vigila los demas.

  H1 paclient (un falso que vuelca lo que ve) no ve ninguna DELPHI_MCP_*, ni el token (ROJA contra
     la 1.26.1)
  H2 control: si ve una variable normal del entorno (MCP_STUB_SONDA): el entorno se hereda, sin lo
     nuestro

Uso:  python tests/test_entorno_hijos_127.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('entorno-hijos-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
VOLCADO = os.path.join(BASE, 'volcado.json')
VUELCA = os.path.join(BASE, 'vuelca.py')
with open(VUELCA, 'w', encoding='utf-8') as f:
    f.write("import json, os\n"
            "nombres = sorted(k.upper() for k in os.environ if k.upper().startswith(('DELPHI_MCP_', 'MCP_STUB_')))\n"
            "open(os.environ['MCP_STUB_VOLCADO'], 'w', encoding='utf-8').write(json.dumps(nombres))\n"
            "raise SystemExit(1)\n")
# paclient = un falso que solo vuelca los NOMBRES de lo que ve (nunca valores)
STUB = os.path.join(BASE, 'paclient.cmd')
with open(STUB, 'w') as f:
    f.write('@echo off\r\npython "%s"\r\n' % VUELCA)
PROF = 'sonda127'
_ad, _host = mc.appdata_perfil(BASE, PROF, '127.0.0.1')
env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = JAIL
env['DELPHI_MCP_PACLIENT'] = STUB
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host
env['DELPHI_MCP_SONDA_127'] = 'centinela'
env['DELPHI_MCP_TOKEN'] = 'tokenCentinela127'
env['MCP_STUB_VOLCADO'] = VOLCADO
env['MCP_STUB_SONDA'] = '1'
srv = mc.Stdio(EXE, env, nombre='entorno-hijos-127', t=120)

try:
    r = srv.call('delphi_paserver', {'command': 'test-connection', 'profile': PROF})
    vio = None
    if os.path.isfile(VOLCADO):
        with open(VOLCADO, encoding='utf-8') as f:
            vio = json.load(f)
    check('fixture: paclient (el falso) corrio y volco lo que ve', vio is not None, r[:300])
    vio = vio or []
    nuestras = [k for k in vio if k.startswith('DELPHI_MCP_')]
    check('H1 paclient no ve ninguna DELPHI_MCP_* del servidor, ni el token', not nuestras, nuestras)
    check('H2 control: si ve una variable normal del entorno (MCP_STUB_SONDA)', 'MCP_STUB_SONDA' in vio, vio)
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('lo que el servidor lanza no hereda su configuracion del entorno 1.27 (A1)')
