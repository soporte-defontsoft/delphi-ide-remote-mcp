# -*- coding: utf-8 -*-
"""A15 de la 1.23: que una linea ES la de un ancla lo dice UNA regla, la misma en
delphi_edit, delphi_textedit, las anclas de bloque y las tandas. Eran tres: el
ancla de una linea de Pascal contaba el final exacto y la de texto y los
bloques lo recortaban (E2); el U+FFFD de un ancla se negaba antes de buscar y
solo en delphi_edit (E3); el mismo hecho tenia dos codigos (E4); y una entrada
de tanda sin desempate cuya ancla se repetia en el fichero de antes de la tanda
se aplicaba donde quedase unica (P2).

  A1 delphi_edit: un ancla de una linea sin los blancos de DETRAS de su linea
     casa y escribe, como en textedit y en un bloque (ROJO hasta la 1.23)
  A2 (guarda) la misma linea en textedit y como bloque de delphi_edit: casa
  A3 occurrence cuenta con esa regla: "  foo;  " es la ocurrencia 1 de "foo;"
     (ROJO hasta la 1.23: contaba la siguiente)
  A4 delphi_edit sobre una linea que LLEVA U+FFFD de verdad (un UTF-8): escribe
     (ROJO hasta la 1.23: EDIT-061 antes de buscar)
  A5 un ancla con U+FFFD que no esta: la negativa lo dice, en las dos tools
     (ROJO hasta la 1.23 en textedit)
  A6 un fragment con U+FFFD que su linea lleva: escribe (ROJO hasta la 1.23: EDIT-005)
  A7 textedit: el ancla repetida y el atline que no es ninguna, con los codigos
     de delphi_edit, EDIT-077 y EDIT-062 (ROJO hasta la 1.23: TEXT-009 y TEXT-002)
  A8 una tanda (las dos tools): la entrada 2 sin desempate y su ancla dos veces
     en el fichero de ANTES: se niega, nada escrito (ROJO hasta la 1.23: APPLIED,
     la 2 caia en la otra)
  A9 (guarda) la misma tanda con occurrence en la 2: escribe las dos
  A10 (guarda) una entrada cuya ancla la crea la anterior (no esta antes): escribe

Uso:  python tests/test_ancla_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_ancla_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def fichero(nombre, lineas):
    ruta = os.path.join(JAIL, nombre)
    with open(ruta, 'wb') as f:
        f.write(('\r\n'.join(lineas) + '\r\n').encode('utf-8'))
    return ruta


def lineas(ruta):
    return open(ruta, 'rb').read().decode('utf-8').split('\r\n')


PAS = ['unit U;', 'interface', 'implementation', 'procedure P;', 'begin',
       '  foo := 1;  ', '  bar := 2;', 'end;', 'end.']
DUP = ['unit U;', 'interface', 'implementation', '  x := 1;', '  y := 2;', '  x := 1;', 'end.']

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-ancla', t=300)
try:
    p = fichero('a1.pas', PAS)
    r = srv.call('delphi_edit', {'path': p, 'old': 'foo := 1;', 'new': 'foo := 10;'})
    check('A1 delphi_edit: un ancla sin los blancos de detras de su linea casa y escribe',
          not mc.rechazado(r) and lineas(p)[5] == '  foo := 10;', (r[:300], lineas(p)[5]))

    p = fichero('a2.txt', PAS)
    r = srv.call('delphi_textedit', {'path': p, 'old': 'foo := 1;', 'new': 'foo := 10;'})
    p2 = fichero('a2.pas', PAS)
    r2 = srv.call('delphi_edit', {'path': p2, 'old': 'foo := 1;\nbar := 2;', 'new': 'foo := 10;\nbar := 20;'})
    check('A2 (guarda) la misma linea en textedit y como bloque de delphi_edit: casa',
          not mc.rechazado(r) and lineas(p)[5] == '  foo := 10;' and not mc.rechazado(r2) and
          lineas(p2)[5:7] == ['foo := 10;', 'bar := 20;'], (r[:200], r2[:200], lineas(p2)[5:7]))

    p = fichero('a3.pas', ['unit U;', 'implementation', 'procedure X;', 'begin', '  foo;  ', '  foo;',
                           'end;', 'end.'])
    r = srv.call('delphi_edit', {'path': p, 'edits': json.dumps([{'old': 'foo;', 'new': 'bar;', 'occurrence': 1}])})
    check('A3 occurrence cuenta con esa regla: "  foo;  " es la ocurrencia 1 de "foo;"',
          not mc.rechazado(r) and lineas(p)[4:6] == ['  bar;', '  foo;'], (r[:300], lineas(p)[4:6]))

    p = fichero('a4.pas', ['unit U;', 'interface', '// a�b', 'implementation', 'end.'])
    r = srv.call('delphi_edit', {'path': p, 'old': '// a�b', 'new': '// ab'})
    check('A4 delphi_edit sobre una linea que LLEVA U+FFFD de verdad: escribe',
          not mc.rechazado(r) and lineas(p)[2] == '// ab', (r[:300], lineas(p)[2]))

    p = fichero('a5.pas', ['unit U;', 'interface', '// Gestión', 'implementation', 'end.'])
    r = srv.call('delphi_edit', {'path': p, 'old': '// Gesti�n', 'new': 'x'})
    p2 = fichero('a5.txt', ['uno', 'Gestión', 'dos'])
    r2 = srv.call('delphi_textedit', {'path': p2, 'old': 'Gesti�n', 'new': 'x'})
    check('A5 un ancla con U+FFFD que no esta: la negativa lo dice, en las dos tools, sin escribir',
          all(mc.rechazado(x) and mc.es(x, 'SN_ANCLA_LLEVA_FFFD') for x in (r, r2)) and
          lineas(p)[2] == '// Gestión' and lineas(p2)[1] == 'Gestión', (r[:300], r2[:300]))

    p = fichero('a6.pas', ['unit U;', 'interface', "const S = 'a�b';", 'implementation', 'end.'])
    r = srv.call('delphi_edit', {'path': p, 'edits': json.dumps([{'fragment': 'a�b', 'new': 'ab', 'atline': 3}])})
    check('A6 un fragment con U+FFFD que su linea lleva: escribe',
          not mc.rechazado(r) and lineas(p)[2] == "const S = 'ab';", (r[:300], lineas(p)[2]))

    p = fichero('a7.txt', DUP)
    r = srv.call('delphi_textedit', {'path': p, 'old': 'x := 1;', 'new': 'x := 3;'})
    r2 = srv.call('delphi_textedit', {'path': p, 'old': 'x := 1;', 'new': 'x := 3;', 'atline': 5})
    check('A7 textedit: el ancla repetida y el atline que no es ninguna, con los codigos de delphi_edit',
          mc.es(r, 'SR_EDIT_ANCLA_NO_UNICA_FMT') and mc.es(r2, 'SR_EDIT_LINEA_ESTA_ESE_ANCLA_FMT') and
          lineas(p) == DUP + [''], (r[:200], r2[:200]))

    for tool, ext in (('delphi_edit', 'pas'), ('delphi_textedit', 'txt')):
        p = fichero('a8.' + ext, DUP)
        r = srv.call(tool, {'path': p, 'edits': json.dumps([
            {'old': 'x := 1;', 'new': 'x := 2;', 'occurrence': 2},
            {'old': 'x := 1;', 'new': 'x := 9;'}])})
        check('A8 %s: una entrada sin desempate con su ancla dos veces en el fichero de ANTES: se niega' % tool,
              mc.rechazado(r) and mc.es(r, 'SR_PATCH_ANCLA_REPETIDA_FMT') and 'lines 4, 6' in r and
              lineas(p) == DUP + [''], (r[:300], lineas(p)))
        p = fichero('a9.' + ext, DUP)  # el suyo: no depende de lo que dejo A8
        r = srv.call(tool, {'path': p, 'edits': json.dumps([
            {'old': 'x := 1;', 'new': 'x := 2;', 'occurrence': 2},
            {'old': 'x := 1;', 'new': 'x := 9;', 'occurrence': 1}])})
        check('A9 (guarda) %s: la misma tanda con occurrence en la 2 escribe las dos' % tool,
              not mc.rechazado(r) and lineas(p)[3] == '  x := 9;' and lineas(p)[5] == '  x := 2;', (r[:300], lineas(p)))
        p = fichero('a10.' + ext, DUP)
        r = srv.call(tool, {'path': p, 'edits': json.dumps([
            {'old': 'y := 2;', 'new': 'z := 5;'},
            {'old': 'z := 5;', 'new': 'z := 6;'}])})
        check('A10 (guarda) %s: el ancla de la entrada 2 la crea la 1: escribe' % tool,
              not mc.rechazado(r) and lineas(p)[4] == '  z := 6;', (r[:300], lineas(p)))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('una regla para la linea de un ancla, A15 de la 1.23')
