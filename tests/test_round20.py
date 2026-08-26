"""E2E battery for v0.83.0-beta - hermes' P1.4: tool-surface profiles.

tools/list measured 62.7k chars / 41 tools (~15k tokens) before an agent had
done anything - the #1 wall for small models. Opt-in trim, OFF by default:
[Tools] Profile=reader|coder|full (or env DELPHI_MCP_TOOLS_PROFILE), plus an
explicit allowlist Only= that overrides the profile. LISTING only: hidden
tools stay callable - permissions remain the access levels and the jail.
delphi_help / delphi_messages / delphi_report are always listed.

  T1  default: all 41 tools listed (no behavior change)
  T2  reader: only the reading/navigation set; edit/build/adb absent
  T3  reader: a HIDDEN tool is still callable (delphi_textedit works)
  T4  coder: everything except adb/paserver/package
  T5  Only= allowlist wins over the profile and keeps the always-set
  T6  unknown profile name hides nothing (fails open, it is not security)

Usage:  python tests/test_round20.py [path-to-DelphiLspMcp.exe]
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


def start(extra_env):
    base = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests',
                        'round20-%d' % (int(time.time() * 1000) % 100000))
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    exe = os.path.join(base, 'DelphiLspMcp.exe')
    shutil.copy(SRC, exe)
    sk = socket.socket()
    sk.bind(('127.0.0.1', 0))
    port = sk.getsockname()[1]
    sk.close()
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = base
    env.update(extra_env)
    proc = subprocess.Popen([exe, '--http', str(port)], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2.3)
    return base, 'http://127.0.0.1:%d/mcp' % port, proc


def rpc(url, body, sid=None):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream'}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        url, data=json.dumps(body).encode(), headers=h, method='POST'), timeout=30)
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


def session(url):
    _, sid = rpc(url, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                       "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                  "clientInfo": {"name": "round20", "version": "1"}}})
    rpc(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return sid


def toolnames(url, sid):
    m, _ = rpc(url, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, sid)
    for x in m:
        if x.get('id') == 2:
            return {t['name'] for t in x['result']['tools']}
    return set()


def call(url, sid, tool, args):
    m, _ = rpc(url, {"jsonrpc": "2.0", "id": 7, "method": "tools/call",
                     "params": {"name": tool, "arguments": args}}, sid)
    for x in m:
        if x.get('id') == 7:
            return x.get('result', {}).get('content', [{}])[0].get('text', 'ERR')
    return '(no)'


READER = {'delphi_read', 'delphi_list', 'delphi_search', 'delphi_symbols',
          'delphi_definition', 'delphi_hover', 'delphi_signature',
          'delphi_completion', 'delphi_diagnostics', 'delphi_references',
          'delphi_projects', 'delphi_installs', 'delphi_workspace',
          'delphi_fetch', 'delphi_help', 'delphi_messages', 'delphi_report',
          'vault_read', 'vault_search'}
DEPLOY = {'delphi_adb', 'delphi_paserver', 'delphi_package'}

# T1 default (the test jail has no vault, so vault_* are not registered:
# every expectation below is relative to THIS server's own census)
base, url, proc = start({})
try:
    sid = session(url)
    ALL = toolnames(url, sid)
    check('T1 sin perfil: el censo completo, con las de escribir dentro',
          'delphi_edit' in ALL and 'delphi_adb' in ALL and len(ALL) >= 36,
          len(ALL))
finally:
    proc.kill()

# T2/T3 reader
base, url, proc = start({'DELPHI_MCP_TOOLS_PROFILE': 'reader'})
try:
    sid = session(url)
    names = toolnames(url, sid)
    check('T2 reader: exactamente el conjunto de lectura/navegacion',
          names == (READER & ALL), sorted(names ^ (READER & ALL)))
    r = call(url, sid, 'delphi_textedit',
             {'path': os.path.join(base, 'x.txt'), 'create': True, 'content': 'x'})
    check('T3 reader: una tool oculta sigue siendo llamable (no es un permiso)',
          'CREADO' in r or 'ESCRITO' in r or os.path.exists(os.path.join(base, 'x.txt')), r[:160])
finally:
    proc.kill()

# T4 coder
base, url, proc = start({'DELPHI_MCP_TOOLS_PROFILE': 'coder'})
try:
    sid = session(url)
    names = toolnames(url, sid)
    check('T4 coder: todo menos el trio de deploy',
          names == (ALL - DEPLOY), sorted(names ^ (ALL - DEPLOY)))
finally:
    proc.kill()

# T5 allowlist
base, url, proc = start({'DELPHI_MCP_TOOLS_ONLY': 'delphi_read,delphi_search'})
try:
    sid = session(url)
    names = toolnames(url, sid)
    check('T5 Only= gana al perfil y conserva help/messages/report',
          names == {'delphi_read', 'delphi_search', 'delphi_help',
                    'delphi_messages', 'delphi_report'}, sorted(names))
finally:
    proc.kill()

# T6 unknown profile
base, url, proc = start({'DELPHI_MCP_TOOLS_PROFILE': 'marciano'})
try:
    sid = session(url)
    names = toolnames(url, sid)
    check('T6 perfil desconocido no oculta nada (no es seguridad)',
          names == ALL, sorted(names ^ ALL))
finally:
    proc.kill()

print('\n== round-20 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
