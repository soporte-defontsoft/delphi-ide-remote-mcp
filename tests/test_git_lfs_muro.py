# -*- coding: utf-8 -*-
"""El muro LFS (GIT-061) se levanta solo cuando el repo USA LFS (9.A, 2.1h).

El juez de "este repo usa LFS" es git (norma 6 del paisaje): ls-files por todas
las fuentes de atributos, ':(attr:filter=lfs)'. Que el filtro filter.lfs.* este
en la config (git-lfs instalado) NO es usarlo. Antes, GIT-061 negaba worktree
add / switch / merge / pull / stash en CUALQUIER repo con origin en un host
fuera de GitRemotes, use LFS o no, SIN tocar la red (falso positivo medido la
noche del 9 al 10-oct: el stash y el worktree de la 1.3 fueron por consola). La
red solo se toca cuando un checkout necesita un objeto LFS que no esta en local.

Control (el falso positivo que se cierra): un repo SIN ficheros LFS con origin
en un host NO permitido -> worktree add y switch FUNCIONAN. Contra el binario de
antes (4d6c63d) estos dos salen ROJOS: aquel niega por el endpoint que deriva
del origin aunque no haya nada que bajar.

Guarda (el muro que SIGUE en pie): un repo CON un fichero marcado filter=lfs y
el mismo origin no permitido -> worktree add NEGADO por su endpoint LFS, con su
mensaje propio y sin ensenar la direccion. El binario de antes tambien lo niega:
es la guarda de que el arreglo no abrio un agujero (se eligio NEGAR; el entorno
con GIT_LFS_SKIP_SMUDGE=1 lo decide David, apendice del encargo).

El origin de prueba es https://192.0.2.1/x.git (TEST-NET, nunca contesta; NUNCA
GitHub de verdad). Nada toca la red: el gate decide antes, y lfs env es local.

Uso:  python tests/test_git_lfs_muro.py [exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git-lfs-muro')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
MINE = os.path.join(BASE, 'mio')      # Roots
OUT = os.path.join(BASE, 'fuera')     # fuera de todo
VIC = os.path.join(OUT, 'victima')
os.makedirs(MINE)
os.makedirs(VIC)
open(os.path.join(VIC, 'v.txt'), 'w').write('fuera')

# un GLOBAL con el filtro LFS, para que el servidor vea filter.lfs.* (HayLfs
# cierto) sin depender de que la maquina lo tenga en SYSTEM; NOSYSTEM lo aisla.
GLOBAL = os.path.join(BASE, 'lfs.config')
open(GLOBAL, 'w').write('[filter "lfs"]\n clean = git-lfs clean -- %f\n'
                        ' smudge = git-lfs smudge -- %f\n'
                        ' process = git-lfs filter-process\n required = true\n')

ORIGIN = 'https://192.0.2.1/x.git'   # TEST-NET, nunca contesta, NUNCA GitHub

# los fixtures se crean SIN el filtro (NOSYSTEM + global vacio): el .bin se
# queda como blob normal, marcado filter=lfs en .gitattributes, sin pointer ni
# objeto ni git-lfs. ls-files ':(attr:filter=lfs)' lo ve por el ATRIBUTO.
VACIO = os.path.join(BASE, 'empty.config')
open(VACIO, 'w').close()
fenv = dict(os.environ, GIT_CONFIG_GLOBAL=VACIO, GIT_CONFIG_NOSYSTEM='1',
            GIT_TERMINAL_PROMPT='0')


def raw(repo, *args):
    p = subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t',
                        '-c', 'commit.gpgsign=false', *args],
                       cwd=repo, env=fenv, capture_output=True, text=True, timeout=30)
    if p.returncode:
        raise RuntimeError(' '.join(args) + ': ' + p.stderr)
    return p.stdout


# repo SIN LFS: el falso positivo que se cierra
SINLFS = os.path.join(MINE, 'sinlfs')
os.makedirs(SINLFS)
raw(SINLFS, 'init', '-q', '-b', 'main')
open(os.path.join(SINLFS, 'DUMMY.txt'), 'w').write('texto\n')
raw(SINLFS, 'add', '-A')
raw(SINLFS, 'commit', '-qm', 'uno')
raw(SINLFS, 'branch', 'otra')
raw(SINLFS, 'remote', 'add', 'origin', ORIGIN)

# repo CON un fichero filter=lfs: el muro de verdad
CONLFS = os.path.join(MINE, 'conlfs')
os.makedirs(CONLFS)
raw(CONLFS, 'init', '-q', '-b', 'main')
open(os.path.join(CONLFS, '.gitattributes'), 'w').write(
    '*.bin filter=lfs diff=lfs merge=lfs -text\n')
open(os.path.join(CONLFS, 'DUMMY.bin'), 'w', newline='\n').write('binario\n')
open(os.path.join(CONLFS, 'DUMMY.txt'), 'w').write('texto\n')
raw(CONLFS, 'add', '-A')
raw(CONLFS, 'commit', '-qm', 'uno')
raw(CONLFS, 'remote', 'add', 'origin', ORIGIN)

# premisa medida: git distingue "hay regla" (filtro en config) de "hay ficheros"
check('fixture: sinlfs no tiene ficheros LFS (ls-files attr=lfs vacio)',
      raw(SINLFS, 'ls-files', ':(attr:filter=lfs)').strip() == '',
      raw(SINLFS, 'ls-files', ':(attr:filter=lfs)'))
check('fixture: conlfs SI tiene un fichero LFS (DUMMY.bin)',
      raw(CONLFS, 'ls-files', ':(attr:filter=lfs)').strip() == 'DUMMY.bin',
      raw(CONLFS, 'ls-files', ':(attr:filter=lfs)'))

server_env = mc.entorno(dict(DELPHI_MCP_ROOTS=MINE, DELPHI_MCP_GIT_REMOTES='example.com',
                             GIT_CONFIG_GLOBAL=GLOBAL, GIT_CONFIG_NOSYSTEM='1'))
server_env.pop('GIT_LFS_SKIP_SMUDGE', None)
srv = mc.Stdio(EXE, server_env, nombre='lfs-muro', t=90)


def git(repo, cmd, **kw):
    return srv.call('delphi_git', dict(repo=repo, command=cmd, **kw))


try:
    # ===== el falso positivo que se cierra (ROJO contra 4d6c63d) =====
    WTS = os.path.join(MINE, 'wt-sinlfs')
    r = git(SINLFS, 'worktree', args='add', path=WTS, ref='main')
    check('sin LFS: worktree add FUNCIONA (GIT-061 era un falso positivo)',
          r.startswith('exit=0') and os.path.isfile(os.path.join(WTS, 'DUMMY.txt')), r[:300])
    r = git(SINLFS, 'switch', args='otra')
    check('sin LFS: switch FUNCIONA (no hay objeto LFS que bajar, no se toca la red)',
          r.startswith('exit=0'), r[:300])

    # ===== la guarda: el muro SIGUE en pie (no se abrio un agujero) =====
    WTC = os.path.join(MINE, 'wt-conlfs')
    r = git(CONLFS, 'worktree', args='add', path=WTC, ref='main')
    check('con LFS: worktree add NEGADO por su endpoint LFS (origin fuera de GitRemotes)',
          mc.es(r, 'SR_GIT_LFS_ENDPOINT_FMT') and 'GitRemotes' in r
          and not os.path.exists(WTC), r[:300])
    check('el rechazo no ensena la direccion del endpoint (192.0.2.1)',
          '192.0.2.1' not in r, r[:300])

    # ===== control FUERA de las raices + victima intacta =====
    r = git(SINLFS, 'worktree', args='add', path=os.path.join(OUT, 'wt'), ref='main')
    check('worktree add FUERA de las raices: negado (control)',
          mc.rechazado(r) and not os.path.exists(os.path.join(OUT, 'wt')), r[:300])
    check('la victima de fuera sigue intacta', os.listdir(VIC) == ['v.txt'], os.listdir(VIC))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('git LFS muro (9.A)')
