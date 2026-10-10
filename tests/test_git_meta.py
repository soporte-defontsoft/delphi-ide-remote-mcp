# -*- coding: utf-8 -*-
"""Los metadatos de git en la puerta de ESCRITURA (9.A). Un gitdir SEPARADO
(git init --separate-git-dir) deja el gitdir real SIN segmento .git, asi que
el atajo de MetadatosGitDenegados no lo ve: un agente podria plantar
sep.gitdir/hooks/pre-commit, que ejecuta el git de la PERSONA. El juez es git
(rev-parse --absolute-git-dir --git-common-dir, por DameGitDirDeCarpeta): si
la ruta cae dentro del gitdir o del comun, es metadato y no se escribe. Solo
la ESCRITURA lo paga (un rev-parse por carpeta, ~43 ms, cacheado).

Mutante (binario de antes, 4d6c63d): el create de sep.gitdir/hooks/pre-commit
se ESCRIBE (el atajo del .git no lo veia). Guardas verdes en ambos: el .git
normal (segmento .git), el arbol de trabajo y el control de fuera.

Uso:  python tests/test_git_meta.py [exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git-meta')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
MINE = os.path.join(BASE, 'mio')      # Roots
OUT = os.path.join(BASE, 'fuera')     # fuera de todo
VIC = os.path.join(OUT, 'victima')
os.makedirs(MINE)
os.makedirs(VIC)
open(os.path.join(VIC, 'v.txt'), 'w').write('fuera')

# un repo con el gitdir SEPARADO, DENTRO de las raices (el agujero)
SEP = os.path.join(MINE, 'sep.gitdir')
WORK = os.path.join(MINE, 'principal2')
subprocess.run(['git', 'init', '-q', '--separate-git-dir', SEP, WORK],
               capture_output=True, text=True)
# un repo NORMAL (con .git CARPETA), para el control del atajo del segmento
NORM = os.path.join(MINE, 'normal')
subprocess.run(['git', 'init', '-q', NORM], capture_output=True, text=True)


def Server(env):
    return mc.Stdio(EXE, mc.entorno(env), nombre='bateria-git-meta',
                    protocolo='2025-03-26', t=180)


srv = Server({'DELPHI_MCP_ROOTS': MINE})


def crea(path):
    return srv.call('delphi_textedit',
                    {'path': path, 'create': True, 'content': '#!/bin/sh\necho hook\n'})


check('fixture: el gitdir separado es una carpeta y el .git del arbol es un FICHERO',
      os.path.isdir(SEP) and os.path.isfile(os.path.join(WORK, '.git')), SEP)

# ===== el agujero que cierra 9.A: escribir metadatos de un gitdir separado =====
HOOK = os.path.join(SEP, 'hooks', 'pre-commit')
r = crea(HOOK)
check('create de sep.gitdir/hooks/pre-commit: NEGADO (git lo juzga metadato) y NO escrito',
      mc.rechazado(r) and mc.es(r, 'SR_GUARD_GIT_METADATA_FMT') and not os.path.exists(HOOK), r[:250])
CFG = os.path.join(SEP, 'config.evil')
r = crea(CFG)
check('create de otro fichero dentro del gitdir separado: NEGADO y NO escrito',
      mc.rechazado(r) and mc.es(r, 'SR_GUARD_GIT_METADATA_FMT') and not os.path.exists(CFG), r[:250])

# ===== guardas (verdes en el binario de antes tambien) =====
NHOOK = os.path.join(NORM, '.git', 'hooks', 'pre-commit')
r = crea(NHOOK)
check('guarda: create en el .git NORMAL (atajo del segmento .git): NEGADO',
      mc.rechazado(r) and mc.es(r, 'SR_GUARD_GIT_METADATA_FMT') and not os.path.exists(NHOOK), r[:250])
OK1 = os.path.join(WORK, 'nuevo.txt')
r = crea(OK1)
check('guarda: un fichero del ARBOL DE TRABAJO (no metadato) SI se escribe',
      not mc.rechazado(r) and os.path.isfile(OK1), r[:250])

# ===== control FUERA de las raices =====
r = crea(os.path.join(OUT, 'x.txt'))
check('control: create FUERA de las raices: negado',
      mc.rechazado(r) and not os.path.exists(os.path.join(OUT, 'x.txt')), r[:250])
check('la victima de fuera sigue intacta', os.listdir(VIC) == ['v.txt'], os.listdir(VIC))

srv.cierra()
mc.borra(BASE)
mc.fin('git metadata gate (9.A)')
