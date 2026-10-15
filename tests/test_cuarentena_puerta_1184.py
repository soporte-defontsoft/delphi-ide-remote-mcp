# -*- coding: utf-8 -*-
"""2t de la 1.18.x (1.18.4): la cuarentena de delphi_upload (un fichero cuyo
sha final no casa) movia y borraba con primitivas crudas sobre un destino
DERIVADO que la puerta no habia visto: la puerta del upload juzgaba <nombre>,
no <nombre>.corrupt. Desde la A de la 1.19.2 la subida mala ya no va a un
<nombre>.corrupt al lado: va a la PAPELERA, sellada en su cajon (corrupt), por
el nombrador de las copias, que pasa la puerta de escribir sobre la ruta real
(TrashPathFor). Lo que esta bateria protege sigue igual: la cuarentena solo
escribe donde la puerta aprobo.

  Q1 un <nombre>.corrupt de ReadOnlyPaths (de antes): la cuarentena ni lo toca
     ni lo usa; la subida mala va a la papelera
  Q2 control: dos subidas malas, dos copias selladas en el cajon de lo
     corrupto, y nada al lado (F3 de test_round9)
  Q3 la papelera de solo lectura (ReadOnlyPaths): la cuarentena no escribe
     alli; el malo se queda con su nombre y el error lo dice: UPLOAD-012

Uso:  python tests/test_cuarentena_puerta_1184.py [ruta-a-DelphiLspMcp.exe]
"""
import base64, json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('cuarentena_puerta_1184')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def lanza(solo=''):
    env = {'DELPHI_MCP_ROOTS': JAIL}
    if solo:
        env['DELPHI_MCP_READONLY_PATHS'] = solo
    return mc.Stdio(EXE, mc.entorno(env), nombre='cuarentena', t=120)


def sube(s, ruta, datos):
    r = s.call('delphi_upload', {'path': ruta, 'chunkbase64': base64.b64encode(datos).decode(),
                                 'offset': 0, 'sha256': '0' * 64})
    try:
        return json.loads(r)
    except ValueError:
        return {'texto': r}


# Q1: un .corrupt de antes, declarado de solo lectura
D1 = os.path.join(JAIL, 'q1')
os.makedirs(D1)
F1 = os.path.join(D1, 'q1.bin')
Q1 = F1 + '.corrupt'
open(Q1, 'wb').write(b'PROTEGIDO')
s = lanza(Q1)
try:
    j = sube(s, F1, b'MALO')
    check('Q1 un .corrupt de ReadOnlyPaths: la cuarentena no lo toca; la subida mala va a la papelera',
          open(Q1, 'rb').read() == b'PROTEGIDO' and not os.path.exists(F1) and 'quarantined' in j
          and [open(c, 'rb').read() for c in mc.copias(D1, 'q1.bin', 'CAJON_CORRUPTOS')] == [b'MALO'],
          (open(Q1, 'rb').read(), os.path.exists(F1), str(j)[:300]))
finally:
    s.cierra()

# Q2: control, sin nada protegido
D2 = os.path.join(JAIL, 'q2')
os.makedirs(D2)
F2 = os.path.join(D2, 'q2.bin')
s = lanza()
try:
    sube(s, F2, b'AAA')
    j = sube(s, F2, b'BBB')
    copias = sorted(open(c, 'rb').read() for c in mc.copias(D2, 'q2.bin', 'CAJON_CORRUPTOS'))
    check('Q2 control: dos subidas malas, dos copias en el cajon de lo corrupto y nada al lado',
          'quarantined' in j and copias == [b'AAA', b'BBB'] and not os.path.exists(F2)
          and not os.path.exists(F2 + '.corrupt'), (str(j)[:300], copias))
finally:
    s.cierra()

# Q3: la papelera de esa carpeta, de solo lectura
D3 = os.path.join(JAIL, 'q3')
os.makedirs(os.path.join(D3, mc.PAPELERA))
F3 = os.path.join(D3, 'q3.bin')
s = lanza(os.path.join(D3, mc.PAPELERA))
try:
    j = sube(s, F3, b'MALO')
    check('Q3 la papelera de solo lectura: la cuarentena no escribe alli, el malo se queda con su nombre (UPLOAD-012)',
          'UPLOAD-012' in j.get('error', '') and 'quarantined' not in j and open(F3, 'rb').read() == b'MALO'
          and mc.copias(D3, 'q3.bin', 'CAJON_CORRUPTOS') == [], str(j)[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('puerta de la cuarentena del upload 1184')
