# -*- coding: utf-8 -*-
r"""La puerta del build juzga lo que lee LA compilacion pedida (1.21.5). Hasta la
1.21.4 LecturasDelBuildDenegadas juzgaba cada valor de cada PropertyGroup del
.dproj, fuera del build que fuese: un keystore que solo lee un build Android64
Debug (PF_KeyStoreDebug, en el grupo '$(Cfg_1_Android64)'!='' que escribe el IDE)
tumbaba un build Linux64 o Win64 con BUILD-050, mientras el IDE lo compilaba
porque nunca lee ese valor (medido el 21-oct-2026 en un proyecto FMX real; un
agente lo informo el mismo dia). David: "si compilamos de una manera hay que
evaluar esa manera, no las demas". Lo que no se sabe de que build es se sigue
juzgando (una de mas es prudencia, una de menos es una puerta).

Fixture: un proyecto de consola (delphi_create) con los definidores que el IDE
escribe para Android64 y para las configs de Win64 (sin ellos msbuild tampoco
evaluaria esos grupos) y un PropertyGroup anadido al final que nombra un
.keystore de FUERA de las raices (no hace falta que exista: se juzga la ruta);
se compila Win64 Release (Cfg_2) salvo donde se dice.

  G0 control: el proyecto recien creado compila
  G1 el valor de fuera en la base ('$(Base)'!=''): BUILD-050 (sigue)
  G2 en el grupo de Debug de Android64 ('$(Cfg_1_Android64)'!=''): compila
  G3 en el grupo de Release de Win64 ('$(Cfg_2_Win64)'!=''), el build pedido: BUILD-050
  G4 en el grupo de Debug de Win64 ('$(Cfg_1_Win64)'!=''): compila (otra config)
  G5 en el grupo de valores de Win32 ('$(Base_Win32)'!=''): compila (otra plataforma)
  G6 en un grupo con una condicion que no es del IDE ('$(Foo)'=='bar'): BUILD-050
      (no se sabe de que build es: se juzga)
  G7 en la base, pero con Condition en el ELEMENTO ('$(Platform)'=='Win32'): compila
  G8 la misma, con la plataforma pedida ('$(Platform)'=='Win64'): BUILD-050
  G9 en el grupo de Debug sin plataforma ('$(Cfg_1)'!=''): pidiendo Release compila,
      pidiendo Debug BUILD-050
  G10 la bandera PLANTADA: un grupo sin condicion pone <Cfg_1>true</Cfg_1> y el
      grupo '$(Cfg_1)'!='' lleva el keystore; pidiendo Release, msbuild lo aplica
      (la propiedad esta puesta): BUILD-050 (revisor A, 21-oct: la clasificacion
      por el nombre de la clave lo saltaba)
  G11 una configuracion HIJA del IDE: Debug2 (Cfg_3, CfgParent Cfg_1) cuyo
      definidor pone tambien <Cfg_1>true</Cfg_1>; el keystore en '$(Cfg_1)'!='';
      pidiendo Debug2, msbuild lee los valores de Debug: BUILD-050
  G12 la clave de BuildConfiguration RENOMBRADA (Release -> Cfg_9) sin tocar los
      grupos: el grupo '$(Cfg_2)'!='' sigue siendo el de Release para msbuild (su
      definidor lo pone por '$(Config)'=='Release'): BUILD-050
  G13 que msbuild LEE de verdad el grupo de G10 (no solo que la puerta lo juzga):
      una unidad que solo esta en FUERA, en el search path de ese grupo; con la
      puerta de 4db0099 compilaba (dcc la encontro: msbuild evaluo el grupo);
      ahora BUILD-050 citando DCC_UnitSearchPath

G2, G4, G5, G7 y la primera mitad de G9 son ROJAS contra 1.21.4 (pasar su exe
como argumento); G10, G11, G12 y G13 son ROJAS contra 4db0099 (la primera forma
de esta puerta, por el nombre de la clave: compilaban, y G13 compilando - la
unidad de FUERA encontrada por ese search path - es la prueba de que msbuild
lee el grupo).

Uso:  python tests/test_build_grupos_1215.py [ruta-a-DelphiLspMcp.exe]
"""
import os
from xml.sax.saxutils import escape
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-grupos')
# FUERA de la raiz del servidor (DELPHI_MCP_ROOTS = BASE), hermana de BASE
FUERA = mc.carpeta('build-grupos-fuera')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='bg', t=600)
KEYSTORE = os.path.join(FUERA, 'x.keystore')


