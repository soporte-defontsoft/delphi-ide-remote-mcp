# -*- coding: utf-8 -*-
"""E2E battery: la jaula NO sigue junctions ni symlinks fuera del root.

EL ESCAPE (encontrado el 20-sep-2026 por un agente auditor, confirmado y
detenido ahi mismo). El control de frontera validaba la ruta TEXTUAL - que
cae dentro del root - pero el sistema de ficheros desreferencia el reparse
point a su destino real. Un junction plantado dentro del root apuntando a
C:\\Windows\\System32\\drivers\\etc hizo que delphi_list listara ese directorio
y que delphi_read devolviera el hosts de la maquina.

Y no hacia falta una consola en el servidor para plantarlo: un
"delphi_git clone" con core.symlinks=true mete el enlace sin salir del MCP,
o sea que el escape era alcanzable por el propio agente. Con el servidor
corriendo como servicio con la cuenta del operador, el alcance era todo lo
que esa cuenta alcanza.

La causa cabe en una linea: TPath.GetFullPath normaliza el TEXTO y no sigue
reparse points. La jaula hay que medirla contra la ruta REAL
(GetFinalPathNameByHandle), y los roots tambien, o se resuelve un solo lado
de la comparacion.

  E1  control: sin enlaces, dentro se lee y fuera se rechaza
  E2  un junction DENTRO del root apuntando FUERA no se puede listar
  E3  ...ni leer a traves de el
  E4  ...ni escribir a traves de el
  E5  ...ni crear un fichero nuevo a traves de el (la ruta aun no existe:
      se resuelve el antecesor)
  E6  un junction que apunta DENTRO del root sigue funcionando: el arreglo
      cierra el escape sin romper el caso legitimo

Necesita poder crear junctions (mklink /J NO pide administrador). Si no se
puede, la bateria lo DICE y no finge que paso.

Usage:  python tests/test_round33.py [path-to-DelphiLspMcp.exe]
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

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:240])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round33')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')        # el botin, fuera de la jaula
DENTRO = os.path.join(JAIL, 'dentro')      # destino legitimo, dentro
for d in (EXEDIR, JAIL, FUERA, DENTRO):
    os.makedirs(d)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

SECRETO = 'unit Secreto;\n\ninterface\n\nimplementation\n\nend.\n'
open(os.path.join(FUERA, 'Secreto.pas'), 'w').write(SECRETO)
open(os.path.join(DENTRO, 'Legitima.pas'), 'w').write(
    SECRETO.replace('Secreto', 'Legitima'))


def junction(enlace, destino):
    """mklink /J no necesita administrador. True si quedo hecho."""
    r = subprocess.run(['cmd', '/c', 'mklink', '/J', enlace, destino],
                       capture_output=True, text=True)
    return r.returncode == 0 and os.path.isdir(enlace)


SALIDA = os.path.join(JAIL, 'salida')      # enlace -> FUERA  (el escape)
INTERNO = os.path.join(JAIL, 'interno')    # enlace -> DENTRO (legitimo)
HAY_SALIDA = junction(SALIDA, FUERA)
HAY_INTERNO = junction(INTERNO, DENTRO)

TOK = 'r33'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R33]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body, timeout=120):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOK}
    if SID:
        h['Mcp-Session-Id'] = SID
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'),
        timeout=timeout)
    raw = r.read().decode('utf-8', 'replace')
    msgs = []
    for l in raw.splitlines():
        if l.startswith('data:'):
            try:
                msgs.append(json.loads(l[5:].strip()))
            except Exception:
                pass
    if not msgs:
        try:
            msgs.append(json.loads(raw))
        except Exception:
            pass
    return (msgs[-1] if msgs else None), r.headers.get('Mcp-Session-Id')


_, SID = rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
              'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                         'clientInfo': {'name': 'r33', 'version': '1'}}})
rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

RID = [100]


def call(tool, args, timeout=120):
    RID[0] += 1
    r, _ = rpc({'jsonrpc': '2.0', 'id': RID[0], 'method': 'tools/call',
                'params': {'name': tool, 'arguments': args}}, timeout)
    try:
        return r['result']['content'][0]['text']
    except Exception:
        return json.dumps(r)[:400]


def negado(t):
    return 'RECHAZADO' in t or t.strip().startswith('error')


try:
    # -------------------------------------------------------------------- E1
    t = call('delphi_read', {'path': os.path.join(DENTRO, 'Legitima.pas')})
    check('E1 control: dentro del root se lee', 'unit Legitima' in t, t[:160])
    t = call('delphi_read', {'path': os.path.join(FUERA, 'Secreto.pas')})
    check('E1b control: la misma ruta por fuera del root se rechaza',
          negado(t) and 'unit Secreto' not in t, t[:160])

    if not HAY_SALIDA:
        check('E2..E5 NO SE HAN PODIDO PROBAR: mklink /J no pudo crear el '
              'junction en este equipo', False, 'sin junction no hay medida')
    else:
        # ---------------------------------------------------------------- E2
        t = call('delphi_list', {'root': SALIDA})
        check('E2 listar a traves de un junction que sale del root: RECHAZADO',
              negado(t) and 'Secreto.pas' not in t, t[:200])
        # ---------------------------------------------------------------- E3
        t = call('delphi_read', {'path': os.path.join(SALIDA, 'Secreto.pas')})
        check('E3 leer a traves de el: RECHAZADO (y NO llega el contenido)',
              negado(t) and 'unit Secreto' not in t, t[:200])
        # ---------------------------------------------------------------- E4
        t = call('delphi_edit', {'path': os.path.join(SALIDA, 'Secreto.pas'),
                                 'old': 'interface', 'new': 'interface // x'})
        check('E4 escribir a traves de el: RECHAZADO', negado(t), t[:200])
        check('E4b ...y el fichero de fuera sigue intacto',
              open(os.path.join(FUERA, 'Secreto.pas')).read() == SECRETO,
              'lo ha tocado')
        # ---------------------------------------------------------------- E5
        # La ruta NO existe aun: lo que hay que resolver es el ANTECESOR.
        nuevo = os.path.join(SALIDA, 'Plantado.md')
        t = call('delphi_textedit', {'path': nuevo, 'create': True,
                                     'content': 'plantado'})
        check('E5 crear algo nuevo a traves de el: RECHAZADO', negado(t),
              t[:200])
        check('E5b ...y de verdad no ha aparecido nada fuera',
              not os.path.exists(os.path.join(FUERA, 'Plantado.md')),
              'se ha plantado fuera de la jaula')

    # -------------------------------------------------------------------- E6
    if not HAY_INTERNO:
        check('E6 NO SE HA PODIDO PROBAR: sin junction interno', False, '')
    else:
        t = call('delphi_read', {'path': os.path.join(INTERNO,
                                                      'Legitima.pas')})
        check('E6 un junction que apunta DENTRO del root sigue funcionando: '
              'el arreglo cierra el escape sin romper el caso legitimo',
              'unit Legitima' in t, t[:200])
finally:
    try:
        proc.kill()
    except Exception:
        pass
    # Los junctions se quitan con rmdir, que NO toca el destino.
    for enlace in (SALIDA, INTERNO):
        try:
            if os.path.isdir(enlace):
                os.rmdir(enlace)
        except Exception:
            pass

print('== test_round33: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
