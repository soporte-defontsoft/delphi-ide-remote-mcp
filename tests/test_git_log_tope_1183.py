# -*- coding: utf-8 -*-
"""D7 de los revisores de cierre de la 1.18.2 (a la 1.18.3): delphi_git log
le pone al git un tope de 20 commits que la tool no dice. Medido: log de un
rango de 30 commits devolvio 20, sin aviso, y offset=20 contestaba GIT-054
"past the end: the answer has 20 lines" (offset pagina las lineas de la
respuesta, no la historia). Ahora, si hay MAS, lo dice git: la misma orden con
un commit mas de tope; con un -n del agente, git usa el suyo en las dos y
salen iguales, asi que no se imita la gramatica de git (norma 6).
Desde la 1.19.0 sin args: el rango va en ref/to y el tope en count (con un
count del agente, lo que pidio es lo que hay).

  L1 log de un rango de 29 commits sin count: 20 lineas y GIT-067 (ROJO en
     produccion: ni una palabra)
  L2 el mismo rango con count=40: los 29, sin GIT-067
  L3 control: un rango de 5: los 5, sin GIT-067
  L4 count=20 explicito con 29 detras: 20 lineas y SIN GIT-067 (pidio 20)
  L5 con format=full (varias lineas por commit) y sin count: GIT-067 igual

Uso:  python tests/test_git_log_tope_1183.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_log_tope_1183')
REPO = os.path.join(BASE, 'repo')
os.makedirs(REPO)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
ENV = dict(os.environ, GIT_AUTHOR_NAME='Probe', GIT_AUTHOR_EMAIL='probe@example.com',
           GIT_COMMITTER_NAME='Probe', GIT_COMMITTER_EMAIL='probe@example.com')


def g(*args):
    return subprocess.run(['git', '-C', REPO] + list(args), capture_output=True, text=True, env=ENV).stdout


g('init', '-q')
for i in range(30):
    with open(os.path.join(REPO, 'f.txt'), 'w') as f:
        f.write('v%d\n' % i)
    g('add', 'f.txt')
    g('commit', '-q', '-m', 'commit %d' % i)
PRIMERO = g('rev-list', '--max-parents=0', 'HEAD').strip()


def lineas(r):
    cuerpo = r.split('\n', 1)[1] if r.startswith('exit=0') else r
    return [l for l in cuerpo.split('\n') if l.strip() and not l.startswith('[GIT-')]


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='git-log-tope', t=120)
try:
    # 1.19.0: sin args; el rango, ref/to; el tope, count
    def log(**campos):
        return srv.call('delphi_git', dict({'repo': REPO, 'command': 'log'}, **campos))

    r = log(ref=PRIMERO, to='HEAD')
    check('L1 un rango de 29 commits sin count: 20 lineas y GIT-067 (hay mas, y como verlos)',
          len(lineas(r)) == 20 and 'GIT-067' in r, (len(lineas(r)), r[-300:]))
    r = log(count=40, ref=PRIMERO, to='HEAD')
    check('L2 el mismo rango con count=40: los 29, sin GIT-067', len(lineas(r)) == 29 and 'GIT-067' not in r,
          (len(lineas(r)), r[-200:]))
    r = log(ref='HEAD~5', to='HEAD')
    check('L3 control: un rango de 5: los 5, sin GIT-067', len(lineas(r)) == 5 and 'GIT-067' not in r,
          (len(lineas(r)), r[-200:]))
    r = log(count=20, ref=PRIMERO, to='HEAD')
    check('L4 count=20 explicito con 29 detras: 20 y SIN GIT-067 (pidio 20)',
          len(lineas(r)) == 20 and 'GIT-067' not in r, (len(lineas(r)), r[-200:]))
    # 1.19.0: log no tiene --stat; format=full tambien da varias lineas por commit
    r = log(format='full', ref=PRIMERO, to='HEAD')
    check('L5 con format=full (varias lineas por commit) y sin count: GIT-067 igual', 'GIT-067' in r, r[-300:])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('git log con su tope 1183 (D7)')
