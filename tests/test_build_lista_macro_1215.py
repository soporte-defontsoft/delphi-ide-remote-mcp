# -*- coding: utf-8 -*-
r"""Lo que un macro expande a una LISTA se juzga trozo a trozo (1.21.5). El IDE
cierra la lista de paquetes de todo proyecto con $(DCC_UsePackage); hasta la
1.21.4 la puerta del build (LecturasDelBuildDenegadas) expandia ese macro a la
lista entera y la juzgaba como UNA ruta relativa, negada en cuanto carpeta +
lista pasaban de MAX_PATH: todo proyecto real con mas de ~25 paquetes caia con
BUILD-050 citando $(DCC_UsePackage) (medido el 21-oct-2026 en un proyecto FMX
real; aislado con un probe: 217 caracteres pasaban, 313 no, 1599 sin macro si).
Ahora lo expandido se parte por ';' como el valor escrito y cada trozo se juzga
solo; un trozo de fuera se sigue negando.

Fixture: un proyecto de consola (delphi_create) con una DCC_UsePackage en su
grupo base (N nombres de paquete pkgNNNN, inertes para un build de consola);
se compila Win64 Release.

  M0 control: el proyecto recien creado compila
  M1 25 nombres + $(DCC_UsePackage) (217 caracteres): compila (ya compilaba)
  M2 37 nombres + $(DCC_UsePackage) (313 caracteres): compila
  M3 200 nombres SIN macro (1599 caracteres): compila (ya compilaba)
  M4 la forma del IDE a dos niveles: 40 en la base y 40 mas + $(DCC_UsePackage)
     en el grupo de Win64: compila
  M5 guarda: un search path que expande a la lista de carpetas del PATH del
     servidor ($(Path), fuera de la jaula): BUILD-050 citando el elemento. En la
     1.21.4 COMPILABA: la lista entera parecia un texto con ':' y barras detras,
     lo que la puerta toma por una URL y no juzga; trozo a trozo, cada carpeta
     de fuera se niega
  M6 guarda: lib;$(DCC_UnitSearchPath) en la base y $(DCC_UnitSearchPath) solo en
     el grupo de Win64, con lib dentro: compila

M2, M4 y M5 son ROJAS contra 1.21.4 (pasar su exe como argumento): M2 y M4 con
BUILD-050 citando $(DCC_UsePackage), M5 compilando lo que no debia.

Uso:  python tests/test_build_lista_macro_1215.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-lista-macro')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='lm', t=600)

BASE_COND = "'$(Base)'!=''"
WIN64_COND = "'$(Base_Win64)'!=''"


def fixture(nombre):
    """Un proyecto de consola nuevo (delphi_create) en su carpeta: (carpeta, .dproj, xml)."""
    carpeta = os.path.join(BASE, nombre)
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check(nombre + ': fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    return carpeta, proyecto, xml


def escribe(proyecto, xml, payload):
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace('</Project>', payload + '</Project>'))


def grupo(condicion, elemento):
    return '<PropertyGroup Condition="%s">%s</PropertyGroup>' % (condicion, elemento)


def paquetes(n, desde=0, macro=True):
    """La forma del IDE: nombres separados por ; y, si se pide, $(DCC_UsePackage) al final."""
    lista = ';'.join('pkg%04d' % i for i in range(desde, desde + n))
    if macro:
        lista += ';$(DCC_UsePackage)'
    return '<DCC_UsePackage>%s</DCC_UsePackage>' % lista


def build(proyecto):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Release'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def lectura_fuera(r, elemento):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and ('<%s>' % elemento) in r


try:
    carpeta, proyecto, xml = fixture('lista')
    r = build(proyecto)
    check('M0 control: el proyecto recien creado compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo(BASE_COND, paquetes(25)))
    r = build(proyecto)
    check('M1 25 nombres + $(DCC_UsePackage), 217 caracteres: compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo(BASE_COND, paquetes(37)))
    r = build(proyecto)
    check('M2 37 nombres + $(DCC_UsePackage), 313 caracteres: compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo(BASE_COND, paquetes(200, macro=False)))
    r = build(proyecto)
    check('M3 200 nombres sin macro, 1599 caracteres: compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo(BASE_COND, paquetes(40)) + grupo(WIN64_COND, paquetes(40, desde=40)))
    r = build(proyecto)
    check('M4 la forma del IDE a dos niveles (base + Win64, 80 nombres): compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo(BASE_COND, '<DCC_UnitSearchPath>$(Path)</DCC_UnitSearchPath>'))
    r = build(proyecto)
    check('M5 guarda: un search path que expande al PATH del servidor: BUILD-050 (sigue)',
          lectura_fuera(r, 'DCC_UnitSearchPath'), r[:300])

    os.makedirs(os.path.join(carpeta, 'lib'))
    escribe(proyecto, xml, grupo(BASE_COND, '<DCC_UnitSearchPath>lib;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>') +
            grupo(WIN64_COND, '<DCC_UnitSearchPath>$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'))
    r = build(proyecto)
    check('M6 guarda: lib;$(DCC_UnitSearchPath) y el macro solo en Win64, lib dentro: compila', compila(r), detalle(r))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('build lista macro 1215')
