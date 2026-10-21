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
      DCCReference): el build la niega (BUILD-050)
  R1  remove-unit con esa ruta (existe, fuera): QUITADA (CFG-125), fuera del
      .dpr y del .dproj, el fichero de fuera intacto y su contenido sin citar
  R2  ...y el build compila
  R3  remove-unit con una ruta de fuera que NO existe: quitada por su nombre
  R4  un search path de fuera: BUILD-050; remove-searchpath lo quita y el
      build compila
  R5  control: add-unit con una ruta de fuera sigue negado (el suelo juzga lo
      que SI se lee)

R1, R3 y R4 (el remove) son ROJAS contra 1.21.2 (pasar su exe como argumento).

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
    check('R0 el proyecto lista una unidad de FUERA: el build la niega (BUILD-050)',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and 'UFuera' in r, r[:300])
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
    check('R4 remove-searchpath con esa ruta: QUITADO, no GUARD-002',
          not mc.rechazado(r) and FUERA.lower() not in lee(dproj).lower(), r[:300])
    r = build(dproj)
    check('R4 ...y el build compila', compila(r), detalle(r))

    # --- R5: control, add-unit de fuera sigue negado ---
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-unit', 'path': victima})
    check('R5 control: add-unit con una ruta de fuera sigue negado (lo que SI se lee)',
          mc.rechazado(r) and 'UFuera' not in lee(dpr), r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('remove fuera 1213')
