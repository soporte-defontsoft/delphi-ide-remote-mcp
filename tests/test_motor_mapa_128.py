# -*- coding: utf-8 -*-
"""El motor de un proyecto ve el in '...' de su fuente principal como esta AHORA (C32 de la 1.28).

DelphiLSP fija a que fichero va cada unidad del proyecto al CARGARLO y no lo vuelve a mirar: medido con
el motor a pelo el 5-nov (sonda_c32): ni los mismos ajustes otra vez, ni unos que cambian, ni
didChangeWatchedFiles del .dpr, ni el .dpr abierto como documento; solo un motor nuevo. Tras un
remove-unit/add-unit que lleva una unidad a otro fichero, definition, references y el juez de rename
contestaban con el mapa viejo. El servidor rehace el motor de un proyecto cuyo mapa cambio.

  M1 Tres lista UCalc in '..\\UCalc.pas': definition del UCalc del uses de su UUsa = la del padre
  M2 remove-unit + add-unit de la copia de su carpeta: definition = la copia (ROJA contra la 1.27.1: la
     del padre, la vista vieja)
  M3 ...y el log del servidor dice que rehizo el motor por eso, una vez
  M4 un cambio del .dpr que no toca el mapa (un comentario) no rehace el motor: la misma respuesta y
     ninguna linea mas en el log

Uso:  python tests/test_motor_mapa_128.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import time
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('motor_mapa_128')
SRVDIR = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRVDIR, src=exe_src)
LOG = os.path.join(SRVDIR, 'logs', 'actual.log')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='motor-mapa', t=300)
call = srv.call

CALC = ('unit UCalc;\n\ninterface\n\nfunction Doble(X: Integer): Integer;\n\nimplementation\n\n'
        'function Doble(X: Integer): Integer;\nbegin\n  Result := X * %d;\nend;\n\nend.\n')
USA = 'unit UUsa;\n\ninterface\n\nimplementation\n\nuses\n  UCalc;\n\nend.\n'  # UCalc en la linea 7


def donde():
    """A que UCalc lleva el del uses de UUsa: 'tres' (la copia), 'padre' o lo que conteste."""
    j = {}
    for _ in range(4):  # el motor recien nacido contesta null mientras indexa
        j = mc.como_json(call('delphi_definition', {'path': PAS_USA, 'line': 7, 'character': 3}, 300))
        if j.get('path'):
            break
        time.sleep(2)
    p = (j.get('path') or '').lower()
    return 'tres' if p.endswith('\\tres\\ucalc.pas') else ('padre' if p.endswith('\\h\\ucalc.pas') else str(j)[:300])


def rehechos(minimo=0, segundos=8):
    """Las lineas del log que dicen que un motor se rehizo porque cambio el in '...' (se vuelca cada medio
    segundo: se esperan hasta ese tope las que tiene que haber)."""
    t0 = time.time()
    while True:
        try:
            r = [l for l in open(LOG, encoding='utf-8', errors='replace') if 'lsp: ENGINE' in l and 'by in' in l]
        except OSError:
            r = []
        if len(r) >= minimo or time.time() - t0 > segundos:
            return r
        time.sleep(0.5)


try:
    h = os.path.join(JAIL, 'h')
    call('delphi_create', {'kind': 'unit', 'name': 'UCalc', 'dir': h, 'content': CALC % 2})
    TRES = os.path.join(h, 'Tres')
    call('delphi_create', {'kind': 'project-console', 'name': 'Tres', 'dir': TRES})
    DPROJ = os.path.join(TRES, 'Tres.dproj')
    DPR = os.path.join(TRES, 'Tres.dpr')
    call('delphi_create', {'kind': 'unit', 'name': 'UCalc', 'dir': TRES, 'content': CALC % 3})
    call('delphi_create', {'kind': 'unit', 'name': 'UUsa', 'project': DPROJ, 'content': USA})
    PAS_USA = os.path.join(TRES, 'UUsa.pas')
    call('delphi_config', {'command': 'add-unit', 'project': DPROJ, 'path': os.path.join(h, 'UCalc.pas')})

    check('M1 Tres lista la UCalc del padre: definition del uses la da', donde() == 'padre', donde())

    call('delphi_config', {'command': 'remove-unit', 'project': DPROJ, 'path': '..\\UCalc.pas'})
    call('delphi_config', {'command': 'add-unit', 'project': DPROJ, 'path': os.path.join(TRES, 'UCalc.pas')})
    d = donde()
    check('M2 tras remove-unit + add-unit de la copia de su carpeta, definition da la copia (el mapa de AHORA)',
          d == 'tres', (d, open(DPR, encoding='utf-8-sig').read()))
    r = rehechos(1)
    check('M3 el log dice que el motor se rehizo porque cambio el in, una vez', len(r) == 1, r)

    texto = open(DPR, encoding='utf-8-sig').read().splitlines()
    call('delphi_edit', {'path': DPR, 'old': texto[0], 'new': texto[0] + '\n// sin tocar el mapa'})
    d = donde()
    r = rehechos(2, 4)
    check('M4 un cambio del .dpr que no toca el mapa no rehace el motor: la misma respuesta, ninguna linea mas',
          d == 'tres' and len(r) == 1, (d, r))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el motor ve el in de su fuente principal como esta ahora 1.28 (C32)')
