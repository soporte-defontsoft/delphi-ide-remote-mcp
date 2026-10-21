# -*- coding: utf-8 -*-
r"""Un search path con el prefijo de ruta extendida de Windows (\\?\) hacia FUERA de las
raices (revisor B de la 1.22.0, medido el 21-oct-2026): la puerta del build (JuzgaTrozo)
tomaba "un ':' con barras detras" por una URL y no juzgaba el trozo, y dcc SI abre una
carpeta por ese prefijo: una unidad que solo estaba fuera compilaba. Ahora el prefijo se
quita antes de juzgar (SinPrefijoDeDispositivo, la casa de Lsp.Rutas) y la ruta pasa por la
puerta como cualquier otra; una de dentro con prefijo sigue compilando.

Fixture: un proyecto de consola (delphi_create) cuyo .dpr usa Ajena, una unidad que solo
esta en FUERA (o en lib\, dentro); el search path va en un grupo base ANTES del primer
<Import> (tras los Import no llega a dcc).

  X0 control: la carpeta de fuera sin prefijo: BUILD-050 citando DCC_UnitSearchPath (sigue)
  X1 la misma con \\?\ delante: BUILD-050 citando DCC_UnitSearchPath (ROJA contra 1.21.4 y
     contra 0edfeb7: compilaba, con la unidad de fuera)
  X2 \\?\ hacia lib\ de DENTRO: compila (el prefijo no niega lo de dentro)

Uso:  python tests/test_build_prefijo_1220.py [ruta-a-DelphiLspMcp.exe]
"""
import os
from xml.sax.saxutils import escape
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-prefijo')
FUERA = mc.carpeta('build-prefijo-fuera')  # fuera de la raiz del servidor, hermana de BASE
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='bp', t=600)

AJENA = 'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n'


def build(proyecto):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Release'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def lectura_fuera(r):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and '<DCC_UnitSearchPath>' in r


try:
    carpeta = os.path.join(BASE, 'fixture')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    open(os.path.join(FUERA, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    dpr = os.path.join(carpeta, 'Fixture.dpr')
    with open(dpr, encoding='utf-8-sig') as f:
        fuente = f.read()
    assert 'uses' in fuente, fuente[:200]
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente.replace('uses', 'uses\r\n  Ajena,', 1))
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    assert '<Import Project=' in xml

    def con_searchpath(ruta):
        payload = ("<PropertyGroup Condition=\"'$(Base)'!=''\"><DCC_UnitSearchPath>%s</DCC_UnitSearchPath></PropertyGroup>"
                   % escape(ruta))
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(xml.replace('<Import Project=', payload + '<Import Project=', 1))

    con_searchpath(FUERA)
    r = build(proyecto)
    check('X0 control: la carpeta de fuera sin prefijo: BUILD-050 (sigue)', lectura_fuera(r), r[:300])

    con_searchpath('\\\\?\\' + FUERA)
    r = build(proyecto)
    check('X1 la carpeta de fuera con el prefijo \\\\?\\: BUILD-050 citando DCC_UnitSearchPath', lectura_fuera(r), r[:300])

    lib = os.path.join(carpeta, 'lib')
    os.makedirs(lib)
    open(os.path.join(lib, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    con_searchpath('\\\\?\\' + lib)
    r = build(proyecto)
    check('X2 el prefijo hacia lib\\ de dentro: compila', compila(r), detalle(r))
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('build prefijo 1220')
