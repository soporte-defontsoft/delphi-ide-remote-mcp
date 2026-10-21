# -*- coding: utf-8 -*-
r"""add-searchpath / remove-searchpath con VARIAS carpetas en una llamada (paths, una
LISTA como la de delphi_git; 1.21.4). Medido el 21-oct-2026: la copia de un proyecto
real de veinte anos pedia 19 llamadas de add-searchpath platform=Win64, una por carpeta
de un componente. Cada carpeta se juzga antes de tocar nada (todo o nada), las que ya
estaban se dicen, UNA escritura del .dproj; con una sola, el contrato de siempre
(CFG-019..022).

  L1  paths=[A,B,C]: ADDED 3 (CFG-128), las tres delante en DCC_UnitSearchPath del
      grupo base, UN elemento
  L2  paths=[B,D]: ADDED 1 y "Already in it: B"
  L3  paths=[E (no existe), F]: CFG-018 + CFG-127 (todo o nada), .dproj byte a byte
  L4  path=G + paths=[H]: las dos, ADDED 2
  L5  paths="no es lista": CFG-126, nada hecho
  L6  remove-searchpath paths=[A,D,Z]: REMOVED 2 (CFG-129) y "Not in it: Z"; A y D fuera
  L7  remove-searchpath paths=[B] (una): CFG-021, el contrato de siempre
  L8  add-searchpath path=A (una): CFG-019, el contrato de siempre
  L9  platform=Win64 paths=[A,B]: en el grupo Win64, y view section=searchpaths las lista
  L10 paths con una carpeta FUERA de las raices: la jaula la niega (GUARD-002), .dproj
      byte a byte

15 de los 19 checks son ROJOS contra 1.21.3 (pasar su exe como argumento): "paths" era un
parametro desconocido (SYS-015); solo pasan la fixture, los dos "byte a byte" y L8 con path.

Uso:  python tests/test_searchpath_lista_1214.py [ruta-a-DelphiLspMcp.exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('searchpath-lista')
FUERA = os.path.join(os.path.dirname(BASE), 'fuera-searchpath-lista')  # hermana de BASE, fuera de la raiz
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='spl', t=300)


def lee(p):
    with open(p, encoding='utf-8-sig') as f:
        return f.read()


def bytes_de(p):
    with open(p, 'rb') as f:
        return f.read()


def paths_del_grupo(xml, condicion):
    """Los DCC_UnitSearchPath del PropertyGroup con esa condicion ('$(Base)' o '$(Base_Win64)')."""
    m = re.search(r"<PropertyGroup Condition=\"'%s'!=''\">(.*?)</PropertyGroup>" % re.escape(condicion), xml, re.S)
    g = m.group(1) if m else ''
    return re.findall(r'<DCC_UnitSearchPath>([^<]*)</DCC_UnitSearchPath>', g)


def base_paths(xml):
    return paths_del_grupo(xml, '$(Base)')


try:
    carpeta = os.path.join(BASE, 'p')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('fixture creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    dproj = os.path.join(carpeta, 'Fixture.dproj')
    for d in 'ABCDFGH':
        os.makedirs(os.path.join(carpeta, 'Lib' + d), exist_ok=True)
    A, B, C, D, E, F, G, H = ['Lib' + x for x in 'ABCDEFGH']  # LibE no existe

    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'paths': [A, B, C]})
    sp = base_paths(lee(dproj))
    check('L1 paths=[A,B,C]: ADDED 3 (CFG-128)',
          not mc.rechazado(r) and mc.es(r, 'SN_CONFIG_PATHS_ADDED_FMT') and 'ADDED 3' in r, r[:300])
    check('L1 ...las tres delante en UN DCC_UnitSearchPath del grupo base',
          sp == ['%s;%s;%s;$(DCC_UnitSearchPath)' % (A, B, C)], sp)

    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'paths': [B, D]})
    sp = base_paths(lee(dproj))
    check('L2 paths=[B,D]: ADDED 1 y "Already in it: B"',
          mc.es(r, 'SN_CONFIG_PATHS_ADDED_FMT') and 'ADDED 1' in r and 'Already in it' in r
          and B in r.split('Already in it')[-1], r[:300])
    check('L2 ...D delante, B sin repetir', sp == ['%s;%s;%s;%s;$(DCC_UnitSearchPath)' % (D, A, B, C)], sp)

    antes = bytes_de(dproj)
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'paths': [E, F]})
    check('L3 paths=[E (no existe), F]: CFG-018 y CFG-127 (todo o nada)',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PATH_MISSING_FMT') and mc.es(r, 'SN_CONFIG_PATHS_NADA_FMT'), r[:300])
    check('L3 ...el .dproj byte a byte', bytes_de(dproj) == antes)

    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'path': G, 'paths': [H]})
    sp = base_paths(lee(dproj))
    check('L4 path=G + paths=[H]: ADDED 2', mc.es(r, 'SN_CONFIG_PATHS_ADDED_FMT') and 'ADDED 2' in r, r[:300])
    check('L4 ...G y H delante', sp == ['%s;%s;%s;%s;%s;%s;$(DCC_UnitSearchPath)' % (G, H, D, A, B, C)], sp)

    antes = bytes_de(dproj)
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'paths': 'no es lista'})
    check('L5 paths="no es lista": CFG-126, nada hecho',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PATHS_NO_ES_LISTA') and bytes_de(dproj) == antes, r[:300])

    r = srv.call('delphi_config', {'project': dproj, 'command': 'remove-searchpath', 'paths': [A, D, 'LibZ']})
    sp = base_paths(lee(dproj))
    check('L6 remove-searchpath paths=[A,D,Z]: REMOVED 2 (CFG-129) y "Not in it: LibZ"',
          not mc.rechazado(r) and mc.es(r, 'SN_CONFIG_PATHS_REMOVED_FMT') and 'REMOVED 2' in r
          and 'Not in it' in r and 'LibZ' in r.split('Not in it')[-1], r[:300])
    check('L6 ...A y D fuera, el resto como estaba', sp == ['%s;%s;%s;%s;$(DCC_UnitSearchPath)' % (G, H, B, C)], sp)

    r = srv.call('delphi_config', {'project': dproj, 'command': 'remove-searchpath', 'paths': [B]})
    check('L7 remove-searchpath paths=[B] (una): CFG-021, el contrato de siempre',
          mc.es(r, 'SN_CONFIG_PATH_REMOVED_FMT') and B in r, r[:300])

    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'path': A})
    check('L8 add-searchpath path=A (una): CFG-019, el contrato de siempre',
          mc.es(r, 'SN_CONFIG_PATH_ADDED_FMT') and A in r, r[:300])
    check('L8 ...delante de lo que habia', base_paths(lee(dproj)) == ['%s;%s;%s;%s;$(DCC_UnitSearchPath)' % (A, G, H, C)],
          base_paths(lee(dproj)))

    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'platform': 'Win64', 'paths': [A, B]})
    sp64 = paths_del_grupo(lee(dproj), '$(Base_Win64)')
    check('L9 platform=Win64 paths=[A,B]: ADDED 2 en el grupo Win64',
          mc.es(r, 'SN_CONFIG_PATHS_ADDED_FMT') and 'ADDED 2' in r and sp64 == ['%s;%s;$(DCC_UnitSearchPath)' % (A, B)],
          (r[:200], sp64))
    r = srv.call('delphi_config', {'project': dproj, 'command': 'view', 'section': 'searchpaths'})
    check('L9 ...view section=searchpaths las lista en Win64', A in r and B in r and 'Win64' in r, r[:400])

    antes = bytes_de(dproj)
    os.makedirs(FUERA, exist_ok=True)
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-searchpath', 'paths': [C, FUERA]})
    check('L10 paths con una carpeta FUERA de las raices: la jaula la niega (GUARD-002)',
          mc.rechazado(r) and 'GUARD-002' in r, r[:300])
    check('L10 ...el .dproj byte a byte', bytes_de(dproj) == antes)
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('searchpath lista 1214')
