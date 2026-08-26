"""E2E battery for v0.78.0-beta - hermes' supplement #1 and #2.

#1 Structured outcomes: the MCP result of every string-answering tool now
   carries structuredContent {ok, code} and isError, so a client never has to
   parse Spanish prefixes. The human text stays byte-identical - the contract
   is additive. Codes: DENIED (policy refusal: jail, guard, ownership),
   NOT_FOUND (the named thing is not there), INVALID_PARAM (the call was
   wrong), INTERNAL (server broke - report it). The jail's anti-probing
   property survives: outside-the-jail refusals use one fixed text whether
   the target exists or not, so both map to DENIED.

#2 Real JSON Schema defaults: optional parameters that have a measured
   default now emit it as a schema "default" (typed), instead of prose only.

  R1  success answers ok:true and no isError
  R2  in-jail missing file answers NOT_FOUND + isError
  R3  outside-the-jail answers DENIED whether the target exists or not
  R4  a wrong parameter value answers INVALID_PARAM
  R5  tools/list carries typed defaults (build platform/config, search
      maxresults, config section)

Usage:  python tests/test_round17.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round17')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
open(os.path.join(BASE, 'ok.pas'), 'w').write(
    'unit ok;\ninterface\nimplementation\nend.\n')

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        text=True, encoding='utf-8')
q = queue.Queue()


def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)


threading.Thread(target=reader, daemon=True).start()
rid = [10]
P = F = 0


def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


def recv(r, t=30):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = q.get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None


def call(tool, args):
    """Returns the FULL MCP result object (content + structuredContent...)."""
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": tool, "arguments": args}})
    r = recv(rid[0])
    return (r or {}).get('result', {})


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round17", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

# R1: success
r = call('delphi_read', {'path': os.path.join(BASE, 'ok.pas')})
sc = r.get('structuredContent', {})
check('R1 exito: structuredContent.ok true, sin code, sin isError',
      sc.get('ok') is True and 'code' not in sc and 'isError' not in r,
      (sc, r.get('isError')))

# R2: in-jail missing file
r = call('delphi_read', {'path': os.path.join(BASE, 'no-esta.pas')})
sc = r.get('structuredContent', {})
check('R2 no existe (dentro del jail): NOT_FOUND + isError',
      sc.get('ok') is False and sc.get('code') == 'NOT_FOUND' and
      r.get('isError') is True,
      (sc, r.get('content', [{}])[0].get('text', '')[:120]))

# R3: outside the jail - existing and non-existing must answer the SAME
r_exist = call('delphi_read', {'path': 'C:\\Windows\\win.ini'})
r_ghost = call('delphi_read', {'path': 'C:\\Windows\\no-such-file-zz.ini'})
sce, scg = r_exist.get('structuredContent', {}), r_ghost.get('structuredContent', {})
te = r_exist.get('content', [{}])[0].get('text', '')
tg = r_ghost.get('content', [{}])[0].get('text', '')
check('R3 fuera del jail: DENIED + isError',
      sce.get('code') == 'DENIED' and r_exist.get('isError') is True, sce)
check('R3 anti-sondeo intacto: mismo code y mismo texto exista o no',
      scg.get('code') == 'DENIED' and
      te.replace('win.ini', 'X') == tg.replace('no-such-file-zz.ini', 'X'),
      (te[:80], tg[:80]))

# R4: wrong parameter value
r = call('delphi_config', {'project': os.path.join(BASE, 'ok.pas'),
                           'command': 'marte'})
sc = r.get('structuredContent', {})
check('R4 parametro invalido: INVALID_PARAM + isError',
      sc.get('ok') is False and sc.get('code') == 'INVALID_PARAM' and
      r.get('isError') is True, sc)

# R5: schema defaults in tools/list
rid[0] += 1
send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/list"})
tl = recv(rid[0]) or {}
tools = {t['name']: t for t in tl.get('result', {}).get('tools', [])}


def prop(tool, name):
    return tools.get(tool, {}).get('inputSchema', {}).get(
        'properties', {}).get(name, {})


check('R5 delphi_build: platform default Win32, config default Debug (tipados)',
      prop('delphi_build', 'platform').get('default') == 'Win32' and
      prop('delphi_build', 'config').get('default') == 'Debug' and
      prop('delphi_build', 'target').get('default') == 'Build',
      {k: prop('delphi_build', k).get('default') for k in ('platform', 'config', 'target')})
check('R5 delphi_search: maxresults default 100 como NUMERO',
      prop('delphi_search', 'maxresults').get('default') == 100 and
      not isinstance(prop('delphi_search', 'maxresults').get('default'), str),
      prop('delphi_search', 'maxresults'))
check('R5 delphi_config: section default summary; delphi_test: platform Win64',
      prop('delphi_config', 'section').get('default') == 'summary' and
      prop('delphi_test', 'platform').get('default') == 'Win64',
      (prop('delphi_config', 'section'), prop('delphi_test', 'platform')))

proc.kill()
print('\n== round-17 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
