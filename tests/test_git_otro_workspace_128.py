# -*- coding: utf-8 -*-
"""El programa del operador vive donde NINGUN agente escribe (C31 de la 1.28: la (8) del revisor de
correccion de la 1.27). ProgramaFueraDelAgente (Lsp.Guard), el juez de git, msbuild, adb, paclient,
brcc32 y DelphiLSP.exe tomados del PATH o de una ruta escrita, preguntaba la jaula de ESCRITURA de la
sesion que llama: un git.exe en una carpeta del PATH dentro de la raiz de OTRO workspace no era "de
este agente" y se lanzaba - con la cuenta del servicio, y plantado por el agente del otro workspace.
Sonda INERTE, la de test_git_por_ruta_119: whoami.exe renombrado a git.exe. Si corre, la respuesta
LLEGA a git (exit=...); el git de verdad no se lanza y se dice GIT-050.

  G1 el agente de B, en cuya raiz esta el git plantado: GIT-050, la sonda no corre (R4 de la 119)
  G2 el agente de A, con OTRA raiz: GIT-050 tambien, la sonda no corre - ROJA contra d3cce37
  G3 testigo: con el git de verdad en el PATH (fuera de toda raiz) A contesta git de verdad: la regla
     no niega git a quien lo tiene donde nadie escribe

Uso:  python tests/test_git_otro_workspace_128.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_otro_workspace_128')
RAIZ_A, RAIZ_B = os.path.join(BASE, 'raiz-a'), os.path.join(BASE, 'raiz-b')
REPO = os.path.join(RAIZ_A, 'repo')
BIN_B = os.path.join(RAIZ_B, 'bin')          # una carpeta del PATH del servidor DENTRO de la raiz de B
for _d in (REPO, BIN_B):
    os.makedirs(_d)
WHOAMI = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32', 'whoami.exe')
shutil.copy(WHOAMI, os.path.join(BIN_B, 'git.exe'))


def git(*a):
    subprocess.run(['git'] + list(a), cwd=REPO, capture_output=True)


git('init', '-q', '-b', 'main')
git('config', 'user.name', 'Bateria')
git('config', 'user.email', 'b@x')
open(os.path.join(REPO, 'a.txt'), 'w').write('uno\n')
git('add', 'a.txt')
git('commit', '-q', '-m', 'primero')

TA, TB = 'git-otro-ws-a', 'git-otro-ws-b'
SIN_GIT = ';'.join(p for p in os.environ.get('PATH', '').split(';')
                   if p and not os.path.isfile(os.path.join(p, 'git.exe')))
CON_GIT = os.environ.get('PATH', '')


def servidor(nombre, path):
    """Un servidor HTTP con los dos workspaces y ESE PATH (el del operador: lo hereda el proceso)."""
    carpeta = os.path.join(BASE, nombre)
    exe = mc.copia_exe(carpeta)
    with open(os.path.join(carpeta, 'settings.ini'), 'w') as f:
        f.write('[Workspace.A]\nToken=%s\nRoots=%s\n\n' % (TA, RAIZ_A))
        f.write('[Workspace.B]\nToken=%s\nRoots=%s\n' % (TB, RAIZ_B))
    puerto = mc.puerto_libre()
    proc = mc.lanza_http(exe, puerto, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1', 'PATH': path}))
    return proc, puerto


def cliente(puerto, token, agente):
    c = mc.Http(puerto, token)
    assert c.session(agente), (token, agente)
    return c


proc, puerto = servidor('srv-plantado', BIN_B + ';' + SIN_GIT)
try:
    rb = cliente(puerto, TB, 'agente-b').call('delphi_git', {'repo': RAIZ_B, 'command': 'status'})
    check('G1 el agente de B, con el git plantado en su raiz: GIT-050, la sonda no corre',
          mc.es(rb, 'SR_GIT_NO_HAY_GIT_FMT') and not mc.llego_a_git(rb), rb[:200])
    ra = cliente(puerto, TA, 'agente-a').call('delphi_git', {'repo': REPO, 'command': 'status'})
    check('G2 el agente de A, con OTRA raiz: el git de la raiz de B tampoco es del operador (GIT-050, '
          'la sonda no corre)',
          mc.es(ra, 'SR_GIT_NO_HAY_GIT_FMT') and not mc.llego_a_git(ra), ra[:200])
finally:
    proc.kill()

proc, puerto = servidor('srv-de-verdad', CON_GIT)
try:
    ra = cliente(puerto, TA, 'agente-a').call('delphi_git', {'repo': REPO, 'command': 'status'})
    check('G3 testigo: el git de verdad, fuera de toda raiz, contesta a A',
          mc.llego_a_git(ra) and '## main' in ra and not mc.fallo(ra), ra[:200])
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('git del operador fuera de toda raiz 1.28 (C31)')
