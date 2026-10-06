"""R1: delphi_build target=Deploy con un perfil cuyo host NO esta en RemoteHosts
llega al PAServer sin pasar por la puerta que SI aplican test-connection,
get-sdk y remote-run (ProfileHostDenido). El motor de deploy la salta.

Servidor de prueba con RemoteHosts restringido a 127.0.0.1 (via
DELPHI_MCP_REMOTE_HOSTS, sin tocar el settings.ini de produccion). El perfil
'linux-desktop' existe en el IDE y apunta a 192.168.1.177, que NO esta en esa
lista y esta caido (un deploy no envia nada). Control: 192.168.1.177 es el
"fuera"; con la puerta puesta no se contacta.

  D1  control: la puerta restringida DENIEGA test-connection a ese perfil
  D2  delphi_build target=Deploy al MISMO perfil es denegado por la MISMA
      puerta (hoy ROJO: el deploy lo salta y llega a marcar/lanzar PAClient)
  D5  el MISMO deploy SIN profile=, con el perfil declarado en el PROYECTO
      (set-profile): msbuild lee $(Profile) del .dproj, asi que la puerta
      juzga ese (medido 2026-10-06 con la primera version del arreglo, que
      solo miraba el argumento: E0003 contra 192.168.1.177)
  D6  sin perfil en la llamada ni en el proyecto: msbuild recibe /p:Profile=
      vacio (global: EnvOptions no le pone otro) y para con su propio error
  D7  remote-run y D8 delphi_desktop con un perfil que NO existe y argumentos
      validos: negados con su motivo (punto 2, la puerta falla cerrado)
  D9  un entorno del IDE con perfil POR DEFECTO para Linux64 (DefaultProfile
      en EnvOptions.proj, en un APPDATA de prueba) que apunta fuera de
      RemoteHosts: un deploy sin perfil no lo usa, porque msbuild recibe
      /p:Profile= vacio, que es global. Medido con el mutante (sin ese vacio):
      msbuild toma el perfil por defecto y el PAClient marca (E0003; con el
      APPDATA de prueba marca localhost, no el host del .profile falso: el
      PAClient no lee ese fichero, y el rojo es por usar un perfil sin juzgar)

Uso:  python tests/test_deploy_remotehost.py [exe]
"""
import os, sys, json
import mcp_cliente as mc
from mcp_cliente import check

PERFIL = 'linux-desktop'           # existe en el IDE, host 192.168.1.177
HOST_PERFIL = '192.168.1.177'
PERMITIDO = '127.0.0.1'            # lo unico que esta en RemoteHosts aqui

BASE = mc.carpeta('deployrh')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL, exist_ok=True)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
ENT = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_REMOTE_HOSTS': PERMITIDO,
                  # D7/D8: los interruptores de remote-run abiertos, para que lo
                  # que niegue sea el PERFIL y no AllowRemoteRun ni la lista
                  'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': 'all'})


def J(t):
    try: return json.loads(t)
    except Exception: return {}


