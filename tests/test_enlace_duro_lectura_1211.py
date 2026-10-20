# -*- coding: utf-8 -*-
r"""Un ENLACE DURO en la jaula a un fichero de FUERA de las raices (2al-H2,
1.21.1). Es el MISMO fichero con otro nombre: la jaula miraba el nombre (y su
ruta real, que para un enlace duro es la suya) y lo dejaba leer. Medido el
20-oct-2026 contra 1.21.0: delphi_read y delphi_search leian el secreto, y
delphi_styles build lo metia en el .res. El juez es Windows: los nombres del
fichero (FindFirstFileNameW), cada uno por la jaula.

  H1 delphi_read del enlace: GUARD-041 y el secreto no sale
  H2 delphi_search del texto del secreto: no lo encuentra
  H3 delphi_styles build con un .rc que lo incluye: el .res no lo lleva
  H4 delphi_move copy=true del enlace: negado, ninguna copia con el secreto
  H5 delphi_textedit del enlace: negado y el fichero de fuera intacto
  H6 delphi_fetch del enlace: negado
  H7 control: un enlace duro con los DOS nombres en la jaula se lee
  H8 control: uno cuyo otro nombre esta en una referencia (solo lectura) se lee
  H9 control: un fichero de un solo nombre (lo normal) se lee como siempre
  H10 el juez es de LEER: borrar el enlace (este nombre) si se puede, y el de
      fuera sigue intacto

H1-H4 y H6 son ROJAS contra 1.21.0 (pasar su exe como argumento).

EL JUEZ SE MIDE AQUI MISMO: donde Windows no lista los nombres de un fichero, la
jaula niega con GUARD-042 (no sabe donde estan los otros). Medido el 20-oct-2026:
bajo %TEMP% de un proceso de la app MSIX de Claude (esta bateria y su servidor)
FindFirstFileNameW da el error 50; en D: y en C:\Windows, y desde el servicio,
contesta. Asi que H1 espera GUARD-041 o GUARD-042 segun lo que diga el juez en
ESTE fixture, y H7/H8 - el camino que lee - solo se miden donde contesta (si
no, que se niegan con GUARD-042, y lo dice). El camino que lee se prueba en vivo
contra produccion.

Uso:  python tests/test_enlace_duro_lectura_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, os
from ctypes import wintypes as w
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('enlace_duro_lectura_1211')
FUERA = mc.carpeta('enlace_duro_lectura_1211-fuera')
JAIL = os.path.join(BASE, 'jail')
REF = os.path.join(BASE, 'ref')
STY = os.path.join(JAIL, 'Styles')
for d in (STY, REF):
    os.makedirs(d)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
SECRETO = 'SECRETO-H2-1211 ' + 'y' * 40
SEC = os.path.join(FUERA, 'secreto.txt')
open(SEC, 'w').write(SECRETO)
antes = open(SEC, 'rb').read()


def enlace(nuevo, existente):
    return bool(ctypes.windll.kernel32.CreateHardLinkW(nuevo, existente, None))


def nombres_listables(p):
    """El juez, preguntado aqui: lista Windows los nombres de p?"""
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.FindFirstFileNameW.restype = ctypes.c_void_p
    k.FindFirstFileNameW.argtypes = [w.LPCWSTR, w.DWORD, ctypes.POINTER(w.DWORD), w.LPWSTR]
    k.FindClose.argtypes = [ctypes.c_void_p]
    buf = ctypes.create_unicode_buffer(32768)
    n = w.DWORD(32768)
    h = k.FindFirstFileNameW(p, 0, ctypes.byref(n), buf)
    if h in (None, ctypes.c_void_p(-1).value):
        return False
    k.FindClose(h)
    return True


ENL = os.path.join(STY, 'leak.txt')
check('preparacion: el enlace duro a fuera se pudo crear', enlace(ENL, SEC))
SOLO = os.path.join(JAIL, 'solo.txt')
open(SOLO, 'w').write('SOLO-1211')
DENTRO = os.path.join(JAIL, 'dentro.txt')
open(DENTRO, 'w').write('DENTRO-1211')
DENTRO2 = os.path.join(JAIL, 'dentro-otro-nombre.txt')
check('preparacion: el enlace duro con los dos nombres dentro', enlace(DENTRO2, DENTRO))
EN_REF = os.path.join(REF, 'de-referencia.txt')
open(EN_REF, 'w').write('REFERENCIA-1211')
REF2 = os.path.join(JAIL, 'nombre-de-la-referencia.txt')
check('preparacion: el enlace duro con el otro nombre en la referencia', enlace(REF2, EN_REF))
open(os.path.join(STY, 'Bat.style'), 'w', encoding='utf-8', newline='\n').write(
    "object TStyleContainer\n  object TLayout\n    StyleName = 'x'\n  end\nend\n")
open(os.path.join(STY, 'Bat.Estilos.rc'), 'w', encoding='utf-8').write('X RCDATA "leak.txt"\n')
JUEZ = nombres_listables(ENL)
print('NOTA: aqui Windows %s los nombres de un fichero: se espera %s' % (
    'lista' if JUEZ else 'NO lista (error 50)', 'GUARD-041' if JUEZ else 'GUARD-042'))
NEGATIVA = 'SR_JAIL_ENLACE_DURO_FMT' if JUEZ else 'SR_JAIL_ENLACE_DURO_SIN_NOMBRES_FMT'

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_READONLY_ROOTS': REF}),
               nombre='enlace-duro-lectura', t=180)
try:
    r = srv.call('delphi_read', {'path': ENL})
    check('H1 delphi_read del enlace: %s y el secreto no sale' % ('GUARD-041' if JUEZ else 'GUARD-042'),
          mc.es(r, NEGATIVA) and 'SECRETO-H2' not in r, r[:300])
    r = srv.call('delphi_search', {'root': STY, 'query': 'SECRETO-H2-1211', 'pattern': '*.txt'})
    check('H2 delphi_search no encuentra el secreto y dice que se salto el enlace (SEARCH-003)',
          'SECRETO-H2' not in r and '"total":0' in r and mc.es(r, 'SN_SEARCH_ILEGIBLES_FMT') and 'leak.txt' in r,
          r[:300])
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    res = os.path.join(STY, 'Bat.Estilos.res')
    lleva = os.path.exists(res) and b'SECRETO-H2' in open(res, 'rb').read()
    check('H3 delphi_styles build: el .res no lleva el secreto', not lleva, r[:300])
    COPIA = os.path.join(JAIL, 'copia.txt')
    r = srv.call('delphi_move', {'path': ENL, 'dest': COPIA, 'copy': True})
    check('H4 delphi_move copy=true del enlace: negado y sin copia',
          mc.rechazado(r) and not os.path.exists(COPIA), r[:300])
    r = srv.call('delphi_textedit', {'path': ENL, 'old': SECRETO, 'new': 'PISADO'})
    check('H5 delphi_textedit del enlace: negado y el de fuera intacto',
          mc.rechazado(r) and open(SEC, 'rb').read() == antes, r[:300])
    r = srv.call('delphi_fetch', {'path': ENL})
    check('H6 delphi_fetch del enlace: negado', mc.rechazado(r) and 'SECRETO-H2' not in r, r[:300])
    r = srv.call('delphi_read', {'path': DENTRO2})
    if JUEZ:
        check('H7 control: con los dos nombres en la jaula se lee', 'DENTRO-1211' in r, r[:300])
    else:
        check('H7 sin juez aqui: con los dos nombres dentro tambien se niega (GUARD-042)',
              mc.es(r, NEGATIVA) and 'DENTRO-1211' not in r, r[:300])
    r = srv.call('delphi_read', {'path': REF2})
    if JUEZ:
        check('H8 control: con el otro nombre en una referencia se lee', 'REFERENCIA-1211' in r, r[:300])
    else:
        check('H8 sin juez aqui: con el otro nombre en una referencia tambien se niega (GUARD-042)',
              mc.es(r, NEGATIVA) and 'REFERENCIA-1211' not in r, r[:300])
    r = srv.call('delphi_read', {'path': SOLO})
    check('H9 un fichero de un solo nombre se lee como siempre (con juez o sin el)', 'SOLO-1211' in r, r[:300])
    # el juez es de LEER: quitar ESTE nombre no toca el otro (va a la papelera)
    r = srv.call('delphi_delete', {'path': ENL})
    check('H10 delphi_delete del enlace: se puede (es solo este nombre) y el de fuera sigue',
          not mc.rechazado(r) and not os.path.exists(ENL) and open(SEC, 'rb').read() == antes, r[:300])
finally:
    srv.cierra()

check('el fichero de fuera sale intacto', open(SEC, 'rb').read() == antes)
mc.borra(BASE)
mc.borra(FUERA)
mc.fin('enlace duro lectura 1.21.1')
