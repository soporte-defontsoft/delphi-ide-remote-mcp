# -*- coding: utf-8 -*-
"""1.29 (A19): delphi_build Deploy de Android con un .deployproj que YA existe y no despliega Android - el que dejo
el deploy de otra plataforma (Linux64, Win64) o el que escribe el IDE con el grupo de Android vacio. El servidor solo
generaba el mapa de Android si no habia manifiesto (BUILD-039) y no completaba uno existente como hace con la salida
de Linux64/Win64 (BUILD-014): msbuild paraba con E8712 (AndroidManifest.xml does not exist). Dos informes, el 31-oct
(1.23.1) y el 7-nov (medido por el agente: con el .deployproj en la papelera, el Deploy genero y salio el apk).

  Q1 un .deployproj con solo Linux64: el Deploy de Android64 sale (el .apk) y BUILD-073 lo dice. ROJO contra 166bea8b (E8712)
  Q1 ...el grupo de Linux64 sigue tal cual, y el de Android64 lleva su manifiesto y su salida con la config
  Q2 otro Deploy: nada que anadir, el .deployproj no cambia y sin nota
  Q3 el grupo vacio del IDE para Android64 (y uno de Win64): se llena, sale el .apk y el de Win64 no se toca

Uso:  python tests/test_android_deployproj_129.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('android_deployproj_129')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='android129', t=900)

CABECERA = ('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
            '    <Import Condition="Exists(\'$(BDS)\\bin\\CodeGear.Deployment.targets\')" '
            'Project="$(BDS)\\bin\\CodeGear.Deployment.targets"/>\n'
            '    <ProjectExtensions>\n        <ProjectFileVersion>12</ProjectFileVersion>\n    </ProjectExtensions>\n')


def grupo_salida(plataforma, nombre, binario):
    return ('    <ItemGroup Condition="\'$(Platform)\'==\'%s\' And \'$(Config)\'==\'Debug\'">\n'
            '        <DeployFile Include="%s\\Debug\\%s" Condition="\'$(Config)\'==\'Debug\'">\n'
            '            <RemoteDir>%s\\</RemoteDir>\n            <RemoteName>%s</RemoteName>\n'
            '            <DeployClass>ProjectOutput</DeployClass>\n            <Operation>1</Operation>\n'
            '            <LocalCommand/>\n            <RemoteCommand/>\n            <Overwrite>True</Overwrite>\n'
            '            <Required>True</Required>\n        </DeployFile>\n    </ItemGroup>\n'
            % (plataforma, plataforma, binario, nombre, binario))


def proyecto(nombre, manifiesto):
    """Un FMX nuevo con Android64 y el .deployproj dado: su .dproj."""
    d = os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': 'project-fmx', 'name': nombre, 'dir': d})
    check('preparacion: el FMX %s' % nombre, not mc.fallo(r), r[:200])
    dproj = os.path.join(d, nombre + '.dproj')
    r = S.call('delphi_config', {'command': 'add-platform', 'project': dproj, 'platform': 'Android64'})
    check('preparacion: Android64 en %s' % nombre, not mc.fallo(r), r[:200])
    with open(os.path.join(d, nombre + '.deployproj'), 'w', encoding='utf-8-sig', newline='') as f:
        f.write(manifiesto.replace('\n', '\r\n'))
    return dproj


def deploy(dproj):
    return mc.como_json(S.call('delphi_build', {'project': dproj, 'platform': 'Android64', 'target': 'Deploy'},
                               900)) or {}


def lee(dproj):
    with open(os.path.splitext(dproj)[0] + '.deployproj', encoding='utf-8-sig', newline='') as f:
        return f.read()


def huella(dproj):
    return hashlib.sha256(open(os.path.splitext(dproj)[0] + '.deployproj', 'rb').read()).hexdigest()


def apk(dproj):
    n = os.path.splitext(os.path.basename(dproj))[0]
    return os.path.join(os.path.dirname(dproj), 'Android64', 'Debug', n, 'bin', n + '.apk')


try:
    # ------------------------------------------------------------------ Q1, Q2
    LINUX = grupo_salida('Linux64', 'Ad', 'Ad')
    D1 = proyecto('Ad', CABECERA + LINUX + '</Project>\n')
    j = deploy(D1)
    check('Q1 un .deployproj con solo Linux64: el Deploy de Android64 sale (el .apk). ROJO contra 166bea8b',
          j.get('success') is True and os.path.isfile(apk(D1)), str(j)[:500])
    check('Q1 ...y BUILD-073 lo dice', mc.abre(j.get('deployManifest', ''), 'SN_BUILD_ANDROID_FILLED_FMT'),
          j.get('deployManifest'))
    x = lee(D1)
    check('Q1 ...el grupo de Linux64 sigue tal cual', LINUX.replace('\n', '\r\n') in x, x[:600])
    android = re.findall(r'<DeployFile Include="([^"]+)" Condition="\'\$\(Config\)\'==\'Debug\'">\s*'
                         r'<RemoteDir>[^<]*</RemoteDir>\s*<RemoteName>[^<]*</RemoteName>\s*'
                         r'<DeployClass>(ProjectAndroidManifest|ProjectOutput)</DeployClass>', x)
    check('Q1 ...y Android64 lleva su manifiesto y su salida (libAd.so) con la config Debug',
          any(c == 'ProjectAndroidManifest' and i.endswith('AndroidManifest.xml') for i, c in android) and
          any(c == 'ProjectOutput' and i.endswith('libAd.so') for i, c in android) and
          "'$(Platform)'=='Android64'" in x, android)
    h = huella(D1)
    j = deploy(D1)
    check('Q2 otro Deploy: sale, el .deployproj no cambia y sin nota del manifiesto',
          j.get('success') is True and huella(D1) == h and not j.get('deployManifest'), str(j)[:300])

    # ------------------------------------------------------------------ Q3
    WIN = grupo_salida('Win64', 'Ae', 'Ae.exe')
    D3 = proyecto('Ae', CABECERA + WIN + '    <ItemGroup Condition="\'$(Platform)\'==\'Android64\'"/>\n</Project>\n')
    j = deploy(D3)
    x = lee(D3)
    check('Q3 el grupo vacio del IDE para Android64: se llena y sale el .apk (BUILD-073)',
          j.get('success') is True and os.path.isfile(apk(D3)) and
          mc.abre(j.get('deployManifest', ''), 'SN_BUILD_ANDROID_FILLED_FMT') and
          "<ItemGroup Condition=\"'$(Platform)'=='Android64'\"/>" not in x and 'ProjectAndroidManifest' in x,
          (str(j)[:300], x[-600:]))
    check('Q3 ...y el de Win64 no se toca', WIN.replace('\n', '\r\n') in x, x[:600])
finally:
    S.cierra()
    mc.borra(BASE)
mc.fin('android deployproj 1.29 (A19)')
