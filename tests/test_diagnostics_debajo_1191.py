# -*- coding: utf-8 -*-
"""H7 de la 1.19.1 (informe de Hermes 091311, MEDIDO EN CRUDO el 15-oct con
sonda_diag_subcarpeta.py contra el DelphiLSP.exe de bin\\, sin este servidor):
el motor NO publica warnings ni hints de una unidad que cuelga por DEBAJO de la
carpeta de su proyecto (Sub1\\, Domain\\Models\\), este listada en el o no; los
errores si. En la carpeta del proyecto y en una carpeta HERMANA (..\\Shared)
publica todo. Descartados con el motor solo: projectFiles con la forma del IDE,
la subcarpeta en -U, abrir antes el .dpr, el `in` absoluto, la forma de la uri.
delphi_diagnostics decia "0 warnings, 0 hints" - un limpio falso, y sin decir
con que proyecto se habia linteado (el de Hermes: el .dproj de la raiz de su
sandbox, que no lista su unidad). Ahora la respuesta nombra el proyecto
("project") y, debajo de su carpeta, lo dice (LSP-046).

  S1 una unidad del proyecto en Domain\\Models con un W1036 y un H2077:
     LSP-046 y "project" = el .dproj (ROJO en produccion)
  S2 una unidad que no lista nadie, debajo de un .dproj de mas arriba (el
     caso de Hermes): LSP-046 y "project" = ese .dproj (ROJO en produccion)
  C1 control: la misma unidad en la carpeta del proyecto: W1036 y H2077,
     sin LSP-046, y "project" (ROJO en produccion: sin "project")
  C2 control: en una carpeta HERMANA, del proyecto: W1036 y H2077, sin LSP-046

Uso:  python tests/test_diagnostics_debajo_1191.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('diagnostics_debajo_1191')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def unidad(nombre):
    # un W1036 (Sobra sin valor) y un H2077 (Result2 que nadie lee)
    return ('unit %s;\n\ninterface\n\nfunction Prueba: Integer;\n\nimplementation\n\n'
            'function Prueba: Integer;\nvar\n  Result2: Integer;\n  Sobra: Integer;\nbegin\n'
            '  Result2 := 7;\n  Result := Sobra;\nend;\n\nend.\n' % nombre)


def diagnostics(srv, pas):
    """Un lint lento contesta "en curso": la misma llamada lo recoge."""
    for _ in range(6):
        r = srv.call('delphi_diagnostics', {'path': pas}, t=240)
        if '"in-progress"' not in r and 'in progress' not in r:
            break
    return r


def todo(r):
    return 'W1036' in r and 'H2077' in r


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='diagnostics-debajo', t=300)
try:
    d = os.path.join(JAIL, 'P')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d}, t=120)
    dpr = os.path.join(d, 'P.dpr')
    for nombre, sub in (('UAbajo', 'Domain\\Models'), ('UJunto', '')):
        a = {'kind': 'unit', 'name': nombre, 'project': dpr, 'content': unidad(nombre)}
        if sub:
            a['dir'] = sub
        srv.call('delphi_create', a, t=120)
    hermana = os.path.join(JAIL, 'Shared')
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UHermana', 'dir': hermana,
                               'content': unidad('UHermana')}, t=120)
    srv.call('delphi_config', {'command': 'add-unit', 'project': dpr,
                               'path': os.path.join(hermana, 'UHermana.pas')}, t=120)

    r = diagnostics(srv, os.path.join(d, 'Domain', 'Models', 'UAbajo.pas'))
    check('S1 unidad del proyecto en Domain\\Models: LSP-046 y el proyecto nombrado',
          'LSP-046' in r and '"project"' in r and 'P.dproj' in r, r[:400])
    r = diagnostics(srv, os.path.join(d, 'UJunto.pas'))
    check('C1 control: en la carpeta del proyecto, W1036 y H2077, sin LSP-046 y con "project"',
          todo(r) and 'LSP-046' not in r and '"project"' in r and 'P.dproj' in r, r[:400])
    # antes de S2: con Raiz.dproj en la raiz, la hermana subiria hasta el
    r = diagnostics(srv, os.path.join(hermana, 'UHermana.pas'))
    check('C2 control: en una carpeta HERMANA del proyecto, W1036 y H2077, sin LSP-046',
          todo(r) and 'LSP-046' not in r, r[:400])

    # el caso de Hermes: una raiz con su .dproj y, mucho mas abajo, una unidad
    # que no lista nadie; FindDproj sube hasta el de la raiz
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Raiz', 'dir': JAIL}, t=120)
    suelta = os.path.join(JAIL, 'otro', 'scratch')
    srv.call('delphi_create', {'kind': 'unit', 'name': 'USuelta', 'dir': suelta,
                               'content': unidad('USuelta')}, t=120)
    r = diagnostics(srv, os.path.join(suelta, 'USuelta.pas'))
    check('S2 unidad que no lista nadie, debajo de un .dproj de mas arriba: LSP-046 y ese .dproj',
          'LSP-046' in r and 'Raiz.dproj' in r, r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('diagnostics debajo de la carpeta del proyecto 1191 (H7)')
