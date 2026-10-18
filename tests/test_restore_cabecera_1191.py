# -*- coding: utf-8 -*-
"""Un restore no devuelve la cabecera vieja de una unit copiada o renombrada
(1.19.1; Hermes, 15-oct-2026, informe 011046).

delphi_move copy=true (o un move que renombra) reescribe "unit X;" al nombre
nuevo (MOVE-015) con el escritor de siempre, que guardaba como PRIMERA copia del
dia el fichero con la cabecera VIEJA. Tras un cambio del agente, restore volvia
a esa copia: "unit UOrig;" dentro de UCopia.pas, con audit=clean (y CREATE-019
niega justo esa disparidad al crear). Medido contra 1bdb4d7.

  R1 copy=true con nombre nuevo, un edit y restore: la linea 1 dice el nombre NUEVO
  R2 move que renombra, un edit y restore: igual
  R3 la mudanza sigue sin tocar el original (copy) y el edit se deshace de verdad

Uso:  python tests/test_restore_cabecera_1191.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('restore_cabecera_1191')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def unit(nombre):
    p = os.path.join(JAIL, nombre + '.pas')
    open(p, 'w', newline='\r\n').write('unit %s;\n\ninterface\n\nfunction Valor: Integer;\n\n'
                                       'implementation\n\nfunction Valor: Integer;\nbegin\n'
                                       '  Result := 1;\nend;\n\nend.\n' % nombre)
    return p


def linea1(p):
    return open(p, encoding='utf-8-sig').readline().strip()


s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='restore-cabecera', t=180)
try:
    orig = unit('UOrig')
    copia = os.path.join(JAIL, 'UCopia.pas')
    s.call('delphi_move', {'path': orig, 'dest': copia, 'copy': True})
    # (revisor de baterias, 18-oct-2026) el edit y el restore se MIRAN: si los dos
    # fallaban, "Result := 1" seguia ahi y R1/R3 pasaban sin restaurar nada
    s.call('delphi_edit', {'path': copia, 'old': '  Result := 1;', 'new': '  Result := 2;'})
    check('R1 preparacion: el edit escribio (Result := 2)',
          '  Result := 2;' in open(copia, encoding='utf-8-sig').read(), open(copia, encoding='utf-8-sig').read()[:200])
    r = s.call('delphi_edit', {'path': copia, 'restore': True, 'confirm': True})
    check('R1 el restore RESTAURO', mc.abre(r, 'SK_EDIT_RESTAURADO_DESDE_FMT'), r[:200])
    check('R1 copy=true + edit + restore: la cabecera es la NUEVA (unit UCopia;)',
          linea1(copia) == 'unit UCopia;', linea1(copia))
    check('R3 ...el original sigue intacto y el edit se deshizo',
          linea1(orig) == 'unit UOrig;' and '  Result := 1;' in open(copia, encoding='utf-8-sig').read(),
          open(copia, encoding='utf-8-sig').read()[:200])

    viejo = unit('UViejo')
    nuevo = os.path.join(JAIL, 'UNuevo.pas')
    s.call('delphi_move', {'path': viejo, 'dest': nuevo})
    s.call('delphi_edit', {'path': nuevo, 'old': '  Result := 1;', 'new': '  Result := 3;'})
    check('R2 preparacion: el edit escribio (Result := 3)',
          '  Result := 3;' in open(nuevo, encoding='utf-8-sig').read(), open(nuevo, encoding='utf-8-sig').read()[:200])
    r = s.call('delphi_edit', {'path': nuevo, 'restore': True, 'confirm': True})
    # la cabecera ya era unit UNuevo por la mudanza: lo que mide el restore es que
    # deshizo el edit SIN volver a la cabecera vieja de la primera copia del dia
    check('R2 move que renombra + edit + restore: restaurado, el 3 fuera y la cabecera es la NUEVA (unit UNuevo;)',
          mc.abre(r, 'SK_EDIT_RESTAURADO_DESDE_FMT') and '  Result := 3;' not in open(nuevo, encoding='utf-8-sig').read()
          and linea1(nuevo) == 'unit UNuevo;', (r[:200], linea1(nuevo)))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('restore cabecera 1.19.1')
