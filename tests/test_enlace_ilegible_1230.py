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

Variante atributos ilegibles (E6-E9): una junction denegada cuya carpeta tampoco
se puede listar hace fallar GetFileAttributes (err 5) y no se sabe si es un
enlace; Windows la atraviesa igual. En %TEMP% no pasa (ACE de capacidad
heredadas), asi que se mide en DELPHI_MCP_TEST_ACLDIR o, por defecto, en el
sandbox D:/SandBox-lsp/testsserver si existe.

  E6 crear a traves de la junction: GUARD-001 (ROJO contra r1222al)
  E7 leer a traves de ella: GUARD-001, sin el contenido de fuera (ROJO contra r1222al)
  E8 move, copy y upload hacia ella: GUARD-001 los tres, nada fuera
  E9 (guarda) carpeta NORMAL denegada de padre listable: crear y leer como siempre

Las ACE se quitan en el finally, antes de borrar.

Uso:  python tests/test_enlace_ilegible_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import base64
import ctypes
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check
from ctypes import wintypes

# GetFileAttributes con su ultimo error, para saber si la variante "atributos
# ilegibles" se planta: un tramo cuyos atributos no se dejan leer (ACCESS_DENIED).
_k32 = ctypes.WinDLL('kernel32', use_last_error=True)
_k32.GetFileAttributesW.argtypes = [wintypes.LPCWSTR]
_k32.GetFileAttributesW.restype = wintypes.DWORD


def attrs_ilegibles(p):
    """True si GetFileAttributes(p) falla con ACCESS_DENIED (err 5): ni los
    atributos del tramo se dejan leer. En %TEMP% las ACE heredadas de capacidad
    los dejan leer (0x410), asi que la variante no se planta ahi."""
    a = _k32.GetFileAttributesW(p)
    return a == 0xFFFFFFFF and ctypes.get_last_error() == 5

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
    return mc.consola(['icacls'] + list(a)).returncode


def foto():
    return {n: open(os.path.join(T, n), 'rb').read() for n in sorted(os.listdir(T))}


def jaula(r):
    return 'GUARD-001' in r and 'INTERNAL' not in r


temp_planta = False
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
    temp_planta = attrs_ilegibles(J)

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


# ---- variante "atributos ilegibles": GetFileAttributes del tramo FALLA
# (ACCESS_DENIED) y no se sabe si es un enlace. En %TEMP% no se planta (ACE
# heredadas de capacidad dejan leer 0x410); se mide en DELPHI_MCP_TEST_ACLDIR,
# creando SOLO el propio subarbol y borrandolo al acabar.
if not temp_planta:
    print('NOTA: en %TEMP% GetFileAttributes de la junction denegada NO falla (ACE heredadas '
          'de capacidad): la variante \"atributos ilegibles\" no se planta aqui; se mide en '
          'DELPHI_MCP_TEST_ACLDIR')

ACLDIR = os.environ.get('DELPHI_MCP_TEST_ACLDIR', '').strip() or (
    os.path.normpath('D:/SandBox-lsp/testsserver') if os.path.isdir('D:/SandBox-lsp/testsserver') else '')
if not ACLDIR:
    print('NOTA: no se mide la variante atributos ilegibles: ni DELPHI_MCP_TEST_ACLDIR '
          'ni el sandbox D:/SandBox-lsp/testsserver (hace falta un volumen donde '
          'GetFileAttributes de una junction denegada falle con ACCESS_DENIED)')
