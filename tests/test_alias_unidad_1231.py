# -*- coding: utf-8 -*-
"""1.23.1 (V119) - the engine gets the project's unit aliases. msbuild gives
dcc $(DCC_UnitAlias) in front of the standard ones (CodeGear.Common.Targets
105-113, UnitAliases); the engine's settings carried only a fixed list, so a
unit used by its alias compiled and resolved nothing in the engine. Measured
on 28-oct-2026 against the build of V117 (b1656de): with DCC_UnitAlias
Legacy=System.SysUtils, delphi_build compiled "uses Legacy" and hover of
IntToStr answered LSP-029 null.

  A1 a console with DCC_UnitAlias Legacy=System.SysUtils (set-property, as the
     IDE writes it) and "uses Legacy": hover of IntToStr resolves, and the
     fabricated settings' -A starts with Legacy=System.SysUtils
  A2 control: the same program with "uses System.SysUtils" resolves
  A3 an entry that is not Name=Target with two unit names (here one with a
     space and -U behind it: another option of the engine's line) does not
     reach dccOptions

A1 is RED against the build before (pass its exe as argument); A2 and A3 are
green with both (A3 guards the line: the build before did not read the alias).

Usage:  python tests/test_alias_unidad_1231.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('alias1231')
EXE = mc.copia_exe(BASE)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA}), nombre='alias1231', t=600)

PROGRAMA = '\r\n'.join(['program %s;', '', '{$APPTYPE CONSOLE}', '', 'uses', '  %s;', '', 'begin',
                        '  Writeln(IntToStr(5));', 'end.', ''])
LINEA = PROGRAMA.split('\r\n').index('  Writeln(IntToStr(5));')
COLUMNA = '  Writeln(IntToStr(5));'.index('IntToStr') + 3


def consola(nombre, uses, alias):
    """Una consola con su DCC_UnitAlias (set-property) y su .dpr escrito: (.dproj, .dpr)."""
    d = os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    check('preparacion: la consola %s' % nombre, not mc.fallo(r), r[:200])
    dproj, dpr = os.path.join(d, nombre + '.dproj'), os.path.join(d, nombre + '.dpr')
    if alias:
        r = S.call('delphi_config', {'command': 'set-property', 'project': dproj, 'name': 'DCC_UnitAlias',
                                     'value': alias + ';$(DCC_UnitAlias)'})
        check('preparacion: DCC_UnitAlias de %s' % nombre, not mc.fallo(r), r[:200])
    open(dpr, 'wb').write((chr(0xfeff) + PROGRAMA % (nombre, uses)).encode('utf-8'))
    return dproj, dpr


def hover(dpr):
    r = ''
    for _ in range(3):
        r = S.call('delphi_hover', {'path': dpr, 'line': LINEA, 'character': COLUMNA}, 300)
        if 'IntToStr' in r and not mc.fallo(r):
            break
    return r


def opciones(dpr):
    """El dccOptions de los ajustes que fabrico el servidor para ese .dpr ('' si no hay)."""
    fab = mc.ajustes_fabricados(dpr, APPDATA)
    return json.load(open(fab, encoding='utf-8-sig'))['settings'].get('dccOptions', '') if fab else ''


# ---------------------------------------------------------------- A1
dproj1, dpr1 = consola('Al', 'Legacy', 'Legacy=System.SysUtils')
b = mc.como_json(S.call('delphi_build', {'project': dproj1}, 600)) or {}
check('A1 preparacion: dcc compila uses Legacy con el alias', b.get('success') is True, str(b)[:300])
r = hover(dpr1)
check('A1 hover de IntToStr con uses Legacy (el alias del proyecto): resuelve',
      'IntToStr' in r and not mc.fallo(r) and not mc.es(r, 'SN_LSP_NULL_NOTE'), r[:300])
o = opciones(dpr1)
check('A1 los ajustes fabricados: -A con los del proyecto delante',
      ' -ALegacy=System.SysUtils;Generics.Collections=' in o, o[:300])

# ---------------------------------------------------------------- A2
dproj2, dpr2 = consola('Sin', 'System.SysUtils', '')
r = hover(dpr2)
check('A2 control: con uses System.SysUtils, resuelve', 'IntToStr' in r and not mc.fallo(r), r[:300])

# ---------------------------------------------------------------- A3
dproj3, dpr3 = consola('Mal', 'System.SysUtils', 'Malo=X -UC:/fuera;Bueno=System.SysUtils')
hover(dpr3)
o = opciones(dpr3)
check('A3 un alias que no es Nombre=Destino no llega a la linea del motor (ni su -U)',
      o != '' and '-UC:/fuera' not in o and 'Malo=' not in o, o[:300])

S.cierra()
mc.borra(BASE)
mc.fin('alias-unidad-1231 battery')
