# -*- coding: utf-8 -*-
"""Una ruta que solo se equivoca de UNIDAD (V92, 1.23.1). Hermes escribio
srvn:\\Program Files (x86)\\Embarcadero\\Studio\\ComponentesDX13.2\\Steema
Software (sus raices estan en srvn:) cuando delphi_workspace le daba esa
carpeta en srvc:; la negativa (GUARD-002 y READ-003) explicaba la zona en
general y no nombraba la buena. Ahora, si la misma ruta bajo otra unidad cae en
un sitio que esta sesion lee, se dice cual. Solo con los sitios que
delphi_workspace ya lista: no pregunta al disco (no es un oraculo).

  O1 delphi_read de C:\\<repo>\\tests\\mcp_cliente.py con la carpeta tests de D:
     como raiz de solo lectura: negado, y la negativa nombra la de D:
  O2 una ruta cuya cola no esta en ningun sitio: la negativa de siempre, sin pista
  O3 una raiz que es una unidad ENTERA contiene por texto cualquier ruta (medido
     en vivo: la pista nombraba srvn:\\Program Files... que no existe): la pista
     nombra la que EXISTE

Uso:  python tests/test_otra_unidad_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('otra_unidad_1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
TESTS = os.path.dirname(os.path.abspath(__file__))
UNIDAD = os.path.splitdrive(TESTS)[0]
OTRA = 'C:' if UNIDAD.upper() != 'C:' else 'D:'
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_READONLY_ROOTS': TESTS}),
               nombre='otra-unidad', t=120)
try:
    mala = OTRA + os.path.splitdrive(os.path.join(TESTS, 'mcp_cliente.py'))[1]
    buena = 'srv' + UNIDAD[0].lower() + ':' + os.path.splitdrive(os.path.join(TESTS, 'mcp_cliente.py'))[1]
    r = srv.call('delphi_read', {'path': mala, 'toline': 2})
    check('O1 la misma ruta en otra unidad: negada, y la negativa nombra la que se lee (%s)' % buena,
          mc.abre(r, 'SR_JAIL_FMT') and mc.es(r, 'SN_READ_OTRA_UNIDAD_FMT') and buena in r, r[:700])
    r = srv.call('delphi_read', {'path': OTRA + '\\NoEstaEnNingunSitio\\x.pas'})
    check('O2 una ruta que no esta en ningun sitio: la negativa de siempre, sin pista de otra unidad',
          mc.abre(r, 'SR_JAIL_FMT') and not mc.es(r, 'SN_READ_OTRA_UNIDAD_FMT'), r[:500])
finally:
    srv.cierra()

# O3: C:\ entera (de solo lectura) DELANTE de la carpeta tests: por texto la ruta
# cabe en las dos, y solo existe en la de tests
LIBRE = mc.letras_libres(1)[0] + ':'
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_READONLY_ROOTS': 'C:\\;' + TESTS}),
               nombre='otra-unidad-2', t=120)
try:
    cola = os.path.splitdrive(os.path.join(TESTS, 'mcp_cliente.py'))[1]
    r = srv.call('delphi_read', {'path': LIBRE + cola, 'toline': 2})
    check('O3 con una unidad entera de raiz, la pista nombra la ruta que EXISTE (%s), no la de C:' % buena,
          mc.abre(r, 'SR_JAIL_FMT') and buena in r and ('srvc:' + cola) not in r, r[:900])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('la ruta en otra unidad 1.23.1 (V92)')
