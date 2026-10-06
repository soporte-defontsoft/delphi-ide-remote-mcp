"""E2E battery for the --http host: Streamable HTTP + Bearer auth.

Usage:  python tests/test_http_auth.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import hashlib, json, os, shutil, subprocess, time, urllib.error, urllib.parse, urllib.request
import mcp_cliente as mc
from mcp_cliente import check

HERE = mc.HERE
# puertos LIBRES (antes 3999, 4123, 4241, 4317 y 4319 fijos): cada servidor
# lo lee de su settings.ini, y se espera a que escuche en el (antes sleep 3)
PORT = mc.puerto_libre()
URL = 'http://127.0.0.1:%d/mcp' % PORT
TOKEN = 'test-token-123'

# v0.91: workspace o nada - the token lives in a [Workspace.*] section, so
# the main server runs from its own folder with its own settings.ini (fixed
# name: the firewall decides per program PATH; we only talk to 127.0.0.1).
REPOROOT = mc.REPO
_maindir = mc.carpeta('http-main')
_mainexe = mc.copia_exe(_maindir)
with open(os.path.join(_maindir, 'settings.ini'), 'w') as f:
    f.write('[Server]' + chr(10) + 'Port=%d' % PORT + chr(10) + 'BindIP=127.0.0.1' + chr(10)
            + 'DelphiVersion=37.0' + chr(10) * 2   # pinned to the one install here (of the server since 5-oct-2026)
            + '[Workspace.Op]' + chr(10) + 'Token=%s' % TOKEN + chr(10)
            + 'Roots=%s' % REPOROOT + chr(10)
            + 'AllowTests=1' + chr(10) + 'LibraryZone=1' + chr(10))
# sin las DELPHI_MCP_* de quien lanza la bateria: el token lo pone el ini
proc = mc.lanza_http(_mainexe, None, mc.entorno(), espera_en=PORT)   # sin puerto: el del ini


def post(payload, token=None):
    # Accept: application/json A SECAS, no el de un cliente streamable (lo
    # que miran los checks de esta bateria); URL es la del servidor en curso
    code, _, body = mc.post(URL, payload, token, accept='application/json', t=60)
    return code, body

INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "http-battery", "version": "1"}}}

try:
    code, body = post(INIT)
    check('http: sin token -> 401', code == 401, '%s %s' % (code, body[:100]))
    # issue #4 (2026-09-27): the 401 said nothing about how to send the token
    try:
        hint = json.loads(body).get('hint', '')
    except ValueError:
        hint = ''
    check('http: the 401 body is JSON and its hint names the header and the ini section',
          'Authorization: Bearer' in hint and '[Workspace.<name>]' in hint and 'settings.ini' in hint,
          body[:300])
    code, body = post(INIT, 'wrong-token')
    check('http: token erroneo -> 401', code == 401, '%s %s' % (code, body[:100]))
    code, body = post(INIT, TOKEN)
    ok = code == 200 and 'delphi-lsp-mcp-service' in body
    check('http: initialize con token', ok, '%s %s' % (code, body[:150]))
    # 28-sep-2026: dos servidores del mismo nombre y version (13.1 aqui, 13.2 en
    # la VM, mismo token) contestaban sin nada que los distinguiera
    try:
        host = json.loads(body)['result']['serverInfo'].get('host', '')
    except (ValueError, KeyError, TypeError):
        host = ''
    check('http: serverInfo.host es la maquina que contesta (COMPUTERNAME)',
          mc.es_esta_maquina(host), '%s vs %s' % (host, os.environ.get('COMPUTERNAME')))
    # streamable-HTTP clients ask with Accept: text/event-stream and read the
    # session from the Mcp-Session-Id header (v0.46: the SSE path emits it too)
    _, h, sse = mc.post(URL, INIT, TOKEN, accept=mc.ACCEPT_STREAMABLE, t=60)
    sid = h.get('Mcp-Session-Id')
    check('http: initialize por SSE devuelve la cabecera Mcp-Session-Id', bool(sid) and sid in sse,
          'header=%s body=%s' % (sid, sse[:120]))

    # v0.55: una sesion que este proceso NUNCA emitio esta MUERTA (el caso
    # real: el cliente la persiste y el server se reinicia). 404 claro para
    # que el cliente re-inicialice, en vez de trabajar contra un fantasma.
    def post_sid(payload, session, token=TOKEN):
        code, _, body = mc.post(URL, payload, token, session, accept='application/json', t=60)
        return code, body
    code, body = post_sid({"jsonrpc": "2.0", "id": 9, "method": "tools/list", "params": {}},
                          '{BASURA-NO-EMITIDA-JAMAS}')
    check('http: sesion desconocida -> 404 con motivo', code == 404 and mc.es(body, 'SR_SESSION_UNKNOWN'),
          '%s %s' % (code, body[:160]))
    # la puerta del 404 mira el "method", no la palabra en el cuerpo: con
    # arguments:{"command":"initialize"} la tool corria en una sesion muerta
    code, body = post_sid({"jsonrpc": "2.0", "id": 11, "method": "tools/call", "params": {
        "name": "delphi_help", "arguments": {"command": "initialize"}}}, '{BASURA-NO-EMITIDA-JAMAS}')
    check('http: "initialize" dentro de los argumentos no abre una sesion muerta (404)',
          code == 404 and mc.es(body, 'SR_SESSION_UNKNOWN'), '%s %s' % (code, body[:160]))
    code, body = post_sid(INIT, '{BASURA-NO-EMITIDA-JAMAS}')
    check('http: initialize con sesion vieja SI pasa (es el arreglo)',
          code == 200 and 'delphi-lsp-mcp-service' in body, '%s %s' % (code, body[:120]))
    # el anuncio de la sesion es UNO para los dos caminos (sexta revision: estaba
    # escrito dos veces y el JSON habia derivado): un initialize con una sesion
    # muerta anuncia la NUEVA en la cabecera, y una llamada normal repite la suya.
    # Son de REGRESION: la deriva que se arreglo no se puede provocar desde
    # fuera (solo initialize lleva sessionId); si vuelve a haber dos, lo ven.
    for camino, acc in [('JSON', 'application/json'), ('SSE', mc.ACCEPT_STREAMABLE)]:
        _, h, b = mc.post(URL, INIT, TOKEN, '{BASURA-NO-EMITIDA-JAMAS}', accept=acc, t=60)
        nuevo = h.get('Mcp-Session-Id') or ''
        check('http: initialize con sesion muerta anuncia la NUEVA en la cabecera (%s)' % camino,
              nuevo not in ('', '{BASURA-NO-EMITIDA-JAMAS}') and
              ('"sessionId":"%s"' % nuevo) in b.replace(' ', ''),
              'header=%s body=%s' % (nuevo, b[:160]))
        _, h, b = mc.post(URL, {"jsonrpc": "2.0", "id": 12, "method": "tools/list",
                                "params": {}}, TOKEN, nuevo, accept=acc, t=60)
        check('http: una llamada normal repite su sesion en la cabecera (%s)' % camino,
              nuevo != '' and h.get('Mcp-Session-Id') == nuevo and 'delphi_build' in b,
              'header=%s' % h.get('Mcp-Session-Id'))
    code, body = post_sid({"jsonrpc": "2.0", "id": 10, "method": "tools/list", "params": {}}, sid)
    check('http: la sesion emitida por este proceso sigue valiendo', code == 200 and 'delphi_build' in body,
          '%s %s' % (code, body[:120]))

    # [Server] DelphiVersion= pins the RAD Studio (a [Workspace] did until
    # 5-oct-2026); pinned to the installed one it is simply the active one,
    # with no note
    code, body = post({"jsonrpc": "2.0", "id": 21, "method": "tools/call",
                       "params": {"name": "delphi_workspace", "arguments": {}}}, TOKEN)
    try:
        ws = json.loads(json.loads(body)['result']['content'][0]['text'])
    except Exception:
        ws = {}
    check('DelphiVersion=37.0 instalada: activeDelphi 37.0, pedida 37.0, sin nota',
          ws.get('activeDelphi') == '37.0' and ws.get('delphiVersionRequested') == '37.0'
          and 'delphiVersionNote' not in ws, json.dumps(ws)[:200])
    # the number means nothing to an agent: the NAME travels with it
    check('activeDelphiName nombra la version (RAD Studio 13) y activeDelphiRoot su carpeta',
          'RAD Studio 13' in ws.get('activeDelphiName', '') and '37.0' in ws.get('activeDelphiRoot', ''),
          json.dumps(ws)[:300])
    # nothing composed by hand: the personality, edition and build come from the
    # registry and bds.exe of THAT install
    check('personality, edition y build salen de la instalacion (Delphi 13, edicion, 37.0.x.y)',
          ws.get('activeDelphiPersonality', '').startswith('Delphi 13') and ws.get('activeDelphiEdition', '') != ''
          and ws.get('activeDelphiBuild', '').startswith('37.0.'), json.dumps(ws)[:300])
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
                'delphi_references', 'delphi_report',
                'delphi_search', 'delphi_signature', 'delphi_symbols',
                'delphi_textedit', 'delphi_upload', 'delphi_workspace',
                'delphi_paserver', 'delphi_delete', 'delphi_move',
                'delphi_adb', 'delphi_desktop',
                'delphi_components', 'delphi_styles', 'delphi_messages',
                'delphi_changeset', 'delphi_designer', 'delphi_rename_symbol',
                'delphi_test', 'delphi_help', 'delphi_docs']
    check('http: tools/list = %d tools' % len(expected), sorted(names) == sorted(expected), names)

    code, body = post({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": "delphi_list",
                   "arguments": {"root": os.path.join(HERE, '..', 'src'),
                                  "pattern": "*.pas"}}}, TOKEN)
    check('http: tools/call funciona', code == 200 and 'Lsp.Patch.pas' in body,
          '%s %s' % (code, body[:150]))

    # --- malformed "arguments" must NEVER crash the binder (measured AV:
    # arguments as [], absent, or a string reached Tool.Execute as nil) ---
    # [] y ausente son "sin argumentos" y la tool corre; un string (un JSON
    # codificado dos veces) se DICE con SYS-030: corria con {} y contestaba
    # "Missing path", que engana (sexta revision)
    for label, params, espera in [
            ('array', {"name": "delphi_installs", "arguments": []}, 'installs'),
            ('ausente', {"name": "delphi_installs"}, 'installs'),
            ('string', {"name": "delphi_installs", "arguments": "hola"},
             '[SYS-030 INVALID_PARAM]')]:
        code, body = post({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                           "params": params}, TOKEN)
        check('http: arguments malformado (%s) sin Access violation' % label,
              code == 200 and 'Access violation' not in body
              and espera in body, '%s %s' % (code, body[:200]))
finally:
    proc.kill()

# --- settings.ini [Server] Port: the port must be configurable, not fixed ---
INI_PORT = mc.puerto_libre()
# A FIXED folder, like every other battery uses (delphi-guard-tests,
# delphi-v012-tests...). It used to be mkdtemp, i.e. a new random path on every
# run - and Windows Firewall decides per program PATH, so each run looked like
# a brand-new program and asked again. Same name every time = asked at most
# once, ever.
tmpdir = mc.carpeta('http-ini-port')
try:
    exe2 = mc.copia_exe(tmpdir)
    with open(os.path.join(tmpdir, 'settings.ini'), 'w') as f:
        # BindIP: loopback only - see the note at the top. This instance runs
        # from a fresh temp folder, so without it the firewall asks again on
        # every run of this battery.
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n'
                '[Workspace.Op]\nToken=%s\nRoots=%s\n'
                % (INI_PORT, TOKEN, tmpdir))
    env2 = mc.entorno()  # the ini must supply the token too
    proc2 = mc.lanza_http(exe2, None, env2, espera_en=INI_PORT)  # no port argument: ini decides
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

# --- read-only access: ReadOnlyToken (el anonimo murio en v0.98: 401) --------
RO_PORT = mc.puerto_libre()
RO_TOKEN = 'ro-token-456'

tmpdir3 = mc.carpeta('http-ro')  # fixed, see above
# El repo de las pruebas de git en solo lectura, DENTRO de la jaula del
# workspace RO: con el del proyecto (fuera de Roots) las paraba la JAULA, y
# ni el modo solo lectura ni el filtro de --output se median (quinta revision)
REPO = os.path.join(tmpdir3, 'repo-ro')
os.makedirs(REPO)
for _g in (['init', '-q'], ['config', 'user.name', 'Probe Bot'], ['config', 'user.email', 'probe@example.com']):
    subprocess.run(['git', '-C', REPO] + _g, capture_output=True)
open(os.path.join(REPO, 'a.txt'), 'w').write('uno\n')
subprocess.run(['git', '-C', REPO, 'add', 'a.txt'], capture_output=True)
subprocess.run(['git', '-C', REPO, 'commit', '-q', '-m', 'uno'], capture_output=True)
try:
    exe3 = mc.copia_exe(tmpdir3)
    paspath = os.path.join(tmpdir3, 'Sample.pas')
    with open(paspath, 'w') as f:
        f.write('unit Sample;\r\ninterface\r\nimplementation\r\nend.\r\n')
    with open(os.path.join(tmpdir3, 'settings.ini'), 'w') as f:
        # v0.98: no generic [Workspace] section and no anonymous mode - only
        # named workspaces exist, and tokenless requests answer 401
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n'
                '[Workspace.Op]\nToken=%s\nReadOnlyToken=%s\nRoots=%s\nAllowTests=1\n'
                % (RO_PORT, TOKEN, RO_TOKEN, tmpdir3))
    proc3 = mc.lanza_http(exe3, None, mc.entorno(), espera_en=RO_PORT)
    try:
        URL = 'http://127.0.0.1:%d/mcp' % RO_PORT

        def call(tool, args, token):
            return post({"jsonrpc": "2.0", "id": 9, "method": "tools/call",
                         "params": {"name": tool, "arguments": args}}, token)

        # El .dproj de la muestra, de verdad: sin el, "el .dproj no fue
        # modificado por el escape de mayusculas" no se ejecutaba NUNCA (el
        # fixture solo tenia el .pas). Lo crea el token COMPLETO, el que si
        # escribe, y es un proyecto al que add-platform Linux64 SI cambiaria.
        call('delphi_create', {'kind': 'project-console', 'dir': tmpdir3,
                               'name': 'Sample'}, TOKEN)

        # v0.91: the RO token is a workspace credential too - it reads inside
        # ITS workspace roots (tmpdir3), not the repo
        code, body = call('delphi_list', {'root': tmpdir3,
                                          'pattern': '*.pas'}, RO_TOKEN)
        check('ro: token RO puede leer (delphi_list)',
              code == 200 and 'Sample.pas' in body, '%s %s' % (code, body[:120]))

        code, body = call('delphi_edit', {'path': paspath, 'old': 'interface',
                                          'new': 'interface // x'}, RO_TOKEN)
        check('ro: token RO NO puede editar', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:150]))

        for tool, args in (('delphi_changeset', {'command': 'begin'}),
                           ('delphi_build', {'project': 'x.dproj'}),
                           ('delphi_package', {'dir': tmpdir3}),
                           ('delphi_create', {'kind': 'project-console',
                                              'dir': tmpdir3, 'name': 'X'})):
            code, body = call(tool, args, RO_TOKEN)
            check('ro: token RO NO puede %s' % tool, mc.es(body, 'SR_READ_ONLY_FMT'),
                  '%s %s' % (code, body[:120]))

        # delphi_styles is mixed: view/get/lint read, set/clone/build write
        code, body = call('delphi_styles', {'path': tmpdir3, 'command': 'lint'}, RO_TOKEN)
        check('ro: delphi_styles lint permitido en RO',
              code == 200 and not mc.es(body, 'SR_READ_ONLY_FMT') and
              mc.resultado(mc.texto(json.loads(body))) not in ('INTERNAL', 'NO_ANSWER'),
              '%s %s' % (code, body[:120]))
        for cmd in ('set', 'clone', 'delete', 'build'):
            code, body = call('delphi_styles', {'path': tmpdir3, 'command': cmd,
                                                'style': 'x', 'prop': 'y', 'value': 'z', 'name': 'n'}, RO_TOKEN)
            check('ro: delphi_styles %s RECHAZADO en RO' % cmd, mc.es(body, 'SR_READ_ONLY_FMT'),
                  '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'status'},
                          RO_TOKEN)
        check('ro: git status permitido en RO (git contesta)',
              code == 200 and not mc.es(body, 'SR_READ_ONLY_FMT') and
              mc.texto(json.loads(body)).startswith('exit=0'),
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'commit',
                                         'message': 'nope'}, RO_TOKEN)
        check('ro: git commit RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'branch',
                                         'args': 'nueva-rama'}, RO_TOKEN)
        check('ro: git branch con args RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_textedit', {'path': tmpdir3 + '\\x.md',
                                              'create': True,
                                              'content': 'nope'}, RO_TOKEN)
        check('ro: delphi_textedit RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))

        # EL ANUNCIO contra LA PUERTA (28-sep-2026): tools/list dice de cada
        # tool annotations.readOnlyHint y _meta.access (read-only / read-write
        # / mixed + readOnlyCommands), desde la MISMA tabla que consulta la
        # puerta (Lsp.Guard ACCESOS). Tool por tool con el token RO: lo
        # anunciado read-write, READ-002; lo mixto, READ-002 con un comando que
        # no lee y NUNCA con uno anunciado como lectura; lo read-only, nunca
        code, body = post({"jsonrpc": "2.0", "id": 40, "method": "tools/list"}, TOKEN)
        anunciadas = json.loads(body)['result']['tools']
        sin_meta, mal_hint, mal_rw, mal_ro, mal_mix_no, mal_mix_si = [], [], [], [], [], []
        for t in anunciadas:
            meta = t.get('_meta') or {}
            acc = meta.get('access')
            hint = (t.get('annotations') or {}).get('readOnlyHint')
            if acc not in ('read-only', 'read-write', 'mixed'):
                sin_meta.append(t['name'])
                continue
            # el hint MCP es "no modifica su entorno": una lectura con efecto
            # (un reporte escrito, un mensaje consumido) lo anuncia en falso
            if hint != (acc == 'read-only' and not meta.get('sideEffect')):
                mal_hint.append('%s: hint %r, access %s' % (t['name'], hint, acc))
            if acc == 'read-write':
                code, body = call(t['name'], {}, RO_TOKEN)
                if not mc.es(body, 'SR_READ_ONLY_FMT'):
                    mal_rw.append(t['name'])
            elif acc == 'read-only':
                code, body = call(t['name'], {}, RO_TOKEN)
                if mc.es(body, 'SR_READ_ONLY_FMT'):
                    mal_ro.append(t['name'])
            else:
                p = meta.get('commandParameter') or 'command'
                code, body = call(t['name'], {p: 'zz-no-lee'}, RO_TOKEN)
                if not mc.es(body, 'SR_READ_ONLY_FMT'):
                    mal_mix_no.append(t['name'])
                for c in meta.get('readOnlyCommands') or []:
                    args = {p: c.split(' ')[0]}
                    if ' ' in c:
                        args['args'] = c.split(' ', 1)[1]
                    code, body = call(t['name'], args, RO_TOKEN)
                    if mc.es(body, 'SR_READ_ONLY_FMT'):
                        mal_mix_si.append('%s %s' % (t['name'], c))
        check('anuncio: toda tool de tools/list lleva _meta.access', not sin_meta, sin_meta)
        check('anuncio: readOnlyHint == (access read-only sin sideEffect)', not mal_hint, mal_hint)
        cuando = {t['name']: (t.get('_meta') or {}).get('readOnlyWhen') for t in anunciadas}
        check('anuncio: git y adb anuncian sus lecturas CONDICIONADAS (readOnlyWhen)',
              set((cuando.get('delphi_git') or {})) == {'branch', 'tag', 'worktree', 'stash'} and
              set((cuando.get('delphi_adb') or {})) == {'logcat'}, cuando)
        efectos = {t['name']: (t.get('_meta') or {}).get('sideEffect') for t in anunciadas}
        check('anuncio: report y messages dicen su efecto y readOnlyHint false',
              bool(efectos.get('delphi_report')) and bool(efectos.get('delphi_messages')), efectos)
        check('anuncio: lo anunciado read-write lo niega la puerta al token RO', not mal_rw, mal_rw)
        check('anuncio: lo anunciado read-only NO lo niega la puerta', not mal_ro, mal_ro)
        check('anuncio: en las mixtas, un comando que no lee se niega (cerrado)', not mal_mix_no, mal_mix_no)
        check('anuncio: en las mixtas, cada comando anunciado como lectura pasa la puerta',
              not mal_mix_si, mal_mix_si)
        # A la credencial de SOLO LECTURA tools/list no le anuncia las tools
        # enteras de escritura - la puerta se las niega siempre (David,
        # 6-oct-2026) -, y si las de lectura y las mixtas. El control: al
        # token de escritura si se le anuncian (la lista de arriba).
        code, body = post({"jsonrpc": "2.0", "id": 41, "method": "tools/list"}, RO_TOKEN)
        ro_nombres = {t['name'] for t in json.loads(body)['result']['tools']}
        rw = {t['name'] for t in anunciadas if (t.get('_meta') or {}).get('access') == 'read-write'}
        resto = {t['name'] for t in anunciadas} - rw
        check('anuncio: al token RO no se le anuncian las de escritura (al RW si: %d)' % len(rw),
              len(rw) >= 9 and not (rw & ro_nombres), sorted(rw & ro_nombres))
        check('anuncio: al token RO SI se le anuncian las de lectura y las mixtas',
              resto <= ro_nombres, sorted(resto - ro_nombres))
        # ...y la tabla de delphi_help, que las nombraria, se lo dice
        _, ayuda_ro = call('delphi_help', {}, RO_TOKEN)
        _, ayuda_rw = call('delphi_help', {}, TOKEN)
        check('anuncio: delphi_help avisa al token RO de que es de solo lectura (al RW no)',
              'YOUR CREDENTIAL IS READ-ONLY' in ayuda_ro and 'YOUR CREDENTIAL IS READ-ONLY' not in ayuda_rw,
              ayuda_ro[-200:])
        # las mixtas SIN el parametro del comando: el defecto de cada una es una
        # lectura... salvo delphi_test, cuyo vacio con project es run (r11c/r11d)
        code, body = call('delphi_test', {'project': tmpdir3 + '\\Sample.dproj'}, RO_TOKEN)
        check('ro: delphi_test sin command con project (= run) RECHAZADO en RO a la entrada',
              mc.es(body, 'SR_READ_ONLY_FMT') and 'delphi_test run' in body, '%s %s' % (code, body[:160]))
        code, body = call('delphi_test', {'path': tmpdir3}, RO_TOKEN)
        check('ro: delphi_test sin command con path (= discover) pasa la puerta',
              not mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:160]))
        code, body = call('delphi_adb', {'command': 'logcat', 'out': tmpdir3 + '\\log.txt'}, RO_TOKEN)
        check('ro: adb logcat con out= (escribe el log) RECHAZADO en RO a la entrada',
              mc.es(body, 'SR_READ_ONLY_FMT') and 'logcat out=' in body, '%s %s' % (code, body[:160]))
        # rename_symbol: apply se niega A LA ENTRADA (antes lo negaba el escritor
        # al llegar a escribir, con otro texto)
        code, body = call('delphi_rename_symbol', {'path': paspath, 'line': 0, 'character': 5,
                                                   'newname': 'Otra', 'mode': 'apply'}, RO_TOKEN)
        check('ro: rename_symbol apply RECHAZADO en RO a la entrada (READ-002)',
              mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'tag'},
                          RO_TOKEN)
        check('ro: git tag sin args (listar) permitido en RO (git contesta)',
              code == 200 and not mc.es(body, 'SR_READ_ONLY_FMT') and
              mc.texto(json.loads(body)).startswith('exit=0'),
              '%s %s' % (code, body[:120]))

        # tag with a message = annotated tag = a WRITE. The gate must catch it
        # even with empty args (it only looked at args before — field audit).
        code, body = call('delphi_git', {'repo': REPO, 'command': 'tag',
                                         'message': 'v1'}, RO_TOKEN)
        check('ro: git tag con message (anotado) RECHAZADO en RO',
              mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:120]))

        # jail/file-write escape: diff --output must be refused (would let a
        # read-only client write a file anywhere on disk).
        code, body = call('delphi_git', {'repo': REPO, 'command': 'diff',
                                         'args': '--output=' + tmpdir3 + '\\PWN.txt'},
                          RO_TOKEN)
        check('ro: git diff --output RECHAZADO en RO (por la puerta, no por la jaula)',
              mc.rechazado(mc.texto(json.loads(body))) and not mc.llego_a_git(mc.texto(json.loads(body)))
              and not mc.es(body, 'SR_JAIL_FMT'), '%s %s' % (code, body[:120]))
        check('ro: git diff --output no escribio el fichero',
              not os.path.exists(tmpdir3 + '\\PWN.txt'), tmpdir3)

        # The read-only decision itself was bypassable by SPELLING: the gate
        # read 'command' case-sensitively while the RTTI binder resolves it
        # ignoring case and '_', so "Command" made the gate see no command at
        # all (delphi_config -> treated as "view", a read) while the handler
        # received add-platform and wrote the .dproj.
        _dproj = paspath.replace('.pas', '.dproj')
        _before = open(_dproj, 'rb').read() if os.path.exists(_dproj) else None
        _mtime = os.path.getmtime(_dproj) if _before is not None else None
        for spelling in ('Command', 'COMMAND', 'com_mand'):
            code, body = call('delphi_config', {'repo': REPO, 'project': _dproj,
                                                spelling: 'add-platform',
                                                'platform': 'Linux64'}, RO_TOKEN)
            check('ro: delphi_config con "%s" sigue siendo SOLO LECTURA' % spelling,
                  mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:130]))
        # SIEMPRE: sin el .dproj de la muestra no hay nada que medir, y eso
        # es un FAIL, no un check que desaparece
        check('ro: el .dproj no fue modificado por el escape de mayusculas',
              _before is not None and os.path.exists(_dproj)
              and open(_dproj, 'rb').read() == _before
              and os.path.getmtime(_dproj) == _mtime,
              _dproj if _before is not None else 'no hay .dproj de la muestra: ' + _dproj)
        # same class on git: an annotated tag hidden behind "Message"
        # sin args: SOLO el "Message" lo convierte en escritura (con args='v9'
        # ya lo era, y el check no vigilaba la ortografia)
        code, body = call('delphi_git', {'repo': REPO, 'command': 'tag',
                                         'Message': 'x'}, RO_TOKEN)
        check('ro: git tag anotado via "Message" RECHAZADO en RO',
              mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:130]))

        # delphi_report is the ONE write available read-only, by design: the
        # restricted agents are the ones most likely to hit a wall.
        code, body = call('delphi_report',
                          {'message': 'Reporte desde credencial de solo lectura.',
                           'title': 'RO puede reportar', 'from': 'test_http_auth'},
                          RO_TOKEN)
        check('ro: delphi_report PERMITIDO en RO (canal de feedback)',
              code == 200 and mc.es(body, 'SN_REPORT_OK_FMT'), '%s %s' % (code, body[:150]))

        # delphi_config: view reads (OK in RO), add-platform writes (refused)
        code, body = call('delphi_config', {'command': 'view',
                                            'project': paspath.replace('.pas', '.dproj')},
                          RO_TOKEN)
        check('ro: delphi_config view NO da SOLO LECTURA (y la vista corre)',
              not mc.es(body, 'SR_READ_ONLY_FMT') and code == 200 and
              not mc.fallo(mc.texto(json.loads(body))),
              '%s %s' % (code, body[:120]))
        code, body = call('delphi_config', {'command': 'add-platform',
                                            'platform': 'Linux64',
                                            'project': paspath.replace('.pas', '.dproj')},
                          RO_TOKEN)
        check('ro: delphi_config add-platform RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))
        # delphi_paserver is read-only, always available
        code, body = call('delphi_paserver', {'command': 'platforms'}, RO_TOKEN)
        check('ro: delphi_paserver PERMITIDO en RO', code == 200 and not mc.es(body, 'SR_READ_ONLY_FMT') and
              mc.resultado(mc.texto(json.loads(body))) not in ('INTERNAL', 'NO_ANSWER'),
              '%s %s' % (code, body[:120]))
        # delphi_components is pure read (a registry listing, no process
        # spawned): fine in RO, and any RAD install registers Embarcadero's
        # own design packages, so the unfiltered list always mentions them
        code, body = call('delphi_components', {}, RO_TOKEN)
        check('ro: delphi_components PERMITIDO en RO y lista packages',
              code == 200 and not mc.es(body, 'SR_READ_ONLY_FMT') and 'Embarcadero' in body,
              '%s %s' % (code, body[:150]))
        code, body = call('delphi_components', {'filter': 'zz-no-existe-zz'}, RO_TOKEN)
        check('ro: delphi_components filter sin resultados responde honesto',
              mc.es(body, 'SN_COMPONENTS_NONE_FMT'), '%s %s' % (code, body[:150]))
        # delete/move are mutating: refused read-only
        code, body = call('delphi_delete', {'path': paspath}, RO_TOKEN)
        check('ro: delphi_delete RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:120]))
        code, body = call('delphi_move', {'path': paspath, 'dest': paspath + '.x'}, RO_TOKEN)
        check('ro: delphi_move RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'), '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'push'},
                          RO_TOKEN)
        check('ro: git push RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_upload', {'path': tmpdir3 + '\\x.bin',
                                            'offset': 0,
                                            'chunkbase64': 'AAAA'}, RO_TOKEN)
        check('ro: delphi_upload RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_git', {'repo': REPO, 'command': 'clone',
                                         'message': 'https://example.com/x.git'},
                          RO_TOKEN)
        check('ro: git clone RECHAZADO en RO', mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:120]))

        code, body = call('delphi_edit', {'path': paspath, 'old': 'interface',
                                          'new': 'interface'}, TOKEN)
        check('ro: token completo SI pasa la puerta',
              code == 200 and not mc.es(body, 'SR_READ_ONLY_FMT'),
              '%s %s' % (code, body[:150]))

        # v0.98 final (David): el anonimo NO EXISTE - o un workspace con su
        # token o 401, sin modo abierto ni de solo lectura sin credencial
        code, body = call('delphi_list', {'root': tmpdir3,
                                          'pattern': '*.pas'}, None)
        check('ro: anonimo = 401 SIEMPRE (el anonimo murio en v0.98)',
              code == 401, '%s %s' % (code, body[:120]))
        code, body = call('delphi_edit', {'path': paspath, 'old': 'interface',
                                          'new': 'interface // y'}, None)
        check('ro: anonimo tampoco edita: 401', code == 401,
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
FILES_PORT = mc.puerto_libre()
tmpdir4 = mc.carpeta('http-files')  # fixed, see above
jail4 = os.path.join(tmpdir4, 'jail')
os.makedirs(os.path.join(jail4, 'sub'), exist_ok=True)
os.makedirs(os.path.join(tmpdir4, 'outside'), exist_ok=True)
try:
    exe4 = mc.copia_exe(tmpdir4)
    small = os.path.join(jail4, 'small.txt')
    with open(small, 'wb') as f:
        f.write(b'hola mundo\r\n')
    bigdata = os.urandom(5 * 1024 * 1024 + 17)          # > 1 MB threshold (4 MB until 1.13.1)
    big = os.path.join(jail4, 'big.bin')
    with open(big, 'wb') as f:
        f.write(bigdata)
    big_sha = hashlib.sha256(bigdata).hexdigest()
    with open(os.path.join(tmpdir4, 'outside', 'secret.txt'), 'wb') as f:
        f.write(b'no me bajes')
    with open(os.path.join(tmpdir4, 'settings.ini'), 'w') as f:
        f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n'
                '[Workspace]\nRoots=%s\n\n'
                '[Workspace.Op]\nToken=%s\nReadOnlyToken=%s\nRoots=%s\n'
                % (FILES_PORT, jail4, TOKEN, RO_TOKEN, jail4))
    proc4 = mc.lanza_http(exe4, None, mc.entorno(), espera_en=FILES_PORT)
    try:
        URL = 'http://127.0.0.1:%d/mcp' % FILES_PORT
        BASE = 'http://127.0.0.1:%d' % FILES_PORT
        vjail = mc.virtual(jail4)                        # D:\x -> srvd:\x

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
        code, hdr, data = get(mc.virtual(os.path.join(tmpdir4, 'outside', 'secret.txt')), TOKEN)
        check('files: fuera de la jaula -> 403 FUERA', code == 403 and mc.es(data.decode('utf-8', 'replace'), 'SR_JAIL_FMT'),
              '%s %r' % (code, data[:120]))
        check('files: el rechazo no ensena letras reales', b'"' + jail4[:2].encode() not in data, data[:160])
        code, hdr, data = get(vjail + '\\sub', TOKEN)
        # un directorio donde va un fichero es la peticion mal hecha (FILE-001
        # INVALID_PARAM): 400, por el resultado de la negativa (septima revision)
        check('files: directorio -> 400', code == 400 and mc.es(data.decode('utf-8', 'replace'), 'SR_FILES_DIR'), '%s %r' % (code, data[:100]))
        code, hdr, data = get(vjail + '\\nada.bin', TOKEN)
        check('files: no existe -> 404', code == 404, '%s %r' % (code, data[:100]))
        code, hdr, data = get('', TOKEN, raw_url=BASE + '/files')
        check('files: sin path -> 400', code == 400, '%s %r' % (code, data[:100]))
        code, hdr, data = get(vjail + '\\small.txt', TOKEN, method='POST')
        check('files: POST -> 405', code == 405, code)
        code, hdr, data = get('srvz:\\Windows\\win.ini', TOKEN)
        check('files: unidad no servida rechazada POR NOMBRE (sin tocar disco)',
              code == 403 and mc.es(data.decode('utf-8', 'replace'), 'SR_FILES_UNIDAD_VIRTUAL_NO_SERVIDA_FMT') and b'Windows' not in data.split(b'srvz:')[0],
              '%s %r' % (code, data[:140]))
        code, hdr, data = get('sub\\x.txt', TOKEN)
        # la misma negativa que a toda tool (GUARD-021): /files tenia un segundo
        # lector de "ruta relativa" con su propio texto (FILE-030)
        check('files: ruta relativa -> 400 GUARD-021 (la puerta de todos)',
              code == 400 and mc.es(data.decode('utf-8', 'replace'), 'SR_GUARD_RUTA_RELATIVA_FMT'),
              '%s %r' % (code, data[:100]))

        # delphi_fetch: small file = chunk + link; big file = link ONLY
        code, body = call('delphi_fetch', {'path': vjail + '\\small.txt'}, TOKEN)
        js = json.loads(json.loads(body)['result']['content'][0]['text'])
        check('fetch: fichero pequeno trae chunkBase64 Y download',
              'chunkBase64' in js and js.get('download', '').startswith('/files?path=srv'),
              body[:200])
        code, body = call('delphi_fetch', {'path': vjail + '\\big.bin'}, TOKEN)
        js = json.loads(json.loads(body)['result']['content'][0]['text'])
        check('fetch: fichero > 1 MB responde SOLO enlace (sin chunk, con sha256)',
              'chunkBase64' not in js and js.get('bytes') == 0 and js.get('sha256') == big_sha
              and 'download' in js and mc.es(js.get('note', ''), 'SN_FETCH_BIG_FMT'),
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
        # a desktop capture in the server's temp folder is CONSUMED by the
        # download route too (David, 2026-09-25): one GET serves it whole from
        # memory and deletes it; the next GET is an honest 404.
        capdir = os.path.join(jail4, '__delphi-temp', 'desktop')
        os.makedirs(capdir, exist_ok=True)
        cap = os.path.join(capdir, 'desktop-bateria-20260925-000000000-cafe02.png')
        cappayload = b'\x89PNG' + os.urandom(5000)
        with open(cap, 'wb') as f:
            f.write(cappayload)
        code, hdr, data = get(vjail + '\\__delphi-temp\\desktop\\desktop-bateria-20260925-000000000-cafe02.png', TOKEN)
        check('files: una captura del agente se sirve entera desde memoria',
              code == 200 and data == cappayload, '%s %d bytes' % (code, len(data)))
        check('files: ...y se borra al servirla', not os.path.exists(cap), cap)
        code, hdr, data = get(vjail + '\\__delphi-temp\\desktop\\desktop-bateria-20260925-000000000-cafe02.png', TOKEN)
        check('files: la segunda peticion de la captura es 404', code == 404, code)
    finally:
        proc4.kill()
        proc4.wait()
finally:
    shutil.rmtree(tmpdir4, ignore_errors=True)

# --- session expiry: [Server] SessionTimeoutMinutes ---------------------------
# 1.0.17: a session idle longer than the timeout is DEAD - 404 with the reason,
# the same door an id this process never issued already got - and initialize
# opens a new one. Three seconds here (decimals are accepted for exactly this).
TTL_PORT = mc.puerto_libre()
tmpdir5 = mc.carpeta('http-ttl')
try:
    exe5 = mc.copia_exe(tmpdir5)
    with open(os.path.join(tmpdir5, 'settings.ini'), 'w') as f:
        f.write('[Server]' + chr(10) + 'Port=%d' % TTL_PORT + chr(10) + 'BindIP=127.0.0.1' + chr(10)
                + 'SessionTimeoutMinutes=0.05' + chr(10) * 2
                + '[Workspace.Op]' + chr(10) + 'Token=%s' % TOKEN + chr(10)
                + 'Roots=%s' % tmpdir5 + chr(10))
    proc5 = mc.lanza_http(exe5, None, mc.entorno(), espera_en=TTL_PORT)
    # Accept: application/json a secas, como el post() de arriba
    cli5 = mc.Http(TTL_PORT, TOKEN, t=60)
    JSON = 'application/json'
    try:
        code, h, body = cli5.post(INIT, accept=JSON)
        sid5 = h.get('Mcp-Session-Id')
        check('ttl: initialize da sesion', code == 200 and bool(sid5), '%s %s' % (code, body[:120]))
        WS = {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": "delphi_workspace", "arguments": {}}}
        code, _, body = cli5.post(WS, sid5, accept=JSON)
        try:
            srv = json.loads(json.loads(body)['result']['content'][0]['text'])['server']
        except Exception:
            srv = {}
        check('ttl: delphi_workspace publica sessions y sessionTimeoutMinutes',
              srv.get('sessions', 0) >= 1 and abs(float(srv.get('sessionTimeoutMinutes', -1)) - 0.05) < 1e-6,
              json.dumps(srv)[:200])
        # (5-oct-2026: la version fijada que no esta ya no se mide aqui - un
        # servidor sin su Delphi no arranca; test_un_delphi U5)
        time.sleep(1.5)
        code, _, body = cli5.post({"jsonrpc": "2.0", "id": 4, "method": "tools/list", "params": {}}, sid5, accept=JSON)
        check('ttl: cada peticion la toca (1,5 s despues sigue viva)', code == 200 and 'delphi_build' in body,
              '%s %s' % (code, body[:120]))
        time.sleep(4)
        code, _, body = cli5.post({"jsonrpc": "2.0", "id": 5, "method": "tools/list", "params": {}}, sid5, accept=JSON)
        check('ttl: 4 s sin usarla -> 404 "Session expired" con el plazo',
              code == 404 and mc.es(body, 'SR_SESSION_EXPIRED_FMT') and '0.05' in body, '%s %s' % (code, body[:200]))
        code, h, body = cli5.post(INIT, sid5, accept=JSON)
        sid5b = h.get('Mcp-Session-Id')
        check('ttl: initialize con la sesion caducada abre otra nueva',
              code == 200 and bool(sid5b) and sid5b != sid5, '%s %s' % (code, body[:120]))
        code, _, body = cli5.post({"jsonrpc": "2.0", "id": 6, "method": "tools/list", "params": {}}, sid5b, accept=JSON)
        check('ttl: la nueva sirve', code == 200 and 'delphi_build' in body, '%s %s' % (code, body[:120]))
        # una sesion sin clientInfo tambien se registra (antes: sin nombre, sin sesion, 404)
        code, h, body = cli5.post({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                   "params": {"protocolVersion": "2025-06-18", "capabilities": {}}},
                                  accept=JSON)
        sid5c = h.get('Mcp-Session-Id')
        # SIN sesion no hay nada que usar: un tools/list sin Mcp-Session-Id
        # tambien contesta 200, y eso es lo que dejaba pasar este check
        # (26-sep: ese initialize contestaba 200 con un Access violation
        # dentro y ninguna sesion). El detalle ensena lo que dijo.
        if sid5c:
            code2, _, body2 = cli5.post({"jsonrpc": "2.0", "id": 7, "method": "tools/list", "params": {}},
                                        sid5c, accept=JSON)
        else:
            code2, body2 = None, body
        check('ttl: initialize SIN clientInfo tambien registra la sesion',
              code == 200 and bool(sid5c) and code2 == 200,
              '%s %s %s' % (code, code2, body2[:160]))
    finally:
        proc5.kill()
        proc5.wait()
finally:
    shutil.rmtree(tmpdir5, ignore_errors=True)

mc.fin('http battery')
