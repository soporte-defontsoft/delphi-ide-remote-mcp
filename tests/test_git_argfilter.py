"""E2E battery: el filtro de argumentos de delphi_git lee los args COMO los
trocea el runtime de C de Windows (lo que hace git.exe, spawn directo sin
shell), asi que una opcion prohibida disfrazada con comillas o barras
invertidas no se cuela por la puerta.

El agujero (medido 26-sep-2026): la puerta troceaba por espacios y el ejecutor
pasaba la cadena cruda a git; `--o"utput"=<ruta>` no casaba con `--output` en la
puerta, pero git le quitaba las comillas y escribia el fichero -> fuga de la
jaula usable hasta por un cliente de solo lectura. Arreglo: la puerta trocea
con TrocearArgs (reglas del CRT) y el ejecutor recompone la linea desde ese
mismo argv con EnComillas (su inversa), asi que git recibe EXACTAMENTE lo que la
puerta valido.

Contra el binario de produccion de hoy (1.5.4) estos checks FALLAN: la opcion
disfrazada pasa y git la ejecuta (medido: escribe el fichero de --output).
Corre:  python tests/test_git_argfilter.py <ruta-a-DelphiLspMcp.exe-1.5.4>

Usage:  python tests/test_git_argfilter.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('gitargfilter')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
REPO_T = os.path.join(BASE, 'repo')
os.makedirs(REPO_T)

env = mc.entorno({'DELPHI_MCP_ROOTS': BASE})
srv = mc.Stdio(EXE, env, nombre='gaf')
call = srv.call


def git(args):
    return call('delphi_git', dict({'repo': REPO_T}, **args))


# ---- repo con un commit ----
git({'command': 'init'})
git({'command': 'config', 'args': 'user.name', 'message': 'Probe Bot'})
git({'command': 'config', 'args': 'user.email', 'message': 'probe@example.com'})
open(os.path.join(REPO_T, 'a.txt'), 'w').write('uno\n')
git({'command': 'add', 'args': '.'})
r = git({'command': 'commit', 'message': 'inicial'})
check('commit inicial', 'exit=0' in r, r[:150])

# El fichero que --output escribiria: DENTRO de la jaula de la bateria, para que
# ni siquiera el binario vulnerable escriba fuera. Que NO exista = puerta OK.
LEAK = os.path.join(BASE, 'leaked.txt')


def sin_fuga():
    return not os.path.exists(LEAK)


# ---- opciones prohibidas DISFRAZADAS: la puerta las ve como las vera git ----
r = git({'command': 'diff', 'args': '--o"utput"=' + LEAK + ' HEAD'})
check('diff --o"utput" (comillas en medio): RECHAZADO y no escribe',
      (mc.rechazado(r) and not mc.llego_a_git(r)) and sin_fuga(), r[:200])
# "RECHAZADO" = lo paro la PUERTA: un git que corre y acaba mal tambien es
# una negativa (GIT-036 DENIED desde la 1.7.0), y con la puerta abierta estos
# checks salian verdes (quinta revision)
r = git({'command': 'diff', 'args': '"--output=' + LEAK + '" HEAD'})
check('diff "--output=..." (comillas envolviendo): RECHAZADO y no escribe',
      (mc.rechazado(r) and not mc.llego_a_git(r)) and sin_fuga(), r[:200])
r = git({'command': 'show', 'args': '--outp"ut"=' + LEAK})
check('show --outp"ut": RECHAZADO y no escribe', (mc.rechazado(r) and not mc.llego_a_git(r)) and sin_fuga(), r[:200])
r = git({'command': 'diff', 'args': '--no-"index" a.txt a.txt'})
check('diff --no-"index" (lee rutas arbitrarias): RECHAZADO', (mc.rechazado(r) and not mc.llego_a_git(r)), r[:200])
r = git({'command': 'log', 'args': '-"c" core.pager=x'})
check('log -"c" (config, disfrazado): RECHAZADO', (mc.rechazado(r) and not mc.llego_a_git(r)), r[:200])
# control sin disfraz: la opcion tal cual tambien se rechaza y no escribe
r = git({'command': 'diff', 'args': '--output=' + LEAK})
check('diff --output directo (control): RECHAZADO y no escribe',
      (mc.rechazado(r) and not mc.llego_a_git(r)) and sin_fuga(), r[:200])

# ---- host remoto disfrazado con comillas: la puerta lo ve igual ----
r = git({'command': 'fetch', 'args': '"https://evil.example/repo"'})
check('fetch a un host no permitido, con comillas: RECHAZADO', (mc.rechazado(r) and not mc.llego_a_git(r)), r[:200])

# ---- lo LEGITIMO sigue pasando: la recomposicion no rompe args validos ----
r = git({'command': 'diff', 'args': 'HEAD'})
check('diff HEAD normal: pasa', 'exit=0' in r, r[:200])
r = git({'command': 'log', 'args': '--grep="dos palabras"'})
check('log --grep con espacios (comillas legitimas): pasa y las conserva',
      'exit=0' in r, r[:200])
r = git({'command': 'log', 'args': '-- "a.txt"'})
check('log -- <ruta comillada>: pasa (recompuesta bien)', 'exit=0' in r, r[:200])

srv.mata()

# ---- la URL de clone viaja en "message" y TAMBIEN pasa por la puerta:
# GitRemoteDenied la trocea con TrocearArgs, asi que un segundo host colado
# tras uno permitido se caza igual; el ejecutor la recompone con EnComillas. ----
env2 = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_GIT_REMOTES': 'allowed.example'})
srv2 = mc.Stdio(EXE, env2, nombre='gaf2')
r = srv2.call('delphi_git', {'repo': os.path.join(BASE, 'clon'), 'command': 'clone',
              'message': 'https://allowed.example/a https://evil.example/b'})
check('clone: segundo host colado en el message, cazado por la puerta al trocear',
      (mc.rechazado(r) and not mc.llego_a_git(r)) and 'evil.example' in r, r[:200])
srv2.mata()
mc.fin('git arg filter battery')
