# -*- coding: utf-8 -*-
"""Round 47: dos de las tres medidas que la 1.0.13 dejo a deber.

La auditoria del 21-sep arreglo tres cosas sin poder medirlas, y lo dijo en
voz alta. Aqui se pagan dos:

  C  La caida CESU-8 del decodificador de hijos. Hacia falta "un hijo que
     emita esos bytes", y lo hay sin inventar nada: `git show HEAD:fichero`
     escupe el contenido CRUDO de un fichero. Se versiona uno con un par
     suplente en CESU-8 (ED A0 BD ED B8 80: bien FORMADO, que es lo que mira
     LooksUtf8, e INVALIDO para el decodificador estricto) y se pide por
     delphi_git. Antes del arreglo eso mataba la llamada con "No mapping for
     the Unicode character..."; ahora cae a la red y el ASCII llega entero.

  R  AgentTempDir con la PRIMERA raiz declarada de solo lectura: el
     entregable tiene que caer en la primera raiz ESCRIBIBLE. Necesita el
     nodo del escritorio y una sesion que pueda capturar; si no, se DICE.

La tercera (la clave de cache entre workspaces solapados) sigue debiendose:
la raiz que resuelve una sesion LSP no sale en ninguna respuesta, y medirla
por sus efectos pide un DelphiLSP vivo y dos tokens. test_round42 cubre el
sintoma cruzado que la motivo.
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
NODO = os.path.join(REPO, 'node', 'McpDesktopNode.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round47')


def borra(d):
    def alafuerza(func, path, _exc):
        try:
            os.chmod(path, 0o700)
            func(path)
        except Exception:
            pass
    if not os.path.isdir(d):
        return
    shutil.rmtree(d, onexc=alafuerza) if sys.version_info >= (3, 12) else \
        shutil.rmtree(d, onerror=alafuerza)


borra(BASE)
EXEDIR = os.path.join(BASE, 'srv')
RO = os.path.join(BASE, 'referencia')     # la PRIMERA raiz, de solo lectura
RW = os.path.join(BASE, 'trabajo')        # la segunda, escribible
os.makedirs(os.path.join(EXEDIR, 'node'))
os.makedirs(RO)
os.makedirs(RW)
shutil.copy(SRC, os.path.join(EXEDIR, 'DelphiLspMcp.exe'))
HAY_NODO = os.path.exists(NODO)
if HAY_NODO:
    shutil.copy(NODO, os.path.join(EXEDIR, 'node', 'McpDesktopNode.exe'))

TOK = 'r47'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R47]', 'Token=%s' % TOK, 'Roots=%s;%s' % (RO, RW),
    'ReadOnlyPaths=%s' % RO, 'AllowDesktopControl=1', '']))

proc = subprocess.Popen(
    [os.path.join(EXEDIR, 'DelphiLspMcp.exe'), '--http', str(PORT)],
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
                         'clientInfo': {'name': 'r47', 'version': '1'}}})
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


def pngs(d):
    if not os.path.isdir(d):
        return []
    return [os.path.join(r, f)
            for r, _, fs in os.walk(d) for f in fs if f.lower().endswith('.png')]


try:
    # ------------------------------------------------------------------- C
    # El fichero lo planta la bateria A MANO: son bytes que ninguna tool de
    # edicion escribiria. El par suplente en CESU-8 va entre dos marcas ASCII.
    repo = os.path.join(RW, 'cesu')
    os.makedirs(repo)
    veneno = b'MARCA-ANTES ' + bytes([0xED, 0xA0, 0xBD, 0xED, 0xB8, 0x80]) + \
        b' MARCA-DESPUES\n'
    open(os.path.join(repo, 'cesu.txt'), 'wb').write(veneno)
    call('delphi_git', {'repo': repo, 'command': 'init'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.name', 'message': 'r47'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.email', 'message': 'r47@example.invalid'})
    call('delphi_git', {'repo': repo, 'command': 'add', 'args': 'cesu.txt'})
    c = call('delphi_git', {'repo': repo, 'command': 'commit',
                            'message': 'fichero con un par suplente CESU-8'})
    check('C0 el fichero venenoso queda versionado', c.startswith('exit=0'), c[:200])
    s = call('delphi_git', {'repo': repo, 'command': 'show',
                            'args': 'HEAD:cesu.txt'})
    check('C1 un hijo que emite CESU-8 ya no mata la llamada',
          'No mapping' not in s and 'Error executing tool' not in s, s[:240])
    check('C2 ...y el ASCII de los dos lados llega entero',
          'MARCA-ANTES' in s and 'MARCA-DESPUES' in s, s[:240])

    # ------------------------------------------------------------------- S
    # delphi_search filtra los artefactos como su gemela delphi_list: sobre
    # la ruta RELATIVA a la raiz, y si nombras la carpeta de compilacion es
    # que la quieres ver. Filtraba la absoluta: buscar DENTRO de
    # Win64\Release devolvia cero, en silencio.
    salida = os.path.join(RW, 'proy', 'Win64', 'Release')
    os.makedirs(salida)
    open(os.path.join(salida, 'Generado.pas'), 'w').write(
        'unit Generado;\n// agujaenelartefacto\ninterface\nimplementation\nend.\n')
    a = call('delphi_search', {'root': os.path.join(RW, 'proy'),
                               'query': 'agujaenelartefacto'})
    check('S1 desde arriba, la carpeta de compilacion sigue oculta',
          'Generado.pas' not in a, a[:200])
    b = call('delphi_search', {'root': salida, 'query': 'agujaenelartefacto'})
    check('S2 nombrada como raiz, se busca dentro (como hace delphi_list)',
          'Generado.pas' in b, b[:200])

    # ------------------------------------------------------------------- R
    # Roots=referencia;trabajo con ReadOnlyPaths=referencia. El entregable
    # por defecto caia en Roots[0] a pelo: justo donde la jaula prohibe
    # escribir (y donde la misma ruta pasada en "out" se rechaza).
    shot = call('delphi_desktop', {'command': 'screenshot'}) if HAY_NODO else ''
    if not HAY_NODO:
        print('NOTA: no hay node/McpDesktopNode.exe; R1/R2 no se miden.')
    elif 'NO pude capturar' in shot or '"screenshot"' not in shot:
        print('NOTA: esta maquina no puede capturar la pantalla ahora mismo '
              '(sesion bloqueada o desconectada); R1/R2 no se miden.')
    else:
        check('R1 la captura por defecto cae en la raiz ESCRIBIBLE',
              bool(pngs(os.path.join(RW, '__delphi-temp'))), shot[:240])
        check('R2 ...y en la raiz de solo lectura no se ha creado nada',
              not os.path.exists(os.path.join(RO, '__delphi-temp')),
              os.listdir(RO))
    print('NOTA: sigue debiendose la medida de la clave de cache entre '
          'workspaces solapados (pide un DelphiLSP vivo y dos tokens).')
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    borra(BASE)

print('== test_round47: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