srv = mc.Stdio(EXE, ENT, nombre='deployrh', t=600)
try:
    # D1 control: la puerta restringida (RemoteHosts=127.0.0.1) deniega el perfil
    tc = srv.call('delphi_paserver', {'command': 'test-connection', 'name': PERFIL})
    denied = mc.es(tc, 'SR_PASERVER_HOST_DENIED_FMT') or ('denied' in tc.lower() and HOST_PERFIL in tc)
    check('D1 control: test-connection al perfil de host no permitido es DENEGADO por la puerta',
          denied, tc[:400])

    # proyecto console Linux64 para poder desplegar
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'DeployTest',
                                   'dir': os.path.join(JAIL, 'DeployTest')})
    DPROJ = os.path.join(JAIL, 'DeployTest', 'DeployTest.dproj')
    r = srv.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64',
                                   'sdk': 'zorin18', 'project': DPROJ})
    # D6: sin perfil en la llamada ni en el proyecto. /p:Profile= vacio es una
    # propiedad global: msbuild no lo rellena con el DefaultProfile del entorno
    # y para con SU error, sin marcar a nadie (y sin rechazar la linea: MSB1006).
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy'}, 600)
    check('D6 deploy sin perfil en ningun sitio: msbuild para con "Missing profile name", sin marcar',
          'Missing profile name' in out and HOST_PERFIL not in out and 'MSB1006' not in out, out[:400])

    # D2: el deploy al perfil de host no permitido
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy', 'profile': PERFIL}, 600)
    j = J(out)
    # denegado por la MISMA puerta = el motivo de host denegado, SIN marcar el host
    por_puerta = mc.es(out, 'SR_PASERVER_HOST_DENIED_FMT') or \
        (('denied' in out.lower()) and (HOST_PERFIL in out) and ('Connecting to' not in out))
    marco_host = ('Connecting to ' + HOST_PERFIL) in out or ('E0003' in out and HOST_PERFIL in out)
    check('D2 el deploy al host no permitido es denegado por la puerta (no llega a marcarlo)',
          por_puerta and not marco_host,
          'por_puerta=%s marco_host=%s | %s' % (por_puerta, marco_host, out[:500]))

    # D3 (punto 2): un perfil que NO existe se NIEGA con su motivo (fail-closed),
    # no se deja pasar al deploy (antes ProfileHostDenido devolvia '' y pasaba).
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy', 'profile': 'noexiste'}, 300)
    check('D3 deploy con perfil inexistente: NEGADO con su motivo (fail-closed, no compila ni marca)',
          mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT') and '"total"' not in out, out[:300])

    # D4 (nombre con espacios): ' linux-desktop ' se juzga IGUAL que
    # 'linux-desktop' -denegado por su host, no "no existe"-. GUARDA, no check
    # con mutante: quitar el Trim del nombrador la deja en verde (medido
    # 2026-10-06), porque el deploy recorta el nombre ANTES y la puerta y msbuild
    # usan ese mismo valor; se pone roja si alguien vuelve a juzgar uno y usar otro.
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy', 'profile': '  linux-desktop  '}, 300)
    check('D4 perfil con espacios: la puerta lo encuentra (Trim) y lo niega por su host, no por "no existe"',
          mc.es(out, 'SR_PASERVER_HOST_DENIED_FMT') and HOST_PERFIL in out, out[:300])

    # D5: el perfil lo declara el PROYECTO y la llamada no lo nombra. msbuild
    # lee $(Profile) del .dproj: la puerta tiene que juzgar ESE.
    r = srv.call('delphi_config', {'command': 'set-profile', 'platform': 'Linux64',
                                   'profile': PERFIL, 'project': DPROJ})
    check('D5 previo: set-profile deja el perfil en el proyecto', 'CFG-014' in r, r[:200])
    out = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64',
                                    'config': 'Debug', 'target': 'Deploy'}, 600)
    marco_host = ('Connecting to ' + HOST_PERFIL) in out or ('E0003' in out and HOST_PERFIL in out)
    check('D5 deploy SIN profile= con el perfil del proyecto: la puerta lo niega por su host y no marca',
          mc.es(out, 'SR_PASERVER_HOST_DENIED_FMT') and HOST_PERFIL in out and not marco_host,
          'marco_host=%s | %s' % (marco_host, out[:400]))

    # D7/D8 (punto 2 en los otros llamadores de la puerta): argumentos validos y
    # un perfil que NO existe -> negado con su motivo, antes de lanzar nada.
    out = srv.call('delphi_paserver', {'command': 'remote-run', 'name': 'noexiste', 'project': DPROJ})
    check('D7 remote-run con perfil inexistente: NEGADO con su motivo (fail-closed)',
          mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT'), out[:300])
    out = srv.call('delphi_desktop', {'command': 'screenshot', 'profile': 'noexiste'})
    check('D8 delphi_desktop con perfil inexistente: NEGADO con su motivo (fail-closed)',
          mc.es(out, 'SR_PROFILE_NO_EXISTE_FMT'), out[:300])

    # D9: el perfil por defecto del ENTORNO (DefaultProfile de EnvOptions.proj),
    # el ultimo sitio del que msbuild saca un perfil. El servidor no lo adivina:
    # le pasa /p:Profile= vacio y msbuild no puede usarlo. Servidor aparte con un
    # APPDATA de prueba cuyo perfil por defecto apunta fuera de RemoteHosts.
    ad9, _ = mc.appdata_perfil(BASE, 'mcp-defecto', HOST_PERFIL, 'Linux64', por_defecto=True)
    ent9 = dict(ENT)
    ent9['APPDATA'] = ad9
    srv9 = mc.Stdio(EXE, ent9, nombre='deployrh9', t=600)
    try:
        srv9.call('delphi_create', {'kind': 'project-console', 'name': 'DeployDef',
                                    'dir': os.path.join(JAIL, 'DeployDef')})
        DPROJ9 = os.path.join(JAIL, 'DeployDef', 'DeployDef.dproj')
        srv9.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64',
                                    'sdk': 'zorin18', 'project': DPROJ9})
        out = srv9.call('delphi_build', {'project': DPROJ9, 'platform': 'Linux64',
                                         'config': 'Debug', 'target': 'Deploy'}, 600)
        marco_host = ('Connecting to ' + HOST_PERFIL) in out or ('E0003' in out and HOST_PERFIL in out)
        check('D9 perfil POR DEFECTO del entorno fuera de RemoteHosts: el deploy sin perfil no lo marca',
              'Missing profile name' in out and not marco_host,
              'marco_host=%s | %s' % (marco_host, out[:400]))
    finally:
        try: srv9.mata()
        except Exception: pass

    mc.fin('deploy RemoteHosts battery')
finally:
    try: srv.mata()
    except Exception: pass
    mc.borra(BASE)
