# -*- coding: utf-8 -*-
"""V160d (1.23.1): the engine resolves a unit via a msbuild-macro search path,
like dcc does.

The build gate expands the reserved msbuild macros (V118) and dcc compiles a
DCC_UnitSearchPath = $(MSBuildProjectDirectory)\\..\\sh; but the engine's path
reader (CleanPathList) expanded only the IDE macros and DROPPED anything still
carrying $(, so the engine never saw that folder: hover/definition/completion
gave LSP-029 for a unit that compiles. V118's one reader
(MacrosReservadasDeMsbuild) now feeds the engine's path reader too; the jail's
read gate (MotorPuedeEnsenar) still trims anything that lands outside.

  D0 control: hover on a System symbol resolves (the engine IS configured)
  D1 the project compiles (dcc finds the unit via the macro'd search path)
  D2 hover on the unit's routine resolves to its .pas (RED against the build
     before: LSP-029 - pass that exe as the argument)

Usage:  python tests/test_motor_searchpath_macro_v160.py [path-to-DelphiLspMcp.exe]
"""
import os, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('motor_searchpath_v160')
JAIL = os.path.join(BASE, 'jail')
SH = os.path.join(JAIL, 'sh')
APPDATA = os.path.join(BASE, 'appdata')
for d in (JAIL, SH, APPDATA):
    os.makedirs(d)
open(os.path.join(SH, 'UCompartida.pas'), 'w', newline='\r\n').write(
    'unit UCompartida;\r\ninterface\r\nfunction FooCompartida(A: Integer): Integer;\r\n'
    'implementation\r\nfunction FooCompartida(A: Integer): Integer;\r\nbegin\r\n  Result := A + 1;\r\nend;\r\nend.\r\n')
S = mc.Stdio(mc.copia_exe(os.path.join(BASE, 's'), src=exe_src),
             mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': APPDATA}), nombre='v160d', t=600)

d = os.path.join(JAIL, 'cons')
assert mc.abre(S.call('delphi_create', {'kind': 'project-console', 'name': 'Consumidor', 'dir': d}),
               'SK_CREATE_CREADO_PROYECTO_FMT')
dproj = os.path.join(d, 'Consumidor.dproj')
dpr = os.path.join(d, 'Consumidor.dpr')
# anade uses UCompartida + una llamada
t = open(dpr, 'rb').read().decode('utf-8-sig')
t = t.replace('  System.SysUtils;', '  System.SysUtils,\r\n  UCompartida;', 1)
t = t.replace("    Writeln('Consumidor running');",
              "    Writeln('Consumidor running');\r\n    Writeln(FooCompartida(41));", 1)
open(dpr, 'wb').write((chr(0xfeff) + t).encode('utf-8'))
# el search path con un macro RESERVADO de msbuild (la puerta lo expande, dcc compila)
r = S.call('delphi_config', {'command': 'set-property', 'project': dproj,
                             'name': 'DCC_UnitSearchPath',
                             'value': '$(MSBuildProjectDirectory)\\..\\sh;$(DCC_UnitSearchPath)'})
assert not mc.fallo(r), r[:200]

# las coordenadas (0-based para las tools LSP) de la llamada y de Writeln
lineas = open(dpr, encoding='utf-8-sig').read().split('\n')
ll = next(i for i, l in enumerate(lineas) if 'FooCompartida(41)' in l)
ch = lineas[ll].index('FooCompartida') + 3
lw = next(i for i, l in enumerate(lineas) if "Writeln('Consumidor running')" in l)
cw = lineas[lw].index('Writeln') + 2

try:
    hw = S.call('delphi_hover', {'path': dpr, 'line': lw, 'character': cw}, 300)
    check('D0 control: el motor esta configurado (hover de un simbolo de System resuelve)',
          'System.pas' in hw or 'Writeln' in hw, hw[:200])
    rb = S.call('delphi_build', {'project': dproj, 'platform': 'Win32', 'config': 'Debug'}, 300)
    check('D1 el proyecto compila (dcc encuentra la unidad por el search path con macro)',
          mc.como_json(rb).get('success') is True, rb[:300])
    hov = S.call('delphi_hover', {'path': dpr, 'line': ll, 'character': ch}, 300)
    check('D2 hover resuelve la unidad por un search path con macro de msbuild (como dcc), no LSP-029',
          'UCompartida' in hov, hov[:200])
finally:
    S.cierra()
    mc.borra(BASE)

mc.fin('V160d motor search-path macro battery')
