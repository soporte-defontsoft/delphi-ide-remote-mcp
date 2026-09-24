# -*- coding: utf-8 -*-
"""E2E battery: un nombre escrito en un comentario no es una referencia.

delphi_references validaba cada candidato preguntandole al motor donde esta
definido. Sobre un comentario o dentro de una cadena el motor contesta lo
mismo que cuando la validacion se queda sin presupuesto -nada- y las dos
cosas caian en el mismo saco, "unverified".

No es el mismo saco: "no lo se" y "se que no" se arreglan distinto. Y se
pagaba caro, porque delphi_rename_symbol bloquea el rename con UN solo
unverified: documentar un identificador dejaba esa tool inservible sobre el.
Medido el 2026-09-21 sobre MaskDriveText del propio repo del servidor: 18
confirmadas y 6 unverified, las SEIS comentarios.

Las dos trampas que separan una implementacion correcta de una ingenua, y
que van medidas aqui:

  M5  'http://x' NO abre un comentario: la llamada que va detras en la
      misma linea sigue siendo codigo
  M6  'don''t' es una comilla escapada, no el final de la cadena: la
      llamada que va detras sigue siendo codigo

Usage:  python tests/test_round41.py [path-to-DelphiLspMcp.exe]
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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:240])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round41')


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
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR, exist_ok=True)
os.makedirs(JAIL, exist_ok=True)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

# El identificador se hace UNICO en cada pasada, y no por gusto: el indice
# del motor sobrevive al reinicio del servidor y se pega al NOMBRE. Medido el
# 2026-09-21: preguntando por "Pinta" en esta jaula, la definicion resolvia a
# un Pinta de la jaula de otra bateria; al borrar ese fichero, caia en el de
# una tercera. El servidor ya lo corta (SR_REFS_TARGET_OUTSIDE_FMT), pero una
# bateria que reutilice un nombre comun se mide a si misma contra la basura
# que dejo la anterior. Cualquier bateria nueva que toque delphi_references
# deberia hacer lo mismo.
SUF = uuid.uuid4().hex[:8]
PIN = 'Pinta' + SUF
DIB = 'Dibuja' + SUF

# 5 veces en CODIGO y 5 en prosa, contadas a mano:
#   codigo    la declaracion, la implementacion y tres llamadas
#   prosa     dos lineas del bloque { }, una de (* *), un // y una cadena
MEN = """unit Men;

interface

type
  TCosa = class
    procedure Pinta;
  end;

implementation

{ Un comentario de bloque que nombra Pinta
  y que en su segunda linea vuelve a decir Pinta. }

(* Otro estilo de comentario, con Pinta dentro. *)

procedure TCosa.Pinta;  // y el comentario de al lado dice Pinta
begin
end;

procedure Usa;
var
  C: TCosa;
  S: string;
begin
  C := TCosa.Create;
  C.Pinta;
  S := 'Pinta escrito dentro de una cadena';
  if S = 'http://x' then C.Pinta;
  if S = 'don''t' then C.Pinta;
  C.Free;
end;

end.
"""

# Sin ninguna cadena: el literal tiene su propio bloqueo en el rename
# (StringLiteralHits) y no es el que se mide aqui. Aqui solo comentarios,
# uno de ellos en la MISMA linea que una llamada de verdad.
COM = """unit Com;

interface

type
  TOtra = class
    procedure Dibuja;
  end;

implementation

// Este comentario nombra Dibuja y no deberia bloquear nada.

procedure TOtra.Dibuja;
begin
end;

procedure Usa2;
var
  O: TOtra;
begin
  O := TOtra.Create;
  O.Dibuja;   { y este bloque tambien nombra Dibuja }
  O.Free;
end;

end.
"""

MEN = MEN.replace('Pinta', PIN)
COM = COM.replace('Dibuja', DIB)

# Las units van con su PROYECTO. No es decoracion: sin un .dproj al lado la
# unit va SIN CONFIGURAR y el motor resuelve la declaracion y poco mas, con
# lo que las llamadas caen en "unverified" por un motivo que no tiene nada
# que ver con lo que mide esta bateria. Antes del 2026-09-21 esto colaba
# igual porque la busqueda de configuracion subia OCHO niveles sin mirar la
# jaula y adoptaba un "fuera-de-la-jaula.dproj" de 10 bytes que se habia
# quedado en %TEMP%: la bateria pasaba en verde montada en un fichero suelto
# de otra. Al cerrar aquello (PuedoSubirA) quedo a la vista.
DPR = """program P41;

uses
  Men in 'Men.pas',
  Com in 'Com.pas';

begin
end.
"""

DPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>P41.dpr</MainSource>
    <Platform>Win32</Platform>
    <DCC_UnitSearchPath>.</DCC_UnitSearchPath>
  </PropertyGroup>
</Project>
"""

