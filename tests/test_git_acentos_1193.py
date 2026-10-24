# -*- coding: utf-8 -*-
"""git y los nombres con ACENTO (1.19.3; medido el 15-oct midiendo el add de un
ignorado). git entrecomilla en octal todo nombre que no es ASCII
(core.quotePath, por defecto): "vendor/Caf\\303\\251.dfm". Dos efectos:

  - el juez de los protegidos (GitReescribeProtegido) leia diff --name-only /
    stash show --name-only y hacia TPath.Combine con la comilla: switch, merge,
    pull y stash pop morian con "SYS-011 Invalid characters in path" en un repo
    con algo protegido dentro, si el cambio tocaba CUALQUIER fichero acentuado
    (falla cerrado: el protegido quedaba intacto, pero la operacion no salia);
  - el agente leia en status, diff y show un nombre que no puede usar como ruta.

El juez tiene su interruptor: -c core.quotePath=false (en Windows un nombre
valido no lleva comilla, barra invertida ni controles, asi que git no
entrecomilla ninguno). Y el juez de protegidos lee cada nombre con LeeRutaDeGit
(la inversa de las comillas de git), de segunda barrera.

  Q1 status: " M Café.txt" y "?? Ñandú.txt", sin octal (ROJO en produccion)
  Q2 diff paths=["Café.txt"]: la cabecera con el nombre, sin octal (ROJO)
  Q3 show: el stat nombra Café.txt, sin octal (ROJO)
  Q4 ReadOnlyPaths=vendor\\Café.dfm, switch b2 que lo cambia: GIT-065 nombrandolo,
     intacto (ROJO: SYS-011)
  Q5 el mismo repo protegido, switch b3 que solo cambia src/Año.txt (no
     protegido): se hace (ROJO: SYS-011)
  Q6 ReadOnlyRoots=vendor, stash pop que devolveria vendor/Café.dfm: GIT-065,
     intacto (ROJO: SYS-011)
  C1 control: un nombre ASCII sale igual que siempre

Y el CONTENIDO (completo de Opus de la 1.22.1): git escribe su texto en UTF-8 y lo de
los ficheros tal cual, y el servidor leia todo lo que no era UTF-8 en la pagina de la
consola: un fuente en la ANSI de la maquina salia en diff y show con cada letra
cambiada ('año' por 'a±o', 1252 leido en 850). Cada linea, UTF-8 si lo es; si no, la
ANSI de la maquina, la que leen dcc y el IDE en un fuente sin BOM:
  Q7 diff de un fuente ANSI y uno UTF-8 a la vez: los dos con sus letras (ROJO)
  Q8 show del commit del ANSI con su parche: con sus letras (ROJO)
  C2 control: un diff solo UTF-8 sale como siempre

Uso:  python tests/test_git_acentos_1193.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_acentos_1193')
JAIL = os.path.join(BASE, 'jail')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
OCTAL = '\\303'


def nuevo_repo(nombre):
    """main con vendor/Café.dfm, src/Año.txt, Café.txt y uno.txt; b2 cambia
    Café.dfm; b3 solo src/Año.txt."""
    repo = os.path.join(JAIL, nombre)
    os.makedirs(os.path.join(repo, 'vendor'))
    os.makedirs(os.path.join(repo, 'src'))

    def git(*a):
        subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@e.com'] + list(a),
                       cwd=repo, capture_output=True)

    def w(rel, txt):
        open(os.path.join(repo, rel.replace('/', os.sep)), 'w', encoding='utf-8').write(txt)
    w('vendor/Café.dfm', 'EN_MAIN\n'); w('src/Año.txt', 'ANO_MAIN\n')
    w('Café.txt', 'base\n'); w('uno.txt', 'base\n')
    git('init', '-q', '-b', 'main'); git('add', '.'); git('commit', '-qm', 'base')
    git('switch', '-qc', 'b2'); w('vendor/Café.dfm', 'DE_B2\n'); git('commit', '-qam', 'b2')
    git('switch', '-qc', 'b3', 'main'); w('src/Año.txt', 'ANO_B3\n'); git('commit', '-qam', 'b3')
    git('switch', '-q', 'main')
    return repo, git, w


def lee(repo, rel):
    return open(os.path.join(repo, rel.replace('/', os.sep)), encoding='utf-8').read().strip()


# (revisor de baterias, 18-oct-2026) la config GLOBAL del usuario, vacia: un
# core.quotePath=false en el ~/.gitconfig de la maquina dejaba Q1-Q3 en verde
# sin el interruptor del servidor
GLOBAL = os.path.join(BASE, 'global.gitconfig')
open(GLOBAL, 'w').close()


def arranca(ro_paths='', ro_roots=''):
    env = {'DELPHI_MCP_ROOTS': JAIL, 'GIT_CONFIG_GLOBAL': GLOBAL}
    if ro_paths:
        env['DELPHI_MCP_READONLY_PATHS'] = ro_paths
    if ro_roots:
        env['DELPHI_MCP_READONLY_ROOTS'] = ro_roots
    return mc.Stdio(EXE, mc.entorno(env), nombre='git-acentos', t=120)


# --------- Q1-Q3 y C1: lo que ve el agente
repo, git, w = nuevo_repo('ver')
w('Café.txt', 'cambio\n'); w('uno.txt', 'cambio\n'); w('Ñandú.txt', 'nuevo\n')
srv = arranca()
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'status'})
    check('Q1 status: " M Café.txt" y "?? Ñandú.txt", sin octal',
          ' M Café.txt' in r and '?? Ñandú.txt' in r and OCTAL not in r, r[:300])
    check('C1 control: un nombre ASCII sale igual que siempre', ' M uno.txt' in r, r[:300])
    r = srv.call('delphi_git', {'repo': repo, 'command': 'diff', 'paths': ['Café.txt']})
    check('Q2 diff paths=["Café.txt"]: la cabecera con el nombre, sin octal',
          'a/Café.txt' in r and '+cambio' in r and OCTAL not in r, r[:400])
    r = srv.call('delphi_git', {'repo': repo, 'command': 'show', 'ref': 'b3'})
    check('Q3 show: el stat nombra src/Año.txt, sin octal',
          'src/Año.txt' in r and OCTAL not in r, r[:500])
finally:
    srv.cierra()

# --------- Q4-Q5: un protegido acentuado dentro del repo
repo, git, w = nuevo_repo('protegido')
srv = arranca(ro_paths=os.path.join(repo, 'vendor', 'Café.dfm'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'b2'})
    check('Q4 switch b2 que cambia el protegido vendor/Café.dfm: GIT-065 nombrandolo, intacto',
          mc.rechazado(r) and 'GIT-065' in r and 'vendor/Café.dfm' in r and 'SYS-011' not in r
          and lee(repo, 'vendor/Café.dfm') == 'EN_MAIN', r[:400])
    r = srv.call('delphi_git', {'repo': repo, 'command': 'switch', 'branch': 'b3'})
    check('Q5 switch b3 que solo cambia src/Año.txt (no protegido): se hace',
          not mc.rechazado(r) and lee(repo, 'src/Año.txt') == 'ANO_B3'
          and lee(repo, 'vendor/Café.dfm') == 'EN_MAIN', r[:400])
finally:
    srv.cierra()

# --------- Q6: stash pop que devolveria un protegido acentuado
repo, git, w = nuevo_repo('pop')
w('vendor/Café.dfm', 'APARCADO\n')
git('stash', '-q')
srv = arranca(ro_roots=os.path.join(repo, 'vendor'))
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'stash', 'action': 'pop'})
    check('Q6 ReadOnlyRoots=vendor, stash pop que devolveria vendor/Café.dfm: GIT-065, intacto',
          mc.rechazado(r) and 'GIT-065' in r and 'vendor/Café.dfm' in r and 'SYS-011' not in r
          and lee(repo, 'vendor/Café.dfm') == 'EN_MAIN', r[:400])
finally:
    srv.cierra()

# --------- Q7, Q8 y C2: el CONTENIDO con acentos, en la ANSI de la maquina y en UTF-8
ANSI = 'cp%d' % mc.ANSI  # la de la maquina (mcp_cliente la pregunta a Windows)
ANTES, DESPUES = "const S = 'año ñu á';", "const S = 'año ñu á ó';"
try:
    ANTES.encode(ANSI)
    DESPUES.encode(ANSI)
    hay_ansi = True
except UnicodeEncodeError:
    hay_ansi = False
repo = os.path.join(JAIL, 'contenido')
os.makedirs(repo)


def git_c(*a):
    subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@e.com'] + list(a),
                   cwd=repo, capture_output=True)


def escribe(rel, txt, enc):
    open(os.path.join(repo, rel), 'wb').write(('unit X;\r\n%s\r\nend.\r\n' % txt).encode(enc))


escribe('UAnsi.pas', ANTES if hay_ansi else 'x', ANSI if hay_ansi else 'ascii')
escribe('UUtf8.pas', "const T = 'Ñandú 😀';", 'utf-8')
git_c('init', '-q', '-b', 'main'); git_c('add', '.'); git_c('commit', '-qm', 'base')
escribe('UAnsi.pas', DESPUES if hay_ansi else 'y', ANSI if hay_ansi else 'ascii')
escribe('UUtf8.pas', "const T = 'Ñandú 😀 ü';", 'utf-8')
srv = arranca()
try:
    r = srv.call('delphi_git', {'repo': repo, 'command': 'diff'})
    if hay_ansi:
        check('Q7 diff de un fuente ANSI (%s) y uno UTF-8 a la vez: los dos con sus letras' % ANSI,
              ('-' + ANTES) in r and ('+' + DESPUES) in r and "+const T = 'Ñandú 😀 ü';" in r, r[:600])
    else:
        print('NOTA Q7 y Q8 no se miden: la ANSI de esta maquina (%s) no tiene estas letras' % ANSI)
    check('C2 control: lo UTF-8 del diff sale como siempre', "-const T = 'Ñandú 😀';" in r, r[:600])
    git_c('commit', '-qam', 'cambio')
    r = srv.call('delphi_git', {'repo': repo, 'command': 'show', 'patch': True})
    if hay_ansi:
        check('Q8 show del commit con su parche: el ANSI con sus letras',
              ('+' + DESPUES) in r and "+const T = 'Ñandú 😀 ü';" in r, r[:600])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('git: nombres con acento 1.19.3')
