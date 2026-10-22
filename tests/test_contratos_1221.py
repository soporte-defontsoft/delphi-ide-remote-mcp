# -*- coding: utf-8 -*-
r"""Parametros que se ignoraban en silencio (test completo de Opus de la 1.22.0, 1.22.1): las tools de varios
modos dicen el que no va con lo pedido (Lsp.Guard.ParametroQueNoVa) y estas dos no.

  L1 delphi_list dirs=true con pattern: LIST-015, nada listado (ROJO contra la 1.22.0: listaba y callaba)
  L2 control: dirs=true sin pattern lista las carpetas
  S1 delphi_symbols de una CARPETA con mode=full: LSP-050 (ROJO: el digest, callando)
  S2 ...con filter: LSP-050 (ROJO igual)
  S3 control: la carpeta sola da el digest; un FICHERO con mode=full, su arbol

Uso:  python tests/test_contratos_1221.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('contratos-1221')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='c1221', t=300)
try:
    d = os.path.join(BASE, 'u')
    os.makedirs(os.path.join(d, 'sub'))
    unit = os.path.join(d, 'UUno.pas')
    open(unit, 'w', newline='\r\n').write('unit UUno;\ninterface\nfunction Uno: Integer;\nimplementation\n'
                                          'function Uno: Integer;\nbegin\n  Result := 1;\nend;\nend.\n')
    r = srv.call('delphi_list', {'root': d, 'dirs': True, 'pattern': '*.pas'})
    check('L1 list dirs=true con pattern: LIST-015 y nada listado',
          mc.abre(r, 'SR_LIST_NO_VA_CON_MODO_FMT') and '"pattern"' in r and '"folders"' not in r, r[:300])
    r = srv.call('delphi_list', {'root': d, 'dirs': True})
    check('L2 control: dirs=true sin pattern lista las carpetas', 'sub' in r and not mc.fallo(r), r[:300])
    for caso, extra in (('S1 ...con mode=full', {'mode': 'full'}), ('S2 ...con filter', {'filter': 'Uno'})):
        args = {'path': d}
        args.update(extra)
        r = srv.call('delphi_symbols', args, 240)
        check('%s: symbols de una carpeta dice LSP-050' % caso,
              mc.abre(r, 'SR_SYMBOLS_NO_VA_CON_CARPETA_FMT') and '"%s"' % list(extra)[0] in r, r[:300])
    r = srv.call('delphi_symbols', {'path': d}, 240)
    check('S3 control: la carpeta sola da el digest', '"units"' in r and 'UUno' in r, r[:300])
    r = srv.call('delphi_symbols', {'path': unit, 'mode': 'full'}, 240)
    check('S3 control: un fichero con mode=full da su arbol', 'Uno' in r and not mc.fallo(r), r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('contratos 1221')
