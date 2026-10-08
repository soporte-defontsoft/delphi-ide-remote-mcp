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
# 1.15.1: el pickaxe -S<texto> / -G<texto> (busqueda en el historial, SOLO
# LECTURA) pasa aunque el valor lleve 'F'/'O'/'c' (antes `-SOpen` caia por la
# 'O' del valor, medido 2026-10-06). El valor va PEGADO; no es ruta ni fichero
# ni comando.
r = git({'command': 'log', 'args': '-SOpen --max-count=1 --oneline'})
check('log -SOpen (pickaxe, valor con O mayuscula): pasa', 'exit=0' in r, r[:200])
r = git({'command': 'log', 'args': '-GOpen --max-count=1 --oneline'})
check('log -GOpen (pickaxe -G, valor con O mayuscula): pasa', 'exit=0' in r, r[:200])
# ...pero -S SUELTO no se traga el siguiente argumento como su valor: cada token
# se revisa por separado, asi que una opcion prohibida DETRAS se caza igual.
r = git({'command': 'log', 'args': '-S --output=' + LEAK})
check('log -S --output=... (-S suelto + opcion prohibida detras): RECHAZADO y no escribe',
      (mc.rechazado(r) and not mc.llego_a_git(r)) and sin_fuga(), r[:200])

# ---- firma: la REAL (gpg) se niega; --signoff NO firma ----
# 1.18.0: --signoff (y -s, y --sign en commit, que es su abreviatura) solo pone
# "Signed-off-by" y se admite; -S / --gpg-sign (y en TAG --sign, que si es -s
# de gpg) se siguen negando. Antes `commit --signoff` caia por StartsWith('--sign').
open(os.path.join(REPO_T, 'b.txt'), 'w').write('dos\n')
git({'command': 'add', 'args': '.'})
r = git({'command': 'commit', 'args': '--signoff', 'message': 'con Signed-off-by'})
check('commit --signoff (no firma gpg) pasa el filtro y llega a git',
      mc.llego_a_git(r) and not mc.es(r, 'SR_GIT_OPTION_FMT'), r[:200])
r = git({'command': 'commit', 'args': '--gpg-sign', 'message': 'x'})
check('commit --gpg-sign (firma gpg) RECHAZADO por el filtro',
      mc.rechazado(r) and not mc.llego_a_git(r) and mc.es(r, 'SR_GIT_OPTION_FMT'), r[:200])
r = git({'command': 'commit', 'args': '-S', 'message': 'x'})
check('commit -S (firma gpg, grupo corto) RECHAZADO por el filtro',
      mc.rechazado(r) and not mc.llego_a_git(r), r[:200])
r = git({'command': 'tag', 'args': '--sign probe-firma'})
check('tag --sign (en tag SI es gpg) RECHAZADO por el filtro',
      mc.rechazado(r) and not mc.llego_a_git(r), r[:200])

srv.mata()

# ---- la URL de clone viaja en "message" y TAMBIEN pasa por la puerta, ENTERA:
# git la recibe como UN argumento, asi que la puerta la juzga como un trozo (la
# troceaba: 'ssh://permitido:22 @otro/x' eran dos trozos sin host y git iba al
# otro; revisor de addc44e). Una direccion con un blanco no la lee igual nadie:
# GIT-062. ----
env2 = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_GIT_REMOTES': 'allowed.example'})
srv2 = mc.Stdio(EXE, env2, nombre='gaf2')
r = srv2.call('delphi_git', {'repo': os.path.join(BASE, 'clon'), 'command': 'clone',
              'message': 'https://allowed.example/a https://evil.example/b'})
check('clone: segundo host colado en el message (con un blanco): GIT-062 y no llega a git',
      mc.abre(r, 'SR_GIT_REMOTE_AMBIGUA_FMT') and not mc.llego_a_git(r), r[:200])
