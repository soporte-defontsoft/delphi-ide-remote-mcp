# -*- coding: utf-8 -*-
"""Battery 1.18.2, point 2: a hard link never lets an operation write outside
the workspace.

Measured 2026-10-11 live, in production: a folder holding a hard link to a
file OUTSIDE the roots, sent to the trash and purged, left that file outside
without its read-only and hidden attributes. The deleter cleared the
attributes of every file before deleting it, and the attributes of a hard
link ARE those of the file - the same file, with its other name outside.
The content was never touched, and a lone read-only hard link was already
refused (SYS-029); a FOLDER took it along.

  H1 purge a folder holding a hard link to a READ-ONLY + HIDDEN file
     outside: the folder goes from the trash, and the file outside keeps
     its attributes and its bytes
  H2 control: a lone read-only hard link is refused by delphi_delete
     (SYS-029) and nothing changes
  H3 control: a lone hidden hard link, trashed and purged: the file outside
     keeps its attributes (green before: that path never cleared them)

Usage:  python tests/test_enlace_duro_1182.py [path-to-DelphiLspMcp.exe]
"""
import atexit
import ctypes
import glob
import os
import mcp_cliente as mc
from mcp_cliente import check

RO, OCULTO = 0x1, 0x2
k32 = ctypes.windll.kernel32
k32.GetFileAttributesW.restype = ctypes.c_uint32

BASE = mc.carpeta('enlace-duro-1182')
JAIL = os.path.join(BASE, 'jail')    # la unica raiz
FUERA = os.path.join(BASE, 'fuera')  # fuera de todo: la victima
for _d in (JAIL, FUERA):
    os.makedirs(_d)
VICTIMAS = []


def suelta():
    # la victima de solo lectura no se deja borrar: se le quitan los atributos
    # (es nuestra, de la bateria) y despues se va la carpeta entera
    for v in VICTIMAS:
        if os.path.exists(v):
            k32.SetFileAttributesW(v, 0x80)


atexit.register(mc.borra, BASE)
atexit.register(suelta)  # atexit es LIFO: suelta antes de borrar
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='enlace-duro', t=300)
call = srv.call


def victima(nombre, atributos):
    p = os.path.join(FUERA, nombre)
    with open(p, 'wb') as f:
        f.write(b'victima ' + nombre.encode())
    k32.SetFileAttributesW(p, atributos)
    VICTIMAS.append(p)
    return p


def atributos(p):
    return k32.GetFileAttributesW(p) & (RO | OCULTO)


def intacta(p, atrib):
    with open(p, 'rb') as f:
        bytes_ok = f.read() == b'victima ' + os.path.basename(p).encode()
    return bytes_ok and atributos(p) == atrib


def en_papelera(patron):
    # la copia, sin su marca de dueno (<copia>.by, la deja la papelera al lado)
    return [p for p in glob.glob(os.path.join(JAIL, '__delphi-patch', '*', 'deleted', patron))
            if not p.endswith('.by')]


def corto(t):
    return ' '.join(str(t).split())[:220]


try:
    # H1: una CARPETA con un enlace duro a un fichero de fuera, +R y oculto
    v1 = victima('v1.txt', RO | OCULTO)
    c1 = os.path.join(JAIL, 'carpeta1')
    os.makedirs(c1)
    os.link(v1, os.path.join(c1, 'enlace.txt'))
    with open(os.path.join(c1, 'normal.txt'), 'wb') as f:
        f.write(b'normal')
    check('H1 fixture: el enlace duro comparte los atributos de la victima',
          atributos(os.path.join(c1, 'enlace.txt')) == RO | OCULTO, atributos(os.path.join(c1, 'enlace.txt')))
    r = call('delphi_delete', {'path': c1})
    copia = en_papelera('carpeta1-*')
    check('H1 la carpeta va a la papelera', len(copia) == 1 and not os.path.exists(c1), corto(r))
    if copia:
        r = call('delphi_delete', {'path': copia[0], 'purge': True})
        check('H1 la purga de la carpeta no cambia los atributos del fichero de FUERA (+R y oculto)',
              intacta(v1, RO | OCULTO), 'atributos=%s %s' % (atributos(v1), corto(r)))
        check('H1b ...y la carpeta se va de la papelera', not os.path.exists(copia[0]), corto(r))

    # H2: un enlace duro +R suelto: SYS-029, nada cambia
    v2 = victima('v2.txt', RO)
    e2 = os.path.join(JAIL, 'enlace2.txt')
    os.link(v2, e2)
    r = call('delphi_delete', {'path': e2})
    check('H2 control: un enlace duro +R suelto se niega (SYS-029) y nada cambia',
          'SYS-029' in r, corto(r))
    check('H2b ...y la victima sigue intacta', intacta(v2, RO) and os.path.exists(e2), atributos(v2))

    # H3: un enlace duro oculto suelto, a la papelera y purgado
    v3 = victima('v3.txt', OCULTO)
    e3 = os.path.join(JAIL, 'enlace3.txt')
    os.link(v3, e3)
    call('delphi_delete', {'path': e3})
    copia = en_papelera('enlace3.txt-*')
    if copia:
        r = call('delphi_delete', {'path': copia[0], 'purge': True})
    check('H3 control: un enlace duro oculto suelto purgado deja la victima intacta',
          len(copia) == 1 and intacta(v3, OCULTO) and not os.path.exists(copia[0]),
          'copia=%s atributos=%s' % (copia, atributos(v3)))
finally:
    srv.cierra()

mc.fin('hard links: no operation writes outside the workspace through one (1.18.2)')
