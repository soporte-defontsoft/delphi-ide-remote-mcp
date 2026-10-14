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

1.19.0 (delphi_git sin "args"): la puerta de opciones se fue con los args.
Cada check manda la llamada vieja (GIT-068, nada hecho: el fichero de
--output sigue sin existir) Y el mismo disfraz en el campo que lo llevaria
hoy: en ref/to lo juzga git como revision (GIT-070), en un nombre de rama o
tag como nombre (GIT-071), en remote tiene que ser un remoto del repo
(GIT-049), en paths va detras de "--" como nombre del repo (GIT-012 si no lo
es) y en search viaja PEGADO a -S, como un solo argumento: es texto. Lo
legitimo (blancos, comillas, un valor que empieza por '-') llega entero.
La firma gpg y --signoff ya no se pueden pedir.

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
git({'command': 'config', 'name': 'user.name', 'message': 'Probe Bot'})
git({'command': 'config', 'name': 'user.email', 'message': 'probe@example.com'})
open(os.path.join(REPO_T, 'a.txt'), 'w').write('uno\n')
git({'command': 'add', 'paths': ['.']})
r = git({'command': 'commit', 'message': 'inicial'})
check('commit inicial', 'exit=0' in r, r[:150])

# El fichero que --output escribiria: DENTRO de la jaula de la bateria, para que
# ni siquiera el binario vulnerable escriba fuera. Que NO exista = puerta OK.
LEAK = os.path.join(BASE, 'leaked.txt')
# un fichero de la jaula FUERA del repo: lo que diff --no-index leeria
FUERA = os.path.join(BASE, 'fuera.txt')
open(FUERA, 'w').write('de fuera del repo\n')


def sin_fuga():
    return not os.path.exists(LEAK)


# 1.19.0: la llamada vieja, con args: GIT-068 y no llega a git
def sin_args(r):
    return mc.rechazado(r) and mc.es(r, 'SR_GIT_ARGS_RETIRADO') and not mc.llego_a_git(r)


# ---- opciones prohibidas DISFRAZADAS: la puerta las ve como las vera git ----
# 1.19.0: sin args, el disfraz solo cabe en un campo; en ref lo juzga git como
# revision (rev-parse --end-of-options) y no es ninguna: GIT-070
r = git({'command': 'diff', 'args': '--o"utput"=' + LEAK + ' HEAD'})
r2 = git({'command': 'diff', 'ref': '--o"utput"=' + LEAK})
check('diff --o"utput" (comillas en medio): en args GIT-068, en ref GIT-070, y no escribe',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_REF_NO_VALE_FMT') and
      not mc.llego_a_git(r2) and sin_fuga(), (r[:120], r2[:200]))
# "RECHAZADO" = lo paro la PUERTA: un git que corre y acaba mal tambien es
# una negativa (GIT-036 DENIED desde la 1.7.0), y con la puerta abierta estos
# checks salian verdes (quinta revision)
r = git({'command': 'diff', 'args': '"--output=' + LEAK + '" HEAD'})
r2 = git({'command': 'diff', 'ref': '"--output=' + LEAK + '"'})
check('diff "--output=..." (comillas envolviendo): en args GIT-068, en ref GIT-070, y no escribe',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_REF_NO_VALE_FMT') and
      not mc.llego_a_git(r2) and sin_fuga(), (r[:120], r2[:200]))
r = git({'command': 'show', 'args': '--outp"ut"=' + LEAK})
r2 = git({'command': 'show', 'ref': '--outp"ut"=' + LEAK})
check('show --outp"ut": en args GIT-068, en ref GIT-070, y no escribe',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_REF_NO_VALE_FMT') and
      not mc.llego_a_git(r2) and sin_fuga(), (r[:120], r2[:200]))
