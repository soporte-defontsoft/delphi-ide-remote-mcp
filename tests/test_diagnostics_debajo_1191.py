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
sandbox, que no lista su unidad). Desde la 1.19.1 la respuesta nombraba el
proyecto ("project") y lo decia (LSP-046).

V61 de la 1.25, medido con el motor a pelo el 31-oct-2026: lo que decide es que la
carpeta del "project" de los ajustes sea la de la unidad, y ese fichero no tiene
que existir. Asi que ahora publica todo, y LSP-046 se fue.

  S1 una unidad del proyecto en Domain\\Models con un W1036 y un H2077: los dos,
     y "project" = el .dproj de verdad
  S2 una unidad que no lista nadie, debajo de un .dproj de mas arriba (el
     caso de Hermes): los dos, y "project" = ese .dproj
  S3 una unidad de debajo que usa otra que solo encuentra el .dpr (in '...'), en
     otra carpeta: sin errores falsos, y su hint
  S4 un error de verdad en una unidad de debajo: se sigue diciendo
  S5 nada de nuestro en la carpeta de la unidad, ni en la respuesta
  S6 la carpeta se puede borrar despues del lint (el motor no se queda con ella)
  C1 control: la misma unidad en la carpeta del proyecto: W1036 y H2077, y "project"
  C2 control: en una carpeta HERMANA, del proyecto: W1036 y H2077

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
    for nombre, sub in (('UAbajo', 'Domain\\Models'), ('UJunto', ''), ('UOtra', 'Otra\\Parte')):
        a = {'kind': 'unit', 'name': nombre, 'project': dpr, 'content': unidad(nombre)}
        if sub:
            a['dir'] = sub
        srv.call('delphi_create', a, t=120)
    hermana = os.path.join(JAIL, 'Shared')
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UHermana', 'dir': hermana,
                               'content': unidad('UHermana')}, t=120)
    srv.call('delphi_config', {'command': 'add-unit', 'project': dpr,
                               'path': os.path.join(hermana, 'UHermana.pas')}, t=120)

    MODELOS = os.path.join(d, 'Domain', 'Models')
    r = diagnostics(srv, os.path.join(MODELOS, 'UAbajo.pas'))
    check('S1 unidad del proyecto en Domain\\Models: W1036 y H2077, y el proyecto de verdad',
          todo(r) and '"project"' in r and 'P.dproj' in r, r[:400])
    check('S5 nada de nuestro en la respuesta: ni el nombre del proyecto de lint', '__delphi-lint' not in r, r[:400])
    check('S5 ...ni en la carpeta de la unidad, ni la unidad cambia',
          sorted(os.listdir(MODELOS)) == ['UAbajo.pas'] and 'unit UAbajo' in open(os.path.join(MODELOS, 'UAbajo.pas'), encoding='utf-8-sig', newline='').read(40),
          os.listdir(MODELOS))
    # una que solo encuentra el .dpr: escrita a mano, porque delphi_create registra su carpeta en el
    # search path y entonces esto pasaria sin que el servidor hiciera nada (medido con un mutante)
    os.makedirs(os.path.join(d, 'SoloIn'))
    with open(os.path.join(d, 'SoloIn', 'USoloIn.pas'), 'w', newline='') as f:
        f.write('unit USoloIn;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
    with open(dpr, encoding='utf-8-sig', newline='') as f:
        DE_DPR = f.read()
    with open(dpr, 'w', encoding='utf-8', newline='') as f:
        f.write(DE_DPR.replace('UAbajo in', "USoloIn in 'SoloIn\\USoloIn.pas',\r\n  UAbajo in", 1))
    check('S3 fixture: la unidad, en el .dpr', 'USoloIn in' in open(dpr, encoding='utf-8-sig').read() and
          'SoloIn' not in open(os.path.join(d, 'P.dproj'), encoding='utf-8-sig').read())
    with open(os.path.join(MODELOS, 'UAbajo.pas'), newline='') as f:
        DE_ABAJO = f.read()
    with open(os.path.join(MODELOS, 'UAbajo.pas'), 'w', newline='') as f:
        f.write(DE_ABAJO.replace('implementation', 'implementation\r\n\r\nuses\r\n  USoloIn, UJunto;', 1))
    check('S3 fixture: el uses esta', 'USoloIn, UJunto' in open(os.path.join(MODELOS, 'UAbajo.pas'), encoding='utf-8-sig').read())
    r = diagnostics(srv, os.path.join(MODELOS, 'UAbajo.pas'))
    check('S3 usa unidades que solo encuentra el .dpr: sin errores falsos, y sus avisos',
          todo(r) and mc.como_json(r).get('errors') == 0 and 'F2613' not in r, r[:500])
    with open(os.path.join(MODELOS, 'UAbajo.pas'), 'w', newline='') as f:
        f.write(DE_ABAJO.replace('Result := Sobra;', 'Result := Sobra + NoExiste;', 1))
    r = diagnostics(srv, os.path.join(MODELOS, 'UAbajo.pas'))
    check('S4 un error de verdad en una unidad de debajo: se dice', 'E2003' in r and mc.como_json(r).get('errors', 0) >= 1, r[:500])
    # el motor de esa carpeta no se queda con ella
    t = srv.call('delphi_delete', {'path': MODELOS}, t=120)
    check('S6 la carpeta se puede borrar despues del lint', not mc.fallo(t) and not os.path.exists(MODELOS), t[:300])
    r = diagnostics(srv, os.path.join(d, 'UJunto.pas'))
    check('C1 control: en la carpeta del proyecto, W1036 y H2077, y con "project"',
          todo(r) and '"project"' in r and 'P.dproj' in r, r[:400])
    # antes de S2: con Raiz.dproj en la raiz, la hermana subiria hasta el
    r = diagnostics(srv, os.path.join(hermana, 'UHermana.pas'))
    check('C2 control: en una carpeta HERMANA del proyecto, W1036 y H2077', todo(r), r[:400])

    # el caso de Hermes: una raiz con su .dproj y, mucho mas abajo, una unidad
    # que no lista nadie; FindDproj sube hasta el de la raiz
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Raiz', 'dir': JAIL}, t=120)
    suelta = os.path.join(JAIL, 'otro', 'scratch')
    srv.call('delphi_create', {'kind': 'unit', 'name': 'USuelta', 'dir': suelta,
                               'content': unidad('USuelta')}, t=120)
    r = diagnostics(srv, os.path.join(suelta, 'USuelta.pas'))
    check('S2 unidad que no lista nadie, debajo de un .dproj de mas arriba: W1036 y H2077, y ese .dproj',
          todo(r) and 'Raiz.dproj' in r, r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('diagnostics debajo de la carpeta del proyecto 1191 (H7)')
