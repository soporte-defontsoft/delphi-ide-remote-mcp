# -*- coding: utf-8 -*-
"""delphi_api (1.29): las APIs HTTP con NOMBRE que define el operador en su fichero de conexiones de APIs
(connections\\apis\\api-connections.json, junto al exe) y abre a cada workspace con ApiAllowedProjects= (aqui, el
modo local: DELPHI_MCP_API_PROJECTS). Un mini Postman generico: el agente pide metodo, ruta, query, cabeceras y
cuerpo; la URL base, la credencial, las cabeceras fijas, el pin y los metodos son del operador.

La bateria levanta sus servidores (hilos de esta misma bateria): un HTTPS con un certificado autofirmado EC propio
(cryptography), un HTTP plano y un puerto cerrado. Cada servidor apunta lo que le LLEGA: una negativa se mide
tambien por el otro lado (no llego nada).

  A1  sin proyectos: tools/list no anuncia delphi_api, tasks dice su clave y la llamada API-002
  A2  connections: las del proyecto permitido con sus metodos; las declaradas mal en unusable con su porque; las
      de otro proyecto en ninguna parte; ninguna URL ni credencial
  A3  GET con pin: 200, el cuerpo JSON como JSON, la query codificada, la cabecera del agente, las fijas y la
      credencial llegan; en la respuesta la credencial va tapada
  A4  POST: JSON como application/json, texto como text/plain, un Content-Type propio manda, form como formulario
  A5  un metodo que la API no permite: API-007, no llega nada
  A6  rutas que salen de la API (.., %2e%2e, host, //, ?, barra invertida): API-008, no llega nada; una con
      espacio y acento llega codificada
  A7  cabeceras del operador, de la credencial, del transporte o con un salto de linea: API-010, no llega nada
  A8  una redireccion vuelve, no se sigue, y su Location sin la direccion del operador
  A9  pin que no casa: API-014 con el pin que presento, no llega nada
  A10 sin pin y un certificado que Windows no acepta: API-013 con su pin, no llega nada
  A11 un cuerpo binario: su nota y sus bytes; out= lo guarda tal cual; un out= fuera de la jaula no llama
  A12 un cuerpo mas largo que una respuesta: truncated y su nota; out= lo guarda entero
  A13 un charset declarado (iso-8859-1) se lee con el
  A14 una API que tarda mas que su timeout: API-012 dentro del plazo
  A15 un 500 vuelve como respuesta, con su cuerpo
  A16 bearer por http: llega su cabecera y la respuesta la tapa
  A17 una clave por query: llega en la URL, no en el path que ve el agente
  A18 credencial de solo lectura (--readonly): GET si; POST y out= negados en la puerta (READ-002)
  A19 un puerto cerrado: API-012
  A20 un parametro que no es del comando: API-016
  A21 ninguna credencial ni la URL base en ninguna respuesta

Uso:  python tests/test_api_129.py [ruta-a-DelphiLspMcp.exe]
"""
import base64
import datetime
import hashlib
import http.server
import io
import json
import os
import socket
import ssl
import threading
import time
import urllib.parse
import mcp_cliente as mc
from mcp_cliente import check

TITULO = 'delphi_api 1.29 (mini Postman)'
try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID
except ImportError:
    print('NOTA: sin el paquete cryptography no hay certificado de prueba: no se mide nada')
    mc.fin(TITULO, sin_checks='sin cryptography en esta maquina')
    raise SystemExit(0)

BASE = mc.carpeta('api_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
FICHERO = os.path.join(SRV, 'connections', 'apis', 'api-connections.json')
LOG = []


def puerto_libre():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def certificado():
    """Un certificado autofirmado EC propio: (pem del cert, pem de la clave, pin SPKI)."""
    clave = ec.generate_private_key(ec.SECP256R1())
    nombre = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'prueba-api-129')])
    ahora = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(nombre).issuer_name(nombre).public_key(clave.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(ahora - datetime.timedelta(days=1))
            .not_valid_after(ahora + datetime.timedelta(days=2)).sign(clave, hashes.SHA256()))
    spki = clave.public_key().public_bytes(serialization.Encoding.DER,
                                           serialization.PublicFormat.SubjectPublicKeyInfo)
    return (cert.public_bytes(serialization.Encoding.PEM),
            clave.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption()),
            'sha256/' + base64.b64encode(hashlib.sha256(spki).digest()).decode())


