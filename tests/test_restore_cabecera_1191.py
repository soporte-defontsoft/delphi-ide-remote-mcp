# -*- coding: utf-8 -*-
"""Un restore tras una copia o un renombrado vuelve a lo que la operacion TRAJO
(1.19.1; Hermes, 15-oct-2026, informe 011046).

Hasta la 1.22, delphi_move copy=true (o un move que renombra) reescribia
"unit X;" al nombre nuevo (MOVE-015) con el escritor de siempre, que guardaba
como PRIMERA copia del dia el fichero con la cabecera VIEJA: tras un cambio del
agente, restore volvia a una version que la operacion nunca dejo (medido contra
1bdb4d7). Desde V19 (1.23) copy y move son los del operador: el fichero llega
byte a byte, y su cabecera la cambia el agente con delphi_edit.

  R1 copy=true con nombre nuevo, un edit y restore: la copia vuelve a los bytes
     que trajo (los del original)
  R2 move que renombra, un edit y restore: igual, los bytes que el move dejo
  R3 la copia no toca el original y el edit se deshace de verdad

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
    bytes_orig = open(orig, 'rb').read()
    copia = os.path.join(JAIL, 'UCopia.pas')
    r = s.call('delphi_move', {'path': orig, 'dest': copia, 'copy': True})
    check('R1 preparacion: copiado byte a byte (la cabecera, la del original)',
          mc.abre(r, 'SK_MOVE_COPIADO_FMT') and open(copia, 'rb').read() == bytes_orig, r[:200])
    # (revisor de baterias, 18-oct-2026) el edit y el restore se MIRAN: si los dos
    # fallaban, "Result := 1" seguia ahi y R1/R3 pasaban sin restaurar nada
    s.call('delphi_edit', {'path': copia, 'old': '  Result := 1;', 'new': '  Result := 2;'})
    check('R1 preparacion: el edit escribio (Result := 2)',
          '  Result := 2;' in open(copia, encoding='utf-8-sig').read(), open(copia, encoding='utf-8-sig').read()[:200])
    r = s.call('delphi_edit', {'path': copia, 'restore': True, 'confirm': True})
    check('R1 el restore RESTAURO', mc.abre(r, 'SK_EDIT_RESTAURADO_DESDE_FMT'), r[:200])
    check('R1 copy=true + edit + restore: la copia vuelve a los bytes que trajo',
          open(copia, 'rb').read() == bytes_orig, linea1(copia))
    check('R3 ...el original sigue intacto y el edit se deshizo',
          linea1(orig) == 'unit UOrig;' and '  Result := 1;' in open(copia, encoding='utf-8-sig').read(),
          open(copia, encoding='utf-8-sig').read()[:200])

    viejo = unit('UViejo')
    bytes_viejo = open(viejo, 'rb').read()
    nuevo = os.path.join(JAIL, 'UNuevo.pas')
    r = s.call('delphi_move', {'path': viejo, 'dest': nuevo})
    check('R2 preparacion: renombrado byte a byte',
          mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and not os.path.exists(viejo) and open(nuevo, 'rb').read() == bytes_viejo,
          r[:200])
    s.call('delphi_edit', {'path': nuevo, 'old': '  Result := 1;', 'new': '  Result := 3;'})
    check('R2 preparacion: el edit escribio (Result := 3)',
          '  Result := 3;' in open(nuevo, encoding='utf-8-sig').read(), open(nuevo, encoding='utf-8-sig').read()[:200])
    r = s.call('delphi_edit', {'path': nuevo, 'restore': True, 'confirm': True})
    # lo que mide el restore: deshizo el edit y volvio a lo que dejo el move, ni mas ni menos
    check('R2 move que renombra + edit + restore: restaurado a los bytes que el move dejo',
          mc.abre(r, 'SK_EDIT_RESTAURADO_DESDE_FMT') and open(nuevo, 'rb').read() == bytes_viejo,
          (r[:200], linea1(nuevo)))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('restore cabecera 1.19.1')
