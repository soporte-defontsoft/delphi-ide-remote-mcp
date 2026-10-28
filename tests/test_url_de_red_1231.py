# -*- coding: utf-8 -*-
r"""El esquema de una direccion de git, por UN lector (V130 de la 1.23.1).

Habia dos lectores de "esto es una direccion de red": GitUrlHost (la puerta de los hosts: el
esquema sin mayusculas) y EsUrlDeRed (lo que clone y un remoto del repo admiten: cuatro esquemas
escritos en minusculas). Medido el juez, git: HTTPS:// y Https:// son https para el (los lleva
curl); GIT:// y SSH:// en mayusculas no los entiende y falla el solo. Asi que HTTPS://<host
permitido>/x pasaba la puerta y la tool lo negaba.

  U1 clone de HTTPS://<permitido>/x: no es SR_GIT_CLONE_URLS_ACCEPTED (ROJA contra b108a04); es git
     el que contesta
  U2 (guarda) clone de HTTPS://<no permitido>/x: la puerta de los hosts lo niega
  U3 fetch de un remoto del repo HTTPS://<permitido>/x: no es SR_GIT_REMOTO_ILEGIBLE_FMT (ROJA)
  U4 (guarda) ...y uno HTTPS://<no permitido>/x: la puerta de los hosts
  U5 un remoto con la forma de un remote-helper de git (https::<dir>, ext::<orden>, fd::17): se
     niega como direccion que la tool no toma (SR_GIT_REMOTO_ILEGIBLE_FMT), no como una carpeta
     fuera de las raices (ROJA: GIT-044, por los ':' de la ruta, por suerte)

Permitido: 127.0.0.1 en el puerto 1, que rechaza al instante (no sale nada a la red). No
permitido: 192.0.2.9 (TEST-NET), que la puerta niega antes de que git lo intente.

Uso:  python tests/test_url_de_red_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('url-de-red')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
PERMITIDA = 'HTTPS://127.0.0.1:1/x.git'
AJENA = 'HTTPS://192.0.2.9/x.git'


def repo_con_remoto(nombre, url):
    r = os.path.join(JAIL, nombre)
    os.makedirs(r)
    subprocess.run(['git', 'init', '-q', r], check=True)
    subprocess.run(['git', '-C', r, 'remote', 'add', 'origin', url], check=True)
    return r


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_GIT_REMOTES': '127.0.0.1'}),
               nombre='url-de-red', t=120)
try:
    r = srv.call('delphi_git', {'command': 'clone', 'repo': os.path.join(JAIL, 'c1'), 'message': PERMITIDA})
    check('U1 clone de HTTPS://<permitido>: lo intenta git (no lo niega la tool)',
          not mc.es(r, 'SR_GIT_CLONE_URLS_ACCEPTED') and not mc.es(r, 'SR_GIT_REMOTE_HOST_FMT'), r[:400])
    r = srv.call('delphi_git', {'command': 'clone', 'repo': os.path.join(JAIL, 'c2'), 'message': AJENA})
    check('U2 clone de HTTPS://<no permitido>: la puerta de los hosts', mc.es(r, 'SR_GIT_REMOTE_HOST_FMT'),
          r[:400])
    rp = repo_con_remoto('r1', PERMITIDA)
    r = srv.call('delphi_git', {'command': 'fetch', 'repo': rp, 'remote': 'origin'})
    check('U3 fetch de un remoto HTTPS://<permitido>: lo intenta git (no es ilegible)',
          not mc.es(r, 'SR_GIT_REMOTO_ILEGIBLE_FMT') and not mc.es(r, 'SR_GIT_REMOTE_HOST_FMT'), r[:400])
    ra = repo_con_remoto('r2', AJENA)
    r = srv.call('delphi_git', {'command': 'fetch', 'repo': ra, 'remote': 'origin'})
    check('U4 ...y uno HTTPS://<no permitido>: la puerta de los hosts', mc.es(r, 'SR_GIT_REMOTE_HOST_FMT'),
          r[:400])
    for i, url in enumerate(('https::127.0.0.1:1/x', 'ext::sh -c true', 'fd::17')):
        rh = repo_con_remoto('h%d' % i, url)
        r = srv.call('delphi_git', {'command': 'fetch', 'repo': rh, 'remote': 'origin'})
        check('U5 un remote-helper de git (%s): direccion que la tool no toma, no una carpeta' % url,
              mc.es(r, 'SR_GIT_REMOTO_ILEGIBLE_FMT') and not mc.es(r, 'SR_GIT_REMOTO_FUERA_FMT'), r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('direccion de red de git 1.23.1 (V130)')
