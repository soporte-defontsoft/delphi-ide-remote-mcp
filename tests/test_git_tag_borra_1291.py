# -*- coding: utf-8 -*-
"""delphi_git tag action=delete (B1 de cierre-final-1-29-1, 11-nov-2026).

El ritual del 10-nov tuvo que borrar un tag local por consola: delphi_git no tenia como. Ahora borra uno LOCAL que
ningun remoto tiene - lo dice ls-remote de cada remoto, por la misma puerta del remoto que el ls-remote del agente -;
uno que un remoto tiene volveria con el siguiente fetch, y borrar en un remoto no lo hace esta tool.

  B1 un tag solo local: se borra (git ya no lo lista) y la respuesta dice a quien pregunto y como reponerlo (GIT-096)
     (ROJO contra 8c3f8a8c: action no iba con tag)
  B2 un tag que el remoto tiene: GIT-094 nombrando el remoto, y el tag sigue
  B3 un tag que no existe: GIT-093
  B4 otra accion: GIT-092
  B5 delete sin name: GIT-091
  B6 ref con delete: no va con el comando (GIT-034)
  B7 un remoto que no contesta (su carpeta ya no esta): GIT-095 y el tag sigue
  B8 reponerlo con el id que dio git ("was ..."): command=tag name=<tag> ref=<id>

Uso:  python tests/test_git_tag_borra_1291.py [ruta-a-DelphiLspMcp.exe]
"""
import os, re, shutil, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('git_tag_borra_1291')
SRV = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
REPO = os.path.join(JAIL, 'repo')
ORIGEN = os.path.join(JAIL, 'origen.git')
ROTO = os.path.join(JAIL, 'roto.git')
os.makedirs(SRV)
os.makedirs(REPO)
EXE = mc.copia_exe(SRV)
# 127.0.0.1 en la lista de hosts: B7 necesita un remoto de RED que la puerta deje y que no conteste (el puerto 1)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_GIT_REMOTES': '127.0.0.1'}),
               nombre='git-tag-borra', t=120)


def git(args):
    return srv.call('delphi_git', dict({'repo': REPO}, **args))


def fuera(*a, cwd):
    """git de la maquina, para montar el escenario (el remoto es una carpeta de la bateria)."""
    r = subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@example.com'] + list(a),
                       cwd=cwd, capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def tags():
    return fuera('tag', cwd=REPO).split()


try:
    fuera('init', '-q', cwd=REPO)
    open(os.path.join(REPO, 'a.txt'), 'w').write('a\n')
    fuera('add', 'a.txt', cwd=REPO)
    fuera('commit', '-q', '-m', 'uno', cwd=REPO)
    fuera('clone', '-q', '--bare', REPO, ORIGEN, cwd=JAIL)
    fuera('remote', 'add', 'origin', ORIGEN, cwd=REPO)
    fuera('tag', 'solo-aqui', cwd=REPO)
    fuera('tag', 'en-remoto', cwd=REPO)
    fuera('push', '-q', 'origin', 'en-remoto', cwd=REPO)
    check('preparacion: dos tags locales, uno de ellos en el remoto',
          {'solo-aqui', 'en-remoto'} <= set(tags()) and 'en-remoto' in fuera('ls-remote', '--tags', ORIGEN, cwd=JAIL),
          (tags(), fuera('ls-remote', '--tags', ORIGEN, cwd=JAIL)))
    ID = fuera('rev-parse', 'solo-aqui', cwd=REPO)

    r = git({'command': 'tag', 'action': 'delete', 'name': 'solo-aqui'})
    check('B1 un tag solo local se borra, y la respuesta dice a quien pregunto y como reponerlo (ROJO: action no iba)',
          'solo-aqui' not in tags() and mc.es(r, 'SN_GIT_TAG_BORRADO_FMT') and 'origin' in r
          and 'name=solo-aqui' in r, r[:400])
    m = re.search(r'\(was ([0-9a-f]+)\)', r)
    check('B1b ...con el id de git ("was ...") que es el del tag borrado', m is not None and ID.startswith(m.group(1)),
          (ID, r[:300]))

    r = git({'command': 'tag', 'action': 'delete', 'name': 'en-remoto'})
    check('B2 un tag que el remoto tiene: GIT-094 nombrando el remoto, y el tag sigue',
          mc.abre(r, 'SR_GIT_TAG_EN_REMOTO_FMT') and '"origin"' in r and 'en-remoto' in tags(), r[:300])

    r = git({'command': 'tag', 'action': 'delete', 'name': 'no-existe'})
    check('B3 un tag que no existe: GIT-093', mc.abre(r, 'SR_GIT_TAG_NO_ESTA_FMT') and 'no-existe' in r, r[:300])

    r = git({'command': 'tag', 'action': 'borrar', 'name': 'en-remoto'})
    check('B4 otra accion: GIT-092 y nada hecho', mc.abre(r, 'SR_GIT_TAG_ACCION_FMT') and 'en-remoto' in tags(), r[:300])

    r = git({'command': 'tag', 'action': 'delete'})
    check('B5 delete sin name: GIT-091', mc.abre(r, 'SR_GIT_TAG_SIN_NOMBRE_FMT') and 'action=delete' in r, r[:300])

    r = git({'command': 'tag', 'action': 'delete', 'name': 'en-remoto', 'ref': 'HEAD'})
    check('B6 ref no va con delete', mc.abre(r, 'SR_GIT_NO_VA_CON_COMANDO_FMT') and 'ref' in r
          and 'en-remoto' in tags(), r[:300])

    # un segundo remoto de RED que la puerta deja (127.0.0.1 esta en la lista) y que no contesta (el puerto 1,
    # cerrado: falla al momento): no se sabe si lo tiene
    fuera('tag', 'otro-solo', cwd=REPO)
    fuera('remote', 'add', 'roto', 'http://127.0.0.1:1/nada.git', cwd=REPO)
    r = git({'command': 'tag', 'action': 'delete', 'name': 'otro-solo'})
    check('B7 un remoto que no contesta: GIT-095 nombrandolo, y el tag sigue',
          mc.abre(r, 'SR_GIT_TAG_REMOTO_NO_CONTESTA_FMT') and '"roto"' in r and 'otro-solo' in tags(), r[:300])
    fuera('remote', 'remove', 'roto', cwd=REPO)
    # ...y uno de CARPETA que ya no esta: lo niega antes la puerta del remoto, con lo que pidio el agente
    os.makedirs(ROTO)
    fuera('remote', 'add', 'roto', ROTO, cwd=REPO)
    mc.borra(ROTO)
    r = git({'command': 'tag', 'action': 'delete', 'name': 'otro-solo'})
    check('B7b la carpeta del remoto ya no esta: la puerta del remoto lo niega nombrando "tag action=delete"',
          mc.rechazado(r) and 'tag action=delete' in r and 'otro-solo' in tags(), r[:300])
    fuera('remote', 'remove', 'roto', cwd=REPO)

    r = git({'command': 'tag', 'name': 'solo-aqui', 'ref': ID})
    check('B8 reponerlo con el id que dio git: command=tag name=solo-aqui ref=<id>',
          'solo-aqui' in tags() and fuera('rev-parse', 'solo-aqui', cwd=REPO) == ID, (r[:200], tags()))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_git tag action=delete (1.29.1, B1)')