os.makedirs(os.path.join(JAIL, 'u'))
open(os.path.join(JAIL, 'u', 'P41.dpr'), 'w', newline='\r\n').write(DPR)
open(os.path.join(JAIL, 'u', 'P41.dproj'), 'w', newline='\r\n').write(DPROJ)
PAS = os.path.join(JAIL, 'u', 'Men.pas')
PAS2 = os.path.join(JAIL, 'u', 'Com.pas')
open(PAS, 'w', newline='\r\n').write(MEN)
open(PAS2, 'w', newline='\r\n').write(COM)
LM = MEN.split('\n')
LC = COM.split('\n')

TOK = 'r41'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R41]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body, timeout=300):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOK}
    if SID:
        h['Mcp-Session-Id'] = SID
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'),
        timeout=timeout)
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


_, SID = rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
              'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                         'clientInfo': {'name': 'r41', 'version': '1'}}})
rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
RID = [100]


def call(tool, args):
    RID[0] += 1
    r, _ = rpc({'jsonrpc': '2.0', 'id': RID[0], 'method': 'tools/call',
                'params': {'name': tool, 'arguments': args}})
    try:
        return json.loads(r['result']['content'][0]['text'])
    except Exception:
        return {'error': json.dumps(r)[:300]}


def linea0(lineas, texto):
    for i in range(len(lineas)):
        if lineas[i].strip() == texto:
            return i
    raise AssertionError('no encuentro ' + texto)


def anclas(lista):
    return [c.get('anchor', '') for c in lista]


try:
    # La declaracion dentro de la clase: desde ahi se pregunta.
    decl = linea0(LM, 'procedure %s;' % PIN)
    col = LM[decl].lower().index(PIN.lower())
    j = call('delphi_references',
             {'path': PAS, 'line': decl, 'character': col})

    conf = anclas(j.get('confirmed', []))
    ment = anclas(j.get('mentions', []))

    # ------------------------------------------------------------------ M1
    check('M1 las 5 apariciones en prosa se cuentan aparte',
          j.get('mentionsCount') == 5,
          'mentionsCount=%s mentions=%s' % (j.get('mentionsCount'), ment))

    # ------------------------------------------------------------------ M2
    # EL ARREGLO: antes las cinco estaban aqui, y con una sola el rename
    # contestaba que no se puede.
    check('M2 ...y ninguna cae ya en "unverified"',
          j.get('unverified') == [],
          json.dumps(j.get('unverified'))[:260])

    # ------------------------------------------------------------------ M3
    check('M3 el comentario de bloque cuenta por sus DOS lineas',
          sum(1 for a in ment if 'comentario de bloque' in a or
              'segunda linea' in a) == 2, ment)
    check('M3b ...y el estilo (* *) tambien',
          any('Otro estilo' in a for a in ment), ment)
    check('M3c ...y el // que va detras de codigo en la misma linea',
          any(a.strip().startswith('procedure TCosa.%s;' % PIN)
              for a in ment), ment)

    # ------------------------------------------------------------------ M4
    check('M4 una cadena que nombra el simbolo es mencion, no referencia',
          any('escrito dentro de una cadena' in a for a in ment) and
          not any('escrito dentro de una cadena' in a for a in conf), ment)

    # ------------------------------------------------------------------ M5
    check("M5 'http://x' no abre un comentario: la llamada de detras es codigo",
          any('http://x' in a for a in conf),
          'confirmed=%s' % conf)

    # ------------------------------------------------------------------ M6
    check("M6 la comilla escapada '' no deja la cadena abierta",
          any("don''t" in a for a in conf),
          'confirmed=%s' % conf)

    # ------------------------------------------------------------------ M7
    check('M7 la respuesta dice que las menciones no bloquean un rename',
          'rename' in j.get('mentionsNote', '').lower(),
          str(j.get('mentionsNote'))[:200])

    # ------------------------------------------------------------------ M8
    # El pago real del arreglo: el rename vuelve a ser posible sobre un
    # simbolo que esta documentado.
    d = linea0(LC, 'procedure %s;' % DIB)
    dc = LC[d].lower().index(DIB.lower())
    rn = call('delphi_rename_symbol',
              {'path': PAS2, 'line': d, 'character': dc,
               'newname': DIB + 'Todo'})
    check('M8 un simbolo nombrado en comentarios se puede renombrar',
          rn.get('applicable') is True,
          'blockers=%s' % json.dumps(rn.get('blockers'))[:260])
    check('M8b ...con las menciones contadas y avisadas, no escondidas',
          rn.get('mentions') == 2 and
          any('coment' in w.lower() for w in rn.get('warnings', [])),
          'mentions=%s warnings=%s' % (rn.get('mentions'),
                                       rn.get('warnings')))
finally:
    try:
        proc.kill()
    except Exception:
        pass

print('== test_round41: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
