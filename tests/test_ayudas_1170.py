# -*- coding: utf-8 -*-
"""Lo que confundio a Hermes en la validacion de la 1.16.0, contestado desde
el servidor (David, 7-oct-2026: "analizar donde se confunde a ver si le
podemos ayudar nosotros desde el server").

  H1  delphi_build de un .dpr compila por su .dproj (DprojDe), como resuelven
      delphi_config y delphi_test; antes BUILD-016 "no es un proyecto".
  H2  control: un fichero que no es un proyecto sigue siendo BUILD-016.
  H3  delphi_config view dice defaultPlatform, la MISMA que compila
      delphi_build sin platform= (summary y platforms).
  H4  un log -S/-G vacio dice lo que recibio git y como comprobar el texto
      (GIT-058); el texto "Oben" del fichero de Hermes, buscado como "Open".
  H5  control: -S con el texto bien escrito encuentra su commit; otra consulta
      vacia repite lo que recibio git SIN la pista de -S/-G; una orden que
      escribe y calla no repite sus argumentos.
  H6  el mensaje de un commit o un tag en args (-m, -am) -> GIT-059, nada
      hecho; control: el tag anotado con message= funciona.
  H7  GIT-014 dice que path y ref son PARAMETROS, no args.
  H8  REPORT-005 dice cuantos caracteres guardo y como acaba (el informe
      final de Hermes llego cortado a 4.000 por su lado).
  H9  delphi_help tasks dice que faltan las vault_* y por que: sin vault (lo
      que vio Hermes: 37 tools donde la documentacion dice 42), con el vault
      de solo lectura; control: con vault de escritura, ninguna nota.
  H10 delphi_paserver se llama "profile" como delphi_build y delphi_desktop:
      tools/list lo anuncia asi, "name" sigue valiendo (alias, la misma
      respuesta) y PAS-051 nombra "profile".
  H11 reseat-sdk y remove-sdk toman solo "sdk": "name" valia de reserva y,
      llamado "profile", nombraria un SDK con un perfil -> PAS-051.
  H12 la puerta del nombre de un perfil (PAS-015) mira "profile" Y "name":
      leia la clave cruda "name", y al renombrar, un "bad name!" paso y se
      hizo un .profile de verdad en el APPDATA (test_paserver, 7-oct-2026). El
      host es uno que nadie permite: si la puerta fallara, add-profile se
      pararia en RemoteHosts y no crearia nada.

Uso:  python tests/test_ayudas_1170.py [exe]
"""
import os, json
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ayudas1170')
JAIL = os.path.join(BASE, 'jail')
VAULT = os.path.join(BASE, 'vault')
for d in (JAIL, VAULT):
    os.makedirs(d, exist_ok=True)
open(os.path.join(VAULT, 'AGENTS-VAULT.md'), 'w').write('# reglas\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ayudas1170', t=900)
servidores = [srv]


def J(t):
    return mc.como_json(t) or {}


def frase(nombre, n=40):
    """El principio de un texto del catalogo que no lleva etiqueta."""
    return mc.catalogo()[nombre].strip()[:n]


