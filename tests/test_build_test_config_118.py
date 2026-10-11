# -*- coding: utf-8 -*-
"""Paridad de validacion de delphi_test con delphi_build (revisor 1.18.1, zona jaula).

delphi_build sanea config/platform en la puerta (BuildArgDenied, Lsp.Guard.pas):
platform por la whitelist exacta (CanonicalPlatform) y config por un charset que
no admite metacaracteres. delphi_test NO pasa por esa puerta (BuildArgDenied solo
se aplica a delphi_build, Lsp.Guard.pas ~2161): su unico control de config es
ConfigDesconocida (Lsp.Dproj.pas), que no restringe nada cuando el .dproj no
declara <BuildConfiguration> (la condicion es "Length(Configs)>0 and not
HasConfig(...)"). Y config termina sin entrecomillar en la linea de msbuild
(Lsp.BuildRunner.pas ~1709, /p:Config=%s /p:Platform=%s), bajo un Job Object que
no aisla el sistema de ficheros.

Esta bateria exige que delphi_test trate config/platform IGUAL que delphi_build:
una config/platform con metacaracteres, sobre un proyecto SIN configuraciones
declaradas, tiene que ser RECHAZADA y no producir NINGUN efecto. Control: la
misma entrada en delphi_build ya se rechaza, y un proyecto CON configuraciones
tambien (ConfigDesconocida por nombre exacto). platform ya esta a salvo
(whitelist exacta) y se vigila que siga.

El efecto observable de prueba (si algo se colara) es crear un fichero VACIO
dentro de la carpeta de la bateria (copy nul <relativo>), con el servidor
lanzado con cwd en esa carpeta: nada real, nada fuera de mc.RAIZ. Con el arreglo
no se crea nada (se rechaza antes). Mutante: quitado el arreglo, el fichero
aparece y la bateria se pone roja.

Margenes amplios; si no hay RAD Studio o delphi_create no deja los proyectos,
sale SIN_CHECKS (no en falso verde). Limpia su carpeta al acabar.

Uso:  python tests/test_build_test_config_118.py [ruta-al-exe]
"""
import atexit
import glob
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

WORK = mc.carpeta('build-test-config-118')
atexit.register(mc.borra, WORK)
EXE = mc.copia_exe(os.path.join(WORK, 'srv'))
JAIL = os.path.join(WORK, 'jaula')
APPDATA = os.path.join(WORK, 'appdata')
os.makedirs(JAIL)
os.makedirs(APPDATA)

# marcadores RELATIVOS: el build corre con el cwd del servidor, que aqui es WORK,
# asi que un 'copy nul <rel>' colado caeria DENTRO de la carpeta de la bateria
MK_TEST = 'marcador-test.txt'
MK_BUILD = 'marcador-build.txt'
MK_CON = 'marcador-concfgs.txt'
for m in (MK_TEST, MK_BUILD, MK_CON):
    p = os.path.join(WORK, m)
    if os.path.exists(p):
        os.remove(p)


def inj(marker):
    # '&' encadena un comando SIN redireccion (copy nul crea un fichero vacio;
    # nada de < > : " | ? *, que son los caracteres que si frena la jaula de
    # rutas); 'rem' se come el resto de la linea
    return 'Debug & copy nul %s & rem ' % marker


SKIP = None
env = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1',
                  'LOCALAPPDATA': APPDATA})
# cwd=WORK: donde caeria un marcador relativo (dentro de la bateria)
srv = mc.Stdio(EXE, env, nombre='build-test-config', cwd=WORK, t=240)
call = srv.call


def crea(nombre, quitar_configs):
    d = os.path.join(JAIL, nombre)
    r = call('delphi_create', {'kind': 'project-console', 'dir': d, 'name': nombre})
    hit = glob.glob(os.path.join(d, '**', nombre + '.dproj'), recursive=True)
    if not hit:
        return None, r
    dproj = hit[0]
    if quitar_configs:
        xml = open(dproj, encoding='utf-8-sig').read()
        # renombrar la etiqueta deja Configs VACIO (el lector busca
        # <BuildConfiguration Include=...>); el proyecto sigue compilando Debug
        open(dproj, 'w', encoding='utf-8').write(re.sub(r'BuildConfiguration', 'BC_SIN', xml))
    return dproj, r


