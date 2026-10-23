# -*- coding: utf-8 -*-
"""A14 de la 1.23: LA plataforma de un comando de config.

K1: add-searchpath, set-sdk, set-profile, add-deployfile y set-property
escribian para una plataforma que el proyecto NO declara (un grupo de
Android64 en un proyecto solo de Windows), y set-sdk contestaba "The project
will compile Linux64 with SDK ..." - lo que el build niega despues (BUILD-046).
Ahora preguntan al juez del build (PlataformaNoDeclarada); quitar no.
K2: "no es una plataforma de Delphi" salia con cuatro codigos segun el comando
(CFG-007, CFG-078, CFG-082, CFG-024) y un quinto en el build (BUILD-003); ahora
uno, con las validas, el de NegativaDePlataforma.

  P1 escribir para una plataforma no declarada se niega con el texto del build,
     y el .dproj queda como estaba, en cada comando (ROJO hasta la 1.23)
  P2 (guarda) quitar si: remove-searchpath con esa plataforma no se niega por eso
  P3 "Win99" da el MISMO texto en los diez comandos y en delphi_build (ROJO hasta
     la 1.23)

Uso:  python tests/test_plataforma_comando_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_plataforma_comando_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
NOTAS = []

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-plataforma', t=300)
try:
    proy = os.path.join(JAIL, 'P')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': proy})
    dproj = os.path.join(proy, 'P.dproj')
    lib = os.path.join(JAIL, 'lib')
    os.makedirs(lib)
    fich = os.path.join(proy, 'datos.txt')
    with open(fich, 'w') as f:
        f.write('x')

    # un SDK de Linux de ESTA maquina y su perfil (lo que dice delphi_paserver, no una lista)
    sdk = perfil = ''
    try:
        for s in json.loads(srv.call('delphi_paserver', {'command': 'profiles'})).get('sdks', []):
            if s.get('glibc') and s.get('profile'):
                sdk, perfil = s['name'], s['profile']
                break
    except Exception:
        pass

    casos = [('add-searchpath', {'platform': 'Android64', 'path': lib}),
             ('add-deployfile', {'platform': 'OSX64', 'path': fich}),
             ('set-property', {'platform': 'Linux64', 'name': 'PF_X', 'value': 'x'})]
    if sdk:
        casos += [('set-sdk', {'platform': 'Linux64', 'sdk': sdk}),
                  ('set-profile', {'platform': 'Linux64', 'profile': perfil})]
    else:
        NOTAS.append('set-sdk y set-profile sin medir: esta maquina no tiene un SDK de Linux con perfil')
    malos = []
    for cmd, args in casos:
        antes = open(dproj, 'rb').read()
        r = srv.call('delphi_config', dict(args, command=cmd, project=dproj))
        if not (mc.es(r, 'SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT') and open(dproj, 'rb').read() == antes):
            malos.append((cmd, r[:120]))
    check('P1 escribir para una plataforma que el proyecto no declara se niega (el juez del build) '
          'y el .dproj no cambia (%d comandos)' % len(casos), not malos, malos)

    r = srv.call('delphi_config', {'command': 'remove-searchpath', 'project': dproj, 'platform': 'Android64',
                                   'path': lib})
    check('P2 (guarda) quitar si: remove-searchpath con una plataforma no declarada no se niega por eso',
          not mc.es(r, 'SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT'), r[:200])

    textos = {}
    for cmd, args in [('add-platform', {}), ('remove-platform', {}), ('add-searchpath', {'path': lib}),
                      ('remove-searchpath', {'path': lib}), ('set-sdk', {'sdk': 'x.sdk'}),
                      ('set-profile', {'profile': 'x'}), ('add-deployfile', {'path': fich}),
                      ('remove-deployfile', {'path': fich}), ('set-active', {}),
                      ('get-property', {'name': 'PF_X'})]:
        r = srv.call('delphi_config', dict(args, command=cmd, project=dproj, platform='Win99'))
        textos[cmd] = r
    textos['delphi_build'] = srv.call('delphi_build', {'project': dproj, 'platform': 'Win99'})
    otros = {c: t[:40] for c, t in textos.items() if not mc.es(t, 'SR_PLATAFORMA_NO_VALIDA_FMT')}
    check('P3 "Win99" da el MISMO texto en los diez comandos y en delphi_build (con las validas)',
          not otros, otros)
finally:
    srv.cierra()

mc.borra(BASE)
for n in NOTAS:
    print('  NOTA: ' + n)
mc.fin('la plataforma de un comando de config, A14 de la 1.23')