def fixture(nombre):
    """Un proyecto de consola nuevo (delphi_create) en su carpeta: (carpeta, .dproj, xml)."""
    carpeta = os.path.join(BASE, nombre)
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check(nombre + ': fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    return carpeta, proyecto, xml


def definidor(plataforma, clave):
    """El grupo DEFINIDOR que el IDE escribe para una plataforma y una clave (Base o Cfg_N):
    sin el, msbuild nunca pone Cfg_N_X y los grupos de valores de ese build no se evaluan."""
    hijos = '<%s_%s>true</%s_%s><CfgParent>%s</CfgParent>' % (clave, plataforma, clave, plataforma, clave)
    if clave != 'Base':
        hijos += '<%s>true</%s>' % (clave, clave)
    hijos += '<Base>true</Base>'
    return ('<PropertyGroup Condition="(\'$(Platform)\'==\'%s\' and \'$(%s)\'==\'true\') or \'$(%s_%s)\'!=\'\'">%s</PropertyGroup>'
            % (plataforma, clave, clave, plataforma, hijos))


# los definidores que el IDE escribe en un proyecto con Android64 y con valores por config en
# Win64 (el de delphi_create solo trae Base_Win32, Base_Win64, Cfg_1, Cfg_1_Win32 y Cfg_2)
DEFINIDORES = (definidor('Android64', 'Base') + definidor('Android64', 'Cfg_1') +
               definidor('Win64', 'Cfg_1') + definidor('Win64', 'Cfg_2'))


def escribe(proyecto, xml, payload):
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace('</Project>', DEFINIDORES + payload + '</Project>'))


def grupo(condicion, elemento=None):
    """Un PropertyGroup con esa Condition ('' = sin ella) y, dentro, el keystore de fuera (o el elemento dado)."""
    if elemento is None:
        elemento = '<PF_KeyStoreDebug>%s</PF_KeyStoreDebug>' % escape(KEYSTORE)
    cond = (' Condition="%s"' % condicion) if condicion else ''
    return '<PropertyGroup%s>%s</PropertyGroup>' % (cond, elemento)


def build(proyecto, config='Release'):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': config}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def lectura_fuera(r):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and '<PF_KeyStoreDebug>' in r