def rad_no(txt):
    return mc.catalogo()['SE_BUILD_RAD_STUDIO_INSTALLATION_DISCOVERED'] in str(txt)


def corto(t, n=200):
    return ' '.join(str(t).split())[:n]


try:
    # el nombre tiene que decir test/tests/spec para que sea un proyecto de test
    PSIN, rs = crea('TestSinCfg', True)    # el agujero: sin <BuildConfiguration>
    PCON, rc = crea('TestConCfg', False)   # control: con configuraciones
    if not PSIN or not PCON:
        SKIP = 'delphi_create no dejo los proyectos: %s %s' % (corto(rs, 80), corto(rc, 80))
    else:
        sin_ok = 'BuildConfiguration Include' not in open(PSIN, encoding='utf-8').read()
        con_ok = 'BuildConfiguration Include' in open(PCON, encoding='utf-8').read()

        # sonda de RAD Studio con la primera construccion
        primera = call('delphi_test', {'command': 'run', 'project': PSIN,
                                        'config': inj(MK_TEST), 'platform': 'Win64'}, t=240)
        if rad_no(primera):
            SKIP = 'no hay RAD Studio en esta maquina'
        elif not (sin_ok and con_ok):
            SKIP = 'fixture: TestSinCfg sin configs=%s, TestConCfg con configs=%s' % (sin_ok, con_ok)
        else:
            # --- lo que se exige de delphi_test ---
            mk_test = os.path.join(WORK, MK_TEST)
            check('delphi_test: una config con metacaracteres (proyecto SIN configuraciones) '
                  'NO produce efecto (ningun fichero creado)',
                  not os.path.exists(mk_test),
                  'marcador presente = la config se ejecuto (vulnerable). %s' % corto(primera))
            check('delphi_test: esa config es RECHAZADA (como en delphi_build)',
                  mc.rechazado(primera), corto(primera))

            # ";" -> propiedades de msbuild: tiene que rechazarse igual
            out_semic = call('delphi_test', {'command': 'run', 'project': PSIN,
                                             'config': 'Debug;ZZZ=1', 'platform': 'Win64'}, t=240)
            check('delphi_test: un ";" en config (propiedad extra de msbuild) es RECHAZADO',
                  mc.rechazado(out_semic), corto(out_semic))

            # platform ya esta a salvo (whitelist exacta): se vigila que siga
            out_plat = call('delphi_test', {'command': 'run', 'project': PSIN,
                                            'config': 'Debug', 'platform': 'Win64;ZZZ=1'}, t=60)
            check('delphi_test: una platform fuera de la whitelist exacta es RECHAZADA',
                  mc.rechazado(out_plat), corto(out_plat))

            # --- CONTROL 1: delphi_build con la MISMA entrada ya se rechaza ---
            mk_build = os.path.join(WORK, MK_BUILD)
            out_b = call('delphi_build', {'project': PSIN, 'config': inj(MK_BUILD),
                                          'platform': 'Win64'}, t=60)
            check('control: delphi_build con la misma config -> RECHAZADA y sin efecto',
                  mc.rechazado(out_b) and not os.path.exists(mk_build), corto(out_b))

            # --- CONTROL 2: proyecto CON configuraciones -> rechazado por nombre ---
            mk_con = os.path.join(WORK, MK_CON)
            out_c = call('delphi_test', {'command': 'run', 'project': PCON,
                                         'config': inj(MK_CON), 'platform': 'Win64'}, t=240)
            check('control: delphi_test con un proyecto CON configuraciones -> RECHAZADA (nombre exacto) y sin efecto',
                  mc.rechazado(out_c) and not os.path.exists(mk_con), corto(out_c))
finally:
    srv.cierra()

mc.fin('build: delphi_test config/platform como delphi_build (1.18.1)', sin_checks=SKIP)
