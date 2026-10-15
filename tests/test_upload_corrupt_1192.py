# -*- coding: utf-8 -*-
"""A de la 1.19.2 (Hermes sobre la 1.19.1, informe 115312): una subida cuyo
sha256 final no casa se apartaba como "<nombre>.corrupt" AL LADO, en la carpeta
viva, compuesto a mano: se quedaba para siempre (tambien tras volver a subirlo
bien), salia en delphi_list como un fichero mas y `git add .` se lo llevaba.
Ahora va a la PAPELERA, sellada en su cajon (corrupt) por el nombrador de las
copias, como lo que pisa una subida (replaced): recuperable, fuera de los
listados y de git.

  K1 una subida con el sha mal: UPLOAD-011, "quarantined" en la papelera
     (__delphi-patch, cajon corrupt), nada publicado con su nombre y ningun
     <nombre>.corrupt al lado (ROJO en produccion)
  K2 la copia de la papelera tiene los bytes de la subida mala
  K3 otra subida mala: su copia es otra, la primera sigue
  K4 subida buena despues: verified, publicada, y la carpeta sin .corrupt (ROJO)
  K5 delphi_list de la carpeta: solo el fichero bueno

Uso:  python tests/test_upload_corrupt_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import base64, hashlib, json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('upload_corrupt_1192')
JAIL = os.path.join(BASE, 'jail')
DIR = os.path.join(JAIL, 'datos')
os.makedirs(DIR)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='upload-corrupt', t=120)
F = os.path.join(DIR, 'carga.bin')


def sube(datos, sha):
    r = s.call('delphi_upload', {'path': F, 'chunkbase64': base64.b64encode(datos).decode(),
                                 'offset': 0, 'sha256': sha})
    try:
        return json.loads(r), r
    except ValueError:
        return {}, r


def corruptos():
    """Lo que hay al lado del fichero con .corrupt en el nombre."""
    return [n for n in os.listdir(DIR) if '.corrupt' in n]


try:
    j, r = sube(b'MALO-1', '0' * 64)
    q1 = str(j.get('quarantined', ''))
    check('K1 sha mal: UPLOAD-011, a la papelera (cajon corrupt), nada publicado y ningun .corrupt al lado',
          'UPLOAD-011' in r and ('\\%s\\' % mc.PAPELERA) in q1 and ('\\%s\\' % mc.CAJON_CORRUPTOS) in q1
          and not os.path.exists(F)
          and corruptos() == [], (r[:400], corruptos()))
    copias = mc.copias(DIR, 'carga.bin', 'CAJON_CORRUPTOS')
    check('K2 la copia de la papelera tiene los bytes de la subida mala',
          any(open(c, 'rb').read() == b'MALO-1' for c in copias), copias)
    sube(b'MALO-2', '0' * 64)
    copias = mc.copias(DIR, 'carga.bin', 'CAJON_CORRUPTOS')
    contenidos = sorted(open(c, 'rb').read() for c in copias)
    check('K3 otra subida mala: su copia es otra y la primera sigue',
          contenidos == [b'MALO-1', b'MALO-2'], contenidos)
    bueno = b'BUENO'
    j, r = sube(bueno, hashlib.sha256(bueno).hexdigest())
    check('K4 subida buena: verified, publicada, y la carpeta sin .corrupt',
          j.get('verified') is True and open(F, 'rb').read() == bueno and corruptos() == [], (r[:300], corruptos()))
    lista = s.call('delphi_list', {'root': DIR, 'pattern': '*'})
    check('K5 delphi_list de la carpeta: solo el fichero bueno',
          'carga.bin' in lista and '.corrupt' not in lista and 'MALO' not in lista, lista[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('upload: la subida mala a la papelera 1.19.2 (A)')