else:
    AB = os.path.join(ACLDIR, 'test_enlace_ilegible_1230')   # SOLO nuestro subarbol
    AJAIL = os.path.join(AB, 'jail')
    AD = os.path.join(AJAIL, 'D')          # carpeta no listable (deny)
    AJ = os.path.join(AD, 'J')             # junction dentro -> fuera de la raiz
    AD2 = os.path.join(AJAIL, 'D2')        # carpeta NORMAL denegada, padre listable
    AT = os.path.join(AB, 'fuera', 'T')
    apuestas = []
    asrv = None

    def afoto():
        return {n: open(os.path.join(AT, n), 'rb').read() for n in sorted(os.listdir(AT))}
    try:
        # todo el montaje dentro del try: si mklink o una ACE fallan, el finally
        # quita las ACE y borra el subarbol igual (nada queda en el sandbox)
        mc.borra(AB)
        for d in (AD, AD2, AT):
            os.makedirs(d)
        open(os.path.join(AT, 'secreto.txt'), 'w').write('SECRETO-DE-FUERA')
        open(os.path.join(AD2, 'existe.txt'), 'w').write('hola')
        for n in ('m.txt', 'c.txt'):
            open(os.path.join(AJAIL, n), 'w').write('x')
        subprocess.run(['cmd', '/c', 'mklink', '/J', AJ, AT], capture_output=True)
        assert os.path.isdir(AJ), 'sin junction en ACLDIR'
        aexe = mc.copia_exe(os.path.join(AB, 'srv'))
        assert icacls(AD, '/deny', USR + ':(RD,RA,REA)') == 0
        apuestas.append([AD])
        assert icacls(AJ, '/L', '/deny', USR + ':(RA,REA,RD)') == 0
        apuestas.append([AJ, '/L'])
        assert icacls(AD2, '/deny', USR + ':(RD,RA,REA)') == 0
        apuestas.append([AD2])
        if not attrs_ilegibles(AJ):
            print('NOTA: en %s la junction denegada no hace fallar GetFileAttributes '
                  '(ACE de capacidad heredadas): la variante no se mide alli' % ACLDIR)
        else:
            asrv = mc.Stdio(aexe, mc.entorno({'DELPHI_MCP_ROOTS': AJAIL}),
                            nombre='test-enlace-ilegible-acl', t=300)
            aantes = afoto()
            a1 = asrv.call('delphi_textedit', {'path': os.path.join(AJ, 'nuevo.txt'), 'create': True, 'content': 'v4'})
            check('E6 (atributos ilegibles) crear a traves de la junction: GUARD-001, la jaula',
                  jaula(a1), a1[:300])
            a2 = asrv.call('delphi_read', {'path': os.path.join(AJ, 'secreto.txt')})
            check('E7 (atributos ilegibles) leer a traves de ella: GUARD-001, sin el contenido de fuera',
                  jaula(a2) and 'SECRETO-DE-FUERA' not in a2, a2[:300])
            a3 = [asrv.call('delphi_move', {'path': os.path.join(AJAIL, 'm.txt'), 'dest': os.path.join(AJ, 'm.txt')}),
                  asrv.call('delphi_move', {'path': os.path.join(AJAIL, 'c.txt'), 'dest': os.path.join(AJ, 'c.txt'), 'copy': True}),
                  asrv.call('delphi_upload', {'path': os.path.join(AJ, 'u.txt'),
                                              'chunkbase64': base64.b64encode(b'u').decode()})]
            check('E8 (atributos ilegibles) move, copy y upload hacia ella: GUARD-001 los tres, nada fuera',
                  all(jaula(r) for r in a3) and afoto() == aantes, [r[:160] for r in a3])
            a4 = [asrv.call('delphi_textedit', {'path': os.path.join(AD2, 'nuevo.txt'), 'create': True, 'content': 'n'}),
                  asrv.call('delphi_read', {'path': os.path.join(AD2, 'existe.txt')})]
            check('E9 (guarda) carpeta NORMAL denegada de padre listable: crear y leer como siempre',
                  not any(mc.rechazado(r) for r in a4) and '1|hola' in a4[1], [r[:160] for r in a4])
    finally:
        if asrv:
            asrv.cierra()
        for a in reversed(apuestas):
            icacls(*(a + ['/remove:d', USR]))
        if os.path.isdir(AJ):
            os.rmdir(AJ)  # la junction, nunca su destino
        mc.borra(AB)
mc.fin('un enlace que no se puede seguir se juzga cerrado, V4 de la 1.23')