# 1.19.0: --no-index no se puede escribir; lo que buscaba (leer una ruta de
# fuera del repo) en paths es GIT-012
r = git({'command': 'diff', 'args': '--no-"index" a.txt a.txt'})
r2 = git({'command': 'diff', 'paths': [FUERA]})
check('diff --no-"index" (lee rutas arbitrarias): en args GIT-068; una ruta de fuera del repo en paths, GIT-012',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_STASH_RUTA_FMT') and
      not mc.llego_a_git(r2) and 'de fuera del repo' not in r2, (r[:120], r2[:200]))
r = git({'command': 'log', 'args': '-"c" core.pager=x'})
r2 = git({'command': 'log', 'ref': '-c'})
check('log -"c" (config, disfrazado): en args GIT-068, en ref no es una revision (GIT-070)',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_REF_NO_VALE_FMT') and
      not mc.llego_a_git(r2), (r[:120], r2[:200]))
# control sin disfraz: la opcion tal cual tambien se rechaza y no escribe. En
# paths iria detras de "--" (un nombre, nunca una opcion), pero antes pasa los
# jueces de toda ruta: el ':' de su unidad, fuera de la unidad, es GUARD-009
r = git({'command': 'diff', 'args': '--output=' + LEAK})
r2 = git({'command': 'diff', 'ref': '--output=' + LEAK})
r3 = git({'command': 'diff', 'paths': ['--output=' + LEAK]})
check('diff --output directo (control): en args GIT-068, en ref GIT-070, en paths GUARD-009; no escribe',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_REF_NO_VALE_FMT') and
      not mc.llego_a_git(r2) and mc.rechazado(r3) and
      mc.es(r3, 'SR_GUARD_RUTA_CONTIENE_FUERA_UNIDAD_FMT') and not mc.llego_a_git(r3) and sin_fuga(),
      (r[:120], r2[:200], r3[:200]))

# ---- host remoto disfrazado con comillas: la puerta lo ve igual ----
# 1.19.0: remote es el NOMBRE de un remoto del repo; una direccion no lo es
r = git({'command': 'fetch', 'args': '"https://evil.example/repo"'})
r2 = git({'command': 'fetch', 'remote': '"https://evil.example/repo"'})
r3 = git({'command': 'fetch', 'remote': 'https://evil.example/repo'})
check('fetch a un host no permitido, con comillas: en args GIT-068; en remote no es un remoto del repo (GIT-049)',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_REMOTO_NO_ESTA_FMT') and not mc.llego_a_git(r2)
      and mc.rechazado(r3) and mc.es(r3, 'SR_GIT_REMOTO_NO_ESTA_FMT') and not mc.llego_a_git(r3),
      (r[:120], r2[:200], r3[:200]))

# ---- lo LEGITIMO sigue pasando: la recomposicion no rompe args validos ----
# 1.19.0: cada valor de un campo va como UN argumento (EnComillas): un commit
# con lo que buscan search y paths
open(os.path.join(REPO_T, 'p.txt'), 'w').write('dos palabras\nOpen\n')
git({'command': 'add', 'paths': ['p.txt']})
git({'command': 'commit', 'message': 'con lo que se busca'})
r = git({'command': 'diff', 'ref': 'HEAD'})
check('diff HEAD normal: pasa', 'exit=0' in r, r[:200])
# 1.19.0: no hay --grep; el texto con blancos va en search (-S), entero
r = git({'command': 'log', 'search': 'dos palabras'})
check('log search con espacios: pasa y los conserva (encuentra el commit)',
      'exit=0' in r and 'con lo que se busca' in r, r[:200])
r = git({'command': 'log', 'paths': ['a.txt']})
check('log -- <ruta>: pasa (recompuesta bien)', 'exit=0' in r and 'inicial' in r and 'con lo que se busca' not in r,
      r[:200])
