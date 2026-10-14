# -*- coding: utf-8 -*-
"""2g de la 1.18.x (1.18.4): una carpeta que no se deja LISTAR dentro de un
arbol que se borra, se copia o se purga. La puerta de los metadatos git
recorre el arbol entero antes (MetadatosGitEnArbolDenegados) y falla cerrada
si no puede, bien; pero contestaba GUARD-033 ("es metadato de git, o lo
contiene"), que no es la causa y manda al agente a buscar un .git que no hay.

  I2 delphi_move copy=true de una carpeta con una subcarpeta ilegible:
     negado, nada copiado, y la negativa dice que no se pudo leer
  I1 delphi_delete de esa carpeta: igual, nada movido ("lo que no se puede
     revisar no se mueve", la regla de la puerta)
  I3 purge=true de una copia de la papelera con una subcarpeta ilegible:
     igual, y la copia sigue
  I4 control: sin nada ilegible, el borrado va a la papelera

Uso:  python tests/test_arbol_ilegible_1184.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('arbol_ilegible_1184')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def arbol(nombre):
    d = os.path.join(JAIL, nombre)
    os.makedirs(os.path.join(d, 'cerrada'))
    open(os.path.join(d, 'a.txt'), 'w').write('a')
    open(os.path.join(d, 'cerrada', 'b.txt'), 'w').write('b')
    return d


def dice_ilegible(r):
    return 'GUARD-040' in r and 'GUARD-033' not in r


s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='arbol-ilegible', t=120)
try:
    X = arbol('X')
    with mc.ilegible(os.path.join(X, 'cerrada')):
        Y = os.path.join(JAIL, 'Y')
        r = s.call('delphi_move', {'path': X, 'dest': Y, 'copy': True})
        check('I2 copiarlo: negado, nada copiado, y la negativa dice que no se pudo leer',
              dice_ilegible(r) and not os.path.exists(Y),
              (r[:400], os.path.exists(Y) and sorted(os.listdir(Y))))
        r = s.call('delphi_delete', {'path': X})
        check('I1 borrar un arbol con una carpeta ilegible: negado, y la negativa dice que no se pudo leer',
              dice_ilegible(r) and os.path.isfile(os.path.join(X, 'a.txt')), r[:400])

    Z = arbol('Z')
    r = s.call('delphi_delete', {'path': Z})
    copia = [ln.split('copy:', 1)[1].strip() for ln in r.splitlines() if 'copy:' in ln]
    check('I4 control: sin nada ilegible el arbol va a la papelera', not os.path.exists(Z) and copia, r[:300])
    if copia:
        C = mc.real(copia[0])
        with mc.ilegible(os.path.join(C, 'cerrada')):
            r = s.call('delphi_delete', {'path': copia[0], 'purge': True})
            check('I3 purgar de la papelera un arbol con una carpeta ilegible: negado, la copia sigue, y lo dice',
                  dice_ilegible(r) and os.path.isfile(os.path.join(C, 'a.txt')), r[:400])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('arbol ilegible 1184')
