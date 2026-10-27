# -*- coding: utf-8 -*-
"""V67 de la 1.23.1: un borrado con comodin se recupera de UNA llamada.

delphi_delete con un comodin (Form1.*) decia, por cada copia, "To recover it:
delphi_move with path=that copy"; para un lote eran N llamadas. Sugerencia del
dirigido de Qwen3.8 Flash Next en Hermes (26-oct). Ahora, si el patron de su
cajon de la papelera (la mascara + "-*", que delphi_move devuelve a su nombre)
recoge EXACTAMENTE las copias del lote - lo pregunta EL lector de los comodines,
el mismo del move -, la respuesta lo da (FILE-052); si recogeria otras copias
del dia, no lo ofrece.

  L1 tres ficheros con UMain.*: FILE-052 con un path de la papelera UMain.*-*
  L2 ...ese move los devuelve los tres con su nombre
  L3 con una copia ANTERIOR del dia que casa con la mascara: sin FILE-052
  C1 control: un borrado de UN fichero, sin FILE-052 (su "To recover it" basta)

Uso:  python tests/test_borrar_lote_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('borrar_lote_1231')
JAIL = os.path.join(BASE, 'jail')
DIR = os.path.join(JAIL, 'app')
os.makedirs(DIR)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='borrar-lote', t=120)
NOMBRES = ('UMain.pas', 'UMain.dfm', 'UMain.txt')


def planta():
    for n in NOMBRES:
        open(os.path.join(DIR, n), 'w', encoding='utf-8').write('contenido de %s\n' % n)


def patron_de(r):
    # la llamada que da FILE-052, tal cual (con sus unidades virtuales: el
    # servidor las entiende de vuelta)
    m = re.search(r'path=(\S+) dest=(\S+) \(', r)
    return (m.group(1), m.group(2)) if m else ('', '')


try:
    planta()
    r = s.call('delphi_delete', {'path': os.path.join(DIR, 'UMain.*')})
    pat, dest = patron_de(r) if mc.es(r, 'SN_FILE_RECUPERA_LOTE_FMT') else ('', '')
    check('L1 tres con UMain.*: FILE-052 con un path de la papelera que acaba en UMain.*-* (ROJO contra 1.23.x)',
          not mc.rechazado(r) and pat.endswith('UMain.*-*') and mc.PAPELERA in pat, r[-700:])
    m = s.call('delphi_move', {'path': pat, 'dest': dest}) if pat else ''
    vuelven = all(os.path.isfile(os.path.join(DIR, n)) for n in NOMBRES)
    check('L2 ...ese move los devuelve los tres con su nombre', bool(pat) and vuelven and not mc.rechazado(m),
          (m[:400], os.listdir(DIR)))

    # una copia ANTERIOR del dia que casa con la mascara: el patron recogeria de mas
    if not vuelven:
        planta()
    s.call('delphi_delete', {'path': os.path.join(DIR, 'UMain.txt')})
    open(os.path.join(DIR, 'UMain.txt'), 'w', encoding='utf-8').write('otra vez\n')
    r = s.call('delphi_delete', {'path': os.path.join(DIR, 'UMain.*')})
    check('L3 con una copia anterior del dia que casa con la mascara: sin FILE-052 (recogeria de mas)',
          not mc.rechazado(r) and not mc.es(r, 'SN_FILE_RECUPERA_LOTE_FMT')
          and r.count(mc.id_de('SK_FILE_BORRADO_PAPELERA_FMT')) == 3, r[-600:])

    open(os.path.join(DIR, 'Suelto.pas'), 'w', encoding='utf-8').write('x\n')
    r = s.call('delphi_delete', {'path': os.path.join(DIR, 'Suelto.pas')})
    check('C1 control: UN fichero, sin FILE-052 (su "To recover it" basta)',
          not mc.rechazado(r) and not mc.es(r, 'SN_FILE_RECUPERA_LOTE_FMT') and mc.es(r, 'SK_FILE_BORRADO_PAPELERA_FMT'),
          r[:400])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('delphi_delete: un lote se recupera de una llamada 1.23.1 (V67)')