# ---- la @ que viene DESPUES de la autoridad es del camino, no del usuario
# (revisor "adivinar vs medir", 8-oct-2026, medido): la puerta tomaba por host
# lo que seguia a la PRIMERA @ del resto de la cadena, asi que con
# allowed.example permitido estas direcciones -que conectan con evil.example-
# pasaban (la forma corta sin usuario, host:ruta, no la acepta clone: va en
# test_git_jaula J15b, por los remotos del repo). La de la ruta se lee bien
# (GIT-005 nombra evil.example); la que cada programa parte de otra forma se
# niega por ilegible (GIT-062). ----
for url, msg in (('https://evil.example/x@allowed.example', 'SR_GIT_REMOTE_HOST_FMT'),
                 ('git@evil.example:x@allowed.example', 'SR_GIT_REMOTE_HOST_FMT'),
                 ('https://evil.example?x@allowed.example', 'SR_GIT_REMOTE_AMBIGUA_FMT')):
    r = srv2.call('delphi_git', {'repo': os.path.join(BASE, 'clon2'), 'command': 'clone',
                  'message': url})
    check('clone %s: negado por SU host (%s), sin llegar a git' % (url, msg),
          mc.abre(r, msg) and not mc.llego_a_git(r) and
          (msg != 'SR_GIT_REMOTE_HOST_FMT' or '"evil.example"' in r), r[:200])
# ---- lo que git, ssh y curl parten de otra forma (revisor de addc44e, medido con
# git real y contra el binario): con allowed.example permitido, la primera
# lectura por la autoridad dejaba pasar estas, y git iba a evil.example; la
# vieja dejaba pasar las de los corchetes y el %. Se niegan por ilegibles. ----
for url in ('ssh://allowed.example?@evil.example/x', 'ssh://allowed.example#@evil.example/x',
            'https://allowed.example\\x@evil.example/x', 'ssh://allowed.example/x@[evil.example]/y',
            'ssh://[evil.example]@allowed.example/y', 'ssh://evil.example%2f@allowed.example/y',
            'git://evil.example%2f@allowed.example/y', 'ssh://allowed.example:22 @evil.example/y',
            'https://a@evil.example@allowed.example/x'):
    r = srv2.call('delphi_git', {'repo': os.path.join(BASE, 'clon2'), 'command': 'clone',
                  'message': url})
    check('clone %s: ilegible, GIT-062, sin llegar a git' % url,
          mc.abre(r, 'SR_GIT_REMOTE_AMBIGUA_FMT') and not mc.llego_a_git(r), r[:200])
# ---- un enlace en el MENSAJE de un commit es texto (va por -F): la puerta solo
# juzga el message de clone (se negaba con GIT-004, medido el 9-oct-2026) ----
open(os.path.join(REPO_T, 'a.txt'), 'w').write('dos\n')
srv2.call('delphi_git', {'repo': REPO_T, 'command': 'add', 'args': '.'})
r = srv2.call('delphi_git', {'repo': REPO_T, 'command': 'commit',
              'message': 'ver https://evil.example/x y git@evil.example:org/repo'})
check('commit con enlaces en el mensaje: no es una conexion, se hace', 'exit=0' in r, r[:200])
srv2.mata()
# ---- con GitRemotes VACIO (como se distribuye): una autoridad que empieza por
# ? # \ o que no tiene host era '' ('no es una direccion') en la primera lectura
# por la autoridad, y clone pasaba a CUALQUIER host (revisor de addc44e, E1) ----
srv3 = mc.Stdio(EXE, env, nombre='gaf3')
for url in ('ssh://?@evil.example/x', 'ssh://#@evil.example/x', 'ssh://\\x@evil.example/x',
            'https://\\x@evil.example/x', 'https:///evil.example/x', 'ssh://:22 @evil.example/y'):
    r = srv3.call('delphi_git', {'repo': os.path.join(BASE, 'clon3'), 'command': 'clone',
                  'message': url})
    check('GitRemotes vacio, clone %s: negado sin llegar a git' % url,
          mc.rechazado(r) and not mc.llego_a_git(r), r[:200])
srv3.mata()
mc.fin('git arg filter battery')
