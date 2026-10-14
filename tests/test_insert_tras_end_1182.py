# -*- coding: utf-8 -*-
"""B1 rev8 del punto 7 de la 1.18.2: insert rutina-global en una unidad con
PROSA detras de su 'end.' final - que dcc no lee: el fichero acaba en el
primer end. - se negaba con EDIT-049 si la prosa decia 'end.' otra vez: la
frontera exigia UN solo 'end.' en todo el texto. Dos 'end.' en ramas de un
IFDEF siguen siendo dos finales posibles y se niega (no se sabe cual compila).

  I1 una unidad con prosa y 'end.' detras del final: la rutina entra (ROJO en
     produccion: EDIT-049)
  I2 ...delante del end. final, y la prosa sigue igual
  I3 control: dos 'end.' en ramas de un IFDEF: EDIT-049 y nada escrito

Y una frontera DENTRO de un condicional (W1 del revisor de cierre, medido): un
initialization dentro de {$IFDEF DEBUG}..{$ENDIF} recibia la rutina DENTRO del
bloque, y la respuesta decia que estaba en su sitio:
  I4 rutina-global: delante del {$IFDEF DEBUG}, fuera del bloque (ROJO en
     produccion: entre el IFDEF y el initialization)
  I5 metodo: su implementacion, tambien delante del {$IFDEF DEBUG}

Uso:  python tests/test_insert_tras_end_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('insert_tras_end_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

PROSA = ('Notas: esta unidad se acaba en el end. de arriba; todo esto no lo lee '
         'el compilador. Ni este end. tampoco.')
U1 = os.path.join(JAIL, 'UProsa.pas')
open(U1, 'w', newline='').write(
    'unit UProsa;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n' + PROSA + '\r\n')
U2 = os.path.join(JAIL, 'UIfdef.pas')
T2 = ('unit UIfdef;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n{$IFDEF UNO}\r\nend.\r\n'
      '{$ELSE}\r\nend.\r\n{$ENDIF}\r\n')
open(U2, 'w', newline='').write(T2)
CODE = 'procedure Nueva;\nbegin\nend;'
T3 = ('unit UDebug;\r\n\r\ninterface\r\n\r\ntype\r\n  TCosa = class\r\n  end;\r\n\r\nimplementation\r\n\r\n'
      'var\r\n  X: Integer;\r\n\r\n{$IFDEF DEBUG}\r\ninitialization\r\n  X := 1;\r\n{$ENDIF}\r\nend.\r\n')
U3 = os.path.join(JAIL, 'UDebug.pas')
open(U3, 'w', newline='').write(T3)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='insert-tras-end', t=120)
try:
    r = srv.call('delphi_edit', {'path': U1, 'insert': 'rutina-global', 'code': CODE})
    check('I1 prosa con "end." detras del end. final: la rutina entra (no EDIT-049)',
          not mc.rechazado(r) and 'procedure Nueva;' in open(U1, encoding='utf-8').read(), r[:300])
    t = open(U1, encoding='utf-8', newline='').read()
    check('I2 ...delante del end. final, y la prosa sigue igual',
          0 <= t.find('procedure Nueva;') < t.find('end.\r\n' + PROSA) and t.endswith(PROSA + '\r\n'), t)
    r = srv.call('delphi_edit', {'path': U2, 'insert': 'rutina-global', 'code': CODE})
    check('I3 control: dos end. en ramas de un IFDEF: EDIT-049 y nada escrito',
          mc.rechazado(r) and 'EDIT-049' in r and open(U2, newline='').read() == T2, r[:300])
    r = srv.call('delphi_edit', {'path': U3, 'insert': 'rutina-global', 'code': CODE})
    t = open(U3, encoding='utf-8', newline='').read()
    check('I4 initialization dentro de {$IFDEF DEBUG}: la rutina va DELANTE del IFDEF, fuera del bloque',
          not mc.rechazado(r) and 0 <= t.find('procedure Nueva;') < t.find('{$IFDEF DEBUG}'), (r[:300], t))
    r = srv.call('delphi_edit', {'path': U3, 'insert': 'metodo', 'inclass': 'TCosa',
                                 'code': 'procedure Hace;\nbegin\nend;'})
    t = open(U3, encoding='utf-8', newline='').read()
    check('I5 ...y la implementacion de un metodo, tambien delante del IFDEF',
          not mc.rechazado(r) and 0 <= t.find('procedure TCosa.Hace;') < t.find('{$IFDEF DEBUG}'), (r[:300], t))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('insert tras el end. final 1182 (B1 rev8)')
