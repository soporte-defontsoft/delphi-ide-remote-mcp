# -*- coding: utf-8 -*-
"""Un perfil se lee solo si el IDE lo lista, y delphi_desktop juzga su nombre en la puerta (V8 de la 1.23).

delphi_desktop no pasaba su "profile" por la regla del nombre de la puerta -la de delphi_build y
delphi_paserver, que la descripcion de "profile" promete para los tres-, y el lector de un perfil
(Lsp.Discovery.HostDePerfil y PlataformaDePerfil) componia la ruta del .profile con lo tecleado: con
un '..' miraba cualquier .profile del disco, fuera de la jaula, y la negativa decia si existia (PAS-054,
"no lo pude leer") o no (PAS-053). Medido en vivo contra r1222br (25-oct-2026). Ahora el lector solo
abre el .profile de un perfil que el IDE lista, por su nombre de la lista (eso lo mide DUnitX,
TPerfilPorLaListaTests), y la puerta de delphi_desktop tiene la regla.

Sin PAServer ni red: paclient es tests/paclient_stub.py (DELPHI_MCP_PACLIENT), que apunta cada llamada,
y el perfil vive en un APPDATA de prueba (mc.appdata_perfil) con un host que no es de nadie.

  P1  desktop con un perfil que sube con ..\\ hasta un .profile plantado FUERA -> PAS-015 (la puerta),
      nunca PAS-054
  P2  ...hasta uno que NO existe -> la MISMA negativa (no hay oraculo)
  P3  desktop con un nombre con espacios y signos -> PAS-015, como delphi_paserver (P3b) y
      delphi_build (P3c)
  P4  (control) un perfil que el IDE lista, escrito con otras mayusculas, pasa la puerta y el juez
      de su host, y a paclient llega con SU nombre, el de la lista

Mutante: produccion (el build sin el arreglo): P1 y P3 rojos (P1 contesta PAS-054).

Uso:  python tests/test_perfil_por_lista_1230.py [exe]
"""
import os, re, shutil
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = mc.carpeta('perfil_por_lista_1230')
JAIL = os.path.join(BASE, 'jaula')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
os.makedirs(FUERA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# el nodo viaja con el servidor (Lsp.RemoteRun: ServerDir('node')); sin el, desktop contesta DESK-021 antes
# de llamar a paclient y P4b no mide nada
shutil.copytree(os.path.join(os.path.dirname(HERE), 'node'), os.path.join(BASE, 'srv', 'node'))
PERFIL = 'PerfilV8'
AD, HOST = mc.appdata_perfil(BASE, PERFIL, '192.0.2.1', 'Linux64')
open(os.path.join(FUERA, 'sonda.profile'), 'w', encoding='utf-8').write('sonda de V8, inerte\n')
LOG = os.path.join(BASE, 'paclient.log')
STUB = os.path.join(BASE, 'paclient.cmd')
with open(STUB, 'w') as _f:
    _f.write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))

srv = mc.Stdio(EXE, mc.entorno({
    'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': AD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
    'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': 'all',
    'DELPHI_MCP_PACLIENT': STUB, 'MCP_STUB_SCRATCH': os.path.join(BASE, 'destino'), 'MCP_STUB_LOG': LOG}),
    nombre='perfil_por_lista_1230', t=300)
try:
    m = re.search(r'"version"\s*:\s*"(\d+\.\d+)"', srv.call('delphi_installs', {}))
    VER = m.group(1) if m else ''
    PERFILES = os.path.join(AD, 'Embarcadero', 'BDS', VER)
    check('P0 fixture: la carpeta de perfiles de prueba tiene el perfil, y la sonda esta FUERA',
          VER != '' and os.path.isfile(os.path.join(PERFILES, PERFIL + '.profile')) and
          os.path.isfile(os.path.join(FUERA, 'sonda.profile')), VER)
    SUBE = os.path.relpath(os.path.join(FUERA, 'sonda'), PERFILES)
    NADA = os.path.relpath(os.path.join(FUERA, 'nada'), PERFILES)
    check('P0b fixture: la ruta sube con ..', SUBE.startswith('..'), SUBE)

    r1 = srv.call('delphi_desktop', {'command': 'status', 'profile': SUBE})
    check('P1 desktop con un perfil que sube hasta un .profile de FUERA: la regla del nombre (PAS-015), '
          'sin decir si existe',
          mc.rechazado(r1) and mc.es(r1, 'SR_PASERVER_NAME_FMT') and not mc.es(r1, 'SR_PROFILE_NO_LEIDO_FMT'),
          r1[:300])
    r2 = srv.call('delphi_desktop', {'command': 'status', 'profile': NADA})
    check('P2 ...y hasta uno que no existe: la MISMA negativa (no hay oraculo)',
          mc.es(r2, 'SR_PASERVER_NAME_FMT') and r2.replace(NADA, '#') == r1.replace(SUBE, '#'),
          r2[:300])
    r3 = srv.call('delphi_desktop', {'command': 'status', 'profile': 'mal nombre!'})
    check('P3 desktop con un nombre con espacios y signos: PAS-015',
          mc.rechazado(r3) and mc.es(r3, 'SR_PASERVER_NAME_FMT'), r3[:300])
    r3b = srv.call('delphi_paserver', {'command': 'test-connection', 'profile': 'mal nombre!'})
    check('P3b ...la misma que delphi_paserver', mc.es(r3b, 'SR_PASERVER_NAME_FMT'), r3b[:300])
    r3c = srv.call('delphi_build', {'project': os.path.join(JAIL, 'x.dproj'), 'platform': 'Linux64',
                                    'profile': 'mal nombre!'})
    check('P3c ...y que delphi_build', mc.es(r3c, 'SR_PASERVER_NAME_FMT'), r3c[:300])

    if os.path.exists(LOG):
        os.remove(LOG)
    r4 = srv.call('delphi_desktop', {'command': 'status', 'profile': PERFIL.upper()}, t=120)
    llamadas = open(LOG, encoding='utf-8').read().splitlines() if os.path.exists(LOG) else []
    perfiles = set(l.rsplit(' ', 1)[-1].strip('"') for l in llamadas if l.strip())
    negativas = ('SR_PASERVER_NAME_FMT', 'SR_PROFILE_NO_EXISTE_FMT', 'SR_PROFILE_NO_LEIDO_FMT',
                 'SR_PROFILE_SIN_HOST_FMT')
    check('P4 (control) el perfil que el IDE lista, con otras mayusculas: pasa la puerta y el juez de su host',
          not any(mc.es(r4, n) for n in negativas), r4[:300])
    check('P4b ...y a paclient llega con SU nombre, el de la lista',
          perfiles == {PERFIL}, '%s | %s' % (sorted(perfiles), llamadas[:3]))
finally:
    srv.cierra()
mc.fin('perfil por lista 1230')