P_TLS, P_HTTP, P_CERRADO = puerto_libre(), puerto_libre(), puerto_libre()
URL_TLS = 'https://127.0.0.1:%d/api' % P_TLS
URL_HTTP = 'http://127.0.0.1:%d/v2' % P_HTTP
BINARIO = bytes(range(256)) * 4
GRANDE = ('{"x": "' + 'abcdefghij' * 9000 + '"}')
LATIN1 = chr(0xD1) + 'and' + chr(0xFA)
ACENTO = 'hola ' + chr(0xE1)


class Eco(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def _manda(self, estado, cuerpo, tipo, extra=None):
        self.send_response(estado)
        self.send_header('Content-Type', tipo)
        self.send_header('Content-Length', str(len(cuerpo)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(cuerpo)

    def _todo(self):
        n = int(self.headers.get('Content-Length') or 0)
        cuerpo = self.rfile.read(n) if n else b''
        LOG.append({'method': self.command, 'path': self.path, 'headers': dict(self.headers), 'body': cuerpo,
                    'tipos': self.headers.get_all('Content-Type') or []})
        ruta = urllib.parse.urlsplit(self.path).path
        if ruta.endswith('/redir'):
            return self._manda(302, b'', 'text/plain', {'Location': URL_TLS + '/eco'})
        if ruta.endswith('/binario'):
            return self._manda(200, BINARIO, 'application/octet-stream')
        if ruta.endswith('/grande'):
            return self._manda(200, GRANDE.encode(), 'application/json')
        if ruta.endswith('/latin1'):
            return self._manda(200, LATIN1.encode('latin-1'), 'text/plain; charset=iso-8859-1')
        if ruta.endswith('/lento'):
            time.sleep(6)
            return self._manda(200, b'tarde', 'text/plain')
        if ruta.endswith('/fallo'):
            return self._manda(500, b'{"error": "roto"}', 'application/json')
        eco = {'method': self.command, 'path': self.path, 'headers': dict(self.headers),
               'body': cuerpo.decode('utf-8', 'replace')}
        self._manda(200, json.dumps(eco).encode(), 'application/json')

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = _todo

    def log_message(self, *a):
        pass


CERT_A, CLAVE_A, PIN_A = certificado()
PIN_B = certificado()[2]
io.open(os.path.join(BASE, 'a.crt'), 'wb').write(CERT_A)
io.open(os.path.join(BASE, 'a.key'), 'wb').write(CLAVE_A)
tls = http.server.ThreadingHTTPServer(('127.0.0.1', P_TLS), Eco)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(os.path.join(BASE, 'a.crt'), os.path.join(BASE, 'a.key'))
tls.socket = ctx.wrap_socket(tls.socket, server_side=True)
plano = http.server.ThreadingHTTPServer(('127.0.0.1', P_HTTP), Eco)
for s in (tls, plano):
    threading.Thread(target=s.serve_forever, daemon=True).start()

SECRETOS = ['usuario-129', 'clave-secreta-129', 'clave-api-secreta-129', 'token-secreto-129', 'clave-query-129',
            base64.b64encode(b'usuario-129:clave-secreta-129').decode(), URL_TLS, URL_HTTP]
BASICA = {'type': 'basic', 'user': 'usuario-129', 'password': 'clave-secreta-129'}
CLAVE = {'type': 'header', 'name': 'X-Api-Key', 'value': 'clave-api-secreta-129'}
TODOS = ['GET', 'POST', 'PUT', 'DELETE']


def api(url, **kw):
    e = {'baseUrl': url, 'methods': TODOS}
    e.update(kw)
    return {k: v for k, v in e.items() if v is not None}


CONEXIONES = {'api-connections': {'projects': {
    'pruebas': {'apis': {
        'eco': api(URL_TLS, pin=PIN_A, auth=[BASICA, CLAVE], headers={'X-Fija': 'fija-129'}),
        'solo_get': api(URL_TLS, pin=PIN_A, methods=['get']),
        'pin_malo': api(URL_TLS, pin=PIN_B),
        'sin_pin': api(URL_TLS),
        'lenta': api(URL_TLS, pin=PIN_A, timeout=2),
        'portador': api(URL_HTTP, auth={'type': 'bearer', 'token': 'token-secreto-129'},
                        headers={'Content-Type': 'application/xml'}),
        'consulta': api(URL_HTTP, auth={'type': 'query', 'name': 'api_key', 'value': 'clave-query-129'}),
        'cerrada': api('http://127.0.0.1:%d' % P_CERRADO),
        'sin_metodos': api(URL_TLS, methods=None),
        'url_mala': api('ftp://127.0.0.1/x'),
        'pin_mal': api(URL_TLS, pin='sha256/no-es-un-pin'),
        'auth_mala': api(URL_TLS, auth={'type': 'oauth'}),
        'plazo_malo': api(URL_TLS, timeout=0),
        # CH2 del revisor de la 1.29: un pin sobre http no comprueba nada y el POST salia en claro con su credencial
        'pin_http': api(URL_HTTP, pin=PIN_A, methods=['post'], auth={'type': 'bearer', 'token': 'token-pin-http-129'})}},
    'ajeno': {'apis': {'oculta': api(URL_TLS)}}}}}
os.makedirs(os.path.dirname(FICHERO))
io.open(FICHERO, 'w', encoding='utf-8').write(json.dumps(CONEXIONES, indent=2))

respuestas = []
srv = None


def llama(s, args, t=None):
    r = s.call('delphi_api', args, t)
    respuestas.append(r)
    return r


def anunciadas(s):
    r = s.request('tools/list') or {}
    return {t['name'] for t in (r.get('result') or {}).get('tools', [])}


def llegaron(desde):
    return LOG[desde:]


try:
    cat = mc.catalogo()
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='api-sin', t=60)
    a = anunciadas(srv)
    t = srv.call('delphi_help', {'command': 'tasks'})
    r = llama(srv, {'command': 'connections'})
    check('A1 sin proyectos: tools/list no anuncia delphi_api, tasks dice su clave y la llamada API-002',
          'delphi_help' in a and 'delphi_api' not in a and cat['SF_HELP_SIN_DESTINO_API'] in t
          and mc.abre(r, 'SR_API_SIN_PROYECTOS'), (t[-300:], r[:300]))
    srv.cierra()

    ENV = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_API_PROJECTS': 'pruebas'})
    srv = mc.Stdio(EXE, ENV, nombre='api', t=120)

    def pide(alias, **kw):
        return llama(srv, dict({'command': 'request', 'api': 'pruebas/' + alias}, **kw), 60)

    r = llama(srv, {'command': 'connections'})
    j = mc.como_json(r)
    apis = {x.get('api'): x.get('methods') for x in j.get('apis', [])}
    malas = {x.get('api'): x.get('why', '') for x in j.get('unusable', [])}
    check('A2 connections: las buenas con sus metodos (en mayusculas)',
          set(apis) == {'pruebas/' + n for n in ('eco', 'solo_get', 'pin_malo', 'sin_pin', 'lenta', 'portador',
                                                 'consulta', 'cerrada')}
          and apis['pruebas/solo_get'] == ['GET'] and apis['pruebas/eco'] == TODOS
          and mc.es(j.get('note', ''), 'SN_API_CONNECTIONS'), r[:600])
    check('A2 ...las declaradas mal en unusable con su porque, y ninguna de otro proyecto',
          malas == {'pruebas/sin_metodos': cat['SF_API_DEF_METODOS'], 'pruebas/url_mala': cat['SF_API_DEF_URL'],
                    'pruebas/pin_mal': cat['SF_API_DEF_PIN'], 'pruebas/auth_mala': cat['SF_API_DEF_AUTH_FMT'] % 'oauth',
                    'pruebas/plazo_malo': cat['SF_API_DEF_PLAZO'],
                    'pruebas/pin_http': cat['SF_API_DEF_PIN_SIN_TLS']} and 'ajeno' not in r, malas)
    n = len(LOG)
    r = pide('pin_http', method='POST', path='eco', body='{}')
    check('A2b CH2 un pin con baseUrl http: la entrada no se usa y al servidor no llega nada (llegaba con su token)',
          mc.rechazado(r) and not llegaron(n) and 'token-pin-http-129' not in r, (r[:300], llegaron(n)))

    n = len(LOG)
    r = pide('eco', path='eco', query=[{'name': 'q', 'value': 'a b&c'}], headers=[{'name': 'X-Mio', 'value': '1'}])
    j = mc.como_json(r)
    vio = (llegaron(n) or [{}])[0]
    cab = {k.lower(): v for k, v in vio.get('headers', {}).items()}
    check('A3 GET con pin: 200 y el cuerpo JSON como JSON',
          j.get('status') == 200 and isinstance(j.get('body'), dict) and j.get('path') == '/eco?q=a+b%26c',
          r[:500])
    check('A3 ...al servidor llegan la ruta bajo la base, la query, la del agente, la fija y la credencial',
          vio.get('path') == '/api/eco?q=a+b%26c' and cab.get('x-mio') == '1' and cab.get('x-fija') == 'fija-129'
          and cab.get('authorization') == 'Basic ' + SECRETOS[5] and cab.get('x-api-key') == SECRETOS[2],
          (vio.get('path'), sorted(cab)))
    eco_cab = {k.lower(): v for k, v in (j.get('body') or {}).get('headers', {}).items()}
    check('A3 ...y en la respuesta (el eco de las cabeceras) la credencial va tapada',
          eco_cab.get('authorization') == 'Basic <pruebas/eco>' and eco_cab.get('x-api-key') == '<pruebas/eco>',
          eco_cab)

    casos = [('JSON', {'body': '{"a": 1}'}, 'application/json', b'{"a": 1}'),
             ('texto', {'body': ACENTO}, 'text/plain; charset=utf-8', ACENTO.encode()),
             ('Content-Type propio', {'body': '{"a": 1}', 'headers': [{'name': 'Content-Type',
                                                                       'value': 'application/vnd.x+json'}]},
              'application/vnd.x+json', b'{"a": 1}'),
             ('form', {'form': [{'name': 'a', 'value': '1'}, {'name': 'b', 'value': 'x y&z'}]},
              'application/x-www-form-urlencoded', b'a=1&b=x+y%26z')]
    for nombre, extra, tipo, cuerpo in casos:
        n = len(LOG)
        r = pide('eco', method='post', path='eco', **extra)
        vio = (llegaron(n) or [{}])[0]
        cab = {k.lower(): v for k, v in vio.get('headers', {}).items()}
        check('A4 POST %s: llega como %s' % (nombre, tipo),
              mc.como_json(r).get('status') == 200 and vio.get('method') == 'POST'
              and cab.get('content-type') == tipo and vio.get('body') == cuerpo, (r[:200], cab.get('content-type'),
                                                                                 vio.get('body')))
    n = len(LOG)
    r = pide('eco', body='x', form=[{'name': 'a', 'value': '1'}], method='POST')
    check('A4 body y form a la vez: API-011, no llega nada', mc.abre(r, 'SR_API_CUERPO_Y_FORM') and not llegaron(n),
          r[:300])

    n = len(LOG)
    r = pide('solo_get', method='POST', path='eco')
    check('A5 un metodo que la API no permite: API-007, no llega nada',
          mc.abre(r, 'SR_API_METODO_FMT') and not llegaron(n), r[:300])

    for ruta in ('../x', 'a/../../x', '%2e%2e/x', 'a/%2E%2e/x', 'https://otro/x', '//otro/x', 'a?b=1', 'a#b',
                 'a\\b', 'a/%2fb'):
        n = len(LOG)
        r = pide('eco', path=ruta)
        check('A6 la ruta %r sale de la API: API-008, no llega nada' % ruta,
              mc.abre(r, 'SR_API_RUTA_FMT') and not llegaron(n), r[:300])
    n = len(LOG)
    r = pide('eco', path='clientes/Jos' + chr(0xE9) + ' Garc' + chr(0xED) + 'a')
    check('A6 una ruta con espacio y acento llega codificada en UTF-8',
          mc.como_json(r).get('status') == 200
          and (llegaron(n) or [{}])[0].get('path') == '/api/clientes/Jos%C3%A9%20Garc%C3%ADa', r[:300])

    for nombre, valor, sf in (('Authorization', 'Basic x', 'SF_API_CABECERA_DEL_OPERADOR'),
                              ('x-api-key', 'robada', 'SF_API_CABECERA_DEL_OPERADOR'),
                              ('X-Fija', 'otra', 'SF_API_CABECERA_DEL_OPERADOR'),
                              ('Host', 'otro', 'SF_API_CABECERA_DEL_OPERADOR'),
                              ('Content-Length', '3', 'SF_API_CABECERA_DEL_OPERADOR'),
                              ('X-Ok', 'a\r\nX-Inyectada: 1', 'SF_API_CABECERA_MAL'),
                              ('X Mal', '1', 'SF_API_CABECERA_MAL')):
        n = len(LOG)
        r = pide('eco', path='eco', headers=[{'name': nombre, 'value': valor}])
        check('A7 la cabecera %r: API-010, no llega nada' % nombre,
              mc.abre(r, 'SR_API_CABECERA_FMT') and cat[sf] in r and not llegaron(n), r[:300])

    n = len(LOG)
    r = pide('eco', path='redir')
    j = mc.como_json(r)
    check('A8 una redireccion vuelve sin seguirse, y su Location sin la direccion del operador',
          j.get('status') == 302 and len(llegaron(n)) == 1
          and (j.get('headers') or {}).get('Location') == '<pruebas/eco>/eco', r[:400])

    n = len(LOG)
    r = pide('pin_malo', path='eco')
    check('A9 un pin que no casa: API-014 con el pin que presento, no llega nada',
          mc.abre(r, 'SR_API_PIN_FMT') and PIN_A in r and not llegaron(n), r[:400])
    n = len(LOG)
    r = pide('sin_pin', path='eco')
    check('A10 sin pin y un autofirmado: API-013 con su pin, no llega nada',
          mc.abre(r, 'SR_API_CERTIFICADO_FMT') and PIN_A in r and not llegaron(n), r[:400])

    r = pide('eco', path='binario')
    j = mc.como_json(r)
    check('A11 un cuerpo binario: su nota y sus bytes, sin body',
          j.get('bytes') == len(BINARIO) and 'body' not in j and mc.es(j.get('note', ''), 'SN_API_BINARIO_FMT'), r[:300])
    salida = os.path.join(JAIL, 'b.bin')
    r = pide('eco', path='binario', out=salida)
    check('A11 ...out= lo guarda tal cual', os.path.isfile(salida) and open(salida, 'rb').read() == BINARIO, r[:300])
    fuera = os.path.join(BASE, 'fuera.bin')
    n = len(LOG)
    r = pide('eco', path='binario', out=fuera)
    check('A11 ...un out= fuera de la jaula se niega antes de llamar',
          mc.fallo(r) and not os.path.exists(fuera) and not llegaron(n), r[:300])

    r = pide('eco', path='grande')
    j = mc.como_json(r)
    check('A12 un cuerpo mas largo que una respuesta: truncated, su nota y su principio',
          j.get('truncated') is True and mc.es(j.get('note', ''), 'SN_API_RECORTADO')
          and isinstance(j.get('body'), str) and GRANDE.startswith(j.get('body', '-')) and j.get('bytes') == len(GRANDE),
          r[:200])
    salida = os.path.join(JAIL, 'grande.json')
    pide('eco', path='grande', out=salida)
    check('A12 ...out= lo guarda entero', os.path.isfile(salida) and open(salida, 'rb').read() == GRANDE.encode(),
          os.path.getsize(salida) if os.path.isfile(salida) else None)

    r = pide('eco', path='latin1')
    check('A13 un charset declarado se lee con el', mc.como_json(r).get('body') == LATIN1, r[:300])

    t0 = time.time()
    r = pide('lenta', path='lento')
    seg = time.time() - t0
    # el plazo lo pone el servidor: el de WinHTTP, con 2 s, contestaba a los 4 aislado y en esta misma tanda unas
    # veces a los 2,5 y otras nunca (6 s y un 200; medido el 6-nov-2026)
    check('A14 una API que tarda mas que su timeout (2 s): API-012 con su plazo, a los 2 s (%.1f s)' % seg,
          mc.abre(r, 'SR_API_NO_RESPONDE_FMT') and cat['SF_API_PLAZO_FMT'] % 2 in r and seg < 3.5,
          (round(seg, 1), r[:300]))

    r = pide('eco', path='fallo')
    j = mc.como_json(r)
    check('A15 un 500 vuelve como respuesta, con su cuerpo',
          j.get('status') == 500 and (j.get('body') or {}).get('error') == 'roto', r[:300])

    n = len(LOG)
    r = pide('portador', path='eco')
    vio = (llegaron(n) or [{}])[0]
    cab = {k.lower(): v for k, v in vio.get('headers', {}).items()}
    check('A16 bearer por http: llega su cabecera y la respuesta la tapa',
          cab.get('authorization') == 'Bearer token-secreto-129' and 'token-secreto-129' not in r
          and '<pruebas/portador>' in r, (cab.get('authorization'), r[:300]))

    n = len(LOG)
    r = pide('portador', method='POST', path='eco', body='{"a": 1}')
    vio = (llegaron(n) or [{}])[0]
    check('A16 un Content-Type fijo del operador: llega ese y solo ese, no tambien el de un cuerpo JSON',
          vio.get('tipos') == ['application/xml'] and vio.get('body') == b'{"a": 1}', (vio.get('tipos'), r[:200]))

    n = len(LOG)
    r = pide('consulta', path='eco', query=[{'name': 'x', 'value': '1'}])
    vio = (llegaron(n) or [{}])[0]
    check('A17 una clave por query: llega en la URL y no en el path que ve el agente',
          vio.get('path') == '/v2/eco?x=1&api_key=clave-query-129' and mc.como_json(r).get('path') == '/eco?x=1',
          (vio.get('path'), r[:300]))

    r = llama(srv, {'command': 'connections', 'api': 'pruebas/eco'})
    check('A20 un parametro que no es del comando: API-016', mc.abre(r, 'SR_API_NO_VA_CON_COMANDO_FMT'), r[:300])
    r = pide('cerrada', path='x')
    check('A19 un puerto cerrado: API-012', mc.abre(r, 'SR_API_NO_RESPONDE_FMT'), r[:300])
    srv.cierra()

    srv = mc.Stdio(EXE, ENV, nombre='api-ro', args=('--readonly',), t=120)
    r = llama(srv, {'command': 'request', 'api': 'pruebas/eco', 'path': 'eco'}, 60)
    check('A18 --readonly: un GET si', mc.como_json(r).get('status') == 200, r[:300])
    for extra in ({'method': 'POST', 'body': 'x'}, {'out': os.path.join(JAIL, 'ro.json')}):
        n = len(LOG)
        r = llama(srv, dict({'command': 'request', 'api': 'pruebas/eco', 'path': 'eco'}, **extra), 60)
        check('A18 --readonly: %s negado en la puerta (READ-002), no llega nada' % list(extra)[0],
              mc.abre(r, 'SR_READ_ONLY_FMT') and not llegaron(n), r[:300])
    fug = sorted({i for i, s in enumerate(SECRETOS) for x in respuestas if s and s.lower() in x.lower()})
    check('A21 ninguna credencial ni URL base en ninguna respuesta (%d respuestas)' % len(respuestas), not fug,
          'secretos que aparecen: posiciones %s de %d' % (fug, len(SECRETOS)))
finally:
    if srv:
        srv.cierra()
    for s in (tls, plano):
        s.shutdown()
        s.server_close()
    mc.borra(BASE)
mc.fin(TITULO)
