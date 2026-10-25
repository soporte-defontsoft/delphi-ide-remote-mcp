# -*- coding: utf-8 -*-
r"""Un symlink de FICHERO en el arbol del proyecto que apunta FUERA de las
raices: la puerta del build no lo negaba (V3 de la 1.23). El camino del `in` del
.dpr ya lo cierra V14 (LecturasDelIn -> ReadPathDenied, en la base). Lo que
quedaba: IncludeDirectivesDenied recorre la carpeta del proyecto (WalkFiles) y
solo miraba enlaces DUROS (EnlaceDuroIlegible) y las directivas, no si un fichero
del arbol es un SYMLINK cuyo destino real esta fuera; dcc, que lo resuelve,
leeria el contenido de fuera. Es el analogo de W12 (enlace duro) de
test_build_lista_blanca con un symlink.

Necesita modo desarrollador (crear un symlink de fichero); si no esta, NOTA.

  V1 (V3) un .pas del arbol es un symlink a un fichero de FUERA: la puerta lo
     niega   [ROJO contra el build sin el arreglo: hoy compila]
  V2 (guarda) un symlink a un fichero de DENTRO: compila (su destino real esta
     en la jaula)

Uso:  python tests/test_build_symlink_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-symlink-1230')
FUERA = mc.carpeta('build-symlink-1230-fuera')   # hermana de BASE: fuera de la raiz
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='build-symlink', t=600)

MARCA = 'SECRETO-DE-FUERA-V3-MARCA'
UNIT = "unit Fuera;\r\ninterface\r\nconst SECRETO_V3 = '" + MARCA + "';\r\nimplementation\r\nend.\r\n"
DENTRO = 'unit Dentro;\r\ninterface\r\nimplementation\r\nend.\r\n'
# el .dpr USA Fuera y lo imprime: si dcc llega a compilar (sin el arreglo), la
# marca queda en el exe -> prueba MEDIDA de que dcc leyo el fichero de FUERA,
# no solo de que la puerta no nego (el .pas suelto en la carpeta no bastaba)
# uses Fuera SIN "in 'Fuera.pas'": asi no lo juzga V14 (LecturasDelIn, el `in`
# del .dpr -> BUILD-061); dcc encuentra Fuera.pas en la carpeta del proyecto (el
# symlink) y es LA barrera de V3 (el recorrido de la carpeta -> BUILD-063) la
# que tiene que negarlo. Sin V3, dcc compila el symlink y lee fuera.
DPR = ("program Fixture;\r\n{$APPTYPE CONSOLE}\r\nuses\r\n  System.SysUtils,\r\n"
       "  Fuera;\r\nbegin\r\n  Writeln(SECRETO_V3);\r\nend.\r\n")
open(os.path.join(FUERA, 'Fuera.pas'), 'w', encoding='utf-8', newline='').write(UNIT)


def marca_en(exe):
    # la marca como Delphi la deja en el exe de un Writeln: UTF-16LE (string) o ascii
    if not exe or not os.path.exists(exe):
        return False
    with open(exe, 'rb') as f:
        data = f.read()
    return MARCA.encode('utf-16-le') in data or MARCA.encode('ascii') in data


def puede_symlink(link, target):
    try:
        os.symlink(target, link)
        return os.path.islink(link)
    except OSError:
        return False


def fixture(nombre):
    carpeta = os.path.join(BASE, nombre)
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    return carpeta, os.path.join(carpeta, 'Fixture.dproj')


def build(proyecto):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


try:
    carpeta, proyecto = fixture('fuera')
    link = os.path.join(carpeta, 'Fuera.pas')
    if not puede_symlink(link, os.path.join(FUERA, 'Fuera.pas')):
        print('NOTA: no se puede crear un symlink de fichero (modo desarrollador apagado): V3 no se mide')
    else:
        # el .dpr USA Fuera (el symlink) y lo imprime: con el arreglo la puerta
        # niega antes de compilar; SIN el arreglo dcc lo sigue, compila y la
        # marca aparece en el exe -> leer fuera es REAL, no solo "no nego"
        open(os.path.join(carpeta, 'Fixture.dpr'), 'w', encoding='utf-8', newline='').write(DPR)
        r = build(proyecto)
        # la ruta REAL del exe (no el campo output, que viene en notacion del
        # servidor srvc:\...): salida por defecto de un console Win64 Debug
        exe_fx = os.path.join(carpeta, 'Win64', 'Debug', 'Fixture.exe')
        check('V1 (V3) un .pas del arbol symlink a FUERA: la puerta lo niega (BUILD-063) y dcc no lee fuera',
              mc.abre(r, 'SR_BUILD_FUENTE_ENLACE_FUERA_FMT') and not compila(r)
              and not marca_en(exe_fx), r[:400])
        c2, p2 = fixture('dentro')
        real = os.path.join(c2, 'objetivo')
        os.makedirs(real)
        open(os.path.join(real, 'Dentro.pas'), 'w', encoding='utf-8').write(DENTRO)
        os.symlink(os.path.join(real, 'Dentro.pas'), os.path.join(c2, 'Dentro.pas'))
        r = build(p2)
        check('V2 (guarda) un symlink a un fichero de DENTRO compila (su destino real esta en la jaula)',
              compila(r), r[:400])
finally:
    srv.cierra()
mc.borra(BASE)
mc.borra(FUERA)
mc.fin('un symlink de fichero del arbol que sale de las raices lo niega la puerta, V3 de la 1.23')
