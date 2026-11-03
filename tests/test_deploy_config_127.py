# -*- coding: utf-8 -*-
r"""C de la 1.27: lo que el proyecto despliega con otra configuracion, y el manifiesto que se genera en Linux.

Medido el 3-nov-2026 contra el Zorin, como agente: add-deployfile de un fichero de datos sin config= lo
anade a la configuracion activa (Debug), como el Deployment Manager del IDE, que anade a una sola; un
Deploy de Release despues no lo llevo y la respuesta no decia nada (la app enseno "SIN DATOS"). Y
BUILD-005 decia que una app GUI necesita el manifiesto rico del IDE: para Linux64 el IDE escribe el
mismo, el binario (el .deployproj de un FMX suyo), y una FMX corrio con el.

Un perfil falso a 192.0.2.1 (TEST-NET-1: nada responde) con el paclient de verdad: msbuild compila,
llega al Deploy y falla. El aviso es de lo que despliega esa configuracion, no de como acabo, asi que
va tambien con un Deploy que falla; el camino bueno se midio en vivo.

  D1 add-deployfile sin config= dice que es solo de esa configuracion
  D2 un Deploy de Release con el fichero solo en Debug lo dice (deployNotThisConfig), y falla en msbuild
  D3 un Deploy de Debug no dice nada
  D4 con el fichero tambien en Release, nada
  D5 el manifiesto que se genera en Linux dice lo medido (BUILD-067), no BUILD-005

Uso:  python tests/test_deploy_config_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('deploy-config-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
PERFIL = 'mcp-c127-%d' % os.getpid()
APPD, HOST = mc.appdata_perfil(BASE, PERFIL, host='192.0.2.1', platform='Linux64')
P1 = os.path.join(JAIL, 'Datos', 'Datos.dproj')
P2 = os.path.join(JAIL, 'Solo', 'Solo.dproj')
env = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
                  'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': P1 + ';' + P2})
srv = mc.Stdio(EXE, env, nombre='deploy-config-127', t=600)


def deploy(proyecto, config):
    t = srv.call('delphi_build', {'project': proyecto, 'platform': 'Linux64', 'config': config,
                                  'target': 'Deploy', 'profile': PERFIL}, t=600)
    return t, mc.como_json(t) or {}


try:
    for p in (P1, P2):
        srv.call('delphi_create', {'kind': 'project-console', 'dir': os.path.dirname(p),
                                   'name': os.path.splitext(os.path.basename(p))[0]})
        srv.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64', 'project': p})
    with open(os.path.join(JAIL, 'Datos', 'datos.txt'), 'w', encoding='utf-8') as f:
        f.write('datos\n')

    t = srv.call('delphi_config', {'command': 'add-deployfile', 'platform': 'Linux64', 'path': 'datos.txt',
                                   'project': P1})
    check('D1 add-deployfile sin config= dice que es solo de esa configuracion',
          mc.abre(t, 'SN_CONFIG_DEPLOY_ADDED_FMT') and 'configuration Debug only' in t, t[:400])

    t, r = deploy(P1, 'Release')
    # y falla en msbuild, no antes: una puerta que lo negara antes no compondria la respuesta del build
    check('D2 fixture: el Deploy llega a msbuild y falla alli', r.get('success') is False and bool(r.get('errors')),
          t[:600])
    nota = r.get('deployNotThisConfig', '')
    check('D2 un Deploy de Release dice que datos.txt solo va en Debug',
          mc.es(nota, 'SN_BUILD_DEPLOY_OTRAS_CONFIGS_FMT') and 'datos.txt (Debug)' in nota and 'config=Release' in nota,
          t[:900])
    check('D2 el binario de Debug no cuenta: va al mismo sitio que el de Release', 'Datos (' not in nota, nota)

    t, r = deploy(P1, 'Debug')
    check('D3 un Deploy de Debug no dice nada', 'deployNotThisConfig' not in r, r.get('deployNotThisConfig'))

    t = srv.call('delphi_config', {'command': 'add-deployfile', 'platform': 'Linux64', 'path': 'datos.txt',
                                   'config': 'Release', 'project': P1})
    check('D4 fixture: anadido tambien a Release', 'configuration Release only' in t, t[:300])
    t, r = deploy(P1, 'Release')
    check('D4 con el fichero en las dos, nada', 'deployNotThisConfig' not in r, r.get('deployNotThisConfig'))

    t, r = deploy(P2, 'Debug')
    man = r.get('deployManifest', '')
    check('D5 el manifiesto que se genera en Linux dice lo medido (BUILD-067), no BUILD-005',
          mc.es(man, 'SN_BUILD_MANIFEST_NEW_LINUX') and not mc.es(man, 'SN_BUILD_MANIFEST_NEW'), t[:900])
finally:
    srv.cierra()

mc.recoge_huellas()
mc.borra(BASE)
mc.fin('lo que despliega otra configuracion y el manifiesto de Linux 1.27 (C)')
