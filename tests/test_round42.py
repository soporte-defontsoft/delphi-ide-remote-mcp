# -*- coding: utf-8 -*-
"""E2E battery: la respuesta del motor puede venir de OTRO workspace.

El indice del motor le sobrevive al servidor. Una unit SIN CONFIGURAR (sin
.delphilsp.json ni .dproj cerca) se resuelve contra otra unit del mismo
nombre que el motor indexo en una sesion anterior - de otro proceso, de otra
jaula, de otro usuario del servidor.

Esa ruta ajena se daba por buena y viajaba hasta el primer sitio que tocaba
la jaula, donde reventaba la llamada ENTERA con un RECHAZADO... que escupia
la ruta. Dos fallos en el mismo punto: una respuesta imposible (buscar los
usos de un simbolo que no es el tuyo) y una fuga (el que pregunta se entera
de que hay otro workspace y de como se llama su carpeta).

La bateria monta la contaminacion a proposito: jaula A indexa el nombre,
jaula B pregunta por el mismo nombre.

Usage:  python tests/test_round42.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:300])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round42')


def borra(d):
    def alafuerza(func, path, _exc):
        try:
            os.chmod(path, 0o700)
            func(path)
        except Exception:
            pass
    shutil.rmtree(d, onexc=alafuerza) if sys.version_info >= (3, 12) else \
        shutil.rmtree(d, onerror=alafuerza)


if os.path.isdir(BASE):
    borra(BASE)

# Unico por pasada: lo que se mide es la contaminacion que monta ESTA
# bateria entre sus dos jaulas, no la que dejaron las anteriores.
IDENT = 'Cruza' + uuid.uuid4().hex[:8]

UNIT = """unit Cru;

interface

type
  TCosa = class
    procedure %s;
  end;

implementation

procedure TCosa.%s;
begin
end;

procedure Usa;
var
  C: TCosa;
begin
  C := TCosa.Create;
  C.%s;
  C.Free;
end;

