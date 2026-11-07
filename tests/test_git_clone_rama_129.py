"""1.29 (B9 del revisor del paisaje): la rama de un clone se juzgaba con
'git -C <primer ancestro que existe> check-ref-format --branch <nombre>'. El
destino de un clone aun no existe, y la carpeta de encima puede estar dentro de
un repositorio FUERA de las raices: --branch le pregunta a ESE repo (@{-1} lee
su reflog). Con '@{-1}' la respuesta del servidor decia si aquel repo tenia una
rama anterior: un bit de un repo ajeno. Ahora el nombre se juzga como la ref
entera refs/heads/<nombre>, que git comprueba sin leer ningun repo.

Usage:  python tests/test_git_clone_rama_129.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('gitclonerama129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def git_fuera(repo, *args):
    """git a pelo, el del arnes: el repo de FUERA lo monta la bateria, no el servidor."""
    return subprocess.run(['git', '-c', 'user.name=Probe Bot', '-c', 'user.email=probe@example.com',
                           '-C', repo] + list(args), capture_output=True, text=True)


def repo_fuera(nombre, con_rama_anterior):
    """Un repo fuera de las raices con una raiz dentro. Con rama anterior, @{-1}
    resuelve (switch a otra rama y vuelta)."""
    repo = os.path.join(BASE, nombre)
    os.makedirs(repo)
    git_fuera(repo, 'init', '-q', '-b', 'main')
    with open(os.path.join(repo, 'a.txt'), 'w') as f:
        f.write('uno\n')
    git_fuera(repo, 'add', 'a.txt')
    git_fuera(repo, 'commit', '-q', '-m', 'inicial')
    if con_rama_anterior:
        git_fuera(repo, 'switch', '-q', '-c', 'secreta')
        git_fuera(repo, 'switch', '-q', 'main')
    jaula = os.path.join(repo, 'jaula')
    os.makedirs(jaula)
    return repo, jaula


CON, JAULA_CON = repo_fuera('fuera-con', True)
SIN, JAULA_SIN = repo_fuera('fuera-sin', False)
r = git_fuera(CON, 'rev-parse', '--abbrev-ref', '@{-1}')
check('(control) el repo de fuera SI tiene rama anterior: @{-1} es "secreta"',
      r.returncode == 0 and r.stdout.strip() == 'secreta', (r.stdout + r.stderr)[:200])

env = mc.entorno({'DELPHI_MCP_ROOTS': JAULA_CON + ';' + JAULA_SIN,
                  'DELPHI_MCP_GIT_REMOTES': 'allowed.example'})
srv = mc.Stdio(EXE, env, nombre='gcr')
call = srv.call
URL = 'https://allowed.example/a.git'


def clone(jaula, nombre, rama):
    return call('delphi_git', {'repo': os.path.join(jaula, nombre), 'command': 'clone',
                               'message': URL, 'branch': rama})


r_con = clone(JAULA_CON, 'c1', '@{-1}')
r_sin = clone(JAULA_SIN, 'c1', '@{-1}')
check('B9: branch=@{-1} se niega como nombre (GIT-071) aunque el repo de FUERA tenga rama anterior',
      mc.abre(r_con, 'SR_GIT_NOMBRE_NO_VALE_FMT'), ' '.join(r_con.split())[:300])
check('...y sin rama anterior, la misma respuesta: el servidor no dice nada del repo de fuera',
      mc.abre(r_sin, 'SR_GIT_NOMBRE_NO_VALE_FMT'), ' '.join(r_sin.split())[:300])
check('...y la negativa no deja la carpeta del clone',
      not os.path.exists(os.path.join(JAULA_CON, 'c1')) and not os.path.exists(os.path.join(JAULA_SIN, 'c1')))

# lo que --branch negaba sigue negado; lo que admitia sigue admitido (git llega a la red y falla en ella)
for rama in ('-x', 'a..b', 'x.lock', 'a b', 'rama~1'):
    r = clone(JAULA_SIN, 'c2', rama)
    check('el nombre %r se sigue negando (GIT-071)' % rama, mc.abre(r, 'SR_GIT_NOMBRE_NO_VALE_FMT'),
          ' '.join(r.split())[:240])
for rama in ('main', 'release/1.2', 'rama-' + chr(0xF1)):
    r = clone(JAULA_SIN, 'c3', rama)
    check('el nombre %r pasa el juez: git llega a la red (el host no existe) y sale con su error' % rama,
          mc.abre(r, 'SR_GIT_EXIT_FMT'), ' '.join(r.split())[:240])
srv.mata()
mc.fin('git clone rama 1.29')
