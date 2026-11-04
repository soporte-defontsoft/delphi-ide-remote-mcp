"""R1: delphi_build target=Deploy con un perfil cuyo host NO esta en RemoteHosts
llega al PAServer sin pasar por la puerta que SI aplican test-connection,
get-sdk y remote-run (ProfileHostDenido). El motor de deploy la salta.

Servidor de prueba con RemoteHosts restringido a 127.0.0.1 (via
DELPHI_MCP_REMOTE_HOSTS, sin tocar el settings.ini de produccion) y un APPDATA de
PRUEBA con un perfil FALSO que apunta a 192.0.2.1 (TEST-NET-1: nada responde). Era
el perfil REAL del IDE (linux-desktop, el Zorin): si la puerta volviera atras, la
bateria desplegaba alli (revisor de baterias de la 1.27; la norma V52).

  D1  control: la puerta restringida DENIEGA test-connection a ese perfil
  D2  delphi_build target=Deploy al MISMO perfil es denegado por la MISMA
      puerta (hoy ROJO: el deploy lo salta y llega a marcar/lanzar PAClient)
  D5  el MISMO deploy SIN profile=, con el perfil declarado en el PROYECTO
      (set-profile): msbuild lee $(Profile) del .dproj, asi que la puerta
      juzga ese (medido 2026-10-06 con la primera version del arreglo, que
      solo miraba el argumento: E0003 contra ese host). Discrimina: el perfil del
      IDE no esta en el APPDATA de prueba, asi que tomarlo daria "no existe"
  D6  sin perfil en la llamada ni en el proyecto: el que el IDE tiene para la
      plataforma (como el IDE; 24-oct-2026), juzgado por la misma puerta (aqui no
      esta en el APPDATA de prueba: "no existe", con su nombre); sin ninguno,
      BUILD-058 antes de compilar (V15 de la 1.23: msbuild recibia /p:Profile=
      vacio y paraba con "Missing profile name" tras 41 s). Se aflojo el 24-oct
      a "cualquier negativa", que aceptaba BUILD-058, justo "no tomo el del IDE"
  D7  remote-run y D8 delphi_desktop con un perfil que NO existe y argumentos
      validos: negados con su motivo (punto 2, la puerta falla cerrado)
  (D9 RETIRADA en la 1.27: el DefaultProfile de EnvOptions.proj ya no interviene,
  un deploy sin perfil no llega a msbuild -BUILD-058 o el perfil del IDE juzgado-,
  y pasaba por PAS-053)

Uso:  python tests/test_deploy_remotehost.py [exe]
"""
import os, sys, json
import mcp_cliente as mc
from mcp_cliente import check

PERFIL = 'mcp-rh-%d' % os.getpid()  # FALSO, en el APPDATA de prueba
HOST_PERFIL = '192.0.2.1'          # TEST-NET-1: nada responde, y no esta en RemoteHosts
PERMITIDO = '127.0.0.1'            # lo unico que esta en RemoteHosts aqui
SDK = 'mcp-rh'                     # un SDK Linux64 FALSO, en el mismo APPDATA

BASE = mc.carpeta('deployrh')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL, exist_ok=True)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
AD, _ = mc.appdata_perfil(BASE, PERFIL, HOST_PERFIL, 'Linux64')
SYSROOT = os.path.join(BASE, 'sysroot-falso')
os.makedirs(SYSROOT, exist_ok=True)
for _ver in os.listdir(os.path.join(AD, 'Embarcadero', 'BDS')):
    with open(os.path.join(AD, 'Embarcadero', 'BDS', _ver, SDK + '.sdk'), 'w', encoding='utf-8') as _f:
        _f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                 '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
                 '  <PropertyGroup>\n    <Profile_platform>Linux64</Profile_platform>\n'
                 '    <Profile_sysroot>%s</Profile_sysroot>\n  </PropertyGroup>\n</Project>\n' % SYSROOT)
ENT = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_REMOTE_HOSTS': PERMITIDO, 'APPDATA': AD,
                  # D7/D8: los interruptores de remote-run abiertos, para que lo
                  # que niegue sea el PERFIL y no AllowRemoteRun ni la lista
                  'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': 'all'})


def marco(out):
    """Si la respuesta dice que se llego a contactar el host del perfil."""
    return ('Connecting to ' + HOST_PERFIL) in out or ('E0003' in out and HOST_PERFIL in out)


