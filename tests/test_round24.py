# -*- coding: utf-8 -*-
"""E2E battery for v0.89.0-beta - one auth mechanism: workspaces.

Operator decision (2026-09-11, after his own [Workopenclaw]+AuthToken= section
vanished silently and its token answered 401 with no clue anywhere):

  - inside a [Workspace.<name>] section, AuthToken= works as an ALIAS of
    Token= (everyone has already typed [Security] AuthToken once; the hand
    repeats it);
  - the startup log LISTS the loaded workspaces - with the legacy [Security]
    pair reported as the "default" workspace over the global roots - and
    WARNS about misconfigurations: misspelled sections ([Workopenclaw]),
    tokenless workspaces, unparseable roots.

  A1  AuthToken= inside a workspace section authenticates (alias)
  A2  a misspelled [Workopenclaw] section: token 401 AND a startup AVISO
      naming the section and the right format
  A3  a tokenless workspace: startup AVISO says IGNORADA and names the key
  A4  startup lists 'Workspaces:' with default (legacy pair) + the sections

Usage:  python tests/test_round24.py [path-to-DelphiLspMcp.exe]
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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round24')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(os.path.join(JAIL, 'alias'))
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Security]', 'AuthToken=op-24', '',
    '[Workspace]', 'Roots=%s' % JAIL, '',
    '[Workspace.Alias]',
    'AuthToken=alias-24',                 # the alias, on purpose
    'Roots=%s' % os.path.join(JAIL, 'alias'), '',
    '[Workopenclaw]',                     # the misspelled section, verbatim
    'Token=perdido-24',
    'Roots=%s' % JAIL, '',
    '[Workspace.SinToken]',               # tokenless: ignored with a warning
    'Roots=%s' % JAIL, '',
]))

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, encoding='utf-8', errors='replace')
time.sleep(2.5)
URL = 'http://127.0.0.1:%d/mcp' % PORT


def rpc(body, tok, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + tok}
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


def init(tok, name):
    m, sid = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}}, tok)
    return m, sid


try:
    # A1: the alias authenticates and is jailed to its workspace
    m, sid = init('alias-24', 'alias-check')
    check('A1 AuthToken= dentro del workspace autentica (alias de Token=)',
          bool(m and m[0].get('result')), m)

    # A2: the misspelled section's token gets 401
    try:
        init('perdido-24', 'x')
        check('A2 el token de [Workopenclaw] (mal escrita) da 401', False, 'acepto')
    except urllib.error.HTTPError as e:
        check('A2 el token de [Workopenclaw] (mal escrita) da 401', e.code == 401, e.code)

    # v0.91: workspace o nada - the legacy [Security] pair gets 401
    try:
        init('op-24', 'op')
        check('A4a el par [Security] ya NO autentica (workspace o nada)', False, 'entro')
    except urllib.error.HTTPError as e:
        check('A4a el par [Security] ya NO autentica (workspace o nada)',
              e.code == 401, e.code)
finally:
    proc.kill()

out = proc.stdout.read() or ''
check('A2b el arranque AVISA de la seccion mal escrita, por su nombre',
      'Workopenclaw' in out and 'Workspace.<nombre>' in out, out[-400:])
check('A3 el arranque AVISA del workspace sin token (IGNORADA, clave Token=)',
      'SinToken' in out and 'IGNORADA' in out and 'Token=' in out, out[-400:])
check('A4 el arranque LISTA los workspaces (sin ningun "default")',
      'Workspaces:' in out and 'Alias' in out and 'default' not in out, out[-500:])
check('A4b el arranque AVISA de que el par [Security] ya no autentica y como migrar',
      'ya NO autentican' in out and 'Workspace.<nombre>' in out, out[-600:])

print('\n== round-24 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
