# -*- coding: utf-8 -*-
r"""La puerta del build expande cada $(Nombre) de un valor que el build LEE con lo que la propiedad
vale EN ESE PUNTO del documento, como msbuild (Lsp.Dproj.ValoresQueLeeElBuild, el mismo recorrido
que evalua las Condition de los grupos). Medido el 22-oct-2026, tres agujeros con una causa: la
puerta expandia con otro valor que el que dcc lee. (1) Con <A>..</A>, luego <DCC_UnitSearchPath>
$(A)\..\<carpeta de fuera>, y luego <A>x</A> la puerta juzgaba x\..\fuera (el ultimo valor) y dcc
leia ..\..\fuera. (2) A=.. UNA vez bajo Condition="Exists('marker.txt')": la puerta no sabe evaluar
Exists, expandia vacio, y msbuild aplicaba el grupo. (3) LANGDIR=.. redefinido por el proyecto: la
puerta expandia con la tabla de rsvars (EN) y msbuild con lo del proyecto. Y (4) el search path
usando $(A) ANTES de la unica definicion de A: la puerta expandia con el valor definido despues y
msbuild lee vacio ahi (\..\fuera, la raiz de la unidad). Ahora una propiedad vale lo ultimo
puesto ANTES de donde se lee en un grupo de este build (vacio hasta entonces, y lo del proyecto
sobre lo del entorno), un Include lo del final, lo que el documento no sabe (la tabla del IDE y de
msbuild, el entorno, lo que nadie define) lo expande la puerta con su tabla, y lo que NO se sabe
(una propiedad puesta bajo una Condition que no se sabe evaluar, una global del build) se niega
con BUILD-056 nombrando el macro. Y dentro de un valor que el build lee un $(...) solo vale si lo de
dentro es un nombre de propiedad simple (letras, cifras y _); cualquier otra cosa (una funcion, un
item, un nombre con un punto o un guion) hace el valor NO verificable y se niega con BUILD-051, antes
de expandir, exista o no la ruta (censo: 0 de 3.651 .dproj con algo asi):

  X0 control: A=.. una sola vez y el search path $(A)\..\fuera: BUILD-050 (sigue)
  X1 A=.. , el search path, y A=x despues: BUILD-050, A vale .. donde el search path la lee (ROJA
     contra la 1.21.4, que compilaba, y contra la lista blanca de la 1.22.0 en curso: BUILD-056)
  X2 una propiedad definida UNA vez que apunta a lib\ de dentro: compila (el caso de
     $(MainSource) en los Include: cada compilacion de esta bateria lo pasa tambien)
  X3 la autorreferencia lib;$(DCC_UnitSearchPath) con lib\ de dentro: compila
  X4 un macro de la tabla del IDE, $(BDS)\lib: compila
  X5 un nombre que nadie define, $(Nadie)\lib: vale vacio y \lib es una ruta con raiz, de
     fuera: BUILD-050 (sigue; medido tambien en el censo: lo que nadie define no es una ruta)
  X6 una definida DOS veces y las dos hacia lib\ de dentro: compila (vale lib\ donde se lee;
     ROJA contra la lista blanca, que negaba por la forma)
  X7 un nombre del entorno del servidor que el proyecto no define, hacia lib\ de dentro:
     compila
  X8 el mismo nombre del entorno, definido DOS veces por el proyecto hacia lib\: compila (lo que
     el proyecto pone manda sobre el entorno, y vale lib\ donde se lee; ROJA igual)
  X9 A=.. una vez bajo Exists('marker.txt') con el marker plantado: BUILD-056 nombrando $(A)
     (ROJA: compilaba con la unidad de fuera)
  X10 LANGDIR=.. (un nombre de la tabla de rsvars) redefinido por el proyecto: BUILD-050 (ROJA:
     compilaba con la unidad de fuera)
  X11 el search path usa $(A) ANTES de la unica definicion de A: vale vacio ahi y \..\..\fuera
     es de fuera: BUILD-050 (ROJA: pasaba la puerta)
  X12 definida una vez por configuracion (Debug hacia .., Release hacia lib\): en Release compila
     (ROJA contra la lista blanca: la contaba dos veces)
  X13 un $(...) cuyo contenido no es un nombre simple ($(No-Simple)) en un valor que el build lee:
     BUILD-051 no verificable, antes de expandir (ROJA contra el anterior, que lo expandia a vacio y
     compilaba con lib\)

Fixture como test_build_evaluador_1220: un proyecto de consola cuyo .dpr usa Ajena, una unidad
que solo esta en FUERA (o en lib\); los grupos van ANTES del primer <Import>.

Uso:  python tests/test_build_macros_1220.py [ruta-a-DelphiLspMcp.exe]
"""
import os
from xml.sax.saxutils import escape
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-macros')
FUERA = mc.carpeta('build-macros-fuera')  # fuera de la raiz del servidor, hermana de BASE
CARPETA = os.path.join(BASE, 'fixture')
LIB = os.path.join(CARPETA, 'lib')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# el nombre del entorno que X7 y X8 usan: lo pone el servidor de esta bateria, no la maquina
NOMBRE_ENTORNO = 'PUNTO_MACROS_1220_LIB'
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, NOMBRE_ENTORNO: LIB}), nombre='bm', t=600)

