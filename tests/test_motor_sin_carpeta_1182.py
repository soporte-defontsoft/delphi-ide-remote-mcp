# -*- coding: utf-8 -*-
"""Punto 5 de la 1.18.2 (rondas de la 1.18.1; MEDIDO EN CRUDO el 14-oct con
sonda_emoji_lsp.py contra DelphiLSP.exe, sin este servidor): en un proyecto
bajo una carpeta con un caracter mas alla de U+FFFF (un emoji), el MOTOR
contesta la definicion con la uri SIN carpeta - {"uri":"file:///UEmo.pas"},
la linea bien -. Este servidor la tomaba por una ruta de fuera y negaba con
LSP-038 "resolves to a definition OUTSIDE this workspace", que es falso: la
unidad esta al lado. Ahora se dice lo que pasa (LSP-043).

  E1 delphi_definition en ese proyecto: LSP-043, no LSP-038 (ROJO en
     produccion)
  E2 delphi_references del mismo simbolo: LSP-043 (no una lista con la
     declaracion como homonima de si misma)
  E3 control: el mismo proyecto en una carpeta sin emoji: la definicion sale

M3 de los revisores de cierre (MEDIDO EN CRUDO el 14-oct con sonda_emoji_diag.py
contra el DelphiLSP.exe de bin\\ que lanza este servidor): bajo esa misma carpeta
el motor publica una lista de diagnosticos VACIA para un E2003 que esta en el
fichero, y delphi_diagnostics decia "0 errors" - un limpio falso. En una carpeta
llana y en una con enye publica el E2003. Ahora se dice (LSP-045) ANTES de
arrancar un motor para nada, como LSP-035.

  E4 delphi_diagnostics de un .dpr con un E2003 bajo la carpeta con emoji:
     LSP-045, no "0 errors" (ROJO en produccion)
  E5 control: el mismo E2003 en la carpeta sin emoji: errors=1, E2003

Uso:  python tests/test_motor_sin_carpeta_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('motor_sin_carpeta_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
UNIDAD = ('unit UEmo;\r\n\r\ninterface\r\n\r\nfunction Doble(N: Integer): Integer;\r\n\r\n'
          'implementation\r\n\r\nfunction Doble(N: Integer): Integer;\r\nbegin\r\n  Result := N * 2;\r\nend;\r\n\r\nend.\r\n')


def proyecto(srv, carpeta):
    d = os.path.join(JAIL, carpeta, 'P')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d}, t=120)
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UEmo', 'project': os.path.join(d, 'P.dpr'),
                               'content': UNIDAD.replace('\r\n', '\n')}, t=120)
    dpr = os.path.join(d, 'P.dpr')
    srv.call('delphi_edit', {'path': dpr, 'old': "    Writeln('P running');",
                             'new': "    Writeln('P running', Doble(21));"}, t=120)
    linea = open(dpr, encoding='utf-8-sig').read().splitlines()[10]
    return dpr, linea.index('Doble') + 2


def diagnostics_con_error(srv, dpr):
    """Mete un E2003 en el .dpr y pide delphi_diagnostics; un lint lento
    contesta "en curso" y se vuelve a pedir (la misma llamada lo recoge)."""
    srv.call('delphi_edit', {'path': dpr, 'old': "    Writeln('P running', Doble(21));",
                             'new': "    Writeln(NoExisteNada, 'P running', Doble(21));"}, t=120)
    for _ in range(6):
        r = srv.call('delphi_diagnostics', {'path': dpr}, t=240)
        if '"in-progress"' not in r:
            break
    return r


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='motor-sin-carpeta', t=300)
try:
    dpr, col = proyecto(srv, 'Emo\U0001F600')
    r = srv.call('delphi_definition', {'path': dpr, 'line': 10, 'character': col}, t=240)
    check('E1 definition bajo una carpeta con emoji: LSP-043 (el motor pierde la carpeta), no LSP-038',
          'LSP-043' in r and 'LSP-038' not in r, r[:300])
    r = srv.call('delphi_references', {'path': dpr, 'line': 10, 'character': col}, t=240)
    check('E2 references del mismo: LSP-043', 'LSP-043' in r, r[:300])
    r = diagnostics_con_error(srv, dpr)
    check('E4 diagnostics de un E2003 bajo la carpeta con emoji: LSP-045, no "0 errors"',
          'LSP-045' in r and '"errors":0' not in r, r[:300])
    dpr, col = proyecto(srv, 'SinEmo')
    r = srv.call('delphi_definition', {'path': dpr, 'line': 10, 'character': col}, t=240)
    check('E3 control: sin emoji la definicion sale (UEmo.pas, linea 9)',
          not mc.rechazado(r) and 'UEmo.pas' in r and 'LSP-04' not in r, r[:300])
    r = diagnostics_con_error(srv, dpr)
    check('E5 control: el mismo E2003 sin emoji se lintea (errors=1, E2003)',
          '"errors":1' in r and 'E2003' in r and 'LSP-045' not in r, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el motor pierde la carpeta 1182 (punto 5)')
