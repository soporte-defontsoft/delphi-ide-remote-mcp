# -*- coding: utf-8 -*-
"""E2E battery: tres respuestas que no se podian leer.

Ninguna de las tres rompia nada. Las tres hacian perder una llamada, que es
como se gasta el contexto de un agente sin que nadie lo apunte.

  D1  el "path" de las tools de POSICION ya no dice que acepta una carpeta.
      Venia heredado de una clase base compartida con delphi_symbols -la
      unica que SI acepta carpeta-, asi que SEIS tools anunciaban algo que no
      hacen. Compartir la clase base hizo compartir una descripcion que solo
      era verdad en una de ellas.
  D2  ...y delphi_symbols sigue diciendo que SI la acepta
  D3  git diff sobre un arbol limpio dice "sin diferencias" en vez de
      contestar "exit=0" y nada, que es indistinguible de una respuesta rota
      (y lo primero que se hace con una respuesta rota es repetirla)
  D4  ...y las demas ordenes mudas dicen que su silencio ES el exito
  D5  la severidad de delphi_diagnostics documenta los CUATRO valores de la
      escala LSP: llegaba un 4 sin que nada dijera que significa
  D6  delphi_definition sobre algo que no se resuelve ya no contesta "null"
      a secas: cuatro caracteres correctos e ilegibles, que no distinguen
      entre apuntar mal, faltar la configuracion del proyecto y no haber
      nada que resolver - y las tres se arreglan de forma distinta

Usage:  python tests/test_round39.py [path-to-DelphiLspMcp.exe]
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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round39')
# git deja sus objetos en SOLO LECTURA y rmtree(ignore_errors) no los quita,
# asi que la segunda pasada se encontraba las carpetas ahi. Es el mismo
# tropiezo que el servidor documenta en ClearReadOnlyTree.
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

TOK = 'r39'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R39]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body, timeout=180):
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
                         'clientInfo': {'name': 'r39', 'version': '1'}}})
rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
RID = [100]


def call(tool, args):
    RID[0] += 1
    r, _ = rpc({'jsonrpc': '2.0', 'id': RID[0], 'method': 'tools/call',
                'params': {'name': tool, 'arguments': args}})
    try:
        return r['result']['content'][0]['text']
    except Exception:
        return json.dumps(r)[:400]


def esquema(tool):
    return json.loads(call('delphi_help', {'command': 'tool', 'name': tool}))


try:
    # ------------------------------------------------------------------ D1
    posicion = ['delphi_definition', 'delphi_hover', 'delphi_completion',
                'delphi_signature', 'delphi_references', 'delphi_rename_symbol']
    mienten = []
    for t in posicion:
        try:
            d = esquema(t)['parameters']['properties']['path']['description']
        except Exception as ex:
            mienten.append('%s (%s)' % (t, ex))
            continue
        # Se afirma el CONTRATO, no la letra: lo que mentia era prometer el
        # digest de una carpeta. Buscar la palabra "carpeta" a secas daria
        # falso positivo con el texto nuevo, que la usa para NEGARLO.
        if 'OFRECE cada unit' in d:
            mienten.append(t)
    check('D1 ninguna tool de posicion promete el digest de una carpeta',
          not mienten, 'lo siguen prometiendo: %s' % mienten)
    dicen = [t for t in posicion
             if 'no una carpeta' in
             esquema(t)['parameters']['properties']['path']['description']]
    check('D1b ...y las de esta unit lo dicen explicitamente',
          len(dicen) >= 4, 'solo lo dicen: %s' % dicen)

    # ------------------------------------------------------------------ D2
    ds = esquema('delphi_symbols')['parameters']['properties']['path']['description']
    check('D2 ...y delphi_symbols sigue diciendo que SI la acepta',
          'CARPETA' in ds.upper(), ds[:200])

    # ------------------------------------------------------------------ D3
    repo = os.path.join(JAIL, 'r')
    os.makedirs(repo)
    call('delphi_git', {'repo': repo, 'command': 'init'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.email', 'message': 'r39@test'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.name', 'message': 'R39'})
    open(os.path.join(repo, 'a.txt'), 'w').write('uno\n')
    call('delphi_git', {'repo': repo, 'command': 'add', 'args': '-A'})
    call('delphi_git', {'repo': repo, 'command': 'commit', 'message': 'uno'})
    d = call('delphi_git', {'repo': repo, 'command': 'diff'})
    check('D3 git diff en arbol limpio dice que no hay diferencias',
          'sin diferencias' in d and len(d.strip()) > len('exit=0') + 5, d[:200])

    # ------------------------------------------------------------------ D4
    a = call('delphi_git', {'repo': repo, 'command': 'add', 'args': '-A'})
    check('D4 una orden muda dice que su silencio ES el exito',
          'exit=0' in a and 'terminado bien' in a, a[:200])

    # ------------------------------------------------------------------ D5
    desc = esquema('delphi_diagnostics')['description']
    check('D5 la severidad documenta los CUATRO valores de la escala LSP',
          '4=hint' in desc and '3=information' in desc, desc[:260])

    # ------------------------------------------------------------------ D6
    pas = os.path.join(JAIL, 'N.pas')
    open(pas, 'w', newline='\r\n').write(
        'unit N;\n\ninterface\n\nimplementation\n\nend.\n')
    # la linea 4 (0-based) es "implementation": una palabra reservada, ahi no
    # hay simbolo que resolver
    n = call('delphi_definition', {'path': pas, 'line': 4, 'character': 2})
    check('D6 un null viene explicado, no a secas',
          n.startswith('null') and len(n) > 200 and '0-BASED' in n, n[:220])
    check('D6b ...y dice las tres causas, que se arreglan distinto',
          ('delphi_read' in n) and ('delphi_symbols' in n), n[:260])
finally:
    try:
        proc.kill()
    except Exception:
        pass

print('== test_round39: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
