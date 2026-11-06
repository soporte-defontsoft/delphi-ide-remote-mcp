# -*- coding: utf-8 -*-
r"""remove-unit / remove-searchpath quitan una entrada que apunta FUERA (1.21.3).
Hasta la 1.21.2 la ruta de un remove-* de delphi_config la juzgaba la jaula
como si la tool fuera a leerla (el suelo generico de [RutaDelServidor] y la
propia tool): una <DCCReference> o un search path que apuntan fuera de lo
legible se negaban con GUARD-002, que es justo lo que BUILD-050 pide quitar
para poder compilar (medido el 21-oct-2026 con un proyecto real copiado al
NAS: 29 referencias absolutas a la carpeta de componentes de OTRA maquina).
Desde la 1.21.3 esa ruta es lo que el proyecto DICE ([NombreSiComando]): ni
se lee ni se escribe, el nucleo no la abre si esta fuera, y la entrada se va
del .dpr y del .dproj; add-unit sigue pidiendo un .pas legible.

  R0  fixture: el proyecto lista una unidad de FUERA (uses in '...' +
      DCCReference): el build la niega por el in de su .dpr, que se juzga
      antes que el .dproj (BUILD-061; V14 de la 1.23 - era BUILD-050, la
      DCCReference: el in no lo juzgaba nadie)
  R1  remove-unit con esa ruta (existe, fuera): QUITADA (CFG-125), fuera del
      .dpr y del .dproj, el fichero de fuera intacto y su contenido sin citar
  R2  ...y el build compila
  R3  remove-unit con una ruta de fuera que NO existe: quitada por su nombre
  R4  un search path de fuera: BUILD-050; remove-searchpath lo quita y el
      build compila
  R5  control: add-unit con una ruta de fuera sigue negado (el suelo juzga lo
      que SI se lee)
  R6  un DeployFile de fuera (el .dproj y el .deployproj, como deja un
      proyecto copiado de otra maquina): BUILD-050 dice remove-deployfile, y
      remove-deployfile lo quita de los dos sin leer el fichero; el build
      compila (informe de fable, 6-nov-2026: GUARD-002, y el .dproj solo lo
      escribe delphi_config)

R1, R3 y R4 (el remove) son ROJAS contra 1.21.2 (pasar su exe como argumento);
R6, contra 1.28.0.

Uso:  python tests/test_remove_fuera_1213.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.larga(mc.carpeta('remove-fuera'))
FUERA = mc.larga(mc.carpeta('remove-fuera-victima'))  # hermana de BASE: fuera de la jaula
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='rf', t=600)
SECRETO = 'SECRETO_REMOVE_FUERA'
UNIDAD = ('unit %s;\r\n\r\ninterface\r\n\r\nprocedure ' + SECRETO + ';\r\n\r\nimplementation\r\n\r\n'
          'procedure ' + SECRETO + ';\r\nbegin\r\nend;\r\n\r\nend.\r\n')


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def lee(path):
    with open(path, encoding='utf-8-sig') as f:
        return f.read()


def escribe(path, texto):
    with open(path, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto)


def fixture(nombre):
    carpeta = os.path.join(BASE, nombre)
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check(nombre + ': fixture creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    return carpeta, os.path.join(carpeta, 'Fixture.dpr'), os.path.join(carpeta, 'Fixture.dproj')


def lista_unidad(dpr, dproj, nombre, ruta):
    """El proyecto lista la unidad por esa ruta, como lo escribe el IDE: uses in '...' + DCCReference."""
    src = lee(dpr)
    src2 = re.sub(r'(\buses\s*\r?\n)', lambda m: m.group(1) + "  %s in '%s',\r\n" % (nombre, ruta), src, count=1)
    check('fixture: el .dpr tenia un uses donde listar ' + nombre, src2 != src, src[:200])
    escribe(dpr, src2)
    xml = lee(dproj)
    escribe(dproj, xml.replace('<ItemGroup>', '<ItemGroup>\r\n        <DCCReference Include="%s"/>' % ruta, 1))


def build(dproj):
    return srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    j = mc.como_json(r)
    return str(j.get('errors') or j.get('error') or r[:300])[:400]


try:
    # --- R0/R1/R2: una unidad de fuera listada por el proyecto ---
    victima = os.path.join(FUERA, 'UFuera.pas')
    escribe(victima, UNIDAD % 'UFuera')
    antes = sha(victima)
    carpeta, dpr, dproj = fixture('r1')
    lista_unidad(dpr, dproj, 'UFuera', victima)
    r = build(dproj)
    check('R0 el proyecto lista una unidad de FUERA: el build la niega por el in del .dpr (BUILD-061)',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_IN_FUERA_FMT') and 'UFuera' in r, r[:300])
    r = srv.call('delphi_config', {'project': dproj, 'command': 'remove-unit', 'path': victima})
    check('R1 remove-unit con la ruta de fuera: QUITADA (CFG-125), no GUARD-002',
          not mc.rechazado(r) and mc.es(r, 'SN_UNIT_REMOVED_FUERA_FMT'), r[:300])
    check('R1 ...fuera del .dpr y del .dproj', 'UFuera' not in lee(dpr) and 'UFuera' not in lee(dproj),
          lee(dpr)[:300])
    check('R1 ...el fichero de fuera intacto y su contenido sin citar',
          sha(victima) == antes and SECRETO not in r, r[:300])
    r = build(dproj)
    check('R2 ...y el build compila', compila(r), detalle(r))

    # --- R3: una ruta de fuera que no existe ---
    carpeta, dpr, dproj = fixture('r3')
    fantasma = os.path.join(FUERA, 'NoEsta', 'UOtra.pas')
    lista_unidad(dpr, dproj, 'UOtra', fantasma)
    r = srv.call('delphi_config', {'project': dproj, 'command': 'remove-unit', 'path': fantasma})
    check('R3 remove-unit con una ruta de fuera que no existe: quitada por su nombre (CFG-125)',
          not mc.rechazado(r) and mc.es(r, 'SN_UNIT_REMOVED_FUERA_FMT') and 'UOtra' not in lee(dpr) and
          'UOtra' not in lee(dproj), r[:300])

    # --- R4: un search path de fuera ---
    carpeta, dpr, dproj = fixture('r4')
    xml = lee(dproj)
    grupo = "<PropertyGroup Condition=\"'$(Base)'!=''\">"
    check('R4 fixture: el .dproj tiene el grupo base', grupo in xml, xml[:400])
    escribe(dproj, xml.replace(grupo, grupo + '\r\n        <DCC_UnitSearchPath>' + FUERA +
                               ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>', 1))
    r = build(dproj)
    check('R4 un search path de FUERA: BUILD-050', mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT'), r[:300])
    r = srv.call('delphi_config', {'project': dproj, 'command': 'remove-searchpath', 'path': FUERA})
    # (revisor de baterias de la 1.27) `not mc.rechazado` dejaba pasar un INTERNAL: QUITADO es su CFG de exito
    check('R4 remove-searchpath con esa ruta: QUITADO, no GUARD-002',
          mc.abre(r, 'SN_CONFIG_PATH_REMOVED_FMT') and FUERA.lower() not in lee(dproj).lower(), r[:300])
    r = build(dproj)
    check('R4 ...y el build compila', compila(r), detalle(r))

    # --- R5: control, add-unit de fuera sigue negado ---
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-unit', 'path': victima})
    # (revisor de baterias de la 1.27) negado POR LA JAULA (GUARD-002): `mc.rechazado` lo cumplia cualquier
    # negativa de add-unit (un parametro, el proyecto)
    check('R5 control: add-unit con una ruta de fuera sigue negado (lo que SI se lee)',
          mc.abre(r, 'SR_JAIL_FMT') and 'UFuera' not in lee(dpr), r[:300])

    # --- R6: un DeployFile de fuera ---
    carpeta, dpr, dproj = fixture('r6')
    escribe(os.path.join(carpeta, 'dentro.txt'), 'se despliega\r\n')
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-deployfile', 'platform': 'Win64',
                                   'path': 'dentro.txt'})
    check('R6 fixture: add-deployfile de un fichero de dentro', mc.abre(r, 'SN_CONFIG_DEPLOY_ADDED_FMT'), r[:300])
    libfuera = os.path.join(FUERA, 'libfuera.so')
    escribe(libfuera, SECRETO + '\r\n')
    antes = sha(libfuera)
    manifiesto = os.path.splitext(dproj)[0] + '.deployproj'
    xml, man = lee(dproj), lee(manifiesto)
    check('R6 fixture: la entrada esta en el .dproj y en el .deployproj',
          'LocalName="dentro.txt"' in xml and 'Include="dentro.txt"' in man, man[:400])
    # como queda un proyecto copiado de otra maquina: la entrada apunta a SU disco
    escribe(dproj, xml.replace('LocalName="dentro.txt"', 'LocalName="%s"' % libfuera))
    escribe(manifiesto, man.replace('Include="dentro.txt"', 'Include="%s"' % libfuera))
    r = build(dproj)
    check('R6 el build lo niega (BUILD-050) y dice como quitarlo: remove-deployfile',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and 'remove-deployfile' in r, r[:400])
    r = srv.call('delphi_config', {'project': dproj, 'command': 'remove-deployfile', 'platform': 'Win64',
                                   'path': libfuera})
    check('R6 remove-deployfile con esa ruta: QUITADO (no GUARD-002), del .dproj y del .deployproj',
          mc.es(r, 'SN_CONFIG_DEPLOY_REMOVED_FMT') and 'libfuera' not in lee(dproj)
          and 'libfuera' not in lee(manifiesto), r[:400])
    check('R6 ...el fichero de fuera intacto y su contenido sin citar',
          sha(libfuera) == antes and SECRETO not in r, r[:300])
    r = build(dproj)
    check('R6 ...y el build compila', compila(r), detalle(r))
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('remove fuera 1213')
