"""E2E battery for the --http host: Streamable HTTP + Bearer auth.

Usage:  python tests/test_http_auth.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, subprocess, time, os, sys, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, '..', 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
PORT = 3999
URL = 'http://127.0.0.1:%d/mcp' % PORT
TOKEN = 'test-token-123'

env = dict(os.environ)
# Loopback ONLY, for every server this battery starts. Listening on all
# interfaces makes Windows Firewall pop its "allow this app?" prompt, and the
# firewall remembers a decision per program PATH - so the instances below, which
# run the exe from a FRESH random temp folder each time, asked again on every
# single run (twice: IPv4 and IPv6) and left a dead rule behind each time. The
# tests only ever talk to 127.0.0.1.
env['DELPHI_MCP_BIND_IP'] = '127.0.0.1'
env['DELPHI_MCP_TOKEN'] = TOKEN
env['DELPHI_MCP_ALLOW_RUN'] = '1'  # so the RO-vs-run check tests the readonly layer
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
                'delphi_paserver', 'delphi_delete', 'delphi_move',
                'delphi_adb', 'delphi_components', 'delphi_styles', 'delphi_messages']
    check('http: tools/list = 31 tools', sorted(names) == sorted(expected), names)

    code, body = post({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": "delphi_list",
                   "arguments": {"root": os.path.join(HERE, '..', 'src'),
                                  "pattern": "*.pas"}}}, TOKEN)
    check('http: tools/call funciona', code == 200 and 'Lsp.Patch.pas' in body,
          '%s %s' % (code, body[:150]))

    # --- malformed "arguments" must NEVER crash the binder (measured AV:
    # arguments as [], absent, or a string reached Tool.Execute as nil) ---
    for label, params in [('array', {"name": "delphi_installs", "arguments": []}),
                          ('ausente', {"name": "delphi_installs"}),
                          ('string', {"name": "delphi_installs",
                                      "arguments": "hola"})]:
        code, body = post({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                           "params": params}, TOKEN)
        check('http: arguments malformado (%s) sin Access violation' % label,
              code == 200 and 'Access violation' not in body
              and 'installs' in body, '%s %s' % (code, body[:200]))
finally:
    proc.kill()

# --- settings.ini [Server] Port: the port must be configurable, not fixed ---
import shutil, tempfile
INI_PORT = 4123
# A FIXED folder, like every other battery uses (delphi-guard-tests,
# delphi-v012-tests...). It used to be mkdtemp, i.e. a new random path on every
# run - and Windows Firewall decides per program PATH, so each run looked like
# a brand-new program and asked again. Same name every time = asked at most
# once, ever.
tmpdir = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'http-ini-port')
shutil.rmtree(tmpdir, ignore_errors=True)
os.makedirs(tmpdir, exist_ok=True)
try:
    exe2 = os.path.join(tmpdir, 'DelphiLspMcp.exe')
    shutil.copyfile(EXE, exe2)
    with open(os.path.join(tmpdir, 'settings.ini'), 'w') as f:
        # BindIP: loopback only - see the note at the top. This instance runs
        # from a fresh temp folder, so without it the firewall asks again on
        # every run of this battery.
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Security]\nAuthToken=%s\n'
                % (INI_PORT, TOKEN))
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
tmpdir3 = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'http-ro')  # fixed, see above
shutil.rmtree(tmpdir3, ignore_errors=True)
os.makedirs(tmpdir3, exist_ok=True)
try:
    exe3 = os.path.join(tmpdir3, 'DelphiLspMcp.exe')
    shutil.copyfile(EXE, exe3)
    paspath = os.path.join(tmpdir3, 'Sample.pas')
    with open(paspath, 'w') as f:
        f.write('unit Sample;\r\ninterface\r\nimplementation\r\nend.\r\n')
    with open(os.path.join(tmpdir3, 'settings.ini'), 'w') as f:
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Security]\nAuthToken=%s\n'
                'ReadOnlyToken=%s\nAnonymousReadOnly=1\nAllowRun=1\n'
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

        # delphi_styles is mixed: view/get/lint read, set/clone/build write
        code, body = call('delphi_styles', {'path': tmpdir3, 'command': 'lint'}, RO_TOKEN)
        check('ro: delphi_styles lint permitido en RO', 'SOLO LECTURA' not in body,
              '%s %s' % (code, body[:120]))
        for cmd in ('set', 'clone', 'build'):
            code, body = call('delphi_styles', {'path': tmpdir3, 'command': cmd,
                                                'style': 'x', 'prop': 'y', 'value': 'z', 'name': 'n'}, RO_TOKEN)
            check('ro: delphi_styles %s RECHAZADO en RO' % cmd, 'SOLO LECTURA' in body,
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

        # The read-only decision itself was bypassable by SPELLING: the gate
        # read 'command' case-sensitively while the RTTI binder resolves it
        # ignoring case and '_', so "Command" made the gate see no command at
        # all (delphi_config -> treated as "view", a read) while the handler
        # received add-platform and wrote the .dproj.
        _dproj = paspath.replace('.pas', '.dproj')
        _before = os.path.getmtime(_dproj) if os.path.exists(_dproj) else None
        for spelling in ('Command', 'COMMAND', 'com_mand'):
            code, body = call('delphi_config', {'repo': REPO, 'project': _dproj,
                                                spelling: 'add-platform',
                                                'platform': 'Linux64'}, RO_TOKEN)
            check('ro: delphi_config con "%s" sigue siendo SOLO LECTURA' % spelling,
                  'SOLO LECTURA' in body, '%s %s' % (code, body[:130]))
        if _before is not None:
            check('ro: el .dproj no fue modificado por el escape de mayusculas',
                  os.path.getmtime(_dproj) == _before, _dproj)
        # same class on git: an annotated tag hidden behind "Message"
        code, body = call('delphi_git', {'repo': REPO, 'command': 'tag',
                                         'args': 'v9', 'Message': 'x'}, RO_TOKEN)
        check('ro: git tag anotado via "Message" RECHAZADO en RO',
              'SOLO LECTURA' in body or 'RECHAZADO' in body,
              '%s %s' % (code, body[:130]))

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
        # delphi_components is pure read (a registry listing, no process
        # spawned): fine in RO, and any RAD install registers Embarcadero's
        # own design packages, so the unfiltered list always mentions them
        code, body = call('delphi_components', {}, RO_TOKEN)
        check('ro: delphi_components PERMITIDO en RO y lista packages',
              code == 200 and 'SOLO LECTURA' not in body and 'Embarcadero' in body,
              '%s %s' % (code, body[:150]))
        code, body = call('delphi_components', {'filter': 'zz-no-existe-zz'}, RO_TOKEN)
        check('ro: delphi_components filter sin resultados responde honesto',
              'Ningun package' in body, '%s %s' % (code, body[:150]))
        # delete/move are mutating: refused read-only
        code, body = call('delphi_delete', {'path': paspath}, RO_TOKEN)
        check('ro: delphi_delete RECHAZADO en RO', 'SOLO LECTURA' in body, '%s %s' % (code, body[:120]))
        code, body = call('delphi_move', {'path': paspath, 'dest': paspath + '.x'}, RO_TOKEN)
        check('ro: delphi_move RECHAZADO en RO', 'SOLO LECTURA' in body, '%s %s' % (code, body[:120]))

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

# --- /files: direct download route + delphi_fetch link-only for big files ----
# Born in the field (2026-08-21): a 72 MB PAServer installer pulled as base64
# chunks through an agent's context. Bytes travel as HTTP now - same exe,
# same port, same Bearer gate, same read jail.
import hashlib, urllib.parse
FILES_PORT = 4317
tmpdir4 = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'http-files')  # fixed, see above
shutil.rmtree(tmpdir4, ignore_errors=True)
jail4 = os.path.join(tmpdir4, 'jail')
os.makedirs(os.path.join(jail4, 'sub'), exist_ok=True)
os.makedirs(os.path.join(tmpdir4, 'outside'), exist_ok=True)
try:
    exe4 = os.path.join(tmpdir4, 'DelphiLspMcp.exe')
    shutil.copyfile(EXE, exe4)
    small = os.path.join(jail4, 'small.txt')
    with open(small, 'wb') as f:
        f.write(b'hola mundo\r\n')
    bigdata = os.urandom(5 * 1024 * 1024 + 17)          # > 4 MB threshold
    big = os.path.join(jail4, 'big.bin')
    with open(big, 'wb') as f:
        f.write(bigdata)
    big_sha = hashlib.sha256(bigdata).hexdigest()
    with open(os.path.join(tmpdir4, 'outside', 'secret.txt'), 'wb') as f:
        f.write(b'no me bajes')
    with open(os.path.join(tmpdir4, 'settings.ini'), 'w') as f:
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Security]\nAuthToken=%s\n'
                'ReadOnlyToken=%s\n\n[Workspace]\nRoots=%s\n'
                % (FILES_PORT, TOKEN, RO_TOKEN, jail4))
    env4 = dict(os.environ)
    env4.pop('DELPHI_MCP_TOKEN', None)
    env4.pop('DELPHI_MCP_ROOTS', None)
    proc4 = subprocess.Popen([exe4, '--http'], env=env4,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)
    try:
        URL = 'http://127.0.0.1:%d/mcp' % FILES_PORT
        BASE = 'http://127.0.0.1:%d' % FILES_PORT
        drive = jail4[0].lower()
        vjail = 'srv%s:%s' % (drive, jail4[2:])          # D:\x -> srvd:\x

        def get(path_value, token, method='GET', raw_url=None):
            url = raw_url or (BASE + '/files?path=' + urllib.parse.quote(path_value, safe=''))
            req = urllib.request.Request(url, method=method)
            if token:
                req.add_header('Authorization', 'Bearer ' + token)
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return r.status, dict(r.headers), r.read()
            except urllib.error.HTTPError as e:
                return e.code, dict(e.headers), e.read()

        def call(tool, args, token):
            return post({"jsonrpc": "2.0", "id": 9, "method": "tools/call",
                         "params": {"name": tool, "arguments": args}}, token)

        code, hdr, data = get(vjail + '\\small.txt', None)
        check('files: sin token -> 401', code == 401, code)
        code, hdr, data = get(vjail + '\\small.txt', RO_TOKEN)
        check('files: token RO descarga el fichero (bytes identicos)',
              code == 200 and data == b'hola mundo\r\n', '%s %r' % (code, data[:40]))
        check('files: Content-Disposition con el nombre',
              'small.txt' in hdr.get('Content-Disposition', ''), hdr.get('Content-Disposition'))
        check('files: X-File-SHA256 correcto',
              hdr.get('X-File-SHA256', '').lower() == hashlib.sha256(b'hola mundo\r\n').hexdigest(),
              hdr.get('X-File-SHA256'))
        code, hdr, data = get('srv%s:%s' % (drive, os.path.join(tmpdir4, 'outside', 'secret.txt')[2:]), TOKEN)
        check('files: fuera de la jaula -> 403 FUERA', code == 403 and b'FUERA' in data,
              '%s %r' % (code, data[:120]))
        check('files: el rechazo no ensena letras reales', b'"' + jail4[:2].encode() not in data, data[:160])
        code, hdr, data = get(vjail + '\\sub', TOKEN)
        check('files: directorio -> 403', code == 403 and b'directorio' in data, '%s %r' % (code, data[:100]))
        code, hdr, data = get(vjail + '\\nada.bin', TOKEN)
        check('files: no existe -> 404', code == 404, '%s %r' % (code, data[:100]))
        code, hdr, data = get('', TOKEN, raw_url=BASE + '/files')
        check('files: sin path -> 400', code == 400, '%s %r' % (code, data[:100]))
        code, hdr, data = get(vjail + '\\small.txt', TOKEN, method='POST')
        check('files: POST -> 405', code == 405, code)
        code, hdr, data = get('srvz:\\Windows\\win.ini', TOKEN)
        check('files: unidad no servida rechazada POR NOMBRE (sin tocar disco)',
              code == 403 and b'no servida' in data and b'Windows' not in data.split(b'srvz:')[0],
              '%s %r' % (code, data[:140]))
        code, hdr, data = get('sub\\x.txt', TOKEN)
        check('files: ruta relativa -> 400 absoluta', code == 400 and b'absoluta' in data,
              '%s %r' % (code, data[:100]))

        # delphi_fetch: small file = chunk + link; big file = link ONLY
        code, body = call('delphi_fetch', {'path': vjail + '\\small.txt'}, TOKEN)
        js = json.loads(json.loads(body)['result']['content'][0]['text'])
        check('fetch: fichero pequeno trae chunkBase64 Y download',
              'chunkBase64' in js and js.get('download', '').startswith('/files?path=srv'),
              body[:200])
        code, body = call('delphi_fetch', {'path': vjail + '\\big.bin'}, TOKEN)
        js = json.loads(json.loads(body)['result']['content'][0]['text'])
        check('fetch: fichero > 4 MB responde SOLO enlace (sin chunk, con sha256)',
              'chunkBase64' not in js and js.get('bytes') == 0 and js.get('sha256') == big_sha
              and 'download' in js and '"download" link' in js.get('note', ''),
              body[:300])
        check('fetch: la respuesta del fichero grande es corta',
              len(body) < 4000, len(body))
        code, hdr, data = get('', RO_TOKEN, raw_url=BASE + js['download'])
        check('files: el enlace de fetch baja el fichero grande integro (sha256 OK)',
              code == 200 and hashlib.sha256(data).hexdigest() == big_sha
              and hdr.get('X-File-SHA256', '').lower() == big_sha,
              '%s %d bytes' % (code, len(data)))
        code, body = call('delphi_fetch', {'path': vjail + '\\big.bin', 'maxbytes': 1048576}, TOKEN)
        js = json.loads(json.loads(body)['result']['content'][0]['text'])
        check('fetch: maxbytes<=1MB explicito SI trae chunk del fichero grande (opt-in)',
              'chunkBase64' in js and js.get('bytes') == 1048576, body[:200])
    finally:
        proc4.kill()
        proc4.wait()
finally:
    shutil.rmtree(tmpdir4, ignore_errors=True)

print()
print('== http battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
