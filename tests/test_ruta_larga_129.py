# -*- coding: utf-8 -*-
"""Una ruta mas larga de lo que Windows abre a este servidor se dice, no "no existe" (A24 de la 1.29).

Medido el 8-nov-2026: la maquina tiene LongPathsEnabled=1 (python escribe esas
rutas) y el exe del servidor no declara longPathAware. Hasta 259 caracteres lee;
desde 260 cada tool contestaba "does not exist" (LSP-011 delphi_read, SYS-012 el
lint) con el fichero en el disco. Ahora lo dice la puerta de la llamada, sobre lo
que nombra el agente (GUARD-046).

  L1 (guarda) 259 caracteres: delphi_read lo lee
  L2 260: delphi_read dice GUARD-046 (ROJO hasta la 1.29: LSP-011 "does not exist")
  L3 270: el lint de un .dfm dice GUARD-046 (ROJO hasta la 1.29: SYS-012)
  L4 270: una escritura tambien (delphi_textedit create), sin crear nada
  L5 (guarda) 240: una escritura sigue diciendo GUARD-028, su tope de siempre
  L6 (guarda) delphi_list de la carpeta del fichero de 260 (la carpeta es mas corta)
     contesta como antes: no es una ruta que el agente nombre

Uso:  python tests/test_ruta_larga_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ruta_larga_129')
# en su forma LARGA: la que mide el servidor (alarga lo que nombra el agente), y la del
# %TEMP% en 8.3 tiene un caracter menos (DFONTA~1): la de "259" medía 260
JAIL = os.path.join(BASE, 'j')
os.makedirs(JAIL)
JAIL = mc.larga(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def ruta_de(n, nombre):
    """Una ruta de n caracteres exactos que acaba en nombre, bajo la jaula."""
    pref = os.path.join(JAIL, 'd%d_' % n)
    d = pref + 'x' * (n - len(pref) - len(nombre) - 1)
    p = os.path.join(d, nombre)
    assert len(p) == n, (len(p), n)
    return p


def planta(p, datos):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(datos)


UNIT = b'unit U;\r\ninterface\r\nimplementation\r\nend.\r\n'
p259 = ruta_de(259, 'U.pas')
p260 = ruta_de(260, 'U.pas')
p270 = ruta_de(270, 'F.dfm')
planta(p259, UNIT)
planta(p260, UNIT)
planta(p270, b'object Form1: TForm1\r\n  Caption = \'x\'\r\nend\r\n')
n270 = ruta_de(270, 'N.txt')
n240 = ruta_de(240, 'N.txt')
os.makedirs(os.path.dirname(n270), exist_ok=True)
os.makedirs(os.path.dirname(n240), exist_ok=True)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ruta-larga', t=120)
try:
    r = srv.call('delphi_read', {'path': p259})
    check('L1 (guarda) 259 caracteres: delphi_read lo lee', r.startswith('[READ-005') and 'unit U;' in r, r[:160])
    r = srv.call('delphi_read', {'path': p260})
    check('L2 260: delphi_read dice que Windows no la abre (GUARD-046)',
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_RUTA_QUE_WINDOWS_NO_ABRE_FMT'), r[:200])
    r = srv.call('delphi_designer', {'command': 'lint', 'path': p270})
    check('L3 270: el lint de un .dfm tambien (GUARD-046)',
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_RUTA_QUE_WINDOWS_NO_ABRE_FMT'), r[:200])
    r = srv.call('delphi_textedit', {'path': n270, 'create': True, 'content': 'hola\r\n'})
    check('L4 270: una escritura tambien, y no crea nada',
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_RUTA_QUE_WINDOWS_NO_ABRE_FMT') and not os.path.exists(n270), r[:200])
    r = srv.call('delphi_textedit', {'path': n240, 'create': True, 'content': 'hola\r\n'})
    check('L5 (guarda) 240: una escritura sigue diciendo GUARD-028',
          mc.rechazado(r) and mc.es(r, 'SR_GUARD_RUTA_LARGA_FMT') and not os.path.exists(n240), r[:200])
    r = srv.call('delphi_list', {'path': os.path.dirname(p260)})
    check('L6 (guarda) delphi_list de la carpeta del de 260 contesta, no niega',
          not mc.rechazado(r), r[:200])
    print('L6 dijo: ' + r[:300].replace('\n', ' '))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('una ruta que Windows no abre se dice, A24 de la 1.29')
