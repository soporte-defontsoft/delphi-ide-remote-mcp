# -*- coding: utf-8 -*-
"""Punto 4 de la 1.18.2 (rondas de la 1.18.1: "sustituto suelto en el NOMBRE de
una carpeta, PathToUri da FFFD"; MEDIDO en produccion el 14-oct con
sonda_suelto_carpeta.py): Windows deja crear una carpeta con medio caracter
(U+D800 suelto) en el nombre, pero la uri de un fichero es UTF-8 y no lo
lleva: el motor contestaba de OTRA ruta - definition y hover null (LSP-029, "la
posicion no cae en un identificador"), references LSP-003, diagnostics "0
errores" -, todo falso. Ahora la regla de las tools del motor
(NoEsFuenteDelphi) lo dice: LSP-044.

  S1 definition en un proyecto bajo esa carpeta: LSP-044 (ROJO en produccion)
  S2 hover, references y diagnostics, lo mismo
  S3 control: el mismo proyecto en una carpeta normal contesta

Uso:  python tests/test_ruta_sin_uri_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ruta_sin_uri_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
UNIDAD = ('unit UA;\n\ninterface\n\nfunction Doble(N: Integer): Integer;\n\nimplementation\n\n'
          'function Doble(N: Integer): Integer;\nbegin\n  Result := N * 2;\nend;\n\nend.\n')


def proyecto(srv, carpeta):
    d = os.path.join(JAIL, carpeta, 'P')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': d}, t=120)
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UA', 'project': os.path.join(d, 'P.dpr'),
                               'content': UNIDAD}, t=120)
    dpr = os.path.join(d, 'P.dpr')
    srv.call('delphi_edit', {'path': dpr, 'old': "    Writeln('P running');",
                             'new': "    Writeln('P running', Doble(21));"}, t=120)
    linea = open(dpr, encoding='utf-8-sig').read().splitlines()[10]
    return dpr, linea.index('Doble') + 2


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ruta-sin-uri', t=300)
try:
    dpr, col = proyecto(srv, 'Suelto' + chr(0xD800) + 'X')
    pos = {'path': dpr, 'line': 10, 'character': col}
    r = srv.call('delphi_definition', pos, t=240)
    check('S1 definition bajo una carpeta con medio caracter: LSP-044', 'LSP-044' in r, ascii(r[:300]))
    otros = [srv.call('delphi_hover', pos, t=240), srv.call('delphi_references', pos, t=240),
             srv.call('delphi_diagnostics', {'path': dpr}, t=240)]
    check('S2 hover, references y diagnostics: LSP-044', all('LSP-044' in x for x in otros),
          [ascii(x[:120]) for x in otros])
    dpr, col = proyecto(srv, 'Normal')
    r = srv.call('delphi_definition', {'path': dpr, 'line': 10, 'character': col}, t=240)
    check('S3 control: en una carpeta normal la definicion sale', 'UA.pas' in r and 'LSP-04' not in r, r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('ruta que el motor no puede nombrar 1182 (punto 4)')
