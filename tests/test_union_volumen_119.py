# -*- coding: utf-8 -*-
"""J8 (2x de la 1.18.2, WATCH): una junction cuyo destino esta escrito como un
VOLUMEN por su GUID (\\??\\Volume{...}\\ruta), hacia una carpeta de FUERA de las
raices que EXISTE. El juez de adonde lleva un enlace que existe es Windows -la
ruta real por su handle, GetFinalPathNameByHandle (Lsp.Rutas.NombreFinal)-, no
el texto del enlace: DestinoDeEnlace (el lector del texto) solo entra cuando el
enlace esta COLGANTE y no se puede abrir. La forma en que este escrito el
destino -un volumen por su GUID- no cambia la ruta real, y esa esta fuera.

MEDIDO el 14-oct-2026 (sonda del scratchpad, 4.8): junction_nt a
\\??\\Volume{GUID}\\...\\<victima> queda plantada, Windows LA SIGUE (os.listdir la
lista) y GetFinalPathNameByHandle la resuelve a su ruta real con letra
(C:\\...), fuera de la jaula. Por eso delphi_read y delphi_list a traves de ella
tienen que NEGAR sin devolver nada, y delphi_move copy=true de la carpeta que
la contiene no debe copiar lo de detras (lo lista como no seguido,
SN_COPY_LINKS_NOT_FOLLOWED_FMT) y la victima queda intacta.

La victima es una carpeta FUERA de las raices, en el MISMO volumen (para poder
escribir su destino por el GUID de ese volumen), con una unit .pas marcada: asi
V2 mide la jaula (una .pas no la para el tipo de fichero) y el marcador delata
cualquier fuga de contenido o de nombre.

  V1 el enlace quedo plantado y Windows lo SIGUE (control: os.listdir lo lista)
  V2 delphi_read de la unit a traves del enlace: negado, sin su contenido
  V3 delphi_list de la carpeta a traves del enlace: negado, sin sus nombres
  V4 delphi_move copy=true de la carpeta que lo contiene: lo de detras no se
     copia (no seguido) y la victima sigue intacta (hash antes/despues)

Uso:  python tests/test_union_volumen_119.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes
import hashlib
import os
from ctypes import wintypes as wt
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('union_volumen_119')
JAIL = os.path.join(BASE, 'jail')
CARPETA = os.path.join(JAIL, 'con-enlace')      # dentro de la jaula
LINK = os.path.join(CARPETA, 'vol')             # la junction de volumen
FUERA = os.path.join(BASE, 'fuera')             # la victima, FUERA de las raices
VICTIMA = os.path.join(FUERA, 'secretos')
os.makedirs(CARPETA)
os.makedirs(VICTIMA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

# contenido de la victima: una unit .pas con un marcador, y otro fichero
MARCADOR = 'MARCADOR_VICTIMA_J8_no_debe_salir'
UNIT = 'Secreto.pas'
open(os.path.join(VICTIMA, UNIT), 'w', encoding='utf-8').write(
    'unit Secreto;\ninterface\n// %s\nimplementation\nend.\n' % MARCADOR)
open(os.path.join(VICTIMA, 'datos.txt'), 'w', encoding='utf-8').write(MARCADOR + '\n')


def sha_arbol(raiz):
    """Hash estable de todo el arbol (rutas relativas + contenido): para decir
    si la victima quedo intacta."""
    h = hashlib.sha256()
    for dp, _dn, fn in os.walk(raiz):
        for n in sorted(fn):
            p = os.path.join(dp, n)
            h.update(os.path.relpath(p, raiz).lower().encode('utf-8', 'replace'))
            h.update(open(p, 'rb').read())
    return h.hexdigest()


# el destino en forma NT de VOLUMEN por su GUID, del volumen que aloja FUERA
k = ctypes.WinDLL('kernel32', use_last_error=True)
k.GetVolumeNameForVolumeMountPointW.argtypes = [wt.LPCWSTR, wt.LPWSTR, wt.DWORD]
drive = os.path.splitdrive(os.path.abspath(VICTIMA))[0]     # 'C:'
_b = ctypes.create_unicode_buffer(64)
_ok = k.GetVolumeNameForVolumeMountPointW(drive + '\\', _b, 64)   # \\?\Volume{GUID}\
rel = os.path.abspath(VICTIMA)[len(drive) + 1:]            # sin 'C:\'
NT = r'\??\Volume' + _b.value.split('Volume', 1)[1].rstrip('\\') + '\\' + rel if _ok else ''

SKIP = None
creado = bool(NT) and mc.junction_nt(LINK, NT)
entradas = []
if not creado:
    SKIP = 'no se pudo plantar la junction de volumen (GUID=%s NT=%r)' % (_ok, NT)
else:
    try:
        entradas = sorted(os.listdir(LINK))   # EL testigo: Windows la sigue
    except OSError as e:
        entradas = []
        SKIP = 'Windows no sigue la junction de volumen (%r): no es el caso a medir' % e
    if entradas and UNIT not in entradas:
        SKIP = 'la junction no lleva a la victima (entradas=%r)' % entradas

VICT_ANTES = sha_arbol(FUERA)
LISTA_ANTES = sorted(os.listdir(VICTIMA))

if SKIP is None:
    # un fichero normal al lado del enlace, para que la copia TENGA algo que
    # copiar y se vea que solo salta el enlace
    open(os.path.join(CARPETA, 'normal.txt'), 'w', encoding='utf-8').write('soy del workspace\n')
    COPIA = os.path.join(JAIL, 'copia')

    s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='union-volumen', t=180)
    try:
        check('V1 el enlace quedo plantado y Windows lo SIGUE (os.listdir lo lista): '
              'enlace VIVO, el juez es Windows no el texto',
              os.path.isjunction(LINK) and UNIT in entradas, (os.path.isjunction(LINK), entradas[:6]))

        r = s.call('delphi_read', {'path': os.path.join(LINK, UNIT)})
        # la negativa del ENLACE/la jaula, no un NOT_FOUND (si la resolucion del
        # GUID fallara, tambien pasaba; revisor de baterias, 18-oct-2026)
        check('V2 delphi_read de la unit a traves del enlace: NEGADO por la jaula y sin su contenido',
              (mc.es(r, 'SR_JAIL_LINK_FMT') or mc.es(r, 'SR_JAIL_FMT')) and MARCADOR not in r, r[:200])

        r = s.call('delphi_list', {'root': LINK})
        check('V3 delphi_list a traves del enlace: NEGADO por la jaula y sin los nombres de detras',
              (mc.es(r, 'SR_JAIL_LINK_FMT') or mc.es(r, 'SR_JAIL_FMT')) and 'Secreto' not in r
              and MARCADOR not in r, r[:200])

        r = s.call('delphi_move', {'path': CARPETA, 'dest': COPIA, 'copy': True}, t=120)
        # la copia copia lo del workspace y NO sigue el enlace
        copiados = []
        for dp, _dn, fn in os.walk(COPIA):
            copiados += [os.path.relpath(os.path.join(dp, n), COPIA) for n in fn]
        victima_colada = any(os.path.basename(x) == UNIT or 'datos.txt' == os.path.basename(x)
                             for x in copiados)
        check('V4 delphi_move copy=true de la carpeta con el enlace: lo de detras NO se copia '
              '(no seguido) y la copia solo lleva lo del workspace',
              (not mc.fallo(r)) and ('normal.txt' in [os.path.basename(x) for x in copiados])
              and not victima_colada and mc.es(r, 'SN_COPY_LINKS_NOT_FOLLOWED_FMT'),
              'copiados=%r | %s' % (copiados, r[:200]))

        check('V4b la victima de fuera sigue intacta (hash y lista antes == despues)',
              sha_arbol(FUERA) == VICT_ANTES and sorted(os.listdir(VICTIMA)) == LISTA_ANTES,
              'antes=%r despues=%r' % (LISTA_ANTES, sorted(os.listdir(VICTIMA))))
    finally:
        s.cierra()

mc.borra(BASE)
mc.fin('union de volumen por GUID en la jaula 1.19.0 (J8)', sin_checks=SKIP)
