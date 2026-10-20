# -*- coding: utf-8 -*-
"""Una ruta con barras normales ('/') en una tool que ESCRIBE (1.21.1). Hermes, en la
validacion de la 1.21.1: delphi_edit de "srvn:/CodeSandBox/.../UCuenta.pas" se nego
con GUARD-037 ("some part of the path is a LINK") despues de que delphi_read leyera
esa misma ruta; con '\' paso. Medido en produccion el 20-oct-2026 con srvd:/ y con
D:/. '/' vale para Windows, pero no para ExtractFileDir y los suyos, que solo ven
'\': la carpeta real del escritor salia la de la unidad. La entrada (AlargaRutas)
deja ahora cada ruta marcada [RutaDelServidor] con '\', para todas las tools.

  B1 delphi_edit con D:/... escribe (no GUARD-037)
  B2 delphi_textedit con D:/... escribe
  B3 delphi_edit createunit con D:/... crea el fichero donde dice
  B4 la unidad virtual con '/' (srvX:/...) escribe tambien
  B5 control: una ruta con '/' FUERA de la jaula sigue negada como fuera (GUARD-002)
  B6 control: delphi_read con '/' lee como siempre

B1-B4 son ROJAS contra 1.21.0 (pasar su exe como argumento).

Uso:  python tests/test_rutas_con_barra_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('rutas_con_barra_1211')
JAIL = os.path.join(BASE, 'jail')
FUERA = mc.carpeta('rutas_con_barra_1211-fuera')
os.makedirs(JAIL)
U = os.path.join(JAIL, 'UBarra.pas')
open(U, 'w', encoding='utf-8', newline='\r\n').write('unit UBarra;\n\ninterface\n\nimplementation\n\nend.\n')
T = os.path.join(JAIL, 'nota.txt')
open(T, 'w', encoding='utf-8', newline='\r\n').write('uno\ndos\n')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='rutas-con-barra', t=120)


def barra(p):
    return mc.larga(p).replace('\\', '/')


try:
    r = S.call('delphi_edit', {'path': barra(U), 'old': 'implementation', 'new': 'implementation\n\n// B1'})
    check('B1 delphi_edit con D:/ escribe', not mc.rechazado(r) and '// B1' in open(U, encoding='utf-8-sig').read(), r[:300])
    r = S.call('delphi_textedit', {'path': barra(T), 'old': 'dos', 'new': 'dos B2'})
    check('B2 delphi_textedit con D:/ escribe', not mc.rechazado(r) and 'dos B2' in open(T, encoding='utf-8').read(), r[:300])
    NUEVA = os.path.join(JAIL, 'sub', 'UNueva.pas')
    r = S.call('delphi_edit', {'path': barra(NUEVA), 'createunit': True})
    check('B3 createunit con D:/ crea el fichero donde dice', not mc.rechazado(r) and os.path.isfile(NUEVA), r[:300])
    r = S.call('delphi_edit', {'path': mc.virtual(mc.larga(U)).replace('\\', '/'), 'old': '// B1', 'new': '// B4'})
    check('B4 la unidad virtual con / escribe tambien', not mc.rechazado(r) and '// B4' in open(U, encoding='utf-8-sig').read(), r[:300])
    r = S.call('delphi_textedit', {'path': barra(os.path.join(FUERA, 'x.txt')), 'create': True, 'content': 'x'})
    check('B5 control: con / FUERA de la jaula sigue negada como fuera',
          mc.rechazado(r) and not os.path.exists(os.path.join(FUERA, 'x.txt')) and 'GUARD-037' not in r, r[:300])
    r = S.call('delphi_read', {'path': barra(U)})
    check('B6 control: delphi_read con / lee', 'unit UBarra' in r, r[:300])
finally:
    S.cierra()

mc.borra(BASE)
mc.borra(FUERA)
mc.fin('rutas con barra 1.21.1')
