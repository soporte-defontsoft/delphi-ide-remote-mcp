# -*- coding: utf-8 -*-
r"""Donde escribe el servidor una propiedad del .dproj: como el IDE (1.22.1).

Medido el 22-oct-2026 con el IDE de David (Project Options sobre un proyecto nuevo): una
propiedad NUEVA entra al FINAL de su grupo, en el orden en que se rellena (cinco opciones
quedaron detras de VerInfo_Keys); una que ya esta no se mueve. El servidor la ponia al
PRINCIPIO, y al cambiar una existente la quitaba y la volvia a poner arriba. msbuild evalua
en orden de documento: DCC_UnitSearchPath=$(MiRuta) creada despues de MiRuta quedaba
ENCIMA y la veia vacia (F2613, medido en vivo). EL sitio: Lsp.Dproj.AnadeAlGrupo, para
set-property (PonPropiedadDelBuild), set-output (FijaPropiedadParaTodos) y add-searchpath.

Fixture: un proyecto de consola (delphi_create) y lib\ULibOrden.pas, que el .dpr usa y que
solo se encuentra por el search path.

  O1 set-property MiRuta=lib y despues DCC_UnitSearchPath=$(MiRuta);...: las dos al final
     del grupo base, en ese orden
  O2 ...y msbuild la lee: compila (la 1.22.0: F2613)
  O3 cambiar la que ya estaba (DCC_UnitSearchPath, otro valor): se queda en su sitio, detras
     de MiRuta, y sigue compilando (la 1.22.0 la subia encima de MiRuta: F2613)
  O4 add-searchpath para Win64, cuyo grupo no lo lleva: entra al final de ese grupo
  O5 set-output con DCC_ExeOutput quitado del grupo base: entra al final del grupo base
  O6 el .dproj escrito lo carga MSXML6, el juez del IDE (si pywin32 esta; si no, no se mide)

Uso:  python tests/test_orden_propiedad_1221.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import xml.etree.ElementTree as ET
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('orden-propiedad-1221')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='orden', t=600)
PROY_DIR = os.path.join(BASE, 'p')
DPROJ = os.path.join(PROY_DIR, 'Orden.dproj')
DPR = os.path.join(PROY_DIR, 'Orden.dpr')


def config(comando, **campos):
    args = {'project': DPROJ, 'command': comando}
    args.update(campos)
    return srv.call('delphi_config', args)


def compila():
    r = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Debug'}, 600)
    return (mc.como_json(r) or {}).get('success') is True, (mc.como_json(r) or {}).get('firstError') or r[:300]


def hijos(condicion):
    """Los nombres de las propiedades del PropertyGroup con esa Condition, en orden."""
    r = ET.parse(DPROJ).getroot()
    for g in r:
        if g.tag.split('}')[-1] == 'PropertyGroup' and \
           (g.get('Condition') or '').replace(' ', '') == condicion.replace(' ', ''):
            return [e.tag.split('}')[-1] for e in g]
    return []


BASE_G = "'$(Base)'!=''"
WIN64_G = "'$(Base_Win64)'!=''"

try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Orden', 'dir': PROY_DIR}, 120)
    srv.call('delphi_create', {'kind': 'unit', 'name': 'ULibOrden', 'dir': os.path.join(PROY_DIR, 'lib'),
                               'content': 'unit ULibOrden;\r\n\r\ninterface\r\n\r\nfunction Triple(A: Integer): '
                                          'Integer;\r\n\r\nimplementation\r\n\r\nfunction Triple(A: Integer): '
                                          'Integer;\r\nbegin\r\n  Result := A * 3;\r\nend;\r\n\r\nend.'})
    srv.call('delphi_edit', {'path': DPR, 'old': '  System.SysUtils;', 'new': '  System.SysUtils,\r\n  ULibOrden;'})
    check('fixture: el proyecto, lib\\ULibOrden.pas y el .dpr que la usa',
          os.path.isfile(DPROJ) and os.path.isfile(os.path.join(PROY_DIR, 'lib', 'ULibOrden.pas')) and
          'ULibOrden' in mc.lee(DPR) and 'DCC_UnitSearchPath' not in hijos(BASE_G), r[:200])
    antes = hijos(BASE_G)

    config('set-property', name='MiRuta', value='lib')
    config('set-property', name='DCC_UnitSearchPath', value='$(MiRuta);$(DCC_UnitSearchPath)')
    h = hijos(BASE_G)
    check('O1 set-property MiRuta y despues DCC_UnitSearchPath: las dos al FINAL del grupo base, en ese orden',
          h[:len(antes)] == antes and h[len(antes):] == ['MiRuta', 'DCC_UnitSearchPath'], h)
    ok, det = compila()
    check('O2 ...y msbuild la lee: compila, encuentra ULibOrden por $(MiRuta)', ok, det)

    config('set-property', name='DCC_UnitSearchPath', value='$(MiRuta);.;$(DCC_UnitSearchPath)')
    h = hijos(BASE_G)
    ok, det = compila()
    check('O3 cambiar la que ya estaba: se queda en su sitio, detras de MiRuta, y sigue compilando',
          h[len(antes):] == ['MiRuta', 'DCC_UnitSearchPath'] and ok, (h, det))

    antes64 = hijos(WIN64_G)
    r = config('add-searchpath', path='lib', platform='Win64')
    h = hijos(WIN64_G)
    check('O4 add-searchpath para Win64, cuyo grupo no lo lleva: entra al FINAL de ese grupo',
          antes64 and 'DCC_UnitSearchPath' not in antes64 and h == antes64 + ['DCC_UnitSearchPath'], (antes64, h, r[:200]))

    config('remove-property', name='DCC_ExeOutput')
    antes = hijos(BASE_G)
    r = config('set-output')
    h = hijos(BASE_G)
    check('O5 set-output con DCC_ExeOutput quitado del grupo base: entra al FINAL del grupo base',
          'DCC_ExeOutput' not in antes and h == antes + ['DCC_ExeOutput'], (antes, h, r[:200]))

    try:
        import win32com.client  # noqa
        x = win32com.client.Dispatch('Msxml2.DOMDocument.6.0')
        x.async_ = False
        check('O6 el .dproj escrito lo carga MSXML6 (el juez del IDE)', x.load(DPROJ), str(x.parseError.reason))
    except ImportError:
        print('  NOTA O6 sin pywin32: el juez MSXML no se mide aqui')
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('orden de las propiedades como el IDE 1.22.1')
