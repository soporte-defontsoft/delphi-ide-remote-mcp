# -*- coding: utf-8 -*-
"""1.29 (AU1): adduses en una clausula con COMENTARIOS la rehacia una unit por linea: cinco units de una
linea pasaban a cinco lineas por una que se anadia (medido el 7-nov-2026 en Lsp.Conexiones). La compacta se
editaba en su sitio solo sin comentarios. Ahora, si solo se anade al final, la clausula se queda como esta: la
ultima entrada cambia su ';' por ',' (con su comentario, que es suyo) y las nuevas van en lineas nuevas.

  U1 la linea compacta y los comentarios intactos; la nueva detras, con la sangria de la clausula
  U2 sin comentario detras del ';': la ultima pasa a ',' y la nueva va en su linea
  U3 control: removeuses en una clausula con comentarios sigue quitando (el camino de siempre)

Uso:  python tests/test_uses_comentarios_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('uses_comentarios_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
CABEZA = 'unit %s;\r\n\r\ninterface\r\n\r\n'
PIE = '\r\nimplementation\r\n\r\nend.\r\n'
CLAUSULA1 = ('uses\r\n  System.SysUtils, System.Classes, System.Types,\r\n  Lsp.Uno, // el uno\r\n'
             '  Lsp.Dos; // el dos\r\n')
CLAUSULA2 = 'uses\r\n  System.SysUtils, System.Classes, // las dos\r\n  Lsp.Dos;\r\n'


def unidad(nombre, clausula):
    ruta = os.path.join(JAIL, nombre + '.pas')
    open(ruta, 'w', encoding='utf-8', newline='').write(CABEZA % nombre + clausula + PIE)
    return ruta


U1 = unidad('Una', CLAUSULA1)
U2 = unidad('Dos', CLAUSULA2)
U3 = unidad('Tres', CLAUSULA1)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='au1', t=60)
try:
    r = srv.call('delphi_edit', {'path': U1, 'adduses': 'System.Math', 'section': 'interface'})
    hay = open(U1, encoding='utf-8', newline='').read()
    esperado = CABEZA % 'Una' + CLAUSULA1.replace('  Lsp.Dos; // el dos\r\n',
                                                 '  Lsp.Dos, // el dos\r\n  System.Math;\r\n') + PIE
    check('U1 la linea compacta y los comentarios intactos, la nueva detras. ROJO contra 958be0fe: una por linea',
          hay == esperado, (r[:160], hay))
    r = srv.call('delphi_edit', {'path': U2, 'adduses': 'System.Math', 'section': 'interface'})
    hay = open(U2, encoding='utf-8', newline='').read()
    esperado = CABEZA % 'Dos' + CLAUSULA2.replace('  Lsp.Dos;\r\n', '  Lsp.Dos,\r\n  System.Math;\r\n') + PIE
    check('U2 sin comentario detras del ";": la ultima pasa a "," y la nueva en su linea', hay == esperado, (r[:160], hay))
    r = srv.call('delphi_edit', {'path': U3, 'removeuses': 'System.Classes', 'section': 'interface'})
    hay = open(U3, encoding='utf-8', newline='').read()
    check('U3 control: removeuses en una clausula con comentarios sigue quitando',
          not mc.fallo(r) and 'System.Classes' not in hay and 'Lsp.Dos; // el dos' in hay, (r[:160], hay))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('adduses en una clausula con comentarios (1.29)')
