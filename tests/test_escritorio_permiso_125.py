# -*- coding: utf-8 -*-
"""V90: ver y actuar en un escritorio es un permiso por HOST, con su propio sitio.

Era una entrada por NOMBRE (McpDesktopNode) en RemoteRunProjects, una lista de rutas de proyectos: un permiso
disfrazado de proyecto, que ademas no distinguia destinos ni ver de teclear, y que `all` concedia sin nombrarlo.
Ahora DesktopAllowedHosts (ver y actuar) y DesktopViewHosts (screenshot y status), por el host del perfil, y hacen
falta ademas de RemoteHosts, que dice a donde llega un perfil. Contra paclient_stub, sin red ni escritorio: lo que se
mide es la puerta, asi que un gesto que la pasa puede fallar despues por cualquier otra cosa.

Usage:  python tests/test_escritorio_permiso_125.py [path-to-DelphiLspMcp.exe]
"""
import os, shutil
import mcp_cliente as mc
from mcp_cliente import check

NIEGA = 'SR_DESKTOP_HOST_DENIED_FMT'
HERE = os.path.dirname(os.path.abspath(__file__))
BASE = mc.carpeta('escritorio-permiso-125')
RAIZ = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ)
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
STUB = os.path.join(BASE, 'paclient.cmd')
with open(STUB, 'w') as f:
    f.write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))
# 192.0.2.x (TEST-NET): nada los marca, contesta el stub
HOSTS = {'actua': '192.0.2.10', 'mira': '192.0.2.11', 'nada': '192.0.2.12'}
for perfil, host in HOSTS.items():
    AD, _ = mc.appdata_perfil(BASE, perfil, host)
BASE_ENV = {'DELPHI_MCP_ROOTS': RAIZ, 'APPDATA': AD, 'DELPHI_MCP_PACLIENT': STUB, 'MCP_STUB_SCRATCH': SCRATCH,
            'MCP_STUB_LOG': os.path.join(BASE, 'paclient.log'), 'DELPHI_MCP_ALLOW_REMOTE_RUN': '1',
            'DELPHI_MCP_REMOTE_HOSTS': '*'}
GESTOS = {'tap': {'x': '1', 'y': '1'}, 'type': {'text': 'hola'}, 'key': {'code': '1'}, 'overview': {}}
VER = {'status': {}, 'screenshot': {'out': os.path.join(RAIZ, 'c.png'), 'inline': False}}
N = [0]


def servidor(extra):
    N[0] += 1
    d = os.path.join(BASE, 'srv%d' % N[0])
    exe = mc.copia_exe(d)
    shutil.copytree(os.path.join(os.path.dirname(HERE), 'node'), os.path.join(d, 'node'))
    return mc.Stdio(exe, mc.entorno(dict(BASE_ENV, **extra)), nombre='escritorio', t=120)


def pide(s, cmd, perfil, args=None, proyecto=''):
    a = dict({'command': cmd, 'profile': perfil}, **(args or {}))
    if proyecto:
        a['project'] = proyecto
    return s.call('delphi_desktop', a, 120)


s = servidor({'DELPHI_MCP_DESKTOP_HOSTS': HOSTS['actua'] + ', OTRO.example', 'DELPHI_MCP_DESKTOP_VIEW_HOSTS': HOSTS['mira']})
try:
    for cmd, args in list(VER.items()) + list(GESTOS.items()):
        t = pide(s, cmd, 'actua', args)
        check('un host de DesktopAllowedHosts: %s pasa la puerta' % cmd, not mc.es(t, NIEGA), t[:300])
    for cmd, args in VER.items():
        t = pide(s, cmd, 'mira', args)
        check('un host de DesktopViewHosts: %s pasa la puerta' % cmd, not mc.es(t, NIEGA), t[:300])
    for cmd, args in GESTOS.items():
        t = pide(s, cmd, 'mira', args)
        check('un host de DesktopViewHosts: %s se niega' % cmd, mc.es(t, NIEGA) and 'act on' in t and HOSTS['mira'] in t, t[:300])
    for cmd, args in list(VER.items()) + list(GESTOS.items()):
        t = pide(s, cmd, 'nada', args)
        check('un host de ninguna lista: %s se niega' % cmd, mc.es(t, NIEGA), t[:300])
    t = pide(s, 'status', 'nada')
    check('la negativa dice que escribir y donde', all(x in t for x in ('DesktopAllowedHosts', 'DesktopViewHosts', 'settings.ini', 'see')), t[:400])
