# -*- coding: utf-8 -*-
r"""A2 de la 1.27: UNA tabla para lo que el build ve de fuera del .dproj, la del IDE.

Medido el 3-nov-2026 en el IDE (una sonda del sandbox que David compilo en el IDE): el cuerpo del
.dproj ve $(BDSLIB), $(BDSUSERDIR), $(BDSCatalogRepository), $(BDSCatalogRepositoryAllUsers),
$(BDSPLATFORMSDKSDIR) y $(BDSBIN), con los mismos valores que la tabla del IDE del servidor
(IdeMacroVars). Nuestro msbuild solo recibia rsvars.bat y en su cuerpo valian vacio: add-searchpath
aceptaba $(BDSLIB)\$(Platform)\release ("verify with delphi_build") y delphi_build lo negaba con
BUILD-050 (leia \Win64\release). Y add-searchpath nunca resolvia $(Config) (CFG-017 siempre, con la
carpeta delante: el ..\lib\$(Platform)\$(Config) que escribe el IDE para los .dcu de un componente)
ni $(Platform) sin platform=.

  T1 add-searchpath platform=Win64 $(BDSLIB)\$(Platform)\release y delphi_build Win64 Release:
     compila (ROJA: BUILD-050)
  T2 lo que dcc recibe es lo que la puerta juzgo: con $(BDSLIB)\$(Platform)\release\<sonda> en el
     search path, la linea de dcc (verbosity=verbose) lleva <lib del IDE>\Win64\release\<sonda>
     (ROJA: BUILD-050; msbuild la leia vacia)
  T3 add-searchpath platform=Win64 lib\$(Config) con lib\Debug y lib\Release: aceptado (ROJA: CFG-017)
  T4 add-searchpath sin plataforma lib\$(Platform) con lib\Win32 y lib\Win64: aceptado (ROJA: CFG-017)
  T5 add-searchpath platform=Win64 nada\$(Platform)\$(Config) sin ninguna de sus carpetas: CFG-147
     nombrando las DOS (Win64\Debug y Win64\Release) y el .dproj intacto (ROJA: CFG-017, la macro no se
     resolvia; y luego CFG-018 nombraba solo la de Debug: A10 de la 1.27, del dirigido de Hermes)
  T6 add-searchpath $(APPDATA)\x: CFG-148, que dice que el entorno del servidor no se resuelve y manda
     a set-property; el valor de APPDATA en ninguna parte y el .dproj intacto (ROJA: CFG-017 "unknown
     macro", A10 de la 1.27)

Uso:  python tests/test_tabla_del_build_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('tabla-del-build-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='tabla-127', t=600)
SONDA = 'SondaTabla127'


def config(comando, **campos):
    args = {'project': DPROJ, 'command': comando}
    args.update(campos)
    return srv.call('delphi_config', args)


def build(verbosity='quiet'):
    return srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Release',
                                     'verbosity': verbosity}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def lee():
    with open(DPROJ, encoding='utf-8-sig') as f:
        return f.read()


try:
    D = os.path.join(JAIL, 'cons')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Cons', 'dir': D})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPROJ = os.path.join(D, 'Cons.dproj')
    ORIGINAL = lee()

    r = config('add-searchpath', platform='Win64', path='$(BDSLIB)\\$(Platform)\\release')
    rb = build()
    check('T1 add-searchpath $(BDSLIB)\\$(Platform)\\release y delphi_build Win64 Release: compila',
          # T1, T3, T4: not mc.fallo, no not rechazado, que deja pasar un INTERNAL (revisor de baterias de la 1.27)
          not mc.fallo(r) and '$(BDSLIB)\\$(Platform)\\release' in lee() and compila(rb), (r[:200], rb[:300]))

    with open(DPROJ, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(ORIGINAL)
    r = config('set-property', name='DCC_UnitSearchPath',
               value='$(BDSLIB)\\$(Platform)\\release\\%s;$(DCC_UnitSearchPath)' % SONDA)
    rb = build('verbose')
    salida = (mc.como_json(rb).get('outputTail') or rb).lower()
    check('T2 la linea de dcc lleva <lib del IDE>\\Win64\\release\\<sonda>: msbuild ve $(BDSLIB) como la puerta',
          compila(rb) and ('\\lib\\win64\\release\\' + SONDA.lower()) in salida, rb[:300])

    with open(DPROJ, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(ORIGINAL)
    for c in ('Debug', 'Release'):
        os.makedirs(os.path.join(D, 'lib', c))
    r = config('add-searchpath', platform='Win64', path='lib\\$(Config)')
    check('T3 add-searchpath platform=Win64 lib\\$(Config) con lib\\Debug y lib\\Release: aceptado',
          not mc.fallo(r) and 'lib\\$(Config)' in lee(), r[:300])

    for p in ('Win32', 'Win64'):
        os.makedirs(os.path.join(D, 'lib', p))
    r = config('add-searchpath', path='lib\\$(Platform)')
    check('T4 add-searchpath sin plataforma lib\\$(Platform) con lib\\Win32 y lib\\Win64: aceptado',
          not mc.fallo(r) and 'lib\\$(Platform)' in lee(), r[:300])

    antes = lee()
    r = config('add-searchpath', platform='Win64', path='nada\\$(Platform)\\$(Config)')
    check('T5 nada\\$(Platform)\\$(Config) sin ninguna de sus carpetas: CFG-147 con las dos y el .dproj intacto',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PATH_MISSING_VARIAS_FMT') and
          'nada\\Win64\\Debug' in r.replace('\\\\', '\\') and 'nada\\Win64\\Release' in r.replace('\\\\', '\\') and
          lee() == antes, r[:300])

    # el valor de APPDATA, con una MARCA unica: 'roaming' a secas no salia con un APPDATA que no lo
    # llevara, y la respuesta va enmascarada. Un servidor aparte, para no tocar el entorno de los
    # builds de arriba (revisor de baterias de la 1.27)
    MARCA = 'appdata-marca-t6-127'
    APPDATA6 = os.path.join(BASE, MARCA)
    os.makedirs(APPDATA6)
    srv6 = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPDATA6}), nombre='tabla-127-t6', t=120)
    try:
        r = srv6.call('delphi_config', {'project': DPROJ, 'command': 'add-searchpath', 'platform': 'Win64',
                                        'path': '$(APPDATA)\\x'})
    finally:
        srv6.cierra()
    check('T6 $(APPDATA)\\x: CFG-148, sin el valor de APPDATA, manda a set-property, el .dproj intacto',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PATH_MACRO_DESCONOCIDA_FMT') and 'set-property' in r and
          MARCA not in r.lower() and lee() == antes, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('una tabla para lo que el build ve de fuera del .dproj 1.27 (A2)')
