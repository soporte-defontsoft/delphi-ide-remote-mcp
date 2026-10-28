# -*- coding: utf-8 -*-
"""1.23.1 (V117) - the package an Android Deploy declares is the one the
packager left, by ONE namer (Lsp.Dproj.PaqueteDeAndroid) with the judge's
grammar (CodeGear.Deployment.targets, APK_FILENAME): the output folder of THAT
build ($(APK_OutputDir), the effective DCC_ExeOutput), its project folder,
bin\\ and the project's name, .aab for a store build of Android64. It was
composed by hand as <Platform>\\<Config>\\<name>\\bin\\<name>.apk. Measured on
28-oct-2026 against the build of V114 (eddf7b6):

  P1 control: a new FMX project, Android64 Deploy: the .apk in
     Android64\\Debug\\<name>\\bin, with BUILD-040
  P2 set-output Compiled and Deploy again: the build declared the OLD .apk of
     P1 (the hand-made path still existed) while the new one was in
     Compiled\\Android64\\Debug\\<name>\\bin
  P3 a project with set-output before its FIRST Deploy: no .apk at the
     hand-made path, so the build declared the .so

P2 and P3 are RED against the build before (pass its exe as argument); P1 is
green with both. The .aab (a store build needs the project's keystore) is the
DUnitX test ElPaqueteDeAndroidComoLoComponeElJuez.

Usage:  python tests/test_paquete_android_1231.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('paquete1231')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='paquete1231', t=900)


def proyecto(nombre):
    """Un FMX nuevo con Android64: su .dproj."""
    d = os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': 'project-fmx', 'name': nombre, 'dir': d})
    check('preparacion: el FMX %s' % nombre, not mc.fallo(r), r[:200])
    dproj = os.path.join(d, nombre + '.dproj')
    r = S.call('delphi_config', {'command': 'add-platform', 'project': dproj, 'platform': 'Android64'})
    check('preparacion: Android64 en %s' % nombre, not mc.fallo(r), r[:200])
    return dproj


def deploy(dproj):
    """delphi_build Deploy de Android64: (json, output en su forma real y larga)."""
    j = mc.como_json(S.call('delphi_build', {'project': dproj, 'platform': 'Android64', 'target': 'Deploy'}, 900)) or {}
    salida = os.path.normcase(mc.larga(mc.real(j['output']))) if j.get('output') else ''
    return j, salida


def esperado(dproj, *trozos):
    nombre = os.path.splitext(os.path.basename(dproj))[0]
    return os.path.normcase(mc.larga(os.path.join(os.path.dirname(dproj), *trozos, nombre, 'bin', nombre + '.apk')))


# ---------------------------------------------------------------- P1 / P2
D1 = proyecto('Pk')
j, salida = deploy(D1)
apk1 = esperado(D1, 'Android64', 'Debug')
check('P1 control: el Deploy declara el .apk de Android64\\Debug\\Pk\\bin, con BUILD-040',
      j.get('success') is True and salida == apk1 and os.path.isfile(apk1) and
      mc.abre(j.get('outputNote', ''), 'SN_BUILD_APK_NOTE'), (salida, str(j)[:300]))
r = S.call('delphi_config', {'command': 'set-output', 'project': D1})
check('P2 preparacion: set-output Compiled', not mc.fallo(r), r[:200])
j, salida = deploy(D1)
apk2 = esperado(D1, 'Compiled', 'Android64', 'Debug')
check('P2 tras set-output, el Deploy declara el .apk NUEVO de Compiled, no el viejo de al lado',
      j.get('success') is True and salida == apk2 and os.path.isfile(apk2) and os.path.isfile(apk1) and
      os.path.getmtime(apk2) >= os.path.getmtime(apk1), (salida, str(j)[:300]))

# ---------------------------------------------------------------- P3
D3 = proyecto('Pk3')
r = S.call('delphi_config', {'command': 'set-output', 'project': D3})
check('P3 preparacion: set-output Compiled antes del primer Deploy', not mc.fallo(r), r[:200])
j, salida = deploy(D3)
apk3 = esperado(D3, 'Compiled', 'Android64', 'Debug')
check('P3 su primer Deploy con salida propia declara su .apk (no el .so), con BUILD-040',
      j.get('success') is True and salida == apk3 and os.path.isfile(apk3) and
      mc.abre(j.get('outputNote', ''), 'SN_BUILD_APK_NOTE'), (salida, str(j)[:300]))

S.cierra()
mc.borra(BASE)
mc.fin('paquete-android-1231 battery')