finally:
    s.cierra()

# lo de antes ya no concede: ni el nombre del nodo ni el comodin de los proyectos
for valor in ('McpDesktopNode', 'all', '*'):
    s = servidor({'DELPHI_MCP_REMOTE_RUN_PROJECTS': valor})
    try:
        t = pide(s, 'status', 'actua')
        check('RemoteRunProjects=%s ya no da el escritorio' % valor, mc.es(t, NIEGA) and 'no longer' in t, t[:300])
    finally:
        s.cierra()

# el comodin de las listas de hosts, como en las otras cuatro
s = servidor({'DELPHI_MCP_DESKTOP_VIEW_HOSTS': '*'})
try:
    check('DesktopViewHosts=*: mira en cualquiera', not mc.es(pide(s, 'status', 'nada'), NIEGA))
    check('...y sigue sin actuar', mc.es(pide(s, 'tap', 'nada', GESTOS['tap']), NIEGA))
finally:
    s.cierra()
s = servidor({'DELPHI_MCP_DESKTOP_HOSTS': '*'})
try:
    check('DesktopAllowedHosts=*: actua en cualquiera', not mc.es(pide(s, 'tap', 'nada', GESTOS['tap']), NIEGA))
finally:
    s.cierra()

# RemoteHosts sigue haciendo falta: son dos preguntas
s = servidor({'DELPHI_MCP_REMOTE_HOSTS': '192.0.2.99', 'DELPHI_MCP_DESKTOP_HOSTS': HOSTS['actua']})
try:
    t = pide(s, 'status', 'actua')
    check('en DesktopAllowedHosts y no en RemoteHosts: se niega por RemoteHosts', mc.es(t, 'SR_PASERVER_HOST_DENIED_FMT'), t[:300])
finally:
    s.cierra()

# project= (desarrollar el nodo) tambien pasa por el host: el escritorio es el mismo
P = os.path.join(RAIZ, 'Nodo.dproj')
with open(P, 'w', encoding='utf-8') as f:
    f.write('<Project/>')
s = servidor({'DELPHI_MCP_REMOTE_RUN_PROJECTS': P, 'DELPHI_MCP_DESKTOP_HOSTS': HOSTS['actua'], 'DELPHI_MCP_DESKTOP_VIEW_HOSTS': HOSTS['mira']})
try:
    t = pide(s, 'status', 'nada', proyecto=P)
    check('project= en un host sin permiso: se niega', mc.es(t, NIEGA), t[:300])
    t = pide(s, 'status', 'actua', proyecto=P)
    check('project= en un host con permiso: pasa la puerta', not mc.es(t, NIEGA), t[:300])
    # ...y project= ejecuta ese proyecto en el destino: no es mirar, aunque el comando sea status
    t = pide(s, 'status', 'mira', proyecto=P)
    check('project= en un host de ninguna lista de actuar: se niega', mc.es(t, NIEGA) and 'act on' in t, t[:300])
    # remote-run es otra pregunta: el proyecto, no el escritorio
    t = s.call('delphi_paserver', {'command': 'remote-run', 'profile': 'nada', 'project': P}, 120)
    check('remote-run no pide el permiso del escritorio', not mc.es(t, NIEGA), t[:300])
    # ...y sin proyecto sigue pidiendolo: quitar el nodo de esa puerta no le abre un hueco
    t = s.call('delphi_paserver', {'command': 'remote-run', 'profile': 'actua'}, 120)
    check('remote-run sin project sigue negado', mc.fallo(t) and not mc.es(t, NIEGA), t[:300])
finally:
    s.cierra()
mc.borra(BASE)
mc.fin('desktop permission 1.25 battery')
