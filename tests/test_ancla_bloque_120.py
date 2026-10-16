# -*- coding: utf-8 -*-
"""EDIT-001 de la 1.20: un edit SUELTO con un ancla de VARIAS lineas se negaba
("el ancla de un edit suelto es UNA linea... mandalo en edits"), cuando el motor
ya sabia aplicar un bloque en una entrada de edits. Medido en el historial de
Hermes el 16-oct: 14 veces (10 con el 27B, 4 con Flash Next; 12 salieron en la
llamada siguiente), y Claude dos veces el mismo dia: una llamada perdida cada
vez. Ahora la suelta con un bloque es la tanda de una entrada
(Lsp.Patch.TandaDeUnBloque), en las dos gemelas.

  B1 delphi_edit, old de 3 lineas + new: aplicado, bytes CP1252 intactos
     (ROJO en produccion: EDIT-001)
  B2 delphi_textedit, lo mismo en un .md (ROJO: EDIT-001)
  B3 delete:true con un bloque: el bloque se quita
  B4 un bloque que aparece dos veces: negado sin escribir; con atline (la linea
     donde empieza) se cambia ESE
  B5 toline con un bloque: EDIT-020 (o el bloque o el rango), nada escrito
  B6 un bloque que no esta: negado con la linea que falta, nada escrito
  B7 el control: el edit de UNA linea sigue su camino de siempre (EDIT-087)

Uso:  python tests/test_ancla_bloque_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ancla_bloque_120')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

CRLF = '\r\n'
PAS_SRC = CRLF.join(['unit UBloque;', '', 'interface', '', 'implementation', '',
                     'procedure Uno;', 'begin', "  Writeln('gestoría');", '  X := 1;', 'end;', '',
                     'procedure Dos;', 'begin', '  X := 1;', 'end;', '',
                     'procedure Tres;', 'begin', '  X := 1;', 'end;', '', 'end.', ''])


def pas(nombre):
    p = os.path.join(JAIL, nombre + '.pas')
    open(p, 'wb').write(PAS_SRC.replace('UBloque', nombre).encode('cp1252'))
    return p


def texto(p):
    return open(p, 'rb').read().decode('cp1252')


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ancla-bloque', t=180)
call = srv.call
try:
    p = pas('UB1')
    r = call('delphi_edit', {'path': p, 'old': "begin\n  Writeln('gestoría');\n  X := 1;",
                             'new': "begin\n  Writeln('gestoría moderna');\n  X := 2;"})
    b = open(p, 'rb').read()
    check('B1 delphi_edit con un ancla de 3 lineas: aplicado, CP1252 intacto',
          not mc.rechazado(r) and b"Writeln('gestor\xeda moderna');\r\n  X := 2;" in b
          and b.count(b'X := 1;') == 2, r[:400])

    md = os.path.join(JAIL, 'notas.md')
    open(md, 'wb').write(b'uno\r\ndos\r\ntres\r\ncuatro\r\n')
    r = call('delphi_textedit', {'path': md, 'old': 'dos\ntres', 'new': 'DOS'})
    check('B2 delphi_textedit con un ancla de 2 lineas: aplicado, CRLF intacto',
          not mc.rechazado(r) and open(md, 'rb').read() == b'uno\r\nDOS\r\ncuatro\r\n', r[:400])

    p = pas('UB3')
    r = call('delphi_edit', {'path': p, 'old': "procedure Dos;\nbegin\n  X := 1;\nend;", 'delete': True})
    check('B3 delete:true con un bloque: el bloque se quita',
          not mc.rechazado(r) and 'procedure Dos;' not in texto(p) and 'procedure Tres;' in texto(p), r[:400])

    p = pas('UB4')
    antes = open(p, 'rb').read()
    r = call('delphi_edit', {'path': p, 'old': "begin\n  X := 1;\nend;", 'new': "begin\n  X := 9;\nend;"})
    check('B4 un bloque repetido: negado, nada escrito, y dice como desempatar',
          mc.rechazado(r) and open(p, 'rb').read() == antes and ('atline' in r or 'occurrence' in r), r[:400])
    n = texto(p).split(CRLF).index('procedure Tres;') + 2   # su begin, 1-based
    r = call('delphi_edit', {'path': p, 'old': "begin\n  X := 1;\nend;", 'new': "begin\n  X := 9;\nend;",
                             'atline': n})
    t = texto(p)
    check('B4b ...con atline (la linea donde empieza) cambia ESE y solo ese',
          not mc.rechazado(r) and t.count('X := 9;') == 1 and t.index('X := 9;') > t.index('procedure Tres;'), r[:400])

    p = pas('UB5')
    antes = open(p, 'rb').read()
    r = call('delphi_edit', {'path': p, 'old': "procedure Dos;\nbegin", 'new': 'x', 'toline': 16})
    check('B5 toline con un bloque: EDIT-020, nada escrito',
          mc.rechazado(r) and mc.es(r, 'SR_RANGE_WITH_BLOCK') and open(p, 'rb').read() == antes, r[:400])

    p = pas('UB6')
    antes = open(p, 'rb').read()
    r = call('delphi_edit', {'path': p, 'old': "procedure Dos;\nbegin\n  Y := 7;", 'new': 'x'})
    check('B6 un bloque que no esta: negado con la linea que falta, nada escrito',
          mc.rechazado(r) and 'Y := 7;' in r and open(p, 'rb').read() == antes, r[:400])

    p = pas('UB7')
    r = call('delphi_edit', {'path': p, 'old': '  Writeln(\'gestoría\');', 'new': "  Writeln('otra');"})
    check('B7 el control: un edit de UNA linea, su camino de siempre (EDIT-087)',
          mc.abre(r, 'SK_EDIT_ESCRITO_EN_FMT') and b"Writeln('otra');" in open(p, 'rb').read(), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un edit suelto con un ancla de varias lineas es un bloque 120 (EDIT-001)')
