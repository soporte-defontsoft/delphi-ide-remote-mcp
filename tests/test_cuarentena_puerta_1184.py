# -*- coding: utf-8 -*-
"""2t de la 1.18.x (1.18.4): la cuarentena de delphi_upload (un fichero cuyo
sha final no casa se aparta como <nombre>.corrupt) movia y borraba con
primitivas crudas sobre un destino DERIVADO que la puerta no habia visto: la
puerta del upload juzga <nombre>, no <nombre>.corrupt.

  Q1 ReadOnlyPaths nombra <nombre>.corrupt: una subida con el sha mal lo
     borraba y lo sustituia por la subida mala -> intacto, el malo se queda
     con su nombre y el error lo dice: UPLOAD-012 (ROJO en produccion; el
     error decia "lo aparte en <nombre>" tambien cuando no pudo apartarlo)
  Q2 control: sin nada protegido la cuarentena funciona como siempre y la de
     antes va a la papelera (F3 de test_round9)

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


# Q1: la cuarentena de antes, declarada de solo lectura
F1 = os.path.join(JAIL, 'q1.bin')
Q1 = F1 + '.corrupt'
open(Q1, 'wb').write(b'PROTEGIDO')
s = lanza(Q1)
try:
    j = sube(s, F1, b'MALO')
    check('Q1 un .corrupt de ReadOnlyPaths: la cuarentena no lo toca y el malo se queda con su nombre',
          open(Q1, 'rb').read() == b'PROTEGIDO' and os.path.isfile(F1) and 'quarantined' not in j
          and 'UPLOAD-012' in j.get('error', ''),
          (open(Q1, 'rb').read(), os.path.isfile(F1), str(j)[:300]))
finally:
    s.cierra()

# Q2: control, sin nada protegido
F2 = os.path.join(JAIL, 'q2.bin')
Q2 = F2 + '.corrupt'
s = lanza()
try:
    sube(s, F2, b'AAA')
    j = sube(s, F2, b'BBB')
    previas = [f for f in mc.copias(JAIL, os.path.basename(Q2), 'CAJON_SUSTITUIDOS')
               if open(f, 'rb').read() == b'AAA']
    check('Q2 control: sin nada protegido la cuarentena aparta la subida mala y la de antes va a la papelera',
          'quarantined' in j and open(Q2, 'rb').read() == b'BBB' and not os.path.exists(F2)
          and len(previas) >= 1,
          (str(j)[:300], previas))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('puerta de la cuarentena del upload 1184')