# 1.15.1: el pickaxe -S<texto> / -G<texto> (busqueda en el historial, SOLO
# LECTURA) pasa aunque el valor lleve 'F'/'O'/'c' (antes `-SOpen` caia por la
# 'O' del valor, medido 2026-10-06). El valor va PEGADO; no es ruta ni fichero
# ni comando.
r = git({'command': 'log', 'search': 'Open', 'count': 1})
check('log search=Open (pickaxe, valor con O mayuscula): pasa', 'exit=0' in r and 'con lo que se busca' in r, r[:200])
# 1.19.0: -G no existe (search es -S); un valor de search que empieza por '-'
# viaja pegado a -S: es texto, no una opcion
r = git({'command': 'log', 'args': '-GOpen --max-count=1 --oneline'})
r2 = git({'command': 'log', 'search': '-GOpen', 'count': 1})
check('log -GOpen: en args GIT-068; en search, texto pegado a -S (pasa)',
      sin_args(r) and 'exit=0' in r2 and '-S-GOpen' in r2, (r[:120], r2[:200]))
# ...pero -S SUELTO no se traga el siguiente argumento como su valor: cada token
# se revisa por separado, asi que una opcion prohibida DETRAS se caza igual.
# 1.19.0: en search, la opcion es el TEXTO que se busca (-S--output=...)
r = git({'command': 'log', 'args': '-S --output=' + LEAK})
r2 = git({'command': 'log', 'search': '--output=' + LEAK})
check('log -S --output=...: en args GIT-068; en search es el texto buscado; no escribe',
      sin_args(r) and 'exit=0' in r2 and '-S--output=' in r2 and sin_fuga(), (r[:120], r2[:200]))

# ---- firma: la REAL (gpg) se niega; --signoff NO firma ----
# 1.18.0: --signoff (y -s, y --sign en commit, que es su abreviatura) solo pone
# "Signed-off-by" y se admite; -S / --gpg-sign (y en TAG --sign, que si es -s
# de gpg) se siguen negando. Antes `commit --signoff` caia por StartsWith('--sign').
# 1.19.0: sin args no se pide ni la una ni la otra (GIT-068, ningun commit);
# commit es message y nada mas
open(os.path.join(REPO_T, 'b.txt'), 'w').write('dos\n')
git({'command': 'add', 'paths': ['.']})
cabeza = git({'command': 'log', 'count': 1})
r = git({'command': 'commit', 'args': '--signoff', 'message': 'con Signed-off-by'})
check('commit --signoff: en args GIT-068 y ningun commit',
      sin_args(r) and git({'command': 'log', 'count': 1}) == cabeza, r[:200])
r = git({'command': 'commit', 'args': '--gpg-sign', 'message': 'x'})
check('commit --gpg-sign (firma gpg): en args GIT-068 y ningun commit',
      sin_args(r) and git({'command': 'log', 'count': 1}) == cabeza, r[:200])
r = git({'command': 'commit', 'args': '-S', 'message': 'x'})
check('commit -S (firma gpg, grupo corto): en args GIT-068 y ningun commit',
      sin_args(r) and git({'command': 'log', 'count': 1}) == cabeza, r[:200])
r = git({'command': 'commit', 'message': 'sin firmar'})
check('...y el commit con su message llega a git', 'exit=0' in r, r[:200])
# 1.19.0: en tag, la opcion solo cabe en name, y un nombre que empieza por '-'
# no lo admite git (check-ref-format): GIT-071
r = git({'command': 'tag', 'args': '--sign probe-firma'})
r2 = git({'command': 'tag', 'name': '--sign'})
check('tag --sign (en tag SI es gpg): en args GIT-068; en name no es un nombre (GIT-071); ningun tag',
      sin_args(r) and mc.rechazado(r2) and mc.es(r2, 'SR_GIT_NOMBRE_NO_VALE_FMT') and
      'probe-firma' not in git({'command': 'tag'}) and '--sign' not in git({'command': 'tag'}),
      (r[:120], r2[:200]))

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
srv2.call('delphi_git', {'repo': REPO_T, 'command': 'add', 'paths': ['.']})
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
