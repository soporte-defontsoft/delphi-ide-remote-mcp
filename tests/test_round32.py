# -*- coding: utf-8 -*-
"""E2E battery for ReadOnlyPaths - carpetas de DENTRO de la jaula que se leen
pero no se escriben.

Nace de un caso real (20-sep-2026). Al estrechar la jaula de este repo al
propio repo, entraron con permiso de escritura dos clones de referencia que
viven dentro y tienen su PROPIO git (gdk-mcp, skybuck-mcp). Sacarlos fuera no
vale: lo relacionado con el proyecto vive en la carpeta del proyecto, que es
lo que encuentra quien lo clona. Y como son repos aparte, una escritura por
descuido ni siquiera sale en el "git status" del principal - puede pasar una
sesion entera sin que nadie se entere.

El servidor ya tenia esta semantica exacta para la zona de biblioteca del IDE
("reading tools may enter it; writing tools never can"), pero cableada. Esto
la abre al settings.ini.

  L1  leer dentro de un ReadOnlyPaths SI se puede (no es la jaula)
  L2  buscar dentro tambien
  L3  editar NO, y la negativa lo distingue de la jaula y nombra la clave
  L4  tras la negativa el fichero esta byte a byte como estaba
  L5  textedit, create y delete tampoco entran
  L6  fuera de esa carpeta se escribe igual que siempre (la regla no se
      desborda)
  L7  una entrada ABSOLUTA vale igual que una relativa

Usage:  python tests/test_round32.py [path-to-DelphiLspMcp.exe]
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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round32')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
VENDOR = os.path.join(JAIL, 'vendor')       # relativa al root
AJENO = os.path.join(BASE, 'otro')          # absoluta, y FUERA del root
MIO = os.path.join(JAIL, 'mio')
for d in (EXEDIR, VENDOR, MIO, AJENO):
    os.makedirs(d)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

UNIT = ('unit Ajena;\n\ninterface\n\n'
        'procedure Saluda;\n\nimplementation\n\n'
        'procedure Saluda;\nbegin\nend;\n\nend.\n')
AJENA = os.path.join(VENDOR, 'Ajena.pas')
open(AJENA, 'w').write(UNIT)
open(os.path.join(VENDOR, 'LEEME.md'), 'w').write('# ajeno\n\nno tocar\n')
MIA = os.path.join(MIO, 'Mia.pas')
open(MIA, 'w').write(UNIT.replace('Ajena', 'Mia'))
# La carpeta absoluta esta FUERA del root a proposito: asi se comprueba que la
# jaula sigue mandando y que ReadOnlyPaths no es una puerta de entrada.
open(os.path.join(AJENO, 'Fuera.pas'), 'w').write(UNIT.replace('Ajena', 'Fuera'))

TOK = 'r32'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R32]',
    'Token=%s' % TOK,
    'Roots=%s' % JAIL,
    'ReadOnlyPaths=vendor;%s' % AJENO,
    '',
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
                         'clientInfo': {'name': 'r32', 'version': '1'}}})
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


ANTES = open(AJENA, 'rb').read()
try:
    # ----------------------------------------------------------------- L1/L2
    t = call('delphi_read', {'path': AJENA})
    check('L1 leer dentro de ReadOnlyPaths SI se puede (no es la jaula)',
          'procedure Saluda' in t, t[:200])
    t = call('delphi_search', {'root': JAIL, 'query': 'Saluda'})
    check('L2 buscar entra igual: aparece el fichero de vendor',
          'Ajena.pas' in t, t[:200])

    # -------------------------------------------------------------------- L3
    t = call('delphi_edit', {'path': AJENA, 'old': 'procedure Saluda;',
                             'new': 'procedure Saludado;', 'atline': 5})
    check('L3 editar dentro se RECHAZA', 'RECHAZADO' in t, t[:200])
    check('L3b la negativa nombra la clave que lo decide',
          'ReadOnlyPaths' in t, t[:250])
    check('L3c y lo distingue de la jaula: dice que leer SI puede',
          'SOLO LECTURA' in t.upper() and 'delphi_read' in t, t[:250])

    # -------------------------------------------------------------------- L4
    check('L4 tras la negativa el fichero sigue byte a byte igual',
          open(AJENA, 'rb').read() == ANTES, 'cambio en disco')

    # -------------------------------------------------------------------- L5
    t = call('delphi_textedit', {'path': os.path.join(VENDOR, 'LEEME.md'),
                                 'old': 'no tocar', 'new': 'tocado'})
    check('L5 textedit tampoco entra', 'RECHAZADO' in t, t[:200])
    t = call('delphi_textedit', {'path': os.path.join(VENDOR, 'Nuevo.md'),
                                 'create': True, 'content': 'x'})
    check('L5b crear dentro tampoco', 'RECHAZADO' in t, t[:200])
    check('L5c ...y de verdad no se ha creado',
          not os.path.exists(os.path.join(VENDOR, 'Nuevo.md')), 'existe')
    t = call('delphi_delete', {'path': AJENA})
    check('L5d borrar dentro tampoco', 'RECHAZADO' in t, t[:200])
    check('L5e ...y el fichero sigue ahi', os.path.exists(AJENA), 'no esta')

    # -------------------------------------------------------------------- L6
    t = call('delphi_edit', {'path': MIA, 'old': 'procedure Saluda;',
                             'new': 'procedure Saludado;', 'atline': 5})
    check('L6 fuera de esa carpeta se escribe igual que siempre: la regla no '
          'se desborda al resto de la jaula',
          'RECHAZADO' not in t and 'Saludado' in open(MIA).read(), t[:200])

    # -------------------------------------------------------------------- L7
    # La entrada ABSOLUTA esta fuera del root: manda la jaula, y la negativa
    # tiene que ser la de la jaula, no la de solo lectura. ReadOnlyPaths NO
    # es una puerta de entrada.
    t = call('delphi_read', {'path': os.path.join(AJENO, 'Fuera.pas')})
    check('L7 una ReadOnlyPaths absoluta FUERA del root no abre nada: '
          'sigue mandando la jaula',
          'ReadOnlyPaths' not in t and ('RECHAZADO' in t or 'error' in t),
          t[:250])
finally:
    try:
        proc.kill()
    except Exception:
        pass

print('== test_round32: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
