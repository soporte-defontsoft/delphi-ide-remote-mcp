# -*- coding: utf-8 -*-
"""E2E battery for v0.88.0-beta - token-scoped workspaces ([Workspace.*]).

The secret decides the jail, not the self-declared agent name: each
[Workspace.<name>] section carries its own Token (read-write inside its
Roots), optional ReadOnlyToken, and optional Profile. HARD boundary by
operator decision (2026-08-28): other workspaces' roots are not even
READABLE. The global AuthToken stays the operator - every root, unchanged.

Overlap is deliberate and must never subtract: here Workspace.Ancho holds a
whole tree and Workspace.Fino holds a THIRD-LEVEL subfolder of that same
tree (the operator's exact case). Ancho still sees the subfolder; Fino never
leaves it.

  W1  wrong token: 401
  W2  Fino (subfolder root): writes inside; write AND read outside -> refused
  W3  Ancho: writes its whole tree INCLUDING Fino's subfolder (no subtraction),
      but not the operator's area outside its root
  W4  operator token: everything, as always
  W5  per-workspace ReadOnlyToken: reads inside its roots, cannot write
  W6  per-workspace Profile=reader trims that token's tools/list only

Usage:  python tests/test_round23.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, time, os, sys, tempfile, shutil, socket, urllib.request, urllib.error

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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round23')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'ws23base')
ANCHO = os.path.join(JAIL, 'ancho')
FINO = os.path.join(ANCHO, 'a', 'b', 'c')          # 3rd-level subfolder of ANCHO
os.makedirs(EXEDIR)
os.makedirs(FINO)
os.makedirs(os.path.join(ANCHO, 'otra'))
open(os.path.join(ANCHO, 'otra', 's.pas'), 'w').write('unit s;\n')
open(os.path.join(FINO, 'dentro.pas'), 'w').write('unit dentro;\n')
open(os.path.join(JAIL, 'fuera.txt'), 'w').write('operador\n')

EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
OP, TA, TF, TFRO = 'op-token-23', 'tok-ancho-23', 'tok-fino-23', 'tok-fino-ro-23'
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Security]', 'AuthToken=%s' % OP, '',
    '[Workspace]', 'Roots=%s' % JAIL, '',
    '[Workspace.Ancho]', 'Token=%s' % TA, 'Roots=%s' % ANCHO, '',
    '[Workspace.Fino]', 'Token=%s' % TF, 'ReadOnlyToken=%s' % TFRO,
    'Roots=%s' % FINO, 'Profile=reader', '',
]))

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.3)
URL = 'http://127.0.0.1:%d/mcp' % PORT


def rpc(body, token, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if token is not None:
        h['Authorization'] = 'Bearer ' + token
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=30)
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
            msgs = [json.loads(raw)]
        except Exception:
            pass
    return msgs, r.headers.get('Mcp-Session-Id')


def session(token, name):
    _, sid = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}}, token)
    rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, token, sid)
    return sid


def call(token, sid, tool, args):
    m, _ = rpc({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                "params": {"name": tool, "arguments": args}}, token, sid)
    for x in m:
        if x.get('id') == 7:
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


def toolnames(token, sid):
    m, _ = rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, token, sid)
    for x in m:
        if x.get('id') == 2:
            return {t['name'] for t in x['result']['tools']}
    return set()


try:
    # W1: wrong token -> 401
    try:
        rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "x", "version": "1"}}}, 'token-malo')
        check('W1 token malo: 401', False, 'acepto un token invalido')
    except urllib.error.HTTPError as e:
        check('W1 token malo: 401', e.code == 401, e.code)

    # W2: Fino - a 3rd-level subfolder as its whole world
    sf = session(TF, 'fino')
    r = call(TF, sf, 'delphi_textedit',
             {'path': os.path.join(FINO, 'mio.txt'), 'create': True, 'content': 'x'})
    check('W2 Fino escribe dentro de su subcarpeta',
          os.path.exists(os.path.join(FINO, 'mio.txt')), r[:160])
    r = call(TF, sf, 'delphi_textedit',
             {'path': os.path.join(ANCHO, 'hack.txt'), 'create': True, 'content': 'x'})
    check('W2 Fino NO escribe fuera (un nivel arriba)',
          'RECHAZADO' in r and not os.path.exists(os.path.join(ANCHO, 'hack.txt')), r[:160])
    r = call(TF, sf, 'delphi_read', {'path': os.path.join(ANCHO, 'otra', 's.pas')})
    check('W2 frontera DURA: Fino ni siquiera LEE fuera de su root',
          'RECHAZADO' in r and 'unit s' not in r, r[:160])
    r = call(TF, sf, 'delphi_list', {'root': JAIL})
    check('W2 Fino tampoco lista el arbol del operador',
          'RECHAZADO' in r and 'fuera.txt' not in r, r[:160])

    # W3: Ancho - overlap never subtracts
    sa = session(TA, 'ancho')
    r = call(TA, sa, 'delphi_textedit',
             {'path': os.path.join(FINO, 'de-ancho.txt'), 'create': True, 'content': 'x'})
    check('W3 Ancho SI escribe en la subcarpeta que ademas es root de Fino (el solape no resta)',
          os.path.exists(os.path.join(FINO, 'de-ancho.txt')), r[:160])
    r = call(TA, sa, 'delphi_textedit',
             {'path': os.path.join(ANCHO, 'suyo.txt'), 'create': True, 'content': 'x'})
    check('W3 Ancho escribe en su arbol', os.path.exists(os.path.join(ANCHO, 'suyo.txt')), r[:160])
    r = call(TA, sa, 'delphi_read', {'path': os.path.join(JAIL, 'fuera.txt')})
    check('W3 Ancho no sale de su workspace (zona del operador vetada)',
          'RECHAZADO' in r and 'operador' not in r, r[:160])

    # W4: operator token - everything, as always
    so = session(OP, 'operador')
    r = call(OP, so, 'delphi_read', {'path': os.path.join(FINO, 'dentro.pas')})
    check('W4 operador lee dentro de Fino', 'unit dentro' in r, r[:160])
    r = call(OP, so, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'op.txt'), 'create': True, 'content': 'x'})
    check('W4 operador escribe en la raiz global', os.path.exists(os.path.join(JAIL, 'op.txt')), r[:160])

    # W5: per-workspace read-only token
    sro = session(TFRO, 'fino-ro')
    r = call(TFRO, sro, 'delphi_read', {'path': os.path.join(FINO, 'dentro.pas')})
    check('W5 token RO del workspace lee dentro', 'unit dentro' in r, r[:160])
    r = call(TFRO, sro, 'delphi_textedit',
             {'path': os.path.join(FINO, 'ro.txt'), 'create': True, 'content': 'x'})
    check('W5 token RO no escribe ni dentro',
          not os.path.exists(os.path.join(FINO, 'ro.txt')), r[:160])
    r = call(TFRO, sro, 'delphi_read', {'path': os.path.join(ANCHO, 'otra', 's.pas')})
    check('W5 token RO tampoco lee fuera de sus roots', 'RECHAZADO' in r, r[:160])

    # W6: per-workspace Profile trims only that token's listing
    names_f = toolnames(TF, sf)
    names_a = toolnames(TA, sa)
    check('W6 Profile=reader del workspace Fino recorta SU tools/list',
          'delphi_edit' not in names_f and 'delphi_read' in names_f and
          len(names_f) < len(names_a), (len(names_f), len(names_a)))
    check('W6 Ancho (sin Profile) sigue viendo el censo completo',
          'delphi_edit' in names_a and 'delphi_build' in names_a, len(names_a))
finally:
    proc.kill()

print('\n== round-23 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
