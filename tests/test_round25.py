# -*- coding: utf-8 -*-
"""E2E battery for v0.90.0-beta - per-workspace configs.

Operator decision (2026-09-11): a workspace carries its PAIR, its ROOTS and
its CONFIGS. The [Security] switches become inheritable DEFAULTS; a
[Workspace.<name>] section may override AllowRun, AllowTests, AllowRemoteRun,
AllowBuildScripts, LibraryZone, AgentConfinement and SharedFolders for the
sessions its tokens open. Absent key = inherit.

  C1  global AllowRun=0 but the workspace says AllowRun=1: delphi_run stops
      being "deshabilitada" for THAT token (fails later for other reasons)
  C2  ...and stays disabled for the default-workspace token (inheritance)
  C3  global AllowTests=1 but the workspace says AllowTests=0: refused there
  C4  AgentConfinement=1 only in the workspace: its agent is confined to
      <root>\\<name>\\, while the default token roams free (global off)

Usage:  python tests/test_round25.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, time, os, sys, tempfile, shutil, socket, urllib.request

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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round25')
shutil.rmtree(BASE, ignore_errors=True)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Security]',
    'AllowRun=0',                       # default: no execution
    'AllowTests=1',                     # default: tests allowed
    'AgentConfinement=0', '',
    '[Workspace]', 'Roots=%s' % JAIL, '',
    '[Workspace.Operador]',             # the widest workspace: inherits all
    'Token=op-25',
    'Roots=%s' % JAIL, '',
    '[Workspace.Runner]',               # may run, may NOT test, confined
    'Token=runner-25',
    'Roots=%s' % JAIL,
    'AllowRun=1',
    'AgentConfinement=1', '',
    '[Workspace.Notest]',               # only override: tests OFF here
    'Token=notest-25',
    'Roots=%s' % JAIL,
    'AllowTests=0', '',
]))

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2.5)
URL = 'http://127.0.0.1:%d/mcp' % PORT


def rpc(body, tok, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + tok}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=60)
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


def session(tok, name):
    _, sid = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}}, tok)
    rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, tok, sid)
    return sid


def call(tok, sid, tool, args):
    m, _ = rpc({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                "params": {"name": tool, "arguments": args}}, tok, sid)
    for x in m:
        if x.get('id') == 7:
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


try:
    s_run = session('runner-25', 'agente')
    s_op = session('op-25', 'operador')
    # inside the agent's own subfolder, so the workspace's confinement
    # (also under test in C4) never preempts the run/tests checks
    ghost = os.path.join(JAIL, 'agente', 'no-existe.exe')

    # C1: the workspace override ENABLES run for its token
    r = call('runner-25', s_run, 'delphi_run', {'path': ghost})
    check('C1 AllowRun=1 del workspace: delphi_run deja de estar deshabilitada',
          'deshabilitada' not in r and 'no existe' in r, r[:200])

    # C2: the default workspace still inherits the global 0
    r = call('op-25', s_op, 'delphi_run', {'path': ghost})
    check('C2 el token default sigue con run deshabilitada (hereda el 0 global)',
          'deshabilitada' in r, r[:200])

    # C3: a workspace whose ONLY override is AllowTests=0 (its AllowRun is
    # inherited 0, so the AllowRun-implies-tests superset does not apply)
    s_nt = session('notest-25', 'probador')
    r = call('notest-25', s_nt, 'delphi_test',
             {'command': 'run', 'project': os.path.join(JAIL, 'X.dproj')})
    check('C3 AllowTests=0 del workspace gana al 1 global: tests rechazados',
          'AllowTests' in r or 'deshabilitad' in r, r[:200])
    r = call('op-25', s_op, 'delphi_test',
             {'command': 'run', 'project': os.path.join(JAIL, 'X.dproj')})
    check('C3b el token default hereda AllowTests=1 (pasa el gate, falla despues)',
          'AllowTests' not in r and 'deshabilitad' not in r, r[:200])

    # C4: confinement only inside the workspace
    r = call('runner-25', s_run, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'suelto.txt'), 'create': True, 'content': 'x'})
    check('C4 confinamiento del workspace: su agente NO escribe suelto en la raiz',
          'RECHAZADO' in r and 'confinado' in r and
          not os.path.exists(os.path.join(JAIL, 'suelto.txt')), r[:200])
    r = call('runner-25', s_run, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'agente', 'mio.txt'), 'create': True, 'content': 'x'})
    check('C4b ...pero si en SU subcarpeta',
          os.path.exists(os.path.join(JAIL, 'agente', 'mio.txt')), r[:200])
    r = call('op-25', s_op, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'libre.txt'), 'create': True, 'content': 'x'})
    check('C4c el token default roams free (confinamiento global apagado)',
          os.path.exists(os.path.join(JAIL, 'libre.txt')), r[:200])
finally:
    proc.kill()

print('\n== round-25 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