AJENA = 'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n'


def build(proyecto):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Release'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def lectura_fuera(r):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and '<DCC_UnitSearchPath>' in r


def macro_negado(r, macro):
    """BUILD-056 sobre <DCC_UnitSearchPath>, nombrando el macro."""
    return (mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_MACRO_FMT') and '<DCC_UnitSearchPath>' in r
            and '$(%s)' % macro in r)


def grupo(ruta, condicion="'$(Base)'!=''"):
    return '<PropertyGroup Condition="%s"><DCC_UnitSearchPath>%s</DCC_UnitSearchPath></PropertyGroup>' % (
        condicion, escape(ruta))


def prop(nombre, valor):
    return '<PropertyGroup><%s>%s</%s></PropertyGroup>' % (nombre, escape(valor), nombre)


try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': CARPETA})
    check('fixture creada (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    proyecto = os.path.join(CARPETA, 'Fixture.dproj')
    open(os.path.join(FUERA, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    os.makedirs(LIB)
    open(os.path.join(LIB, 'Ajena.pas'), 'w', encoding='utf-8').write(AJENA)
    dpr = os.path.join(CARPETA, 'Fixture.dpr')
    with open(dpr, encoding='utf-8-sig') as f:
        fuente = f.read()
    assert 'uses' in fuente, fuente[:200]
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente.replace('uses', 'uses\r\n  Ajena,', 1))
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    assert '<Import Project=' in xml

    def con(payload):
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(xml.replace('<Import Project=', payload + '<Import Project=', 1))

    # desde la carpeta del proyecto (BASE\fixture): ..\..\<nombre de FUERA> es FUERA, y con A=x,
    # x\..\<nombre de FUERA> es una carpeta de DENTRO que no existe
    al_fuera = '$(A)\\..\\' + os.path.basename(FUERA)

    con(prop('A', '..') + grupo(al_fuera))
    r = build(proyecto)
    check('X0 control: A=.. una vez y el search path hacia fuera: BUILD-050 (sigue)', lectura_fuera(r), r[:300])

    con(prop('A', '..') + grupo(al_fuera) + prop('A', 'x'))
    r = build(proyecto)
    check('X1 A=.. , el search path y A=x despues: BUILD-050, A vale .. donde el search path la lee',
          lectura_fuera(r), r[:300])

    con(prop('MiLib', LIB) + grupo('$(MiLib)'))
    r = build(proyecto)
    check('X2 una propiedad definida UNA vez hacia lib\\ de dentro: compila', compila(r), detalle(r))

    con(grupo(LIB + ';$(DCC_UnitSearchPath)'))
    r = build(proyecto)
    check('X3 la autorreferencia lib;$(DCC_UnitSearchPath): compila', compila(r), detalle(r))

    con(grupo(LIB + ';$(BDS)\\lib'))
    r = build(proyecto)
    check('X4 un macro de la tabla del IDE, $(BDS)\\lib: compila', compila(r), detalle(r))

    con(grupo('$(NadieLaDefine1220)\\lib'))
    r = build(proyecto)
    check('X5 un nombre que nadie define vale vacio: \\lib es de fuera, BUILD-050 (sigue)',
          lectura_fuera(r), r[:300])

    con(prop('Dos', LIB) + prop('Dos', LIB) + grupo('$(Dos)'))
    r = build(proyecto)
    check('X6 definida DOS veces, las dos hacia lib\\ de dentro: compila (vale lib\\ donde se lee)',
          compila(r), detalle(r))

    con(grupo('$(%s)' % NOMBRE_ENTORNO))
    r = build(proyecto)
    check('X7 un nombre del entorno del servidor que el proyecto no define: compila', compila(r), detalle(r))

    con(prop(NOMBRE_ENTORNO, LIB) + prop(NOMBRE_ENTORNO, LIB) + grupo('$(%s)' % NOMBRE_ENTORNO))
    r = build(proyecto)
    check('X8 el mismo nombre del entorno definido DOS veces por el proyecto hacia lib\\: compila',
          compila(r), detalle(r))

    # desde la carpeta del proyecto: in\$(X)\..\..\<FUERA> es BASE\<FUERA> (dentro, no existe) con X
    # vacio o con el EN de la tabla, y FUERA con X=..
    al_fuera_por = 'in\\$(%s)\\..\\..\\' + os.path.basename(FUERA)
    marker = os.path.join(CARPETA, 'marker.txt')
    open(marker, 'w').write('x')
    con('<PropertyGroup Condition="Exists(\'marker.txt\')"><A>..</A></PropertyGroup>' + grupo(al_fuera_por % 'A'))
    r = build(proyecto)
    check('X9 A=.. una vez bajo una Condition que la puerta no sabe evaluar (Exists): BUILD-056 nombrando $(A)',
          macro_negado(r, 'A'), r[:300])
    os.remove(marker)

    con(prop('LANGDIR', '..') + grupo(al_fuera_por % 'LANGDIR'))
    r = build(proyecto)
    check('X10 un nombre de la tabla (LANGDIR, de rsvars) que el proyecto redefine: lo del proyecto, BUILD-050',
          lectura_fuera(r), r[:300])

    con(grupo('$(A)\\..\\..\\' + os.path.basename(FUERA)) + prop('A', 'x\\y'))
    r = build(proyecto)
    check('X11 el search path usa $(A) ANTES de su unica definicion: vale vacio ahi, \\..\\..\\fuera es de fuera, BUILD-050',
          lectura_fuera(r), r[:300])

    con('<PropertyGroup><A Condition="\'$(Config)\'==\'Debug\'">..</A>'
        '<A Condition="\'$(Config)\'==\'Release\'">%s</A></PropertyGroup>' % escape(LIB) + grupo('$(A)'))
    r = build(proyecto)
    check('X12 definida una vez por configuracion (Debug hacia .., Release hacia lib\\): en Release compila',
          compila(r), detalle(r))

    con('<PropertyGroup><DCC_UnitSearchPath>$(No-Simple)%s</DCC_UnitSearchPath></PropertyGroup>' % escape(LIB))
    r = build(proyecto)
    check('X13 un $(...) que no es un nombre simple ($(No-Simple)) en DCC_UnitSearchPath: BUILD-051 no verificable '
          '(ROJA contra el anterior, que lo expandia a vacio y compilaba con lib\\)',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_NO_VERIFICABLE_FMT') and '<DCC_UnitSearchPath>' in r, r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('build macros 1220')
