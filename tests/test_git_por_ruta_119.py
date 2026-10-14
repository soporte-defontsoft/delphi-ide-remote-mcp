# -*- coding: utf-8 -*-
"""git por su RUTA COMPLETA (1.19.0; CLAUDE.md, 13-oct-2026: el programa por su
ruta, encontrada donde el agente no escribe). El servidor lanzaba git.exe por su
NOMBRE, y a un nombre sin carpeta CreateProcess lo busca en la CARPETA ACTUAL
del proceso PADRE (su GetCurrentDirectory, NO el cwd= del hijo): por stdio esa
es la de quien lanza el servidor, el repo del agente. Sonda INERTE: un git.exe
plantado ahi que es whoami.exe; si el servidor lo ejecuta, no es git de verdad.

  R1 testigo: un git.exe A SECAS lanzado DESDE esa carpeta corre la sonda
     plantada. Se prueba con whoami SIN argumentos, que imprime el usuario
     (exit 0): esa es la marca FIABLE. NO con 'WHOAMI /?' -medido el 14-oct-2026
     (4.8): un whoami.exe RENOMBRADO a git.exe, con los argumentos de git, sale
     con exit 1 y NO imprime su uso (1 byte, un espacio), al reves que bajo su
     propio nombre, que si da 'ERROR ... Escriba "WHOAMI /?" para su uso.'
     (su texto de uso depende de su propio nombre de fichero). Para que el padre
     busque en esa carpeta: su CWD ahi (os.chdir) y NoDefaultCurrentDirectoryInExePath
     fuera del entorno del PADRE -la pone el arnes de Claude, el servicio no, y
     CreateProcess la lee del padre; os.environ.pop la quita del bloque Win32
     (medido), no basta con quitarla del env del hijo-.
  R2 status con el git.exe plantado en la carpeta actual del servidor: este
     build contesta git DE VERDAD (lo lanza por su ruta completa: exit 0 en un
     repo sano; la sonda no corre)
  R3 un PATH sin git y la misma carpeta: GIT-050 y NADA lanzado (la plantada
     tampoco)
  R4 un git.exe que SI esta en el PATH pero en una carpeta donde el agente
     escribe (dentro de las raices): no es el git del operador -> GIT-050 y la
     sonda no corre (B1 del cierre de la 1.19.0; rojo contra 45dd5a8)

  Por que contra el BUILD ANTERIOR (el que lanzaba git por nombre) status salia
  con exit=1 pero SIN marca en el cuerpo -medido el 14-oct-2026 (4.8), leido el
  codigo viejo con git show df060cc~1, no recompilado-: no es la captura ni la
  codificacion. RunCapturedIn junta stdout y stderr en el MISMO pipe
  (SI.hStdError := WriteH) y decodifica UTF-8 estricto y, si no, la pagina de
  consola/OEM (Lsp.BuildRunner), asi que una marca ASCII no se perderia. Es que
  la sonda es whoami RENOMBRADO a git.exe: el flujo de status corre primero el
  prefacio 'rev-parse --absolute-git-dir ...' de DondeViveElRepo, y ese whoami
  renombrado, con esos argumentos, sale con exit 1 emitiendo 1 byte (un espacio)
  -nada de 'WHOAMI /?'-. El build viejo lo encontraba por nombre en la carpeta
  actual, lo corria, recogia exit=1 con salida vacia y DondeViveElRepo devolvia
  False -> GitFallo(1, '') -> el cuerpo queda "exit=1" sin detalle. El exit=1 es
  el testigo de que la sonda CORRIO (git de verdad en un repo sano da 0); el
  cuerpo vacio es el silencio del whoami renombrado, no un fallo de captura.

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


# R1 testigo: un git.exe a secas, lanzado con el PADRE en PLANTA, corre la sonda
# plantada. CreateProcess busca el nombre suelto en el CWD del padre, y la
# variable que lo desactiva (la del arnes de Claude) se quita del entorno del
# PADRE. whoami SIN argumentos imprime el usuario: marca fiable e independiente
# de como se llame el exe (al contrario que 'WHOAMI /?', que no sale renombrado).
_prev = os.getcwd()
os.environ.pop('NoDefaultCurrentDirectoryInExePath', None)
os.chdir(PLANTA)
try:
    _p = subprocess.run(['git.exe'], capture_output=True)   # hereda el CWD del padre
    _salida = (_p.stdout + _p.stderr).decode('cp850', 'replace')
finally:
    os.chdir(_prev)
_usuario = os.environ.get('USERNAME', '').lower()
check('R1 testigo: un git.exe a secas desde la carpeta actual CORRE la sonda plantada '
      '(whoami sin args imprime el usuario, exit 0)',
      _p.returncode == 0 and bool(_usuario) and _usuario in _salida.lower(),
      'exit=%d salida=%r usuario=%r' % (_p.returncode, ' '.join(_salida.split())[:60], _usuario))


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

# R4 (B1): el programa del operador vive donde el agente NO escribe. Un git.exe
# en una carpeta del PATH que esta dentro de las raices es del agente
# (ProgramaDelOperador, Lsp.Guard): GIT-050, sin lanzar nada
BIN = os.path.join(JAIL, 'bin')
os.makedirs(BIN)
shutil.copy(WHOAMI, os.path.join(BIN, 'git.exe'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'PATH': BIN + ';' + SIN_GIT}), nombre='git-por-ruta-raiz', cwd=PLANTA)
try:
    r = s.call('delphi_git', {'repo': REPO, 'command': 'status'})
    check('R4 un git.exe del PATH en una carpeta donde el agente escribe: GIT-050, y la sonda no corre',
          'GIT-050' in r and 'exit=' not in r and MARCA not in r, r[:200])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('git por su ruta 1.19.0')
