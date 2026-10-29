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

V168: el lector leia OTRA cadena que git. Quitaba comillas y blancos alrededor (git recibe la
direccion tal cual: '"https' es su protocolo y lo niega), pedia una letra al principio de un
remote-helper (git, url.c is_urlschemechar: una letra o una CIFRA) y plegaba con Unicode. Medido
con git 2.53 (`git ls-remote`, ssh falso):

  U6 clone de "https://<permitido>/x" (con comillas): la tool lo niega como direccion que no es
     de red (ROJA contra b48699c: pasaba y git contestaba "protocol '"https' is not supported")
  U7 (guarda) clone de " https://<permitido>/x" y de "https://<permitido>/x\n" (blancos
     alrededor, una direccion pegada): clone se los quita (UrlDeClone) y git recibe la que se
     juzgo, asi que lo intenta git; la puerta de los hosts juzga ESA, no la del message (con los
     lectores sin recortar, el salto de detras la hacia ilegible)
  U8 un remoto 1x::foo (git lo lleva a git-remote-1x): direccion que la tool no toma, no una
     carpeta fuera de las raices (ROJA: GIT-044)
  U9 un remoto "https://<permitido>/x" (con comillas): direccion que la tool no toma (ROJA: pasaba)
  U11 un remoto " https://<permitido>/x" (un blanco delante, guardado asi en el repo): igual -
     la direccion se juzga como git la da (remote get-url), no recortada (ROJA: pasaba)
  U10 (guardas) 192.0.2.9:x://<permitido>/y - git: protocol '192.0.2.9:x', su connect.c corta en
     el PRIMER '://' - se niega en clone y en un remoto; y g\u0130t:// y h2:// (git: protocolo que no
     soporta; h2, un remote-helper) son direcciones que la tool no toma

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

    # V168: lo que git recibe, tal cual
    r = srv.call('delphi_git', {'command': 'clone', 'repo': os.path.join(JAIL, 'U6'),
                                'message': '"https://127.0.0.1:1/x.git"'})
    check('U6 clone de una direccion con comillas: no es de red como la lee git (la tool la niega)',
          mc.es(r, 'SR_GIT_CLONE_URLS_ACCEPTED'), r[:400])
    for clave, url in (('U7a', ' https://127.0.0.1:1/x.git'), ('U7b', 'https://127.0.0.1:1/x.git\n')):
        r = srv.call('delphi_git', {'command': 'clone', 'repo': os.path.join(JAIL, clave), 'message': url})
        check('%s (guarda) clone de %r: lo intenta git con la que se juzgo (ni la puerta ni la tool lo niegan)'
              % (clave, url), not mc.es(r, 'SR_GIT_CLONE_URLS_ACCEPTED') and not mc.es(r, 'SR_GIT_REMOTE_HOST_FMT')
              and not mc.es(r, 'SR_GIT_REMOTE_AMBIGUA_FMT'), r[:400])
    for clave, que, url in (('U8', 'un remote-helper que empieza por cifra (1x::foo)', '1x::foo'),
                            ('U9', 'una direccion con comillas', '"https://127.0.0.1:1/x.git"'),
                            ('U10a', 'un :// detras de host:ruta (git: protocol 192.0.2.9:x)',
                             '192.0.2.9:x://127.0.0.1:1/x.git'),
                            ('U10b', 'un esquema que no es ASCII (g, I con punto, t)', 'g\u0130t://127.0.0.1:1/x.git'),
                            ('U10c', 'un esquema con cifra (h2, un remote-helper)', 'h2://127.0.0.1:1/x.git'),
                            ('U11', 'un blanco delante', ' https://127.0.0.1:1/x.git')):
        rv = repo_con_remoto(clave, url)
        r = srv.call('delphi_git', {'command': 'fetch', 'repo': rv, 'remote': 'origin'})
        check('%s un remoto con %s: direccion que la tool no toma' % (clave, que),
              mc.es(r, 'SR_GIT_REMOTO_ILEGIBLE_FMT') and not mc.es(r, 'SR_GIT_REMOTO_FUERA_FMT'), r[:300])
    r = srv.call('delphi_git', {'command': 'clone', 'repo': os.path.join(JAIL, 'U10d'),
                                'message': '192.0.2.9:x://127.0.0.1:1/x.git'})
    check('U10d (guarda) clone de 192.0.2.9:x://<permitido>: no es de red', mc.es(r, 'SR_GIT_CLONE_URLS_ACCEPTED'),
          r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('direccion de red de git 1.23.1 (V130)')
