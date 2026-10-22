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
  K6 (1.22.0) el fichero ENTERO en una llamada con el sha mal, sobre el bueno: UPLOAD-015, no
     se escribe nada (el bueno sigue con su nombre) y no hay copia nueva en ningun cajon. Antes
     se escribia, el bueno iba a la papelera y lo subido se apartaba: el fichero dejaba de
     estar con su nombre (test completo de Hermes; ROJO contra rel1220j)
  K7 (1.22.0) a trozos sobre el bueno con el sha mal: UPLOAD-011 dice como volver al de antes
     (delphi_move de la copia que nombro "backup"), y siguiendo el mensaje vuelve byte a
     byte (ROJO contra rel1220j en el mensaje)

Las subidas malas de K1-K3 van a TROZOS (mc.subida_en_dos): con el fichero entero en una
llamada, desde la 1.22.0, no se escribe nada y no hay cuarentena que medir.

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
    """A trozos (dos llamadas): la respuesta de la ultima."""
    for a in mc.subida_en_dos(F, datos, sha):
        r = s.call('delphi_upload', a)
    try:
        return json.loads(r), r
    except ValueError:
        return {}, r


def cajones():
    """Las copias de carga.bin en los cajones de lo corrupto y lo sustituido."""
    return (len(mc.copias(DIR, 'carga.bin', 'CAJON_CORRUPTOS')), len(mc.copias(DIR, 'carga.bin', 'CAJON_SUSTITUIDOS')))


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

    antes = cajones()
    r = s.call('delphi_upload', {'path': F, 'chunkbase64': base64.b64encode(b'MALO-3').decode(),
                                 'offset': 0, 'sha256': '0' * 64})
    check('K6 entero en una llamada con el sha mal: UPLOAD-015, nada escrito y el bueno sigue con su nombre',
          mc.rechazado(r) and mc.es(r, 'SR_UPLOAD_SHA_ENTERO_MISMATCH_FMT') and open(F, 'rb').read() == bueno
          and cajones() == antes, (r[:300], cajones(), antes))

    a1, a2 = mc.subida_en_dos(F, b'MALO-4', '0' * 64)
    j1 = mc.como_json(s.call('delphi_upload', a1)) or {}
    r = s.call('delphi_upload', a2)
    copia = j1.get('backup', '')
    check('K7 a trozos sobre el bueno con el sha mal: UPLOAD-011 dice como volver al de antes',
          'UPLOAD-011' in r and 'delphi_move' in r and 'backup' in r and copia != '' and not os.path.exists(F),
          (r[:400], copia))
    r = s.call('delphi_move', {'path': copia, 'dest': F})
    check('K7 ...y siguiendo el mensaje vuelve byte a byte',
          os.path.exists(F) and open(F, 'rb').read() == bueno, r[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('upload: la subida mala a la papelera 1.19.2 (A)')
