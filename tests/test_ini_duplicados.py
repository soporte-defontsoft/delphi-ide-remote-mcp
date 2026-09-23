# -*- coding: utf-8 -*-
"""Duplicados en settings.ini (David, 2026-09-23): un copia-pega futuro puede
dejar el mismo token en dos workspaces, la misma clave dos veces en una
seccion o la misma seccion dos veces. TIniFile lee lo primero y calla; el
servidor CIERRA los workspaces afectados (401) y lo dice al arrancar.

  D1  dos workspaces con el mismo Token=: los dos 401
  D2  Token= igual a ReadOnlyToken= en uno: 401 (con cualquiera de los dos)
  D3  clave repetida dentro de la seccion (Roots= dos veces): 401
  D4  seccion escrita dos veces: 401 con el token de cualquiera de las dos
  D5  el workspace limpio de al lado sigue entrando, y se llama como se llama
  D6  el arranque nombra cada caso (AVISO ...)

Usage:  python tests/test_ini_duplicados.py [path-to-DelphiLspMcp.exe]
"""
import json, os, shutil, socket, subprocess, sys, tempfile, time, urllib.request, urllib.error

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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'inidup')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.Uno]', 'Token=t-uno', 'Roots=%s' % JAIL, '',
    '[Workspace.Dos]', 'Token=t-uno', 'Roots=%s' % JAIL, '',        # D1: copia-pega del token
    '[Workspace.Tres]', 'Token=t-tres', 'ReadOnlyToken=t-tres', 'Roots=%s' % JAIL, '',  # D2
    '[Workspace.Cuatro]', 'Token=t-cuatro', 'Roots=%s' % JAIL, 'Roots=%s' % JAIL, '',   # D3
    '[Workspace.Cinco]', 'Token=t-cinco', 'Roots=%s' % JAIL, '',
    '[Workspace.Cinco]', 'Token=t-cinco-bis', 'Roots=%s' % JAIL, '',  # D4
    '[Workspace.Limpio]', 'Token=t-limpio', 'Roots=%s' % JAIL, '',
]))

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
proc = subprocess.Popen([EXE, '--http', str(PORT)], stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
time.sleep(2.5)
URL = 'http://127.0.0.1:%d/mcp' % PORT


def init(tok):
    """HTTP status of an initialize with that Bearer, and the session id."""
    h = {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + tok}
    body = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "inidup", "version": "1"}}}
    try:
        r = urllib.request.urlopen(urllib.request.Request(
            URL, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=60)
        return r.status, r.headers.get('Mcp-Session-Id')
    except urllib.error.HTTPError as e:
        return e.code, None


def workspace_name(tok, sid):
    h = {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + tok, 'Mcp-Session-Id': sid}
    urllib.request.urlopen(urllib.request.Request(URL, data=json.dumps(
        {"jsonrpc": "2.0", "method": "notifications/initialized"}).encode(), headers=h, method='POST'), timeout=60)
    r = urllib.request.urlopen(urllib.request.Request(URL, data=json.dumps(
        {"jsonrpc": "2.0", "id": 7, "method": "tools/call",
         "params": {"name": "delphi_workspace", "arguments": {}}}).encode(), headers=h, method='POST'), timeout=60)
    raw = r.read().decode('utf-8', 'replace')
    for l in raw.splitlines():
        if l.startswith('data:'):
            raw = l[5:].strip()
    try:
        return json.loads(json.loads(raw)['result']['content'][0]['text']).get('workspace')
    except Exception:
        return raw[:200]


try:
    check('D1 token compartido: el primero 401', init('t-uno')[0] == 401, init('t-uno'))
    check('D2 Token = ReadOnlyToken: 401', init('t-tres')[0] == 401, init('t-tres'))
    check('D3 clave repetida en la seccion: 401', init('t-cuatro')[0] == 401, init('t-cuatro'))
    check('D4 seccion repetida: 401 con el primer token', init('t-cinco')[0] == 401, init('t-cinco'))
    check('D4 seccion repetida: 401 con el segundo token', init('t-cinco-bis')[0] == 401, init('t-cinco-bis'))
    code, sid = init('t-limpio')
    check('D5 el workspace limpio entra', code == 200 and sid, (code, sid))
    if sid:
        check('D5 y se llama Limpio', workspace_name('t-limpio', sid) == 'Limpio', '')
finally:
    proc.kill()
    out = proc.stdout.read() if proc.stdout else ''

avisos = [l for l in out.splitlines() if 'AVISO' in l]
check('D6 arranque: nombra el par que comparte token', any('[Workspace.Uno] y [Workspace.Dos]' in l for l in avisos), avisos)
check('D6 arranque: nombra Token = ReadOnlyToken', any('[Workspace.Tres]' in l and 'MISMO valor' in l for l in avisos), avisos)
check('D6 arranque: nombra la clave repetida', any('[Workspace.Cuatro] repite la clave Roots' in l for l in avisos), avisos)
check('D6 arranque: nombra la seccion repetida', any('[Workspace.Cinco] aparece DOS veces' in l for l in avisos), avisos)

print('\n== ini duplicados: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
