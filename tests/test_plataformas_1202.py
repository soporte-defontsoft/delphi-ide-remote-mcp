# -*- coding: utf-8 -*-
"""Lo que es cada plataforma lo decia su NOMBRE, a mano en ~20 sitios
(StartsWith('Win'), StartsWith('Android')...), y tres preguntas distintas
compartian una respuesta: "se compila aqui" valia por "corre aqui" y por
"no despliega por PAServer". Medido el 18-oct-2026 en produccion: view decia
needsProfileForDeploy=true para Android64 con "Android takes no profile" al
lado; set-profile escribia <Profile> en Android64 (el primer Deploy fallaba
E8712 y los siguientes decian "Deployed through profile zorin-desktop" con el
.apk aqui) y aceptaba un perfil de Windows para Linux64 (set-sdk SI mira la
plataforma de su .sdk); y delphi_test ejecutaba un WinARM64EC en este x64:
0xC0000005 y la culpa al runner. Ahora: UNA tabla en Lsp.Dproj (sistema,
maquina, ABI), el juez del perfil en Lsp.Discovery (su Profile_platform, por
sistema: un Mac sirve a OSX e iOS) y Windows dice que maquinas corre.

  P1 view: Android64 needsProfileForDeploy=false y needsSDKForBuild=true
     (ROJO en produccion); Linux64 true/true y Win64 false/false (control)
  P2 set-profile Android64: CFG-123 y el .dproj intacto (ROJO: CFG-014)
  P3 set-profile Linux64 con un perfil de Windows: CFG-124 nombrando el que
     sirve, .dproj intacto (ROJO); P3b control: el de Linux SI (CFG-014)
  P4 Deploy Android64 con profile=: CFG-123 antes de msbuild (ROJO)
  P5 Deploy Linux64 con un perfil de Windows: CFG-124 antes de msbuild y de
     marcar su host (ROJO)
  P6 delphi_test WinARM64EC en una maquina que no ejecuta ARM64: TEST-007 sin
     compilar (ROJO: compilaba y reventaba); P6b control: Win64 corre
  P7 add-deployfile de un .so en Android64: library\\lib\\arm64-v8a\\ (guarda:
     la carpeta del apk sale ahora de la tabla)

Uso:  python tests/test_plataformas_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('plataformas_1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# dos perfiles FALSOS en un APPDATA de prueba: uno de Linux y uno de Windows
AD, HOST = mc.appdata_perfil(BASE, 'linux-p', '127.0.0.1', 'Linux64')
mc.appdata_perfil(BASE, 'win-p', '127.0.0.1', 'Win64')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': AD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
                                'DELPHI_MCP_ALLOW_TESTS': '1'}), nombre='plataformas', t=300)
call = srv.call


def lee(ruta):
    return open(ruta, 'rb').read()


try:
    PROY = os.path.join(JAIL, 'fmx')
    DPROJ = os.path.join(PROY, 'PFmx.dproj')
    r = call('delphi_create', {'kind': 'project-fmx', 'name': 'PFmx', 'dir': PROY}, t=120)
    check('fixture: el proyecto FMX', not mc.fallo(r) and os.path.isfile(DPROJ), r[:200])
    for plat in ('Android64', 'Linux64'):
        r = call('delphi_config', {'project': DPROJ, 'command': 'add-platform', 'platform': plat})
        check('fixture: add-platform %s' % plat, not mc.rechazado(r), r[:200])

    # ------------------------------------------------------------------ P1
    r = call('delphi_config', {'project': DPROJ, 'command': 'view', 'section': 'platforms'})
    plats = {p.get('name'): p for p in (mc.como_json(r) or {}).get('platforms', [])}

    def par(nombre):
        p = plats.get(nombre, {})
        return p.get('needsSDKForBuild'), p.get('needsProfileForDeploy')

    check('P1 view: Android64 lleva SDK y NO perfil para desplegar (despliega por adb)',
          par('Android64') == (True, False), (par('Android64'), r[:300]))
    check('P1 control: Linux64 SDK y perfil, Win64 ninguno de los dos',
          par('Linux64') == (True, True) and par('Win64') == (False, False),
          (par('Linux64'), par('Win64')))

    # ------------------------------------------------------------------ P2
    antes = lee(DPROJ)
    r = call('delphi_config', {'project': DPROJ, 'command': 'set-profile', 'platform': 'Android64',
                               'profile': 'linux-p'})
    check('P2 set-profile en Android64: CFG-123 y el .dproj intacto',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PROFILE_SIN_PASERVER_FMT') and lee(DPROJ) == antes, r[:250])

    # ------------------------------------------------------------------ P3
    r = call('delphi_config', {'project': DPROJ, 'command': 'set-profile', 'platform': 'Linux64',
                               'profile': 'win-p'})
    check('P3 set-profile Linux64 con un perfil de Windows: CFG-124 con el que sirve, .dproj intacto',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PROFILE_OTRO_SISTEMA_FMT') and 'linux-p' in r
          and lee(DPROJ) == antes, r[:300])
    r = call('delphi_config', {'project': DPROJ, 'command': 'set-profile', 'platform': 'Linux64',
                               'profile': 'linux-p'})
    check('P3b control: el perfil de Linux SI se fija en Linux64 (CFG-014)',
          mc.abre(r, 'SN_CONFIG_PROFILE_PUESTO_FMT') and b'<Profile>linux-p</Profile>' in lee(DPROJ), r[:250])

    # ------------------------------------------------------------------ P4
    r = call('delphi_build', {'project': DPROJ, 'platform': 'Android64', 'target': 'Deploy',
                              'profile': 'linux-p'}, t=600)
    check('P4 Deploy Android64 con profile=: CFG-123 antes de compilar',
          mc.es(r, 'SR_CONFIG_PROFILE_SIN_PASERVER_FMT') and '"exitCode"' not in r, r[:250])

    # ------------------------------------------------------------------ P5
    r = call('delphi_build', {'project': DPROJ, 'platform': 'Linux64', 'target': 'Deploy',
                              'profile': 'win-p'}, t=600)
    check('P5 Deploy Linux64 con un perfil de Windows: CFG-124 antes de compilar',
          mc.es(r, 'SR_CONFIG_PROFILE_OTRO_SISTEMA_FMT') and '"exitCode"' not in r, r[:250])

    # ------------------------------------------------------------------ P7
    so = os.path.join(PROY, 'libextra.so')
    open(so, 'wb').write(b'\x7fELF')
    r = call('delphi_config', {'project': DPROJ, 'command': 'add-deployfile', 'platform': 'Android64',
                               'path': so})
    dep = os.path.join(PROY, 'PFmx.deployproj')
    texto = open(dep, encoding='utf-8-sig', errors='replace').read() if os.path.isfile(dep) else ''
    check('P7 add-deployfile de un .so en Android64: a library\\lib\\arm64-v8a\\ del apk',
          not mc.rechazado(r) and 'library\\lib\\arm64-v8a\\' in texto, r[:250])

    # ------------------------------------------------------------------ P6
    TEST = os.path.join(JAIL, 'ptest')
    TDPROJ = os.path.join(TEST, 'PArm.dproj')
    r = call('delphi_create', {'kind': 'project-test', 'name': 'PArm', 'dir': TEST}, t=120)
    check('fixture: el proyecto de tests', not mc.fallo(r) and os.path.isfile(TDPROJ), r[:200])
    r = call('delphi_config', {'project': TDPROJ, 'command': 'add-platform', 'platform': 'WinARM64EC'})
    check('fixture: add-platform WinARM64EC', not mc.rechazado(r), r[:200])
    # lo que dice Windows de ARM64 en esta maquina (GetMachineTypeAttributes,
    # el juez del servidor; 1 = UserEnabled)
    attrs = ctypes.c_uint(0)
    try:
        hr = ctypes.windll.kernel32.GetMachineTypeAttributes(0xAA64, ctypes.byref(attrs))
        arm64 = (hr == 0) and bool(attrs.value & 1)
    except AttributeError:
        arm64 = False   # Windows sin la funcion: x86/x64
    if arm64:
        print('NOTA P6 sin medir: esta maquina ejecuta ARM64, WinARM64EC SI corre aqui')
    else:
        r = call('delphi_test', {'command': 'run', 'project': TDPROJ, 'platform': 'WinARM64EC'}, t=600)
        check('P6 delphi_test WinARM64EC en una maquina que no ejecuta ARM64: TEST-007 sin compilar',
              mc.es(r, 'SR_TEST_PLATFORM_FMT') and '"binary"' not in r and '"exitCode"' not in r, r[:250])
    r = call('delphi_test', {'command': 'run', 'project': TDPROJ, 'platform': 'Win64'}, t=600)
    check('P6b control: Win64 compila y corre aqui',
          (mc.como_json(r) or {}).get('result') == 'pass', r[:250])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('plataformas por la tabla y los jueces 1202')
