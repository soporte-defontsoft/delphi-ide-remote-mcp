# -*- coding: utf-8 -*-
"""insert=rutina-global visible=true encuentra el implementation por LA regla de la seccion (P10 del revisor del
paisaje de la 1.27).

La declaracion de una rutina visible va delante del implementation; Lsp.Patch lo buscaba como una linea que
solo dice eso, y FinDeSeccion (Lsp.ProjectUnits), la regla de adduses y del renombrado, lo toma la primera vez
que la palabra sale entera en el codigo, este donde este en su linea.

  V1 "implementation uses System.SysUtils;" en una linea: la declaracion en el interface y el cuerpo
     (ROJA contra a92f053: no la encontraba, y se deshacia el cuerpo)
  V2 "  TX = record A: Integer; end; implementation": lo de delante sigue en el interface, la declaracion
     detras y el implementation despues (ROJA)
  V3 control: "implementation" sola, como siempre
  y en los tres: el cuerpo detras del implementation, y el fichero sigue en CRLF (la declaracion se
  compone con #10: un LF suelto saldria aqui; revisor de baterias de la 1.27)

Uso:  python tests/test_seccion_visible_127.py [exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('seccion_visible_127')
EXE = mc.copia_exe(BASE, src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='seccion-visible-127', t=300)
try:
    CASOS = (('V1', 'type\r\n  TX = record A: Integer; end;\r\n\r\nimplementation uses System.SysUtils;\r\n',
              'implementation uses System.SysUtils;'),
             ('V2', 'type\r\n  TX = record A: Integer; end; implementation\r\n', 'implementation'),
             ('V3', 'type\r\n  TX = record A: Integer; end;\r\n\r\nimplementation\r\n', 'implementation'))
    for etiqueta, cuerpo, seccion in CASOS:
        pas = os.path.join(JAIL, 'U%s.pas' % etiqueta)
        open(pas, 'w', newline='').write('unit U%s;\r\n\r\ninterface\r\n\r\n%s\r\nend.\r\n' % (etiqueta, cuerpo))
        r = srv.call('delphi_edit', {'path': pas, 'insert': 'rutina-global', 'visible': True,
                                     'code': 'procedure Nueva;\nbegin\nend;'})
        x = open(pas, encoding='utf-8-sig', newline='').read()
        decl = x.find('procedure Nueva;')
        imp = x.find(seccion)
        cuerpo = x.rfind('procedure Nueva;')
        check('%s insert visible con "%s": la declaracion en el interface y el cuerpo detras' % (etiqueta, seccion),
              not mc.fallo(r) and x.count('procedure Nueva;') == 2 and
              0 <= x.find('TX = record A: Integer; end;') < decl < imp < cuerpo, (r[:300], x))
        check('%s el fichero sigue en CRLF, sin saltos sueltos' % etiqueta,
              x.count('\n') == x.count('\r\n') > 0, repr(x))
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('la seccion de una rutina visible 1.27 (P10)')
