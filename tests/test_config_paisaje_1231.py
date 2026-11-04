# -*- coding: utf-8 -*-
"""delphi_config y delphi_create: cinco reglas que vivian en dos sitios con dos respuestas (V203, V205,
V206, V213 y V214 de la 1.23.1, revisor del paisaje del 29-oct).

  K1 set-sdk sdk=ZORIN18: el .dproj lleva el nombre de la LISTA del IDE (zorin18.sdk), no la grafia
     tecleada; el build ya elegia el de la lista y set-sdk escribia el del agente (V203; ROJA contra
     283f3f2). Sin zorin18.sdk registrado en esta maquina no se mide (NOTA)
  K2 add-searchpath platform=Win64 path=lib\\$(Platform): se acepta (la puerta expandia solo los macros
     del IDE: CFG-017 "unknown macro" de un search path que el build expande; V205, ROJA)
  K3 add-searchpath path=$(MSBuildProjectDirectory)\\comun: se acepta (las reservadas de msbuild, las que
     ya leian los ajustes del motor; V205, ROJA)
  K4 remove-searchpath de una entrada con una letra no ASCII pedida en otra caja (A-ene-O / a-ene-o): se quita,
     como add-searchpath ya la daba por listada (SameText solo junta A..Z; V206, ROJA)
  K5 el .gitignore de un proyecto nuevo ignora la salida de las 13 plataformas (nombraba 6: V213, ROJA)
  K6 create kind=datamodule en un proyecto FMX cuyo .dproj no trae FrameworkType: el modulo es de FMX,
     por EL juez del marco (el del form; V214, ROJA: Vcl.Controls.TControl)

Uso:  python tests/test_config_paisaje_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('config_paisaje_1231')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='config-paisaje', t=300)


def config(proyecto, comando, **campos):
    args = {'project': proyecto, 'command': comando}
    args.update(campos)
    return srv.call('delphi_config', args)


def lee(ruta):
    with open(ruta, encoding='utf-8-sig') as f:
        return f.read()


try:
    D = os.path.join(JAIL, 'cons')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Cons', 'dir': D})
    DPROJ = os.path.join(D, 'Cons.dproj')

    # (revisor de baterias de la 1.27) la version, la de la instalacion activa (delphi_installs), no '37.0' a mano
    VER = mc.instalacion_activa(srv.call).get('version', '')
    SDK = os.path.join(os.environ.get('APPDATA', ''), 'Embarcadero', 'BDS', VER, 'zorin18.sdk')
    if VER and os.path.exists(SDK):
        config(DPROJ, 'add-platform', platform='Linux64')
        r = config(DPROJ, 'set-sdk', platform='Linux64', sdk='ZORIN18')
        x = lee(DPROJ)
        check('K1 set-sdk sdk=ZORIN18: el .dproj lleva el nombre de la lista del IDE (zorin18.sdk)',
              '<PlatformSDK>zorin18.sdk</PlatformSDK>' in x, (r[:200], re.findall(r'<PlatformSDK>[^<]*<', x)))
    else:
        print('NOTA: K1 no se mide: zorin18.sdk no esta registrado en el IDE de esta maquina')

    os.makedirs(os.path.join(D, 'lib', 'Win64'))
    r = config(DPROJ, 'add-searchpath', platform='Win64', path='lib\\$(Platform)')
    # (revisor de baterias de la 1.27) K2-K4: `not mc.rechazado` dejaba pasar un INTERNAL o un timeout; aceptado
    # es su CFG de exito (SN_CONFIG_PATH_ADDED_FMT / _REMOVED_FMT)
    check('K2 add-searchpath platform=Win64 path=lib\\$(Platform): aceptado',
          mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and 'lib\\$(Platform)' in lee(DPROJ), r[:300])
    os.makedirs(os.path.join(D, 'comun'))
    r = config(DPROJ, 'add-searchpath', path='$(MSBuildProjectDirectory)\\comun')
    check('K3 add-searchpath path=$(MSBuildProjectDirectory)\\comun: aceptado',
          mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and '$(MSBuildProjectDirectory)\\comun' in lee(DPROJ), r[:300])

    ANO, ano = 'A' + chr(0xd1) + 'O', 'a' + chr(0xf1) + 'o'
    os.makedirs(os.path.join(D, ANO))
    # (revisor de baterias de la 1.27) el montaje con su control: si el add no escribia A-ENE-O, "no esta tras el
    # remove" pasaba sin quitar nada (y la NOTA de "no estaba", CFG-022, no es un rechazo)
    ra = config(DPROJ, 'add-searchpath', path=ANO)
    check('K4 fixture: add-searchpath escribe A-ENE-O', mc.abre(ra, 'SN_CONFIG_PATH_ADDED_FMT') and ANO in lee(DPROJ),
          ra[:300])
    r = config(DPROJ, 'remove-searchpath', path=ano)
    check('K4 remove-searchpath a-ene-o de la entrada A-ENE-O: se quita (como add-searchpath la daba por listada)',
          mc.abre(r, 'SN_CONFIG_PATH_REMOVED_FMT') and ANO not in lee(DPROJ), r[:300])

    # (revisor de baterias de la 1.27) las plataformas, las que el servidor conoce (su BUILD-003 las lista, la
    # misma PlataformasConocidas de Lsp.Dproj), no 7 de las 13 a mano
    rp = config(DPROJ, 'add-platform', platform='NoEsPlataforma')
    _p = mc.catalogo()['SR_PLATAFORMA_NO_VALIDA_FMT'].split('%s')
    todas = ([p.strip() for p in rp.split(_p[1], 1)[1].split(_p[2], 1)[0].split(',')]
             if mc.abre(rp, 'SR_PLATAFORMA_NO_VALIDA_FMT') and _p[1] in rp and _p[2] in rp else [])
    gi = lee(os.path.join(D, '.gitignore'))
    faltan = [p for p in todas if (p + '/') not in gi.splitlines()]
    check('K5 el .gitignore de un proyecto nuevo ignora la salida de todas las plataformas',
          len(todas) > 1 and not faltan, (faltan, rp[:300]))

    F = os.path.join(JAIL, 'fmx')
    srv.call('delphi_create', {'kind': 'project-fmx', 'name': 'Fx', 'dir': F})
    FDPROJ = os.path.join(F, 'Fx.dproj')
    x = lee(FDPROJ)
    with open(FDPROJ, 'w', encoding='utf-8', newline='') as f:
        f.write(re.sub(r'\s*<FrameworkType>[^<]*</FrameworkType>', '', x))
    r = srv.call('delphi_create', {'kind': 'datamodule', 'name': 'UDatos', 'project': os.path.join(F, 'Fx.dpr')})
    pas = os.path.join(F, 'UDatos.pas')
    check('K6 datamodule en un FMX sin FrameworkType en su .dproj: el modulo es de FMX',
          os.path.exists(pas) and 'FMX.Controls.TControl' in lee(pas), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_config y delphi_create: reglas en dos sitios 1231 (V203, V205, V206, V213, V214)')