try:
    carpeta, proyecto, xml = fixture('grupos')
    r = build(proyecto)
    check('G0 control: el proyecto recien creado compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo("'$(Base)'!=''"))
    r = build(proyecto)
    check('G1 el keystore de fuera en la base: BUILD-050 (sigue)', lectura_fuera(r), r[:300])

    escribe(proyecto, xml, grupo("'$(Cfg_1_Android64)'!=''"))
    r = build(proyecto)
    check('G2 en el grupo de Debug de Android64: un build Win64 Release compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo("'$(Cfg_2_Win64)'!=''"))
    r = build(proyecto)
    check('G3 en el grupo de Release de Win64 (el build pedido): BUILD-050', lectura_fuera(r), r[:300])

    escribe(proyecto, xml, grupo("'$(Cfg_1_Win64)'!=''"))
    r = build(proyecto)
    check('G4 en el grupo de Debug de Win64 (otra config): compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo("'$(Base_Win32)'!=''"))
    r = build(proyecto)
    check('G5 en el grupo de valores de Win32 (otra plataforma): compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo("'$(Foo)'=='bar'"))
    r = build(proyecto)
    check('G6 en un grupo con una condicion que no es del IDE: BUILD-050 (no se sabe, se juzga)',
          lectura_fuera(r), r[:300])

    escribe(proyecto, xml, grupo("'$(Base)'!=''",
            '<PF_KeyStoreDebug Condition="\'$(Platform)\'==\'Win32\'">%s</PF_KeyStoreDebug>' % escape(KEYSTORE)))
    r = build(proyecto)
    check('G7 la Condition en el ELEMENTO, de otra plataforma: compila', compila(r), detalle(r))

    escribe(proyecto, xml, grupo("'$(Base)'!=''",
            '<PF_KeyStoreDebug Condition="\'$(Platform)\'==\'Win64\'">%s</PF_KeyStoreDebug>' % escape(KEYSTORE)))
    r = build(proyecto)
    check('G8 la Condition en el elemento, de la plataforma pedida: BUILD-050', lectura_fuera(r), r[:300])

    escribe(proyecto, xml, grupo("'$(Cfg_1)'!=''"))
    r = build(proyecto, 'Release')
    check('G9 en el grupo de Debug sin plataforma, pidiendo Release: compila', compila(r), detalle(r))
    r = build(proyecto, 'Debug')
    check('G9 ...y pidiendo Debug: BUILD-050', lectura_fuera(r), r[:300])

    escribe(proyecto, xml, '<PropertyGroup><Cfg_1>true</Cfg_1></PropertyGroup>' + grupo("'$(Cfg_1)'!=''"))
    r = build(proyecto, 'Release')
    check('G10 la bandera Cfg_1 plantada sin condicion: el grupo de Debug se aplica en Release: BUILD-050',
          lectura_fuera(r), r[:300])

    hija = ('<ItemGroup><BuildConfiguration Include="Debug2"><Key>Cfg_3</Key><CfgParent>Cfg_1</CfgParent>'
            '</BuildConfiguration></ItemGroup>'
            '<PropertyGroup Condition="\'$(Config)\'==\'Debug2\' or \'$(Cfg_3)\'!=\'\'">'
            '<Cfg_3>true</Cfg_3><CfgParent>Cfg_1</CfgParent><Cfg_1>true</Cfg_1><Base>true</Base></PropertyGroup>')
    escribe(proyecto, xml, hija + grupo("'$(Cfg_1)'!=''"))
    r = build(proyecto, 'Debug2')
    check('G11 una configuracion hija (Debug2 de Debug): los valores de Debug se leen: BUILD-050',
          lectura_fuera(r), r[:300])

    renombrado = xml.replace('<Key>Cfg_2</Key>', '<Key>Cfg_9</Key>')
    assert renombrado != xml
    escribe(proyecto, renombrado, grupo("'$(Cfg_2)'!=''"))
    r = build(proyecto, 'Release')
    check('G12 la clave de Release renombrada en BuildConfiguration: el grupo Cfg_2 sigue siendo el suyo: BUILD-050',
          lectura_fuera(r), r[:300])

    open(os.path.join(FUERA, 'Ajena.pas'), 'w', encoding='utf-8').write(
        'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n')
    dpr = os.path.join(carpeta, 'Fixture.dpr')
    with open(dpr, encoding='utf-8-sig') as f:
        fuente = f.read()
    assert 'uses' in fuente, fuente[:200]
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente.replace('uses', 'uses\r\n  Ajena,', 1))
    # ANTES del primer <Import>: un PropertyGroup detras de los Import no llega a dcc (medido el
    # 21-oct-2026: DCC_UnitSearchPath tras los Import da F2613), y aqui hace falta que llegue
    payload = DEFINIDORES + '<PropertyGroup><Cfg_1>true</Cfg_1></PropertyGroup>' + \
        grupo("'$(Cfg_1)'!=''", '<DCC_UnitSearchPath>%s</DCC_UnitSearchPath>' % escape(FUERA))
    assert '<Import Project=' in xml
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace('<Import Project=', payload + '<Import Project=', 1))
    r = build(proyecto, 'Release')
    check('G13 msbuild LEE el grupo de la bandera plantada (una unidad solo en FUERA por su search path): BUILD-050',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and '<DCC_UnitSearchPath>' in r, r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('build grupos 1215')
