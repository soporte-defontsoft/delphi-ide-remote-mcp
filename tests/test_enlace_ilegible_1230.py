# -*- coding: utf-8 -*-
"""Un enlace que el servidor no puede seguir se juzga CERRADO (V4 de la 1.23).

Fixture: una junction J dentro de la jaula (jail\\D\\J -> fuera\\T) y unas ACE
deny para el usuario que corre la bateria (el del servidor): D sin listar ni leer
atributos, J sin leer atributos. Asi CreateFile(J, acceso 0) falla (medido: err
5) y RealPath no sabe adonde lleva J; Windows, en cambio, SI la atraviesa (lee y
escribe en T). RealPath se quedaba con la forma TEXTUAL, dentro de la jaula:
ninguna negativa, y solo un fallo de ForceDirectories/FileExists de la RTL
impedia escribir o leer fuera (medido contra r1222ah: SYS-009, SYS-006,
MOVE-012/011 INTERNAL).

  E1 (V4) crear un fichero a traves de J: GUARD-001, la jaula (ROJO hasta la 1.23)
  E2 (V4) leer un fichero de T a traves de J: GUARD-001 (ROJO hasta la 1.23)
  E3 (V4) move, copy y upload hacia J: GUARD-001 los tres (ROJO hasta la 1.23);
     en ningun caso aparece ni cambia nada en T
  E4 (guarda) una carpeta NORMAL que no se puede abrir (sin enlace): crear, leer y
     editar dentro funcionan como siempre (su texto es su ruta real)
  E5 (guarda) la misma junction sin ACE: GUARD-001, un enlace que sale

Las ACE se quitan en el finally, antes de borrar.

Uso:  python tests/test_enlace_ilegible_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import base64
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

USR = '%s\\%s' % (os.environ['USERDOMAIN'], os.environ['USERNAME'])
BASE = mc.carpeta('test_enlace_ilegible_1230')
JAIL = os.path.join(BASE, 'jail')
D = os.path.join(JAIL, 'D')
D2 = os.path.join(JAIL, 'D2')
T = os.path.join(BASE, 'fuera', 'T')
J = os.path.join(D, 'J')
J2 = os.path.join(JAIL, 'J2')
for d in (D, D2, T):
    os.makedirs(d)
open(os.path.join(T, 'secreto.txt'), 'w').write('SECRETO-DE-FUERA\n')
open(os.path.join(D2, 'existe.txt'), 'w').write('hola\n')
for n in ('m.txt', 'c.txt'):
    open(os.path.join(JAIL, n), 'w').write('x\n')
subprocess.run(['cmd', '/c', 'mklink', '/J', J, T], capture_output=True)
subprocess.run(['cmd', '/c', 'mklink', '/J', J2, T], capture_output=True)
assert os.path.isdir(J) and os.path.isdir(J2), 'sin junctions'
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def icacls(*a):
    return subprocess.run(['icacls'] + list(a), capture_output=True, text=True).returncode


def foto():
    return {n: open(os.path.join(T, n), 'rb').read() for n in sorted(os.listdir(T))}


def jaula(r):
    return 'GUARD-001' in r and 'INTERNAL' not in r


puestas = []
srv = None
try:
    assert icacls(D, '/deny', USR + ':(RD,RA,REA)') == 0
    puestas.append([D])
    assert icacls(J, '/L', '/deny', USR + ':(RA,REA,RD)') == 0
    puestas.append([J, '/L'])
    assert icacls(D2, '/deny', USR + ':(RD,RA,REA)') == 0
    puestas.append([D2])
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-enlace-ilegible', t=300)
    antes = foto()

    r1 = srv.call('delphi_textedit', {'path': os.path.join(J, 'nuevo.txt'), 'create': True, 'content': 'v4\n'})
    check('E1 crear a traves de un enlace que no se puede seguir: la jaula lo niega (GUARD-001)',
          jaula(r1), r1[:300])
    r2 = srv.call('delphi_read', {'path': os.path.join(J, 'secreto.txt')})
    check('E2 leer a traves de el: la jaula lo niega (GUARD-001), sin el contenido de fuera',
          jaula(r2) and 'SECRETO-DE-FUERA' not in r2, r2[:300])
    r3 = [srv.call('delphi_move', {'path': os.path.join(JAIL, 'm.txt'), 'dest': os.path.join(J, 'm.txt')}),
          srv.call('delphi_move', {'path': os.path.join(JAIL, 'c.txt'), 'dest': os.path.join(J, 'c.txt'), 'copy': True}),
          srv.call('delphi_upload', {'path': os.path.join(J, 'u.txt'),
                                     'chunkbase64': base64.b64encode(b'u\n').decode()})]
    check('E3 move, copy y upload hacia el: GUARD-001 los tres, y nada aparece ni cambia fuera',
          all(jaula(r) for r in r3) and foto() == antes, [r[:160] for r in r3])

    r4 = [srv.call('delphi_textedit', {'path': os.path.join(D2, 'nuevo.txt'), 'create': True, 'content': 'n\n'}),
          srv.call('delphi_read', {'path': os.path.join(D2, 'existe.txt')}),
          srv.call('delphi_textedit', {'path': os.path.join(D2, 'existe.txt'), 'old': 'hola', 'new': 'adios'})]
    check('E4 (guarda) una carpeta normal que no se puede abrir: crear, leer y editar como siempre',
          not any(mc.rechazado(r) for r in r4) and '1|hola' in r4[1], [r[:160] for r in r4])

    r5 = srv.call('delphi_textedit', {'path': os.path.join(J2, 'nuevo.txt'), 'create': True, 'content': 'v4\n'})
    check('E5 (guarda) la misma junction sin ACE: GUARD-001, un enlace que sale',
          jaula(r5) and foto() == antes, r5[:300])
finally:
    if srv:
        srv.cierra()
    for a in reversed(puestas):
        icacls(*(a + ['/remove:d', USR]))
    for j in (J, J2):
        if os.path.isdir(j):
            os.rmdir(j)  # la junction, nunca su destino

check('E4b (guarda) lo de la carpeta normal quedo escrito',
      os.path.exists(os.path.join(D2, 'nuevo.txt')) and
      open(os.path.join(D2, 'existe.txt')).read().strip() == 'adios')
mc.borra(BASE)
mc.fin('un enlace que no se puede seguir se juzga cerrado, V4 de la 1.23')