try:
    # ---- H1-H3: el proyecto por su .dpr, la plataforma por defecto ----
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'PC', 'dir': os.path.join(JAIL, 'PC')})
    D = os.path.join(JAIL, 'PC', 'PC.dproj')
    out = srv.call('delphi_build', {'project': os.path.join(JAIL, 'PC', 'PC.dpr')}, 900)
    jb = J(out)
    check('H1 delphi_build de un .dpr compila por su .dproj (antes BUILD-016)',
          jb.get('success') is True and not mc.es(out, 'SR_BUILD_NOT_A_PROJECT_FMT'), out[:300])

    md = os.path.join(JAIL, 'PC', 'NOTAS.md')
    open(md, 'w').write('# notas\n')
    out = srv.call('delphi_build', {'project': md}, 120)
    check('H2 control: lo que no es un proyecto sigue siendo BUILD-016',
          mc.es(out, 'SR_BUILD_NOT_A_PROJECT_FMT'), out[:200])

    vista = J(srv.call('delphi_config', {'project': D}))
    plats = J(srv.call('delphi_config', {'project': D, 'section': 'platforms'}))
    check('H3 view dice defaultPlatform, la que compila delphi_build sin platform= (summary y platforms)',
          vista.get('defaultPlatform') and vista.get('defaultPlatform') == jb.get('platform')
          and plats.get('defaultPlatform') == vista.get('defaultPlatform'),
          '%s / %s / build %s' % (vista.get('defaultPlatform'), plats.get('defaultPlatform'), jb.get('platform')))

    # ---- H4-H7: git ----
    R = os.path.join(JAIL, 'repo')
    os.makedirs(R)
    srv.call('delphi_git', {'repo': R, 'command': 'init'})
    srv.call('delphi_git', {'repo': R, 'command': 'config', 'args': 'user.name', 'message': 'Bateria'})
    srv.call('delphi_git', {'repo': R, 'command': 'config', 'args': 'user.email', 'message': 'b@x.local'})
    open(os.path.join(R, 'open.txt'), 'w').write('Oben test 1.17.0\n')   # la errata de Hermes
    srv.call('delphi_git', {'repo': R, 'command': 'add', 'args': 'open.txt'})
    srv.call('delphi_git', {'repo': R, 'command': 'commit', 'message': 'add open.txt'})

    out = srv.call('delphi_git', {'repo': R, 'command': 'log', 'args': '-SOpen'})
    check('H4 log -S vacio: dice lo que recibio git (-SOpen) y como comprobar el texto (GIT-058)',
          mc.es(out, 'SN_GIT_CONSULTA_VACIA_FMT') and '-SOpen' in out and mc.es(out, 'SN_GIT_PICKAXE_VACIO'), out[:300])

    out = srv.call('delphi_git', {'repo': R, 'command': 'log', 'args': '-SOben'})
    vacia = srv.call('delphi_git', {'repo': R, 'command': 'log', 'args': '--author=nadie'})
    tag = srv.call('delphi_git', {'repo': R, 'command': 'tag', 'args': 'ligero1170'})
    check('H5 control: -S bien escrito encuentra su commit; otra consulta vacia repite lo recibido sin la '
          'pista de -S/-G; una orden que escribe y calla no repite sus argumentos',
          'add open.txt' in out and '--author=nadie' in vacia and not mc.es(vacia, 'SN_GIT_PICKAXE_VACIO')
          and mc.es(vacia, 'SN_GIT_CONSULTA_VACIA_FMT') and not mc.es(tag, 'SN_GIT_CONSULTA_VACIA_FMT')
          and mc.es(tag, 'SN_GIT_SILENT_OK_FMT') and 'ligero1170' not in tag,
          '%s | %s | %s' % (out[:120], vacia[:200], tag[:160]))

    # el arbol SUCIO: si la negativa fallase, -m y -am SI harian un commit (con
    # el arbol limpio antes == despues no podia fallar: revision de la 1.17.0);
    # el commit de control de abajo prueba que habia algo que commitear
    open(os.path.join(R, 'open.txt'), 'a').write('cambio\n')
    open(os.path.join(R, 'nuevo.txt'), 'w').write('nuevo\n')
    srv.call('delphi_git', {'repo': R, 'command': 'add', 'args': 'nuevo.txt'})
    antes = srv.call('delphi_git', {'repo': R, 'command': 'log', 'args': '--format=%s'})
    c1 = srv.call('delphi_git', {'repo': R, 'command': 'commit', 'args': '-m hola', 'message': 'x'})
    c2 = srv.call('delphi_git', {'repo': R, 'command': 'commit', 'args': '-am hola', 'message': 'x'})
    t1 = srv.call('delphi_git', {'repo': R, 'command': 'tag', 'args': '-m anotado v2'})
    despues = srv.call('delphi_git', {'repo': R, 'command': 'log', 'args': '--format=%s'})
    tags = srv.call('delphi_git', {'repo': R, 'command': 'tag'})
    t2 = srv.call('delphi_git', {'repo': R, 'command': 'tag', 'args': 'v3', 'message': 'anotado'})
    tags2 = srv.call('delphi_git', {'repo': R, 'command': 'tag'})
    srv.call('delphi_git', {'repo': R, 'command': 'commit', 'message': 'control 1170'})
    control = srv.call('delphi_git', {'repo': R, 'command': 'log', 'args': '--format=%s'})
    check('H6 el mensaje en args (-m, -am) de commit y tag -> GIT-059 sin hacer nada; control: tag con message=',
          all(mc.es(x, 'SR_GIT_MENSAJE_EN_ARGS') for x in (c1, c2, t1)) and antes == despues
          and 'v2' not in tags and 'v3' in tags2 and not mc.es(t2, 'SR_GIT_MENSAJE_EN_ARGS')
          and 'control 1170' in control and 'control 1170' not in despues,
          '%s | %s | %s | %s' % (c1[:120], c2[:120], t1[:120], tags2[:120]))

    out = srv.call('delphi_git', {'repo': R, 'command': 'worktree', 'args': 'add path=otra'})
    check('H7 GIT-014 dice que path y ref son PARAMETROS, nunca dentro de args',
          mc.es(out, 'SR_GIT_WORKTREE_ARGS') and 'never inside args' in out, out[:300])

    # ---- H8: lo que guardo un informe ----
    msg = 'A' * 100 + ' final FIN-1170'
    out = srv.call('delphi_report', {'message': msg + '\n', 'agent': 'bateria', 'kind': 'question'})
    check('H8 REPORT-005 dice cuantos caracteres guardo y como acaba',
          mc.es(out, 'SN_REPORT_OK_FMT') and ('%d characters' % len(msg)) in out
          and ('"...' + msg[-60:] + '"') in out, out[:400])

    # ---- H9: lo que tools/list no anuncia, y por que ----
    tareas = srv.call('delphi_help', {'command': 'tasks'})
    sv = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'srv_ro')),
                  mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                              'DELPHI_MCP_VAULT_READONLY': '1'}), nombre='ayudas1170ro', t=120)
    servidores.append(sv)
    tareas_ro = sv.call('delphi_help', {'command': 'tasks'})
    sw = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'srv_rw')),
                  mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                              'DELPHI_MCP_VAULT_READONLY': '0'}), nombre='ayudas1170rw', t=120)
    servidores.append(sw)
    tareas_rw = sw.call('delphi_help', {'command': 'tasks'})
    sin, lect = frase('SF_HELP_TASKS_SIN_VAULT'), frase('SF_HELP_TASKS_VAULT_LECTURA')
    check('H9 help tasks dice que faltan las vault_* y por que (sin vault; vault de solo lectura); '
          'control: con vault de escritura, ninguna nota',
          sin in tareas and lect not in tareas and lect in tareas_ro and sin not in tareas_ro
          and sin not in tareas_rw and lect not in tareas_rw,
          '%s... | %s...' % (tareas[-300:], tareas_ro[-200:]))

    # ---- H10: "profile" en delphi_paserver ----
    lista = srv.request('tools/list') or {}
    props = {}
    for t in lista.get('result', {}).get('tools', []):
        if t.get('name') == 'delphi_paserver':
            props = t.get('inputSchema', {}).get('properties', {})
    con_profile = srv.call('delphi_paserver', {'command': 'test-connection', 'profile': 'noexiste1170'})
    con_name = srv.call('delphi_paserver', {'command': 'test-connection', 'name': 'noexiste1170'})
    sobra = srv.call('delphi_paserver', {'command': 'platforms', 'profile': 'x'})
    check('H10 delphi_paserver anuncia "profile" (no "name"); "name" sigue valiendo con la misma respuesta; '
          'PAS-051 nombra "profile"',
          'profile' in props and 'name' not in props and con_profile == con_name
          and not mc.es(con_profile, 'SR_SYS_UNKNOWN_PARAM_FMT') and 'noexiste1170' in con_profile
          and mc.es(sobra, 'SR_PASERVER_NO_VA_CON_COMANDO_FMT') and '"profile"' in sobra,
          '%s | %s | %s | %s' % (sorted(props), con_profile[:150], con_name[:150], sobra[:150]))

    # un SDK que NO existe: el servidor de bateria usa el APPDATA real, y el
    # mutante (el binario de antes) BORRO el zorin18.sdk de verdad con
    # 'zorin18' aqui (7-oct-2026, repuesto desde una copia de la bateria)
    q1 = srv.call('delphi_paserver', {'command': 'remove-sdk', 'profile': 'noexiste1170'})
    q2 = srv.call('delphi_paserver', {'command': 'reseat-sdk', 'name': 'noexiste1170'})
    check('H11 reseat-sdk y remove-sdk toman solo "sdk": un perfil (o "name") ahi -> PAS-051 sin hacer nada',
          all(mc.es(q, 'SR_PASERVER_NO_VA_CON_COMANDO_FMT') and 'takes sdk' in q for q in (q1, q2))
          # quien mando "name" lee por que se habla de "profile" (revision de la 1.17.0)
          and 'old spelling of "profile"' in q2,
          '%s | %s' % (q1[:200], q2[:200]))
    # en un comando que nunca tomo "name" no hay nota de "name", y uno sin
    # parametros dice que no toma ninguno, no "takes ." (segunda revision)
    q3 = srv.call('delphi_paserver', {'command': 'platforms', 'profile': 'noexiste1170'})
    check('H11 ...platforms con un perfil: PAS-051 "takes no parameters" y sin la nota de "name"',
          mc.es(q3, 'SR_PASERVER_NO_VA_CON_COMANDO_FMT') and 'takes no parameters' in q3 and
          'old spelling' not in q3, q3[:200])

    malos = [srv.call('delphi_paserver', {'command': 'add-profile', k: 'mal nombre!',
                                          'host': '192.0.2.1', 'password': 'x'}) for k in ('profile', 'name')]
    malos.append(srv.call('delphi_paserver', {'command': 'test-connection', 'profile': 'mal nombre!'}))
    check('H12 la puerta del nombre de un perfil mira "profile" y "name" (PAS-015), antes de todo',
          all(mc.abre(m, 'SR_PASERVER_NAME_FMT') for m in malos), ' | '.join(m[:150] for m in malos))
finally:
    for s in servidores:
        try: s.mata()
        except Exception: pass

try:
    mc.fin('ayudas 1170 battery')  # sys.exit: la carpeta se borra en el finally
finally:
    mc.borra(BASE)
