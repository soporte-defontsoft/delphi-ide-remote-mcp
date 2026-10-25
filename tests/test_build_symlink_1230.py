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

UNIT = 'unit Fuera;\r\ninterface\r\nconst SECRETO_V3 = 42;\r\nimplementation\r\nend.\r\n'
DENTRO = 'unit Dentro;\r\ninterface\r\nimplementation\r\nend.\r\n'
open(os.path.join(FUERA, 'Fuera.pas'), 'w', encoding='utf-8').write(UNIT)


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
        r = build(proyecto)
        check('V1 (V3) un .pas del arbol que es symlink a FUERA: la puerta lo niega',
              mc.rechazado(r) and not compila(r), r[:400])
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