end.
""" % (IDENT, IDENT, IDENT)


def monta(nombre):
    """Una jaula con su servidor propio. Devuelve (exedir, jail, pas)."""
    exedir = os.path.join(BASE, nombre, 'srv')
    jail = os.path.join(BASE, nombre, 'jail')
    os.makedirs(os.path.join(jail, 'u'), exist_ok=True)
    os.makedirs(exedir, exist_ok=True)
    shutil.copy(SRC, os.path.join(exedir, 'DelphiLspMcp.exe'))
    pas = os.path.join(jail, 'u', 'Cru.pas')
    open(pas, 'w', newline='\r\n').write(UNIT)
    return exedir, jail, pas


class Servidor:
    def __init__(self, exedir, jail, tok):
        self.tok = tok
        sk = socket.socket()
        sk.bind(('127.0.0.1', 0))
        self.port = sk.getsockname()[1]
        sk.close()
        open(os.path.join(exedir, 'settings.ini'), 'w').write('\n'.join([
            '[Server]', 'BindIP=127.0.0.1', '',
            '[Workspace.%s]' % tok.upper(), 'Token=%s' % tok,
            'Roots=%s' % jail, '']))
        self.proc = subprocess.Popen(
            [os.path.join(exedir, 'DelphiLspMcp.exe'), '--http', str(self.port)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)
        self.url = 'http://127.0.0.1:%d/mcp' % self.port
        self.sid = None
        _, self.sid = self.rpc(
            {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
             'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                        'clientInfo': {'name': tok, 'version': '1'}}})
        self.rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        self.rid = 100

    def rpc(self, body, timeout=300):
        h = {'Content-Type': 'application/json',
             'Accept': 'application/json, text/event-stream',
             'Authorization': 'Bearer ' + self.tok}
        if self.sid:
            h['Mcp-Session-Id'] = self.sid
        r = urllib.request.urlopen(urllib.request.Request(
            self.url, data=json.dumps(body).encode(), headers=h,
            method='POST'), timeout=timeout)
        raw = r.read().decode('utf-8', 'replace')
        for l in raw.splitlines():
            if l.startswith('data:'):
                m = json.loads(l[5:].strip())
                if 'result' in m or 'error' in m:
                    return m, r.headers.get('Mcp-Session-Id')
        try:
            return json.loads(raw), r.headers.get('Mcp-Session-Id')
        except Exception:
            return None, r.headers.get('Mcp-Session-Id')

    def refs(self, pas, line, col):
        self.rid += 1
        r, _ = self.rpc({'jsonrpc': '2.0', 'id': self.rid,
                         'method': 'tools/call',
                         'params': {'name': 'delphi_references',
                                    'arguments': {'path': pas, 'line': line,
                                                  'character': col}}})
        try:
            return r['result']['content'][0]['text']
        except Exception:
            return json.dumps(r)[:400]

    def para(self):
        try:
            self.proc.kill()
        except Exception:
            pass
        time.sleep(1)


L = UNIT.split('\n')
DECL = [i for i, x in enumerate(L) if x.strip() == 'procedure %s;' % IDENT][0]
COL = L[DECL].lower().index(IDENT.lower())

exeA, jailA, pasA = monta('A')
exeB, jailB, pasB = monta('B')
a = b = None
respuestas = {}
try:
    # Las DOS jaulas existen a la vez, con el mismo nombre de unit y el mismo
    # identificador: es la contaminacion, montada a proposito. Cual de las dos
    # elige el motor no se puede mandar, asi que no se mide ESO: se mide el
    # invariante, que vale siempre y es el que importa.
    a = Servidor(exeA, jailA, 'r42a')
    respuestas['A'] = a.refs(pasA, DECL, COL)
    a.para()
    b = Servidor(exeB, jailB, 'r42b')
    respuestas['B'] = b.refs(pasB, DECL, COL)
    b.para()

    ajena = {'A': jailB, 'B': jailA}
    for quien in ('A', 'B'):
        r = respuestas[quien]
        otra = ajena[quien]

        # -------------------------------------------------------------- X1
        # EL INVARIANTE: pase lo que pase por dentro, en la respuesta no
        # puede salir una ruta de OTRO workspace. Este servidor sirve varios
        # [Workspace.X] con tokens distintos, asi que esto no es estetica.
        check('X1%s la respuesta de la jaula %s no nombra la otra jaula'
              % (quien.lower(), quien),
              otra.lower() not in r.lower(),
              'se ha colado %s en: %s' % (otra, r[:240]))

        # -------------------------------------------------------------- X2
        # Y no puede morir con la negativa cruda de la jaula: eso es el
        # sintoma de haber dado por buena una ruta que no era de aqui.
        check('X2%s ...ni muere con un RECHAZADO de jaula' % quien.lower(),
              'FUERA de los workspaces permitidos' not in r, r[:240])

        # -------------------------------------------------------------- X3
        # Las dos salidas legitimas: contestar bien, o decir con claridad
        # que la definicion cae fuera. Cualquier otra cosa no vale.
        if 'FUERA de este workspace' in r:
            check('X3%s la salida es el error que se entiende' % quien.lower(),
                  IDENT in r and 'SIN CONFIGURAR' in r and
                  'delphi_definition' in r, r[:300])
        else:
            try:
                j = json.loads(r)
            except Exception:
                j = {}
            # No se mide CUANTAS confirma: estas units van sin configurar a
            # proposito y el motor resuelve lo que puede. Lo que se mide es
            # que la respuesta habla de MI fichero y mira donde le toca.
            propia = {'A': jailA, 'B': jailB}[quien].lower()
            defe = (j.get('definition') or {}).get('path', '')
            check('X3%s la respuesta habla de su propio fichero'
                  % quien.lower(),
                  j.get('identifier') == IDENT and
                  propia in defe.lower().replace('srvc:', 'c:'),
                  'identifier=%s definition=%s' % (j.get('identifier'), defe))
            check('X3%s-b ...y solo mira dentro de su jaula'
                  % quien.lower(),
                  bool(j.get('scope')) and
                  all(propia in s.lower().replace('srvc:', 'c:')
                      for s in j.get('scope', [])),
                  'scope=%s' % j.get('scope'))
finally:
    for s in (a, b):
        if s:
            s.para()

print('== test_round42: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
