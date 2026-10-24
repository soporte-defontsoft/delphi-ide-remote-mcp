# -*- coding: utf-8 -*-
r"""Arreglos evidentes pequenos de la 1.23 (V15, V35, V16). Cada caso, medido en produccion
antes de arreglarlo (24-oct-2026):

  E1  V15: delphi_build target=Deploy de Win64 sin perfil en la llamada, el proyecto ni el
      IDE (este registro no tiene Default_Win64): BUILD-058 antes de msbuild, nada compilado
      y los perfiles que despliegan la plataforma. Con su manifiesto paraba en "Missing
      profile name" de msbuild (en Linux64, tras 41 s compilando)...
  E1b ...y sin manifiesto, en MSB4057 "The target Deploy does not exist", que no dice que
      falta un perfil
  E2  V35: un escritor del .dproj (add-searchpath) en un .dproj MIXTO (LF con una linea
      CRLF): lo que no toca, byte a byte, y lo nuevo con el dominante. Dejaba en CRLF la
      linea LF de delante del bloque insertado (PatchSaveConSuSalto pasaba lo nuevo al
      dominante solo si el fichero no tenia ningun CRLF)
  E3  V16 (Hermes, 22-oct): el .res de version, uno para las plataformas que comparten
      carpeta: un Build de Linux64 lo deja sin recursos (32 bytes) y lo dice, BUILD-059,
      una vez; un Make de Win64 no lo rehace (el exe sin icono ni version) y lo dice,
      BUILD-060; un Build lo rehace y calla. Callaba

Mutante: produccion antes de este bloque (r1222av): E1, E1b, E2 y E3 rojos.

Uso:  python tests/test_evidente_1230.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('evidente1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def tam(p):
    return os.path.getsize(p) if os.path.isfile(p) else -1


antes_atomos = mc.atomos_rtl_nombres()
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='evidente1230', t=900)
try:
    # --- E1, E1b -------------------------------------------------------------------
    # el juez de "no hay perfil del IDE para Win64": el registro que ve este servidor
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Embarcadero\BDS\37.0\RemoteProfiles') as k:
            del_ide = winreg.QueryValueEx(k, 'Default_Win64')[0]
    except OSError:
        del_ide = ''
    if del_ide:
        print('NOTA: E1/E1b no se miden: este registro tiene perfil del IDE para Win64 (%s)' % del_ide)
    else:
        SDIR = os.path.join(JAIL, 'sinmanifiesto')
        srv.call('delphi_create', {'kind': 'project-console', 'name': 'Sm', 'dir': SDIR})
        r = srv.call('delphi_build', {'project': os.path.join(SDIR, 'Sm.dproj'), 'platform': 'Win64',
                                      'config': 'Debug', 'target': 'Deploy'}, t=600)
        check('E1b Deploy Win64 sin perfil ni manifiesto: BUILD-058 (no MSB4057), nada compilado',
              mc.abre(r, 'SR_BUILD_DEPLOY_SIN_PERFIL_FMT') and 'MSB4057' not in r
              and tam(os.path.join(SDIR, 'Win64', 'Debug', 'Sm.exe')) < 0, r[:400])
        DDIR = os.path.join(JAIL, 'conmanifiesto')
        srv.call('delphi_create', {'kind': 'project-console', 'name': 'Dm', 'dir': DDIR})
        DDPROJ = os.path.join(DDIR, 'Dm.dproj')
        r = srv.call('delphi_config', {'command': 'add-deployfile', 'project': DDPROJ, 'platform': 'Win64',
                                       'file': os.path.join(DDIR, 'Dm.dpr')})
        check('E1 previo: add-deployfile deja el manifiesto', os.path.isfile(os.path.join(DDIR, 'Dm.deployproj')),
              r[:300])
        r = srv.call('delphi_build', {'project': DDPROJ, 'platform': 'Win64', 'config': 'Debug',
                                      'target': 'Deploy'}, t=600)
        check('E1 Deploy Win64 sin perfil en ningun sitio y con manifiesto: BUILD-058 antes de msbuild '
              '(no "Missing profile name"), nada compilado, y nombra la plataforma',
              mc.abre(r, 'SR_BUILD_DEPLOY_SIN_PERFIL_FMT') and 'Missing profile name' not in r
              and 'Profiles that deploy Win64:' in r
              and tam(os.path.join(DDIR, 'Win64', 'Debug', 'Dm.exe')) < 0, r[:400])

    # --- E2 ------------------------------------------------------------------------
    XDIR = os.path.join(JAIL, 'mixto')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Mx', 'dir': XDIR})
    XDPROJ = os.path.join(XDIR, 'Mx.dproj')
    b = open(XDPROJ, 'rb').read().replace(b'\r\n', b'\n')
    i = b.index(b'<ProjectGuid>')
    j = b.index(b'\n', i)
    b = b[:j] + b'\r' + b[j:]   # la linea del ProjectGuid, la unica en CRLF
    open(XDPROJ, 'wb').write(b)
    r = srv.call('delphi_config', {'command': 'add-searchpath', 'project': XDPROJ, 'path': XDIR})
    d = open(XDPROJ, 'rb').read()
    crlf = [ln for ln in d.split(b'\n') if ln.endswith(b'\r')]
    check('E2 add-searchpath en un .dproj LF con una linea CRLF: anadido, y la unica CRLF sigue siendo '
          'la del ProjectGuid (la de delante del bloque se quedaba en CRLF)',
          mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and len(crlf) == 1 and b'<ProjectGuid>' in crlf[0]
          and b'DCC_UnitSearchPath' in d, (r[:200], crlf))

    # --- E3 ------------------------------------------------------------------------
    RDIR = os.path.join(JAIL, 'res')
    srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'Rs', 'dir': RDIR})
    RDPROJ = os.path.join(RDIR, 'Rs.dproj')
    RES = os.path.join(RDIR, 'Rs.res')
    J = mc.como_json

    def build(plat, target):
        return srv.call('delphi_build', {'project': RDPROJ, 'platform': plat, 'config': 'Debug',
                                         'target': target}, t=900)

    r = build('Win64', 'Build')
    check('E3 previo: Build Win64 deja el .res con sus recursos, sin nota',
          J(r).get('success') is True and tam(RES) > 32 and 'resNote' not in J(r), (tam(RES), r[:300]))
    srv.call('delphi_config', {'command': 'add-platform', 'project': RDPROJ, 'platform': 'Linux64'})
    r = build('Linux64', 'Build')
    check('E3 Build Linux64: deja el .res SIN recursos y lo dice (BUILD-059), con el Make y el Build de Windows',
          J(r).get('success') is True and tam(RES) == 32
          and mc.abre(J(r).get('resNote', ''), 'SN_BUILD_RES_SIN_RECURSOS_FMT')
          and 'target=Build' in J(r).get('resNote', ''), (tam(RES), r[:500]))
    r = build('Linux64', 'Build')
    check('E3 ...otro Build Linux64 con el .res ya vacio: no lo repite',
          J(r).get('success') is True and 'resNote' not in J(r), r[:400])
    r = build('Win64', 'Make')
    check('E3 Make Win64 con el .res vacio: no lo rehace y lo dice (BUILD-060)',
          J(r).get('success') is True and tam(RES) == 32
          and mc.abre(J(r).get('resNote', ''), 'SN_BUILD_RES_SIN_RECURSOS_MAKE_FMT'), (tam(RES), r[:500]))
    r = build('Win64', 'Build')
    check('E3 Build Win64: lo rehace (con recursos) y calla',
          J(r).get('success') is True and tam(RES) > 32 and 'resNote' not in J(r), (tam(RES), r[:400]))
finally:
    srv.cierra()
    print('atomos RTL nuevos de procesos muertos:', mc.atomos_rtl_dejados(antes_atomos))
    try:
        mc.fin('arreglos evidentes pequenos 1230 (V15, V35, V16)')
    finally:
        mc.borra(BASE)
