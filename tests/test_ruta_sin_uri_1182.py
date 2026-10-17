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
    # la linea se busca: el esqueleto de consola cambia (1.20.1, {$R *.res})
    lineas = open(dpr, encoding='utf-8-sig').read().splitlines()
    lin = next(i for i, l in enumerate(lineas) if 'Doble(21)' in l)
    return dpr, lin, lineas[lin].index('Doble') + 2


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ruta-sin-uri', t=300)
try:
    dpr, lin, col = proyecto(srv, 'Suelto' + chr(0xD800) + 'X')
    pos = {'path': dpr, 'line': lin, 'character': col}
    r = srv.call('delphi_definition', pos, t=240)
    check('S1 definition bajo una carpeta con medio caracter: LSP-044', 'LSP-044' in r, ascii(r[:300]))
    otros = [srv.call('delphi_hover', pos, t=240), srv.call('delphi_references', pos, t=240),
             srv.call('delphi_diagnostics', {'path': dpr}, t=240)]
    check('S2 hover, references y diagnostics: LSP-044', all('LSP-044' in x for x in otros),
          [ascii(x[:120]) for x in otros])
    dpr, lin, col = proyecto(srv, 'Normal')
    r = srv.call('delphi_definition', {'path': dpr, 'line': lin, 'character': col}, t=240)
    check('S3 control: en una carpeta normal la definicion sale', 'UA.pas' in r and 'LSP-04' not in r, r[:300])
    # W12 del revisor de cierre: el control de un par VALIDO (un emoji entero):
    # el nombrador lo escribe (no LSP-044); lo que el motor haga con el es otra
    # cosa (LSP-043, el motor pierde la carpeta)
    dpr, lin, col = proyecto(srv, 'Par' + '\U0001F600')
    r = srv.call('delphi_definition', {'path': dpr, 'line': lin, 'character': col}, t=240)
    check('S4 control: un par de sustitutos ENTERO no es medio caracter: nada de LSP-044',
          'LSP-044' not in r, ascii(r[:300]))
    # W5 del revisor de cierre: LSP-044 vivia en un borde (NoEsFuenteDelphi) y el
    # NOMBRADOR seguia escribiendo U+FFFD en silencio: un candidato de references
    # bajo una carpeta con medio caracter se abria en el motor por otra ruta y
    # acababa sin verificar sin decir por que. (Un search path asi no puede
    # existir: el escritor del .dproj lo rechaza, EDIT-078.) Ahora lo dice el
    # nombrador a quien se lo pida, y references lo cuenta por candidato
    sub = os.path.join(JAIL, 'Normal', 'P', 'sub' + chr(0xDC00))
    os.makedirs(sub)
    open(os.path.join(sub, 'UB.pas'), 'w', encoding='utf-8-sig', newline='').write(
        'unit UB;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nuses UA;\r\n\r\nfunction Cuatro: Integer;\r\n'
        'begin\r\n  Result := Doble(2);\r\nend;\r\n\r\nend.\r\n')
    r = srv.call('delphi_references', {'path': dpr, 'line': lin, 'character': col}, t=240)
    # MEDIDO (14-oct, con el motor solo y con el servidor): con esa carpeta en el
    # arbol del proyecto el MOTOR pierde la carpeta tambien de sus vecinas (la
    # definicion de Doble sale file:///UA.pas), asi que la respuesta es LSP-043
    # antes de llegar a los candidatos; el candidato sin uri queda como guarda
    # declarada (unit tests del nombrador). Lo que no puede pasar: U+FFFD en la
    # respuesta, ni una ruta que no es la del fichero
    check('S5 una unidad bajo una carpeta con medio caracter en el arbol: el motor pierde la carpeta '
          '(LSP-043, medido) o el candidato queda sin verificar con su motivo (LSP-044); nunca U+FFFD',
          ('LSP-043' in r or ('LSP-044' in r and 'UB.pas' in r)) and '�' not in r and 'FFFD' not in r,
          ascii(r[:500]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('ruta que el motor no puede nombrar 1182 (punto 4)')
