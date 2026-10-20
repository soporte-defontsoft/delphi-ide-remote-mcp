# -*- coding: utf-8 -*-
"""delphi_git command=config SIN message lee el valor (1.21.1). Se negaba con
GIT-033 y un agente no tenia forma de saber con que identidad iba a firmar
(lista de pendientes de la 1.21, parche pequeno).

  C1 config name=user.name sin message: lo LEE y no escribe nada
  C2 config name=user.email sin message y sin fijar en ningun config: GIT-079,
     que no es un error, y nada escrito
  C3 con message escribe, como siempre; leerlo despues lo devuelve
  C4 en una raiz de SOLO LECTURA: leer va (es una consulta); escribir, no
  C5 una clave que no es de identidad sigue negada aunque sea para leer (GIT-024)

El global y el del sistema de git se apartan (GIT_CONFIG_GLOBAL a un fichero
vacio, GIT_CONFIG_NOSYSTEM=1, para el servidor y para el git de la bateria):
C2 no depende de lo que tenga fijado esta maquina.

Uso:  python tests/test_git_config_lee_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_config_lee_1211')
JAIL = os.path.join(BASE, 'jail')
RO = os.path.join(BASE, 'ro')
REPO = os.path.join(JAIL, 'repo')
REPO_RO = os.path.join(RO, 'repo')
VACIO = os.path.join(BASE, 'global-vacio.gitconfig')
for d in (REPO, REPO_RO):
    os.makedirs(d)
open(VACIO, 'w').close()
SIN_GLOBAL = {'GIT_CONFIG_GLOBAL': VACIO, 'GIT_CONFIG_NOSYSTEM': '1'}


def git(*a, cwd=REPO):
    return subprocess.run(['git'] + list(a), cwd=cwd, capture_output=True, text=True,
                          env=dict(os.environ, **SIN_GLOBAL)).stdout


for r in (REPO, REPO_RO):
    git('init', '-q', '-b', 'main', cwd=r)
    git('config', 'user.name', 'Bateria Lee', cwd=r)


def lee(p):
    return open(p, 'rb').read()


CFG = os.path.join(REPO, '.git', 'config')
CFG_RO = os.path.join(REPO_RO, '.git', 'config')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno(dict({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_READONLY_ROOTS': RO}, **SIN_GLOBAL)),
             nombre='git-config-lee', t=120)


def g(**kw):
    kw.setdefault('repo', REPO)
    m = s.call_msg('delphi_git', kw)
    return mc.texto(m, s.respaldo_json), bool(((m or {}).get('result') or {}).get('isError'))


try:
    antes = lee(CFG)
    r, err = g(command='config', name='user.name')
    check('C1 config sin message LEE user.name', not err and 'Bateria Lee' in r, r[:300])
    check('C1b ...y no escribe nada', lee(CFG) == antes)

    r, err = g(command='config', name='user.email')
    check('C2 sin fijar en ningun config: GIT-079 y no es un error',
          not err and mc.es(r, 'SN_GIT_CONFIG_SIN_VALOR_FMT'), r[:300])
    check('C2b ...y nada escrito', lee(CFG) == antes and git('config', '--get', 'user.email') == '')

    r, err = g(command='config', name='user.email', message='lee@example.com')
    check('C3 con message escribe, como siempre',
          not err and git('config', '--get', 'user.email').strip() == 'lee@example.com', r[:300])
    r, err = g(command='config', name='User.Email')
    check('C3b leerlo despues lo devuelve (el nombre en cualquier caja)',
          not err and 'lee@example.com' in r, r[:300])

    antes_ro = lee(CFG_RO)
    r, err = g(repo=REPO_RO, command='config', name='user.name')
    check('C4 en una raiz de solo lectura, leer va', not err and 'Bateria Lee' in r, r[:300])
    r, err = g(repo=REPO_RO, command='config', name='user.name', message='Intruso')
    check('C4b ...y escribir no', err and lee(CFG_RO) == antes_ro, r[:300])

    r, err = g(command='config', name='core.editor')
    check('C5 otra clave sigue negada aunque sea para leer (GIT-024)',
          err and mc.es(r, 'SR_GIT_CONFIG_ONLY_ACCEPTS_USER'), r[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git config lee 1.21.1')
