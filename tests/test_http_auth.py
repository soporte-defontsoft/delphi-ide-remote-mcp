"""E2E battery for the --http host: Streamable HTTP + Bearer auth.

Usage:  python tests/test_http_auth.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, subprocess, time, os, sys, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, '..', 'src', 'Win64', 'Debug', 'DelphiLspMcp.exe')
PORT = 3999
URL = 'http://127.0.0.1:%d/mcp' % PORT
TOKEN = 'test-token-123'

env = dict(os.environ)
env['DELPHI_MCP_TOKEN'] = TOKEN
proc = subprocess.Popen([EXE, '--http', str(PORT)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)

P = F = 0
def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:170])

def post(payload, token=None):
    req = urllib.request.Request(URL, json.dumps(payload).encode('utf-8'),
        {'Content-Type': 'application/json', 'Accept': 'application/json'})
    if token:
        req.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')

INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "http-battery", "version": "1"}}}

try:
    code, body = post(INIT)
    check('http: sin token -> 401', code == 401, '%s %s' % (code, body[:100]))
    code, body = post(INIT, 'wrong-token')
    check('http: token erroneo -> 401', code == 401, '%s %s' % (code, body[:100]))
    code, body = post(INIT, TOKEN)
    ok = code == 200 and 'delphi-lsp-mcp-service' in body
    check('http: initialize con token', ok, '%s %s' % (code, body[:150]))

    code, body = post({"jsonrpc": "2.0", "id": 2, "method": "tools/list",
                       "params": {}}, TOKEN)
    try:
        names = sorted(t['name'] for t in json.loads(body)['result']['tools'])
    except Exception:
        names = []
    expected = ['delphi_build', 'delphi_completion', 'delphi_create',
                'delphi_definition', 'delphi_diagnostics', 'delphi_edit',
                'delphi_fetch', 'delphi_git', 'delphi_hover',
                'delphi_installs', 'delphi_list', 'delphi_package',
                'delphi_config', 'delphi_projects', 'delphi_read',
                'delphi_references', 'delphi_report', 'delphi_run',
                'delphi_search', 'delphi_signature', 'delphi_symbols',
                'delphi_textedit', 'delphi_upload', 'delphi_workspace',
                'delphi_paserver']
    check('http: tools/list = 25 tools', sorted(names) == sorted(expected), names)

    code, body = post({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": "delphi_list",
                   "arguments": {"root": os.path.join(HERE, '..', 'src'),
                                  "pattern": "*.pas"}}}, TOKEN)
    check('http: tools/call funciona', code == 200 and 'Lsp.Patch.pas' in body,
          '%s %s' % (code, body[:150]))
finally:
    proc.kill()

# --- settings.ini [Server] Port: the port must be configurable, not fixed ---
import shutil, tempfile
INI_PORT = 4123
tmpdir = tempfile.mkdtemp(prefix='mcp-ini-port-')
try:
    exe2 = os.path.join(tmpdir, 'DelphiLspMcp.exe')
    shutil.copyfile(EXE, exe2)
    with open(os.path.join(tmpdir, 'settings.ini'), 'w') as f:
        f.write('[Server]\nPort=%d\n\n[Security]\nAuthToken=%s\n' % (INI_PORT, TOKEN))
    env2 = dict(os.environ)
    env2.pop('DELPHI_MCP_TOKEN', None)  # the ini must supply the token too
    proc2 = subprocess.Popen([exe2, '--http'],  # no port argument: ini decides
                             env=env2,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)
    try:
        URL = 'http://127.0.0.1:%d/mcp' % INI_PORT
        code, body = post(INIT, TOKEN)
        check('ini: [Server] Port respetado sin --http <puerto>',
              code == 200 and 'delphi-lsp-mcp-service' in body,
              '%s %s' % (code, body[:120]))
    finally:
        proc2.kill()
        proc2.wait()
finally:
    shutil.rmtree(tmpdir, ignore_errors=True)

# --- read-only access: ReadOnlyToken + AnonymousReadOnly ---------------------
RO_PORT = 4241
RO_TOKEN = 'ro-token-456'
REPO = os.path.abspath(os.path.join(HERE, '..'))
tmpdir3 = tempfile.mkdtemp(prefix='mcp-ro-')
try:
    exe3 = os.path.join(tmpdir3, 'DelphiLspMcp.exe')
    shutil.copyfile(EXE, exe3)
    paspath = os.path.join(tmpdir3, 'Sample.pas')
    with open(paspath, 'w') as f:
        f.write('unit Sample;\r\ninterface\r\nimplementation\r\nend.\r\n')
    with open(os.path.join(tmpdir3, 'settings.ini'), 'w') as f:
        f.write('[Server]\nPort=%d\n\n[Security]\nAuthToken=%s\n'
                'ReadOnlyToken=%s\nAnonymousReadOnly=1\n'
                % (RO_PORT, TOKEN, RO_TOKEN))
    env3 = dict(os.environ)
    env3.pop('DELPHI_MCP_TOKEN', None)
    proc3 = subprocess.Popen([exe3, '--http'], env=env3,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)
    try:
        URL = 'http://127.0.0.1:%d/mcp' % RO_PORT

        def call(tool, args, token):
            return post({"jsonrpc": "2.0", "id": 9, "method": "tools/call",
                         "params": {"name": tool, "arguments": args}}, token)

        code, body = call('delphi_list', {'root': os.path.join(REPO, 'src'),
                                          'pattern': '*.pas'}, RO_TOKEN)
        check('ro: token RO puede leer (delphi_list)',
              code == 200 and 'Lsp.Guard.pas' in body, '%s %s' % (code, body[:120]))

        code, body = call('delphi_edit', {'path': paspath, 'old': 'interface',
                                          'new': 'interface // x'}, RO_TOKEN)
        check('ro: token RO NO puede editar', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:150]))

        for tool, args in (('delphi_build', {'project': 'x.dproj'}),
                           ('delphi_run', {'path': 'x.exe'}),
                           ('delphi_package', {'dir': tmpdir3}),
                           ('delphi_create', {'kind': 'project-console',
                                              'dir': tmpdir3, 'name': 'X'})):
            code, body = call(tool, args, RO_TOKEN)
            check('ro: token RO NO puede %s' % tool, 'SOLO LECTURA' in body,
                  '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'status'},
                          RO_TOKEN)
        check('ro: git status permitido en RO',
              code == 200 and 'SOLO LECTURA' not in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'commit',
                                         'message': 'nope'}, RO_TOKEN)
        check('ro: git commit RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'branch',
                                         'args': 'nueva-rama'}, RO_TOKEN)
        check('ro: git branch con args RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_textedit', {'path': tmpdir3 + '\\x.md',
                                              'create': True,
                                              'content': 'nope'}, RO_TOKEN)
        check('ro: delphi_textedit RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'tag'},
                          RO_TOKEN)
        check('ro: git tag sin args (listar) permitido en RO',
              code == 200 and 'SOLO LECTURA' not in body,
              '%s %s' % (code, body[:120]))

        # tag with a message = annotated tag = a WRITE. The gate must catch it
        # even with empty args (it only looked at args before — field audit).
        code, body = call('delphi_git', {'repo': REPO, 'command': 'tag',
                                         'message': 'v1'}, RO_TOKEN)
        check('ro: git tag con message (anotado) RECHAZADO en RO',
              'SOLO LECTURA' in body, '%s %s' % (code, body[:120]))

        # jail/file-write escape: diff --output must be refused (would let a
        # read-only client write a file anywhere on disk).
        code, body = call('delphi_git', {'repo': REPO, 'command': 'diff',
                                         'args': '--output=' + tmpdir3 + '\\PWN.txt'},
                          RO_TOKEN)
        check('ro: git diff --output RECHAZADO en RO', 'RECHAZADO' in body,
              '%s %s' % (code, body[:120]))
        check('ro: git diff --output no escribio el fichero',
              not os.path.exists(tmpdir3 + '\\PWN.txt'), tmpdir3)

        # delphi_report is the ONE write available read-only, by design: the
        # restricted agents are the ones most likely to hit a wall.
        code, body = call('delphi_report',
                          {'message': 'Reporte desde credencial de solo lectura.',
                           'title': 'RO puede reportar', 'from': 'test_http_auth'},
                          RO_TOKEN)
        check('ro: delphi_report PERMITIDO en RO (canal de feedback)',
              code == 200 and 'GRACIAS' in body, '%s %s' % (code, body[:150]))

        # delphi_config: view reads (OK in RO), add-platform writes (refused)
        code, body = call('delphi_config', {'repo': REPO, 'command': 'view',
                                            'project': paspath.replace('.pas', '.dproj')},
                          RO_TOKEN)
        check('ro: delphi_config view NO da SOLO LECTURA', 'SOLO LECTURA' not in body,
              '%s %s' % (code, body[:120]))
        code, body = call('delphi_config', {'command': 'add-platform',
                                            'platform': 'Linux64',
                                            'project': paspath.replace('.pas', '.dproj')},
                          RO_TOKEN)
        check('ro: delphi_config add-platform RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))
        # delphi_paserver is read-only, always available
        code, body = call('delphi_paserver', {'command': 'platforms'}, RO_TOKEN)
        check('ro: delphi_paserver PERMITIDO en RO', code == 200 and 'SOLO LECTURA' not in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'push'},
                          RO_TOKEN)
        check('ro: git push RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_upload', {'path': tmpdir3 + '\\x.bin',
                                            'offset': 0,
                                            'chunkbase64': 'AAAA'}, RO_TOKEN)
        check('ro: delphi_upload RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'clone',
                                         'message': 'https://example.com/x.git'},
                          RO_TOKEN)
        check('ro: git clone RECHAZADO en RO', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_edit', {'path': paspath, 'old': 'interface',
                                          'new': 'interface'}, TOKEN)
        check('ro: token completo SI pasa la puerta',
              code == 200 and 'SOLO LECTURA' not in body,
              '%s %s' % (code, body[:150]))

        code, body = call('delphi_list', {'root': os.path.join(REPO, 'src'),
                                          'pattern': '*.pas'}, None)
        check('ro: anonimo (AnonymousReadOnly=1) puede leer',
              code == 200 and 'Lsp.Guard.pas' in body, '%s %s' % (code, body[:120]))

        code, body = call('delphi_edit', {'path': paspath, 'old': 'interface',
                                          'new': 'interface // y'}, None)
        check('ro: anonimo NO puede editar', 'SOLO LECTURA' in body,
              '%s %s' % (code, body[:150]))

        code, body = call('delphi_list', {'root': REPO}, 'wrong-token')
        check('ro: token erroneo sigue siendo 401', code == 401,
              '%s %s' % (code, body[:100]))
    finally:
        proc3.kill()
        proc3.wait()
finally:
    shutil.rmtree(tmpdir3, ignore_errors=True)

print()
print('== http battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
