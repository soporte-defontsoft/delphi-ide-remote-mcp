# -*- coding: utf-8 -*-
r"""Las COPIAS que el servidor hace por su cuenta y un ENLACE DURO a un fichero
de FUERA de las raices (1.21.1). La puerta de leer ya negaba leerlo
(GUARD-041/042, test_enlace_duro_lectura_1211), pero quien copiaba sus bytes
sin preguntarla los metia en la jaula, y delphi_upload escribia DENTRO de el.
Medido el 20-oct-2026 contra f83f2d0 (sondas del scratchpad):
sonda_upload_enlace, sonda_copia_carpeta_enlace.

  C1 upload offset=0 sobre el enlace: GUARD-043, el de fuera intacto y sus
     bytes en ninguna copia de la jaula (escribia lo subido FUERA y dejaba
     los bytes de fuera en la papelera)
  C2 upload que anade (offset = su tamano): GUARD-043 y el de fuera intacto
  C3 control: upload sobre un fichero de un nombre sustituye con su copia
  C4 delphi_move del enlace: se mueve ESTE nombre, sin copia en la papelera
     (la copia salia con los bytes de fuera)
  C5 copy=true de una carpeta con el enlace dentro: el resto se copia y el
     enlace no, dicho en FILE-032 (la copia salia con los bytes de fuera)
  C6 delphi_styles build con el .res enlazado: negado ANTES de convertir
     (ningun .bin.style nace) y sin copia en la papelera
  C7 delphi_delete del enlace: la papelera guarda el NOMBRE, no una copia
  y al final: el fichero de fuera intacto y sus bytes en ninguna copia

C1, C2, C4, C5 y C6 son ROJAS contra 1.21.0 y contra f83f2d0 (pasar su exe como
argumento; C7 cae con ellas porque C1 ya escribio el de fuera).
Donde Windows no lista los nombres (el %TEMP% de la app MSIX de Claude: error
50, ver test_enlace_duro_lectura_1211) las negativas de leer son GUARD-042;
GUARD-043 cuenta los nombres, que Windows da en todas partes.

Uso:  python tests/test_enlace_duro_copias_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import base64, ctypes, os
from ctypes import wintypes as w
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('enlace_duro_copias_1211')
FUERA = mc.carpeta('enlace_duro_copias_1211-fuera')
JAIL = os.path.join(BASE, 'jail')
STY = os.path.join(JAIL, 'Styles')
CARPETA = os.path.join(JAIL, 'carpeta')
for d in (STY, CARPETA):
    os.makedirs(d)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
SECRETO = b'SECRETO-COPIAS-1211 ' + b'x' * 40
SEC = os.path.join(FUERA, 'secreto.bin')
open(SEC, 'wb').write(SECRETO)


def enlace(nuevo):
    return bool(ctypes.windll.kernel32.CreateHardLinkW(nuevo, SEC, None))


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


def copias_del_secreto():
    """Los ficheros de la jaula (papelera incluida) con los bytes de fuera que
    son una COPIA (un nombre): un nombre del mismo fichero no es una fuga."""
    hay = []
    for raiz, _, ficheros in os.walk(JAIL):
        for f in ficheros:
            p = os.path.join(raiz, f)
            try:
                if os.stat(p).st_nlink == 1 and SECRETO in open(p, 'rb').read():
                    hay.append(os.path.relpath(p, JAIL))
            except OSError:
                pass
    return hay


def intacto():
    return open(SEC, 'rb').read() == SECRETO


def b64(b):
    return base64.b64encode(b).decode()


UP = os.path.join(JAIL, 'subida.bin')
check('preparacion: el enlace duro de upload', enlace(UP))
JUEZ = nombres_listables(UP)
print('NOTA: aqui Windows %s los nombres de un fichero: las negativas de leer seran %s' % (
    'lista' if JUEZ else 'NO lista (error 50)', 'GUARD-041' if JUEZ else 'GUARD-042'))
NEGATIVA = 'SR_JAIL_ENLACE_DURO_FMT' if JUEZ else 'SR_JAIL_ENLACE_DURO_SIN_NOMBRES_FMT'
NORMAL = os.path.join(JAIL, 'normal.bin')
open(NORMAL, 'wb').write(b'NORMAL-ANTES')
MOV = os.path.join(JAIL, 'mover.bin')
check('preparacion: el enlace duro de move', enlace(MOV))
open(os.path.join(CARPETA, 'otro.txt'), 'w').write('OTRO-1211')
DENTRO = os.path.join(CARPETA, 'enlazado.bin')
check('preparacion: el enlace duro dentro de la carpeta', enlace(DENTRO))
open(os.path.join(STY, 'Bat.style'), 'w', encoding='utf-8', newline='\n').write(
    "object TStyleContainer\n  object TLayout\n    StyleName = 'x'\n  end\nend\n")
open(os.path.join(STY, 'Bat.Estilos.rc'), 'w', encoding='utf-8').write('BAT RCDATA "Bat.bin.style"\n')
RES = os.path.join(STY, 'Bat.Estilos.res')
check('preparacion: el .res es un enlace duro', enlace(RES))
BORRA = os.path.join(JAIL, 'borrar.bin')
check('preparacion: el enlace duro de delete', enlace(BORRA))

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='enlace-duro-copias', t=180)
try:
    r = srv.call('delphi_upload', {'path': UP, 'offset': 0, 'chunkbase64': b64(b'SUBIDO-C1')})
    check('C1 upload offset=0 sobre el enlace: GUARD-043, el de fuera intacto y sin copia de sus bytes',
          mc.es(r, 'SR_ESCRITURA_EN_ENLACE_DURO_FMT') and intacto() and not copias_del_secreto(),
          (r[:300], open(SEC, 'rb').read()[:30], copias_del_secreto()))
    r = srv.call('delphi_upload', {'path': UP, 'offset': len(SECRETO), 'chunkbase64': b64(b'ANADIDO-C2')})
    check('C2 upload que anade al enlace: GUARD-043 y el de fuera intacto',
          mc.es(r, 'SR_ESCRITURA_EN_ENLACE_DURO_FMT') and intacto(), (r[:300], open(SEC, 'rb').read()[-30:]))
    r = srv.call('delphi_upload', {'path': NORMAL, 'offset': 0, 'chunkbase64': b64(b'NORMAL-DESPUES')})
    check('C3 control: upload sobre un fichero de un nombre lo sustituye y guarda la copia',
          '"replaced":true' in r and '"backup"' in r and open(NORMAL, 'rb').read() == b'NORMAL-DESPUES',
          r[:300])
    MOVIDO = os.path.join(JAIL, 'movido.bin')
    r = srv.call('delphi_move', {'path': MOV, 'dest': MOVIDO})
    check('C4 delphi_move del enlace: se mueve este nombre, sin copia de los bytes de fuera',
          not mc.rechazado(r) and os.path.exists(MOVIDO) and not os.path.exists(MOV) and
          os.stat(MOVIDO).st_nlink > 1 and intacto() and not copias_del_secreto(),
          (r[:300], copias_del_secreto()))
    COPIA = os.path.join(JAIL, 'copia')
    r = srv.call('delphi_move', {'path': CARPETA, 'dest': COPIA, 'copy': True})
    check('C5 copy=true de la carpeta: lo demas se copia, el enlace no (FILE-032) y sin sus bytes',
          not mc.rechazado(r) and mc.es(r, 'SN_COPY_LINKS_NOT_FOLLOWED_FMT') and 'enlazado.bin' in r and
          os.path.exists(os.path.join(COPIA, 'otro.txt')) and
          not os.path.exists(os.path.join(COPIA, 'enlazado.bin')) and not copias_del_secreto(),
          (r[:400], copias_del_secreto()))
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'})
    check('C6 styles build con el .res enlazado: %s antes de convertir y sin copia de sus bytes'
          % ('GUARD-041' if JUEZ else 'GUARD-042'),
          mc.es(r, NEGATIVA) and not os.path.exists(os.path.join(STY, 'Bat.bin.style')) and
          intacto() and not copias_del_secreto(), (r[:300], copias_del_secreto()))
    r = srv.call('delphi_delete', {'path': BORRA})
    check('C7 delphi_delete del enlace: la papelera guarda el nombre, no una copia',
          not mc.rechazado(r) and not os.path.exists(BORRA) and intacto() and not copias_del_secreto(),
          (r[:300], copias_del_secreto()))
finally:
    srv.cierra()

check('el fichero de fuera sale intacto', intacto(), open(SEC, 'rb').read()[:40])
check('sus bytes no estan en ninguna copia de la jaula', not copias_del_secreto(), copias_del_secreto())
mc.borra(BASE)
mc.borra(FUERA)
mc.fin('enlace duro copias 1.21.1')
