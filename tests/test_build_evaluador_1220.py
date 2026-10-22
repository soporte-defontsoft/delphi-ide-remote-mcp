# -*- coding: utf-8 -*-
r"""La puerta del build evalua las Condition de los grupos del .dproj como msbuild, y lo que
decia que era de OTRO build no se juzgaba. El revisor E de la 1.22.0 (medido el 21-oct-2026 con
el msbuild 4.8 del IDE) encontro cinco formas en que el evaluador decia "falso" donde msbuild
aplica el grupo, y un search path hacia FUERA en ese grupo compilaba con una unidad de fuera:

  X0 control: el search path de fuera en un grupo base: BUILD-050 (sigue)
  X1 un PropertyGroup dentro de ProjectExtensions (msbuild lo ignora) ponia a 0 la bandera que
     abre el grupo: BUILD-050 (ROJA contra 2860249: compilaba con la unidad de fuera)
  X2 ...dentro de un <Target> que nadie ejecuta: BUILD-050 (roja igual)
  X3 un valor se fija EXPANDIDO al definirlo (<Tarde>$(Antes)</Tarde> vale lo que Antes valia
     entonces, no despues): Tarde vale a, el grupo se aplica: BUILD-050 (roja: compilaba)
  X4 una global del build (/p:PreBuildEvent=, vaciado) gana a lo que el .dproj pone, aun
     definido antes: BUILD-050 (roja)
  X5 msbuild compara '1.0'=='1' como numeros y desescapa '%31': BUILD-050 (roja)
  X6 control: la forma de X3 con Antes definida UNA vez (Tarde vale a, el grupo se aplica) hacia
     lib\ de DENTRO: compila (no se niega de mas)

Fixture como test_build_prefijo_1220: un proyecto de consola cuyo .dpr usa Ajena, una unidad que
solo esta en FUERA (o en lib\); los grupos van ANTES del primer <Import>, y en X1 el
ProjectExtensions del IDE se mueve delante (msbuild solo admite uno, en cualquier sitio: MSB4079
con dos, medido).

Uso:  python tests/test_build_evaluador_1220.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
from xml.sax.saxutils import escape
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-evaluador')
FUERA = mc.carpeta('build-evaluador-fuera')  # fuera de la raiz del servidor, hermana de BASE
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='be', t=600)

AJENA = 'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n'
PEREZOSA = '<PropertyGroup><Antes>a</Antes><Tarde>$(Antes)</Tarde><Antes>b</Antes></PropertyGroup>'


def build(proyecto):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Release'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def lectura_fuera(r):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and '<DCC_UnitSearchPath>' in r


def grupo(ruta, condicion=''):
    cond = ' Condition="%s"' % condicion if condicion else ''
    return '<PropertyGroup%s><DCC_UnitSearchPath>%s</DCC_UnitSearchPath></PropertyGroup>' % (cond, escape(ruta))


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
    m = re.search(r'<ProjectExtensions>.*?</ProjectExtensions>', xml, re.S)
    assert m, 'el .dproj del IDE trae ProjectExtensions'
    extensiones = m.group(0)
    sin_extensiones = xml.replace(extensiones, '', 1)

    def con(payload, extensiones_delante=False):
        base = sin_extensiones if extensiones_delante else xml
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(base.replace('<Import Project=', payload + '<Import Project=', 1))

    con(grupo(FUERA, "'$(Base)'!=''"))
    r = build(proyecto)
    check('X0 control: el search path de fuera en un grupo base: BUILD-050 (sigue)', lectura_fuera(r), r[:300])

    # el ProjectExtensions del IDE, movido delante y con un PropertyGroup plantado dentro
    plantado = extensiones.replace('<ProjectExtensions>',
                                   '<ProjectExtensions><PropertyGroup><Puerta>0</Puerta></PropertyGroup>', 1)
    con('<PropertyGroup><Puerta>1</Puerta></PropertyGroup>' + plantado + grupo(FUERA, "'$(Puerta)'=='1'"), True)
    r = build(proyecto)
    check('X1 la bandera a 0 dentro de ProjectExtensions (msbuild lo ignora): BUILD-050', lectura_fuera(r), r[:300])

    con('<PropertyGroup><Puerta>1</Puerta></PropertyGroup>'
        '<Target Name="Nada"><PropertyGroup><Puerta>0</Puerta></PropertyGroup></Target>' + grupo(FUERA, "'$(Puerta)'=='1'"))
    r = build(proyecto)
    check('X2 la bandera a 0 dentro de un Target que nadie ejecuta: BUILD-050', lectura_fuera(r), r[:300])

    con(PEREZOSA + grupo(FUERA, "'$(Tarde)'=='a'"))
    r = build(proyecto)
    check('X3 un valor se fija expandido al definirlo (Antes dos veces): Tarde vale a y el grupo se aplica: BUILD-050',
          lectura_fuera(r), r[:300])

    con('<PropertyGroup><PreBuildEvent>echo x</PreBuildEvent></PropertyGroup>' + grupo(FUERA, "'$(PreBuildEvent)'==''"))
    r = build(proyecto)
    check('X4 la global del build (/p:PreBuildEvent= vaciado) gana al .dproj: BUILD-050', lectura_fuera(r), r[:300])

    con('<PropertyGroup><Puerta>1.0</Puerta><Esc>%31</Esc></PropertyGroup>' + grupo(FUERA, "'$(Puerta)'=='1' and '$(Esc)'=='1'"))
    r = build(proyecto)
    check('X5 numeros (1.0 es 1) y escapes (%31 es 1) como msbuild: BUILD-050', lectura_fuera(r), r[:300])

    lib = os.path.join(carpeta, 'lib')
    os.makedirs(lib)
    open(os.path.join(lib, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    con('<PropertyGroup><Antes>a</Antes><Tarde>$(Antes)</Tarde></PropertyGroup>' + grupo(lib, "'$(Tarde)'=='a'"))
    r = build(proyecto)
    check('X6 control: Antes una vez, Tarde vale a y el grupo se aplica hacia lib\\ de dentro: compila', compila(r), detalle(r))
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('build evaluador 1220')
