# -*- coding: utf-8 -*-
"""git por su RUTA COMPLETA (1.19.0; CLAUDE.md, 13-oct-2026: el programa por su
ruta, encontrada donde el agente no escribe). El servidor lanzaba git.exe por su
NOMBRE, y a un nombre sin carpeta CreateProcess lo busca PRIMERO en la carpeta
del exe y en la CARPETA ACTUAL del proceso: por stdio es la de quien lanza el
servidor, el repo del agente. Sonda INERTE: un git.exe plantado en la carpeta
actual del servidor que es whoami.exe (con los argumentos de git contesta su
uso, "WHOAMI /?", y sale): si el servidor lo ejecuta, esa marca sale en la
respuesta de status.

  (El testigo de que un git.exe a secas corre desde esa carpeta es el ROJO de
   R2 y R3 contra el build anterior, medido el 14-oct-2026: status salia con
   exit=1 en un repo sano con la sonda plantada, y con 0 con este build. Un
   testigo dentro de la bateria, y por que la marca no sale en esa respuesta,
   al encargo de 4.8: el clasificador corta ese seguimiento.)
  R2 status con el git.exe plantado en la carpeta actual del servidor:
     contesta git DE VERDAD (la marca no aparece)
  R3 un PATH sin git y la misma carpeta: GIT-050 y NADA lanzado (la plantada
     tampoco)

Uso:  python tests/test_git_por_ruta_119.py [ruta-a-DelphiLspMcp.exe]
"""
import os, shutil, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_por_ruta_119')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
PLANTA = os.path.join(BASE, 'cwd-del-agente')   # la carpeta ACTUAL del servidor
os.makedirs(REPO)
os.makedirs(PLANTA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

WHOAMI = os.path.join(os.environ.get('SystemRoot', r'C:\Windows'), 'System32', 'whoami.exe')
shutil.copy(WHOAMI, os.path.join(PLANTA, 'git.exe'))
MARCA = 'WHOAMI /?'


def git(*a):
    subprocess.run(['git'] + list(a), cwd=REPO, capture_output=True)


git('init', '-q', '-b', 'main')
git('config', 'user.name', 'Bateria')
git('config', 'user.email', 'b@x')
open(os.path.join(REPO, 'a.txt'), 'w').write('uno\n')
git('add', 'a.txt')
git('commit', '-q', '-m', 'primero')


s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='git-por-ruta', cwd=PLANTA)
try:
    r = s.call('delphi_git', {'repo': REPO, 'command': 'status'})
    check('R2 status con un git.exe plantado en la carpeta actual del servidor: contesta git de verdad',
          mc.llego_a_git(r) and not mc.fallo(r) and MARCA not in r, ('marca' if MARCA in r else 'sin marca', r[:200]))
finally:
    s.cierra()

# un PATH sin git: las entradas de la maquina que no tienen un git.exe
SIN_GIT = ';'.join(p for p in os.environ.get('PATH', '').split(';')
                   if p and not os.path.isfile(os.path.join(p, 'git.exe')))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'PATH': SIN_GIT}), nombre='git-por-ruta-sin', cwd=PLANTA)
try:
    r = s.call('delphi_git', {'repo': REPO, 'command': 'status'})
    check('R3 un PATH sin git con la sonda en la carpeta actual: GIT-050, y la sonda no corre',
          'GIT-050' in r and MARCA not in r, ('marca' if MARCA in r else 'sin marca', r[:200]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git por su ruta 1.19.0')
