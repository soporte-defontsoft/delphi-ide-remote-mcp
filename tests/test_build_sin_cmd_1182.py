# -*- coding: utf-8 -*-
"""2an de la 1.18.2: el build no pasa por cmd.exe (David, 13-oct: "un agente
pide una operacion, nunca ejecuta nada"; CLAUDE.md, "An agent asks for an
operation"). msbuild se lanzaba como cmd.exe /c "rsvars.bat && msbuild ...",
con la configuracion, el perfil y el dispositivo del agente en esa linea, y
heredando el entorno ENTERO del servidor - su configuracion incluida
(DELPHI_MCP_ROOTS, el token...). Ahora msbuild.exe se lanza directo
(CreateProcess), con el entorno de rsvars.bat leido por EL lector
(Lsp.Discovery.VariablesDeRsVars) y sin las DELPHI_MCP_* (EntornoSinConfiguracion,
el mismo de delphi_test).

El rojo es de COMPORTAMIENTO, sin inyectar nada: un .dproj con un <Target>
inerte (un <Message>, que no pide AllowBuildScripts) que imprime lo que msbuild
ve del entorno. En produccion sale la jaula; con el arreglo, vacio.

  E1 msbuild NO ve $(DELPHI_MCP_ROOTS) (rojo en produccion: la ruta de la jaula)
  E2 ...ni $(DELPHI_MCP_ALLOW_TESTS)
  E3 control: una variable que no es de configuracion (MARCA_2AN_1182) SI llega:
     el entorno no se vacia (msbuild necesita PATH, TEMP, SystemRoot...)
  E4 control: las de rsvars.bat llegan aunque el servidor no las tenga
     ($(FrameworkVersion) y $(BDSCOMMONDIR)): sin cmd, las pone EL lector
  E5 el build compila (el Target corre DESPUES de Build: si no compila, no hay
     sonda)
  E6 un msbuild.bat que el agente deja en la carpeta de su proyecto NO se
     ejecuta, y compila el msbuild de verdad. Con cmd.exe en medio, cmd busca
     'msbuild' PRIMERO en su cwd, que desde 2ak es esa carpeta: en produccion
     (cfea828) el .bat corria con la cuenta del servicio (medido el 13-oct con
     este mismo .bat inerte: crea un marcador y sale con 1).

OJO, medido: el harness de Claude pone NoDefaultCurrentDirectoryInExePath=1,
que le quita a cmd esa busqueda, y el servicio NO la tiene (ni de usuario ni de
maquina). mc.entorno se la QUITA a todo servidor de prueba (y esta bateria, por
si acaso, tambien): con ella heredada, E6 pasaba en verde contra produccion (la
primera sonda salio negativa por eso).

La config con espacio ("Release Plus") la mide test_config_1181 (C4/C4b).

Uso:  python tests/test_build_sin_cmd_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import glob
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build_sin_cmd_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

env = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1',
                  'MARCA_2AN_1182': 'visible'})
# lo de rsvars.bat FUERA del entorno del servidor: si msbuild lo ve, lo puso
# quien lanza msbuild (rsvars por cmd antes, EL lector ahora), no la herencia
for k in list(env):
    if k.upper() in ('BDS', 'BDSINCLUDE', 'BDSCOMMONDIR', 'LANGDIR', 'FRAMEWORKDIR',
                     'FRAMEWORKVERSION', 'FRAMEWORKSDKDIR', 'PLATFORMSDK',
                     'NODEFAULTCURRENTDIRECTORYINEXEPATH'):
        del env[k]

SONDA = ('<Target Name="Sonda2an" AfterTargets="Build"><Message Importance="high" '
         'Text="SONDA2AN ROOTS=[$(DELPHI_MCP_ROOTS)] TESTS=[$(DELPHI_MCP_ALLOW_TESTS)] '
         'OTRA=[$(MARCA_2AN_1182)] FWVER=[$(FrameworkVersion)] BDSCOMMON=[$(BDSCOMMONDIR)]"/></Target>')

SKIP = None
srv = mc.Stdio(EXE, env, nombre='build-sin-cmd', cwd=BASE, t=600)
try:
    d = os.path.join(JAIL, 'Sonda2an')
    r = srv.call('delphi_create', {'kind': 'project-console', 'dir': d, 'name': 'Sonda2an'})
    hit = glob.glob(os.path.join(d, '**', 'Sonda2an.dproj'), recursive=True)
    if not hit:
        SKIP = 'delphi_create no dejo el proyecto: %s' % r[:200]
    else:
        dproj = hit[0]
        raw = open(dproj, 'rb').read()
        bom = raw.startswith(b'\xef\xbb\xbf')
        xml = raw.decode('utf-8-sig')
        assert xml.count('</Project>') == 1
        xml = xml.replace('</Project>', SONDA + '\r\n</Project>')
        open(dproj, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + xml.encode('utf-8'))
        r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug',
                                      'verbosity': 'normal'}, t=600)
        if mc.catalogo()['SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED'] in r:
            SKIP = 'no hay RAD Studio en esta maquina'
        else:
            m = re.search(r'SONDA2AN ROOTS=\[(.*?)\] TESTS=\[(.*?)\] OTRA=\[(.*?)\] '
                          r'FWVER=\[(.*?)\] BDSCOMMON=\[(.*?)\]', r)
            check('E5 el build compila y la sonda (un <Message> despues de Build) habla',
                  m is not None and '"success": true' in r.replace('"success":true', '"success": true'),
                  r[:600])
            if m:
                roots, tests, otra, fwver, bdscommon = m.groups()
                check('E1 msbuild NO ve DELPHI_MCP_ROOTS (la configuracion del servidor)',
                      roots == '', roots)
                check('E2 ...ni DELPHI_MCP_ALLOW_TESTS', tests == '', tests)
                check('E3 control: una variable que no es de configuracion SI llega (el entorno no se vacia)',
                      otra == 'visible', otra)
                # FrameworkVersion y BDSCOMMONDIR: solo las pone rsvars.bat (LANGDIR
                # no vale: los targets de Embarcadero la redefinen, sale " '' " con
                # cmd y sin el, medido el 13-oct)
                check('E4 control: las de rsvars.bat llegan sin que el servidor las tenga '
                      '($(FrameworkVersion), $(BDSCOMMONDIR))',
                      fwver.strip() != '' and bdscommon.strip() != '', (fwver, bdscommon))

            # E6 un msbuild.bat plantado en la carpeta del proyecto
            d = os.path.join(JAIL, 'Planta2an')
            srv.call('delphi_create', {'kind': 'project-console', 'dir': d, 'name': 'Planta2an'})
            hit = glob.glob(os.path.join(d, '**', 'Planta2an.dproj'), recursive=True)
            if hit:
                carpeta = os.path.dirname(hit[0])
                marca = os.path.join(carpeta, 'marcador.txt')
                open(os.path.join(carpeta, 'msbuild.bat'), 'w').write(
                    '@echo off\r\necho plantado> "%~dp0marcador.txt"\r\nexit /b 1\r\n')
                r = srv.call('delphi_build', {'project': hit[0], 'platform': 'Win64', 'config': 'Debug'}, t=600)
                check('E6 un msbuild.bat plantado en la carpeta del proyecto NO se ejecuta (y compila el de verdad)',
                      not os.path.exists(marca) and '"success":true' in r.replace(' ', ''),
                      (os.path.exists(marca), r[:300]))
            else:
                check('E6 delphi_create dejo el proyecto de la planta', False, '')
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('build sin cmd.exe 1182 (2an)', sin_checks=SKIP)