srv = mc.Stdio(EXE, ENT, nombre='deployrh', t=600)
try:
    # D1 control: la puerta restringida (RemoteHosts=127.0.0.1) deniega el perfil
    tc = srv.call('delphi_paserver', {'command': 'test-connection', 'name': PERFIL})
    check('D1 control: test-connection al perfil de host no permitido es DENEGADO por la puerta',
          mc.rechazado(tc) and mc.es(tc, 'SR_PASERVER_HOST_DENIED_FMT') and HOST_PERFIL in tc, tc[:400])

    # proyecto console Linux64 para poder desplegar
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'DeployTest',
                                   'dir': os.path.join(JAIL, 'DeployTest')})
    DPROJ = os.path.join(JAIL, 'DeployTest', 'DeployTest.dproj')
    check('fixture: el proyecto nace', not mc.fallo(r) and os.path.isfile(DPROJ), r[:200])
    r = srv.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64',
                                   'sdk': SDK, 'project': DPROJ})
    check('fixture: Linux64 entra en el proyecto con el SDK de prueba', not mc.fallo(r), r[:200])
    # D6: sin perfil en la llamada ni en el proyecto, el que el IDE tiene para la
    # plataforma (RemoteProfiles\Default_Linux64: como despliega el IDE, UNO para todos
    # sus proyectos; David, 24-oct-2026), y JUZGADO como cualquiera: aqui no esta en el
    # APPDATA de prueba y la puerta lo niega por "no existe", con su nombre, antes de
    # compilar. Sin ninguno en el registro (el mismo que ve este servidor), BUILD-058
    VER = mc.instalacion_activa(srv.call).get('version', '')
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Embarcadero\BDS\%s\RemoteProfiles' % VER) as k:
            DEL_IDE = winreg.QueryValueEx(k, 'Default_Linux64')[0]
    except OSError:
        DEL_IDE = ''
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy'}, 600)
    BINARIO = os.path.join(JAIL, 'DeployTest', 'Linux64', 'Debug', 'DeployTest')
    if DEL_IDE:
        check('D6 deploy sin perfil en la llamada ni en el proyecto: toma el del IDE (%s) y la puerta lo juzga '
              '(no esta en este APPDATA: no existe), sin BUILD-058 ni marcar' % DEL_IDE,
              mc.rechazado(out) and mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT') and DEL_IDE in out and
              not mc.es(out, 'SR_BUILD_DEPLOY_SIN_PERFIL_FMT') and not marco(out), out[:400])
    else:
        check('D6 deploy sin perfil en ningun sitio: BUILD-058 antes de compilar, sin marcar ni msbuild',
              mc.abre(out, 'SR_BUILD_DEPLOY_SIN_PERFIL_FMT') and 'Missing profile name' not in out
              and not marco(out) and not os.path.isfile(BINARIO), out[:400])

    # D2: el deploy al perfil de host no permitido, denegado por la MISMA puerta, SIN marcar el host
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy', 'profile': PERFIL}, 600)
    check('D2 el deploy al host no permitido es denegado por la puerta (no llega a marcarlo)',
          mc.rechazado(out) and mc.es(out, 'SR_PASERVER_HOST_DENIED_FMT') and HOST_PERFIL in out and not marco(out),
          out[:500])

    # D3 (punto 2): un perfil que NO existe se NIEGA con su motivo (fail-closed),
    # no se deja pasar al deploy (antes ProfileHostDenido devolvia '' y pasaba).
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy', 'profile': 'noexiste'}, 300)
    check('D3 deploy con perfil inexistente: NEGADO con su motivo (fail-closed, no compila ni marca)',
          mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT') and '"total"' not in out, out[:300])

    # D4 (nombre con espacios): '  <perfil>  ' se juzga IGUAL que '<perfil>' -denegado
    # por su host, no "no existe"-. GUARDA, no check con mutante: quitar el Trim del
    # nombrador la deja en verde (medido 2026-10-06), porque el deploy recorta el nombre
    # ANTES y la puerta y msbuild usan ese mismo valor; se pone roja si alguien vuelve a
    # juzgar uno y usar otro.
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy', 'profile': '  %s  ' % PERFIL}, 300)
    check('D4 perfil con espacios: la puerta lo encuentra (Trim) y lo niega por su host, no por "no existe"',
          mc.es(out, 'SR_PASERVER_HOST_DENIED_FMT') and HOST_PERFIL in out, out[:300])

    # D5: el perfil lo declara el PROYECTO y la llamada no lo nombra. msbuild
    # lee $(Profile) del .dproj: la puerta tiene que juzgar ESE.
    r = srv.call('delphi_config', {'command': 'set-profile', 'platform': 'Linux64',
                                   'profile': PERFIL, 'project': DPROJ})
    check('D5 previo: set-profile deja el perfil en el proyecto', mc.abre(r, 'SN_CONFIG_PROFILE_PUESTO_FMT'), r[:200])
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy'}, 600)
    check('D5 deploy SIN profile= con el perfil del proyecto: la puerta lo niega por su host y no marca',
          mc.es(out, 'SR_PASERVER_HOST_DENIED_FMT') and HOST_PERFIL in out and not marco(out), out[:400])

    # D7/D8 (punto 2 en los otros llamadores de la puerta): argumentos validos y
    # un perfil que NO existe -> negado con su motivo, antes de lanzar nada.
    out = srv.call('delphi_paserver', {'command': 'remote-run', 'name': 'noexiste', 'project': DPROJ})
    check('D7 remote-run con perfil inexistente: NEGADO con su motivo (fail-closed)',
          mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT'), out[:300])
    out = srv.call('delphi_desktop', {'command': 'screenshot', 'profile': 'noexiste'})
    check('D8 delphi_desktop con perfil inexistente: NEGADO con su motivo (fail-closed)',
          mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT'), out[:300])
finally:
    try:
        srv.mata()
    except Exception:
        pass
mc.borra(BASE)
mc.fin('deploy RemoteHosts battery')
