# -*- coding: utf-8 -*-
"""El DESTINO de delphi_git worktree add no puede CONTENER un lugar protegido
(1.18.2, 2v). worktree add hace un checkout que escribe el arbol en la carpeta
nueva; un ReadOnlyPaths que nombra un fichero de DENTRO de esa carpeta se
escribia (exit 0, el fichero escrito; 3.er emisor de la regla del 2r). Ahora
ProtegidoDenegado(Destino, True) lo niega ANTES con MOVE-020 y no escribe nada.

  V1 ReadOnlyPaths nombra <wt>\\U.dfm: worktree add da MOVE-020 y <wt>\\U.dfm NO
     se escribe (ni la carpeta nace con ese fichero)
  V2 el control: sin ese ReadOnlyPaths, worktree add funciona y escribe el arbol
     (si no, V1 no mide nada)

clone comparte la puerta (ProtegidoDenegado(Repo, True) en la misma funcion),
pero pide un remoto http con GitRemotes: no se mide aqui (NOTA).

Uso:  python tests/test_git_destino_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_destino_1182')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
os.makedirs(REPO)


def git(*a):
    subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@e.com'] + list(a),
                   cwd=REPO, capture_output=True, text=True)


open(os.path.join(REPO, 'U.dfm'), 'w').write("object U: TForm\n  Caption = 'U'\nend\n")
open(os.path.join(REPO, 'a.txt'), 'w').write('a\n')
git('init', '-q', '-b', 'main')
git('add', '.')
git('commit', '-qm', 'base')
git('switch', '-qc', 'otra')
open(os.path.join(REPO, 'U.dfm'), 'w').write("object U: TForm\n  Caption = 'OTRA'\nend\n")
git('add', '.')
git('commit', '-qm', 'otra')
git('switch', '-q', 'main')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def arranca(ro=''):
    env = {'DELPHI_MCP_ROOTS': JAIL}
    if ro:
        env['DELPHI_MCP_READONLY_PATHS'] = ro
    return mc.Stdio(EXE, mc.entorno(env), nombre='git-destino', t=120)


# ---- V1: ReadOnlyPaths dentro del destino del worktree
WT1 = os.path.join(JAIL, 'wt1')
RO = os.path.join(WT1, 'U.dfm')
srv = arranca(RO)
try:
    r = srv.call('delphi_git', {'repo': REPO, 'command': 'worktree', 'args': 'add', 'path': WT1, 'ref': 'otra'})
    check('V1 worktree add cuyo destino CONTIENE un ReadOnlyPaths: MOVE-020 y no escribe el fichero',
          mc.abre(r, 'SR_MUDANZA_DESTINO_PROTEGIDO_FMT') and not os.path.exists(RO), (r[:260], os.path.exists(RO)))
finally:
    srv.cierra()

# ---- V2: control, sin el ReadOnlyPaths
WT2 = os.path.join(JAIL, 'wt2')
srv = arranca()
try:
    r = srv.call('delphi_git', {'repo': REPO, 'command': 'worktree', 'args': 'add', 'path': WT2, 'ref': 'otra'})
    check('V2 el control: sin ReadOnlyPaths, worktree add escribe el arbol',
          not mc.fallo(r) and os.path.isfile(os.path.join(WT2, 'U.dfm')), r[:260])
finally:
    srv.cierra()

print('NOTA V3 (clone) no se mide aqui: comparte la puerta (ProtegidoDenegado(Repo, True) en la misma '
      'funcion de Mcp.Tools.Git) pero pide un remoto http con GitRemotes; medido por el revisor del 2r')
mc.borra(BASE)
mc.fin('git destino protegido 1182')
