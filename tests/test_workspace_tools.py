"""E2E battery for delphi_search / delphi_list / delphi_git over MCP stdio.

Usage:  python tests/test_workspace_tools.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green. Uses an independent repository as the git fixture.
"""
import json, os, base64, hashlib, subprocess
import mcp_cliente as mc
from mcp_cliente import check

# Every scratch folder this battery needs lives under ITS folder, with FIXED
# names. mkdtemp gave each run a new random path, which scatters leftovers all
# over %TEMP% and - for anything that opens a port - makes Windows Firewall
# treat each run as a brand-new program and ask again.
BASE = mc.carpeta('workspace-tools')


def _fixed(name):
    # mc.carpeta empties it even with read-only files (a clone leaves them
    # under .git\objects) and says so if it cannot: the next run must never
    # find a repo already there (git clone refused and three checks quietly
    # stopped running).
    return mc.carpeta(os.path.join('workspace-tools', name))


REPO = mc.REPO
SRC = os.path.join(REPO, 'src', 'Server')  # la carpeta del servidor: units, .dproj y Compiled (reorganizacion 24-sep)
# Its OWN copy, in a folder that IS build output by name (Compiled\Win64\
# Release): 'list: root explicito DENTRO de build output' lists that folder,
# not the repo's.
EXE = mc.copia_exe(os.path.join(BASE, 'Compiled', 'Win64', 'Release'))

# La forma de un checkout (rama y .git comun) no condiciona estas pruebas.
GIT_REPO = os.path.join(BASE, 'git-fixture')
subprocess.run(['git', 'init', '-b', 'main', GIT_REPO],
               check=True, capture_output=True)
for _i in range(5):
    with open(os.path.join(GIT_REPO, 'dato.txt'), 'a', encoding='utf-8') as _f:
        _f.write('dato %d\n' % _i)
    subprocess.run(['git', '-C', GIT_REPO, 'add', 'dato.txt'],
                   check=True, capture_output=True)
    subprocess.run(['git', '-C', GIT_REPO, '-c', 'user.name=Fixture',
                    '-c', 'user.email=fixture@example.invalid',
                    'commit', '-m', 'Fixture %d' % _i],
                   check=True, capture_output=True)

# Explicit git URLs need the operator's allowlist since v0.62 (an arbitrary URL
# made the SERVER open the connection). The clone check below is about cloning,
# not about the allowlist, so allow the host it uses.
# v0.98: sin jaula = solo lectura; esta bateria toca el repo Y su carpeta
_env = mc.entorno({'DELPHI_MCP_ROOTS': REPO + ';' + BASE,
                   'DELPHI_MCP_GIT_REMOTES': 'github.com'})
# 'servidor' y no 'srv': mas abajo 'srv' es la ficha de delphi_workspace
servidor = mc.Stdio(EXE, _env, inicializa=False, t=90)
assert servidor.inicializa('ws-battery'), 'no initialize response'
call = servidor.call

# --- search ---
out = call('delphi_search', {"root": SRC, "query": "RequestWithRetry", "wholeword": True})
try:
    d = json.loads(out)
    ok = d['total'] >= 3 and any('Lsp.Client.pas' in h['path'] for h in mc.aciertos(d))
    check('search: encuentra en Lsp.Client', ok, out[:200])
    check('search: linea 1-based y texto', all(h['line'] >= 1 and h['text'] for h in mc.aciertos(d)), '')
except Exception as e:
    check('search: parsea', False, out[:200])

out = call('delphi_search', {"root": SRC, "query": "retry", "wholeword": True})
# --- search: el texto que devuelve es el REAL, no mojibake ---------------
# Sin BOM no significa CP1252. Darlo por hecho convertia en basura todo
# fichero UTF-8 sin BOM, y ese texto corrupto es justo el que un agente copia
# para construir un ancla de delphi_edit (medido el 2026-09-20 buscando en los
# .md de este repo: cada raya volvia como tres caracteres raros).
_enc = _fixed('encodings')
_u8 = os.path.join(_enc, 'utf8_sin_bom.md')
_cp = os.path.join(_enc, 'legacy_cp1252.pas')
_TEXTO = 'La gestoria envio la accion - con acentos: aeiou ' + 'áéíóúñ — fin'
with open(_u8, 'w', encoding='utf-8', newline='') as _f:   # UTF-8 SIN BOM
    _f.write('# titulo\n' + _TEXTO + '\n')
_CP = 'unit legacy; // la accion se ejecuto: ' + 'áéíóúñ'
with open(_cp, 'w', encoding='cp1252', newline='') as _f:  # CP1252 de siempre
    _f.write(_CP + '\ninterface\nimplementation\nend.\n')
for _nom, _ruta, _esperado, _aguja in (
        ('utf-8 sin BOM', _u8, _TEXTO, 'acentos'),
        ('cp1252 legacy', _cp, _CP, 'accion')):
    _d = json.loads(call('delphi_search', {"root": _ruta, "query": _aguja}))
    _hit = (mc.aciertos(_d) or [{}])[0].get('text', '')
    check('search: devuelve el texto real de un fichero %s' % _nom,
          _hit == _esperado, '%r != %r' % (_hit[:70], _esperado[:70]))

d = json.loads(out)
out2 = call('delphi_search', {"root": SRC, "query": "retry", "wholeword": False})
d2 = json.loads(out2)
check('search: wholeword filtra', d2['total'] > d['total'], '%s vs %s' % (d['total'], d2['total']))

# --- search: regex=true y el tope de tamano (muros del 4-oct-2026) ---------
_rx = _fixed('regex')
with open(os.path.join(_rx, 'URx.pas'), 'w', encoding='utf-8', newline='\r\n') as _f:
    _f.write('unit URx;\ninterface\nprocedure Pinta1;\nprocedure PintaDos;\nfunction Pinta3: Integer;\n'
             'implementation\nend.\n')
_d = json.loads(call('delphi_search', {"root": _rx, "query": r"^PROCEDURE\s+pinta\d+;", "regex": True}))
check('search regex: casa por linea (^ es el principio de una linea), sin distinguir mayusculas',
      _d.get('total') == 1 and mc.aciertos(_d)[0]['text'] == 'procedure Pinta1;' and mc.aciertos(_d)[0]['character0'] == 0,
      str(_d)[:300])
# (revision de la 1.13.0) con pinta\w* wholeword no media nada: \w* acaba
# siempre en un borde. Un prefijo no es la palabra entera
_d = json.loads(call('delphi_search', {"root": _rx, "query": r"PINTA\w*", "regex": True, "wholeword": True}))
check('search regex + wholeword: la palabra entera de lo que caso', _d.get('total') == 3, str(_d)[:300])
_d = json.loads(call('delphi_search', {"root": _rx, "query": "pinta", "regex": True, "wholeword": True}))
check('search regex + wholeword: un prefijo (pinta de Pinta1) no es la palabra entera',
      _d.get('total') == 0, str(_d)[:300])
_r = call('delphi_search', {"root": _rx, "query": "procedure Pinta1;\nprocedure PintaDos;"})
check('search con una consulta de dos lineas: rechazada, no un total 0 en silencio (SEARCH-008)',
      mc.rechazado(_r) and mc.tiene(_r, 'SEARCH-008'), _r[:200])
_r = call('delphi_search', {"root": _rx, "query": "(sin cerrar", "regex": True})
check('search regex mal escrita: rechazada antes de buscar (SEARCH-004)',
      mc.rechazado(_r) and mc.tiene(_r, 'SEARCH-004'), _r[:200])
with open(os.path.join(_rx, 'larga.txt'), 'w', encoding='utf-8') as _f:
    _f.write('a' * 40 + 'b\n')
_r = call('delphi_search', {"root": _rx, "query": "(a+)+$", "regex": True, "pattern": "*.txt"})
check('search regex que se dispara: se dice donde y no cuelga el servidor (SEARCH-005)',
      mc.rechazado(_r) and mc.tiene(_r, 'SEARCH-005') and 'larga.txt' in _r, _r[:300])
_grande = os.path.join(_rx, 'grande.txt')
with open(_grande, 'w', encoding='ascii') as _f:
    _f.write(('x' * 1023 + '\n') * (9 * 1024))  # 9 MB
_d = json.loads(call('delphi_search', {"root": _rx, "query": "x", "pattern": "*.txt"}))
check('search: un fichero de mas de 8 MB en la carpeta se salta y se nombra (SEARCH-006)',
      mc.tiene(_d.get('bigFilesNote', ''), 'SEARCH-006') and 'grande.txt' in _d.get('bigFilesNote', ''),
      str(_d)[:300])
_r = call('delphi_search', {"root": _grande, "query": "x"})
check('search: ...y nombrado a solas, se dice por que no (SEARCH-007)',
      mc.rechazado(_r) and mc.tiene(_r, 'SEARCH-007'), _r[:200])

# --- projects: por paginas -----------------------------------------------
# Sin paginar, una maquina de trabajo (7025 .dproj) contestaba 82 KB y
# reventaba el limite del cliente: la tool era inservible sin "root" (medido
# el 2026-09-20 usando el servidor como agente).
_p1 = json.loads(call('delphi_projects', {"root": REPO, "maxresults": 5}))
check('projects: la pagina respeta maxresults',
      _p1.get('shown') == 5 and len(mc.ficheros(_p1, 'projects')) == 5,
      str(_p1.get('shown')))
check('projects: dice que hay mas y por donde seguir',
      _p1.get('hasMore') is True and _p1.get('nextOffset') == 5 and
      'offset=5' in _p1.get('note', ''),
      (_p1.get('hasMore'), _p1.get('nextOffset'), _p1.get('note', '')[:80]))
check('projects: cuando hay mas, dice en que carpetas estan',
      isinstance(_p1.get('byFolder'), list) and len(_p1['byFolder']) >= 1 and
      all(' = ' in f for f in _p1['byFolder']) and
      sum(int(f.rsplit(' = ', 1)[1]) for f in _p1['byFolder']) == _p1['total'],
      str(_p1.get('byFolder'))[:200])
check('projects: un proyecto en la propia raiz sale como "." y no como otra carpeta',
      any(f.startswith('. = ') for f in _p1.get('byFolder', [])),
      str(_p1.get('byFolder'))[:200])
_p2 = json.loads(call('delphi_projects',
                      {"root": REPO, "maxresults": 5, "offset": 5}))
check('projects: la siguiente pagina es OTRA y dice su offset',
      _p2.get('offset') == 5 and
      mc.ficheros(_p2, 'projects')[0]['path'] != mc.ficheros(_p1, 'projects')[0]['path'],
      (_p2.get('offset'), mc.ficheros(_p2, 'projects')[0]['name'], mc.ficheros(_p1, 'projects')[0]['name']))
_vistos, _off, _vueltas = [], 0, 0
while _vueltas < 20:
    _pg = json.loads(call('delphi_projects',
                          {"root": REPO, "maxresults": 5, "offset": _off}))
    _vistos += [p['path'] for p in mc.ficheros(_pg, 'projects')]
    _vueltas += 1
    if not _pg.get('hasMore'):
        break
    _off = _pg['nextOffset']
check('projects: recorrer nextOffset llega a TODOS y sin repetir',
      len(_vistos) == _p1['total'] and len(set(_vistos)) == len(_vistos),
      '%d vistos / total %d' % (len(_vistos), _p1['total']))
_pd = json.loads(call('delphi_projects', {"root": REPO}))
check('projects: por defecto no vuelca la lista entera',
      _pd.get('shown', 0) <= 50, str(_pd.get('shown')))

# --- list ---
out = call('delphi_list', {"root": SRC, "pattern": "*.pas"})
try:
    d = json.loads(out)
    fs = mc.ficheros(d)
    names = [os.path.basename(f['path']) for f in fs]
    check('list: unidades presentes', 'Lsp.Patch.pas' in names and 'Lsp.Client.pas' in names, names[:10])
    check('list: sin artefactos', fs and not any('Win64' in f['path'] for f in fs), '')
except Exception:
    check('list: parsea', False, out[:200])

# --- list dirs (explorer mode) ---
out = call('delphi_list', {"root": REPO, "dirs": True})
try:
    d = json.loads(out)
    names = [f['name'] for f in mc.ficheros(d, hijos='dirs')]
    check('list dirs: carpetas de primer nivel', 'src' in names and 'docs' in names
          and 'vendor' in names, names)
    check('list dirs: oculta artefactos', '.git' not in names, names)
except Exception:
    check('list dirs: parsea', False, out[:200])

# --- list: artifact filtering is RELATIVE to the root (v0.29) ---
# from above, build output stays hidden but the result SAYS so
out = call('delphi_list', {"root": SRC, "pattern": "*.exe"})
try:
    d = json.loads(out)
    check('list: build output oculto pero DECLARADO (hidden+note)',
          d.get('hidden', 0) >= 1 and 'delphi_package' in d.get('note', ''), out[:200])
except Exception:
    check('list: parsea (hidden)', False, out[:200])
# naming the build-output folder itself as root serves its contents
RELDIR = os.path.dirname(os.path.abspath(EXE))
out = call('delphi_list', {"root": RELDIR, "pattern": "*.exe"})
try:
    d = json.loads(out)
    check('list: root explicito DENTRO de build output lista el exe',
          any(os.path.basename(EXE).lower() == f['name'].lower()
              for f in mc.ficheros(d)), out[:200])
except Exception:
    check('list: parsea (root en build output)', False, out[:200])
# dirs browse of the folder holding the platform dirs: hidden children counted
out = call('delphi_list', {"root": os.path.join(SRC, 'Compiled'), "dirs": True})
try:
    d = json.loads(out)
    check('list dirs: hijos de build output contados en hidden con nota',
          d.get('hidden', 0) >= 1 and 'note' in d, out[:200])
except Exception:
    check('list dirs: parsea (hidden)', False, out[:200])
# dirs browse INSIDE artifact territory serves the children (explicit root)
out = call('delphi_list', {"root": os.path.dirname(RELDIR), "dirs": True})
try:
    d = json.loads(out)
    names = [f['name'] for f in mc.ficheros(d, hijos='dirs')]
    check('list dirs: root dentro de build output muestra sus hijos',
          os.path.basename(RELDIR) in names, out[:200])
except Exception:
    check('list dirs: parsea (root en build output)', False, out[:200])

# --- projects locator ---
out = call('delphi_projects', {"root": REPO})
try:
    d = json.loads(out)
    names = sorted(os.path.splitext(p['name'])[0] for p in mc.ficheros(d, 'projects'))
    # ONE server project now: the terminal, the service and the tray are three
    # modes of the same executable, not three projects.
    check('projects: encuentra los del repo',
          'DelphiLspMcp' in names and 'LspUnitTests' in names, names)
    check('projects: el proyecto del tray ya no existe por separado',
          'DelphiLspMcpTray' not in names, names)
except Exception:
    check('projects: parsea', False, out[:200])
out = call('delphi_projects', {"root": REPO, "name": "unittests"})
d = json.loads(out)
check('projects: filtro por nombre', d['total'] == 1 and mc.ficheros(d, 'projects')[0]['name'] == 'LspUnitTests.dproj', out[:150])
out = call('delphi_projects', {})
# v0.98: la bateria declara su jaula, asi que sin root explicito descubre
# DENTRO de ella (el estado "sin configurar" ya no existe: o jaula o RO)
check('projects: sin root explicito descubre dentro de la jaula',
      '"total"' in out and not mc.fallo(out), out[:200])

# --- fetch (chunked download with sha256) ---
LIC = os.path.join(REPO, 'LICENSE')
blob = b''
off = 0
sha = None
while True:
    out = call('delphi_fetch', {"path": LIC, "offset": off, "maxbytes": 400})
    d = json.loads(out)
    if off == 0:
        sha = d.get('sha256')
    blob += base64.b64decode(d['chunkBase64'])
    if d['eof']:
        break
    off += d['bytes']
local = open(LIC, 'rb').read()
check('fetch: reensamblado identico byte a byte', blob == local, '%d vs %d' % (len(blob), len(local)))
check('fetch: sha256 cuadra', sha and sha.lower() == hashlib.sha256(local).hexdigest(), sha)
check('fetch: fue en varios chunks', len(local) > 400, len(local))

# --- a desktop capture in the server's temp folder is CONSUMED on retrieval
# (David, 2026-09-25: delete it once the agent has fetched it; no cache, no
# rotation, nothing kept). Retrieved = last chunk served. A normal file stays.
# In the battery's own root, never in the repo: REPO\__delphi-temp is where a
# server whose first writable root is this repo leaves its deliverables.
capdir = os.path.join(BASE, '__delphi-temp', 'desktop')
os.makedirs(capdir, exist_ok=True)
cap = os.path.join(capdir, 'desktop-bateria-20260925-000000000-cafe01.png')
payload = b'\x89PNG' + os.urandom(3000)
open(cap, 'wb').write(payload)
try:
    d1 = json.loads(call('delphi_fetch', {"path": cap, "offset": 0, "maxbytes": 2000}))
    check('captura: el primer trozo NO la borra (aun no esta recogida)',
          d1.get('consumedOnServer') is False and os.path.exists(cap), json.dumps(d1)[:200])
    d2 = json.loads(call('delphi_fetch', {"path": cap, "offset": d1['bytes'], "maxbytes": 2000}))
    got = base64.b64decode(d1['chunkBase64']) + base64.b64decode(d2['chunkBase64'])
    check('captura: el ultimo trozo la entrega entera y la borra del servidor',
          d2.get('eof') is True and d2.get('consumedOnServer') is True and got == payload and not os.path.exists(cap),
          json.dumps(d2)[:200])
    out = call('delphi_fetch', {"path": cap, "offset": 0})
    check('captura: pedirla otra vez es "no existe" (nada cacheado)', mc.resultado(out) == 'NOT_FOUND' and mc.es(out, 'SR_WS_NO_EXISTE_FMT'), out[:120])
    d3 = json.loads(call('delphi_fetch', {"path": LIC, "offset": 0, "maxbytes": 400}))
    check('un fichero normal no se consume', 'consumedOnServer' not in d3 and os.path.exists(LIC), json.dumps(d3)[:120])
finally:
    mc.borra(capdir)

# --- git (repo independiente dentro de la jaula) ---
out = call('delphi_git', {"repo": GIT_REPO, "command": "status"})
check('git: status', out.startswith('exit=0') and '## main' in out, out[:150])
out = call('delphi_git', {"repo": GIT_REPO, "command": "log"})
# --oneline -20: assert on the SHAPE (hash + subject lines), never on a
# specific old commit message - it scrolls out of the window as we release.
check('git: log', out.startswith('exit=0')
      and len([l for l in out.splitlines()[1:] if l.strip()]) >= 5, out[:150])
out = call('delphi_git', {"repo": GIT_REPO, "command": "branch"})
check('git: branch', out.startswith('exit=0') and 'main' in out, out[:150])
# The stat of the LAST COMMIT, not of the working tree: the working tree is
# being edited while the battery runs, the commit is fixed. And it has to be
# the SAME stat git gives here - until 2026-09-26 any "exit=" passed, a
# fatal "exit=128" included.
out = call('delphi_git', {"repo": GIT_REPO, "command": "diff", "args": "--stat HEAD~1 HEAD"})
_git = subprocess.run(['git', '-C', GIT_REPO, 'diff', '--stat', 'HEAD~1', 'HEAD'],
                      capture_output=True, text=True, encoding='utf-8', errors='replace')
_stat = lambda t: [l.strip() for l in t.splitlines() if l.strip()]
check('git: diff --stat', out.startswith('exit=0') and bool(_stat(_git.stdout))
      and _stat(out)[1:] == _stat(_git.stdout) and 'changed' in _stat(out)[-1],
      (out[:120], _git.stdout[-120:]))
out = call('delphi_git', {"repo": GIT_REPO, "command": "rebase"})
check('git: comando fuera de whitelist rechaza', mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_GIT_UNKNOWN_COMMAND_FMT'), out[:120])
out = call('delphi_git', {"repo": GIT_REPO, "command": "log", "args": "; del *"})
check('git: metacaracteres rechazados', mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_GIT_SHELL_METACHARS_ARGS'), out[:120])

# --- delphi_signature + definition kind variants (real LSP semantics) ---
GUARD = os.path.join(SRC, 'Lsp.Guard.pas')
lines = open(GUARD, 'rb').read().decode('utf-8-sig', 'replace').replace('\r\n', '\n').split('\n')
sig_line = ident_line = -1
for i, ln in enumerate(lines):
    # la llamada es PathDenied(APath) (hasta la 1.7.3 llevaba un motivo); el
    # ancla acepta las dos formas para no casarse con una firma.
    if 'Result := PathDenied(APath' in ln:
        sig_line = ident_line = i
        paren_char = ln.index('PathDenied(') + len('PathDenied(')
        ident_char = ln.index('PathDenied') + 3
        break
if sig_line >= 0:
    out = call('delphi_signature', {"path": GUARD, "line": sig_line,
                                    "character": paren_char}, 180)
    check('signature: firma de PathDenied en la llamada',
          'PathDenied' in out or 'APath' in out, out[:200])
    out = call('delphi_definition', {"path": GUARD, "line": ident_line,
                                     "character": ident_char, "kind": "xx"})
    # the refusal OF THE PARAMETER, naming the valid kinds - not any RECHAZADO
    # (a jail refusal passed too)
    check('definition: kind invalido rechaza',
          mc.rechazado(out) and mc.es(out, 'SR_LSP_KIND_DEBE_SER_DEFINITION')
          and 'definition | declaration | implementation' in out, out[:120])
else:
    check('signature: ancla de test encontrada en Lsp.Guard.pas', False, 'no anchor')

# decl vs impl only split for METHODS (measured: for global routines both
# return the interface declaration) - so test on a TLspClient method usage.
CLIENT = os.path.join(SRC, 'Lsp.Client.pas')
clines = open(CLIENT, 'rb').read().decode('utf-8-sig', 'replace').replace('\r\n', '\n').split('\n')
m_line = -1
for i, ln in enumerate(clines):
    if "Result := RequestWithRetry('textDocument/hover'" in ln:
        m_line = i
        m_char = ln.index('RequestWithRetry') + 4
        break
if m_line >= 0:
    out_decl = call('delphi_definition', {"path": CLIENT, "line": m_line,
                                          "character": m_char,
                                          "kind": "declaration"}, 180)
    out_def = call('delphi_definition', {"path": CLIENT, "line": m_line,
                                         "character": m_char}, 180)
    # measured semantics: definition = the body, declaration = the
    # interface declaration (two different lines of the same unit)
    ok = ('Lsp.Client.pas' in out_decl and 'Lsp.Client.pas' in out_def
          and out_decl != out_def and not mc.es(out_decl, 'SN_LSP_NULL_NOTE'))
    check('definition: kind declaration vs default (las dos mitades)',
          ok, ('decl=%s | def=%s' % (out_decl[:90], out_def[:90])))
else:
    check('definition: ancla de metodo encontrada en Lsp.Client.pas', False, 'no anchor')

# --- workspace: roots as the round-trip variable (server vs own paths) ---
out = call('delphi_workspace', {})
try:
    d = json.loads(out)
    check('workspace: expone roots', isinstance(d.get('roots'), list), out[:200])
    check('workspace: avisa que son rutas del servidor',
          mc.es(d.get('note', ''), 'SN_WORKSPACE_NOTE'),
          out[:200])
    check('workspace: nivel de acceso', d.get('access') in ('read-write', 'read-only'),
          out[:200])
    # QUIEN contesta: sin esto, comprobar un despliegue obligaba a mirar el
    # proceso desde FUERA del MCP (medido el 2026-09-20 usando el servidor
    # como agente: la version solo vivia en el titulo de la bandeja y dentro
    # de un delphi_report).
    srv = d.get('server', {})
    check('workspace: ficha del servidor (version, modo, transporte, pid)',
          srv.get('version', '') != '' and
          srv.get('mode') in ('console', 'tray', 'service') and
          srv.get('transport') in ('stdio', 'http') and
          isinstance(srv.get('pid'), int) and srv['pid'] > 0, str(srv)[:200])
    check('workspace: lanzado por la bateria = consola por stdio',
          srv.get('mode') == 'console' and srv.get('transport') == 'stdio',
          str(srv)[:200])
    check('workspace: dice desde cuando vive y con que exe',
          srv.get('startedAt', '').startswith('20') and
          srv.get('exe', '').lower().endswith('delphilspmcp.exe') and
          srv.get('uptime', '') != '', str(srv)[:200])
    # 28-sep-2026: dos servidores del mismo nombre y version (13.1 aqui, 13.2 en
    # la VM, mismo token) contestaban sin nada que los distinguiera
    check('workspace: dice en que maquina corre (host = COMPUTERNAME)',
          mc.es_esta_maquina(srv.get('host', '')), str(srv)[:200])
except Exception:
    check('workspace: parsea', False, out[:200])

# --- installs: every Delphi on the machine, as a list ---
out = call('delphi_installs', {})
try:
    d = json.loads(out)
    check('installs: al menos una instalacion', d['total'] >= 1, out[:200])
    check('installs: la activa tiene DelphiLSP',
          d['activeForLsp'] != '' and any(
              i['active'] and i['delphilsp'] for i in d['installs']), out[:200])
    check('installs: rootdir descubierto no vacio',
          all(i['rootdir'] for i in d['installs']), out[:200])
except Exception:
    check('installs: parsea', False, out[:200])

# --- git init / tag / push (in a THROWAWAY dir - never against this repo) ---
tmpgit = _fixed('git')
try:
    out = call('delphi_git', {"repo": tmpgit, "command": "init"})
    check('git: init crea repo', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "status"})
    check('git: status tras init', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "tag"})
    check('git: tag sin args lista (permitido)', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "push"})
    check('git: push permitido (falla sin remote, pero NO por whitelist)',
          mc.llego_a_git(out) and not mc.es(out, 'SR_GIT_UNKNOWN_COMMAND_FMT'), out[:150])

    # identity via whitelisted config + commit with normal punctuation
    out = call('delphi_git', {"repo": tmpgit, "command": "config",
                              "args": "user.name", "message": "Agente Remoto"})
    check('git: config user.name', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "config",
                              "args": "user.email", "message": "agente@test.local"})
    check('git: config user.email', out.startswith('exit=0'), out[:150])
    out = call('delphi_git', {"repo": tmpgit, "command": "config",
                              "args": "core.sshCommand", "message": "evil"})
    check('git: config fuera de user.name/email rechazado',
          mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_GIT_CONFIG_ONLY_ACCEPTS_USER'), out[:150])
    with open(os.path.join(tmpgit, 'nota.txt'), 'w') as f:
        f.write('hola\n')
    call('delphi_git', {"repo": tmpgit, "command": "add", "args": "."})
    out = call('delphi_git', {"repo": tmpgit, "command": "commit",
        "message": "Commit de prueba (con parentesis), 'comillas' y ¡signos!"})
    check('git: commit con puntuacion normal en message', out.startswith('exit=0'),
          out[:200])
    out = call('delphi_git', {"repo": tmpgit, "command": "log"})
    check('git: log muestra el commit', 'parentesis' in out, out[:200])
    check('git: acentos del mensaje SIN mojibake (utf-8 bien decodificado)',
          '¡signos!' in out and 'Ã' not in out, out[:200])
    # la respuesta por paginas (muro del 4-oct-2026: un diff de mas de 30000
    # caracteres salia cortado y no habia forma de ver el resto)
    with open(os.path.join(tmpgit, 'nota.txt'), 'w') as f:
        f.write(''.join('linea %04d %s\n' % (i, 'x' * 60) for i in range(1200)))
    out = call('delphi_git', {"repo": tmpgit, "command": "diff"})
    import re as _re
    _m = _re.search(r'offset=(\d+)', out)
    check('git diff largo: una pagina, y la nota dice que lineas son y como seguir (GIT-053)',
          mc.tiene(out, 'GIT-053') and _m is not None and '+linea 0000' in out and '+linea 1199' not in out,
          out[-300:])
    # pagina a pagina hasta la ultima: juntas, las 1200 lineas en orden, sin
    # huecos ni repetidas
    _vistas, _pag, _n = [], out, 0
    while True:
        _vistas += _re.findall(r'\+linea (\d{4})', _pag)
        _m2 = _re.search(r'offset=(\d+)', _pag) if mc.tiene(_pag, 'GIT-053') else None
        _n += 1
        if not _m2 or _n > 10:
            break
        _pag = call('delphi_git', {"repo": tmpgit, "command": "diff", "offset": int(_m2.group(1))})
    check('git diff offset: pagina a pagina, todas las lineas, en orden y una vez',
          _vistas == ['%04d' % i for i in range(1200)] and _n > 1, '%d paginas, %d lineas' % (_n, len(_vistas)))
    out3 = call('delphi_git', {"repo": tmpgit, "command": "diff", "offset": 99999})
    check('git diff offset pasado del final: se dice cuantas lineas tiene (GIT-054)',
          mc.tiene(out3, 'GIT-054'), out3[:200])
    out4 = call('delphi_git', {"repo": tmpgit, "command": "add", "args": ".", "offset": 5})
    check('git offset con una orden que escribe: no va con ella (repetirla la volveria a ejecutar)',
          mc.rechazado(out4) and mc.es(out4, 'SR_GIT_NO_VA_CON_COMANDO_FMT'), out4[:200])
    # (revision de la 1.13.0) una linea mas larga que la pagina sale cortada y
    # se DICE: la pagina siguiente empieza en la otra y su cola no se veia
    with open(os.path.join(tmpgit, 'nota.txt'), 'w') as f:
        f.write('corta\n' + 'L' * 40000 + 'FINAL\n' + 'otra\n')
    # (no cabe con las de antes: va sola en la pagina siguiente)
    out5 = call('delphi_git', {"repo": tmpgit, "command": "diff"})
    _m5 = _re.search(r'offset=(\d+)', out5) if mc.tiene(out5, 'GIT-053') else None
    out5b = call('delphi_git', {"repo": tmpgit, "command": "diff",
                                "offset": int(_m5.group(1))}) if _m5 else ''
    check('git diff con una linea mas larga que la pagina: cortada y dicho (GIT-055)',
          mc.tiene(out5b, 'GIT-055') and 'LLLL' in out5b and 'LFINAL' not in out5b,
          out5[-200:] + ' | ' + out5b[-400:])
    # branch y tag sin argumentos son consultas: su nota GIT-053 ofrece offset
    # y el parametro se rechazaba; con argumentos escriben, y ahi no va
    out6 = call('delphi_git', {"repo": tmpgit, "command": "branch", "offset": 5})
    check('git branch (consulta) admite offset: pasado del final, GIT-054',
          mc.tiene(out6, 'GIT-054') and not mc.es(out6, 'SR_GIT_NO_VA_CON_COMANDO_FMT'), out6[:200])
    out7 = call('delphi_git', {"repo": tmpgit, "command": "tag", "args": "v9.9",
                               "message": "x", "offset": 5})
    out8 = call('delphi_git', {"repo": tmpgit, "command": "tag"})
    check('git tag que escribe con offset: GIT-056 y la etiqueta NO se crea',
          mc.rechazado(out7) and mc.tiene(out7, 'GIT-056') and 'v9.9' not in out8, out7[:200] + ' | ' + out8[:200])
finally:
    mc.borra(tmpgit)

# --- delphi_upload: mirror of fetch, byte-identical reassembly ---
import base64, secrets
tmpup = _fixed('upload')
try:
    blob = secrets.token_bytes(120000)
    sha = hashlib.sha256(blob).hexdigest()
    dst = os.path.join(tmpup, 'sub', 'Artefacto.res')
    half = len(blob) // 2
    o1 = call('delphi_upload', {"path": dst, "offset": 0,
                                "chunkbase64": base64.b64encode(blob[:half]).decode()})
    try:
        d1 = json.loads(o1)
        o2 = call('delphi_upload', {"path": dst, "offset": d1['nextOffset'],
                                    "chunkbase64": base64.b64encode(blob[half:]).decode(),
                                    "sha256": sha})
        d2 = json.loads(o2)
        check('upload: dos chunks, tamano final correcto',
              d2['size'] == len(blob), o2[:150])
        check('upload: sha256 verificado por el servidor',
              d2.get('verified') is True, o2[:150])
        check('upload: fichero byte-identico en disco',
              open(dst, 'rb').read() == blob, 'mismatch')
        check('upload: crea subcarpetas', os.path.isdir(os.path.dirname(dst)), dst)
    except Exception as e:
        check('upload: parsea', False, '%s | %s' % (e, o1[:150]))
    out = call('delphi_upload', {"path": os.path.join(tmpup, 'X.bin'), "offset": 99,
                                 "chunkbase64": "AAAA"})
    check('upload: offset>0 sobre fichero inexistente rechaza',
          mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_WS_OFFSET_FICHERO_NO_EXISTE'), out[:120])
    out = call('delphi_upload', {"path": os.path.join(tmpup, 'Y.bin'), "offset": 0,
                                 "chunkbase64": "no-es-base64!!"})
    check('upload: base64 invalido rechaza (no escribe basura)',
          mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_B64_ALPHABET_FMT') and not os.path.exists(os.path.join(tmpup, 'Y.bin')),
          out[:120])
    # 2026-09-25 (hermes): a chunk with a character lost or gained in transit
    # decoded to 2 extra bytes and only the whole-file sha at the END caught
    # it, file already in quarantine. Now the length is checked per chunk and
    # chunkSha256 verifies a chunk BEFORE it is written.
    zb = os.path.join(tmpup, 'Z.bin')
    good = base64.b64encode(b'0123456789abcdef').decode()
    out = call('delphi_upload', {"path": zb, "offset": 0, "chunkbase64": good[:-1]})
    check('upload: base64 con longitud no multiplo de 4 rechaza sin escribir',
          mc.rechazado(out) and mc.es(out, 'SR_B64_LEN_FMT') and not os.path.exists(zb), out[:160])
    out = call('delphi_upload', {"path": zb, "offset": 0, "chunkbase64": good,
                                 "chunksha256": '0' * 64})
    check('upload: chunkSha256 que no coincide rechaza sin escribir',
          mc.rechazado(out) and mc.es(out, 'SR_UPLOAD_CHUNK_SHA_MISMATCH_FMT') and not os.path.exists(zb), out[:160])
    out = call('delphi_upload', {"path": zb, "offset": 0, "chunkbase64": good,
                                 "chunksha256": hashlib.sha256(b'0123456789abcdef').hexdigest()})
    try:
        dz = json.loads(out)
        check('upload: chunkSha256 correcto -> chunkVerified true y escrito',
              dz.get('chunkVerified') is True and open(zb, 'rb').read() == b'0123456789abcdef', out[:160])
    except Exception as e:
        check('upload: chunkSha256 correcto parsea', False, '%s | %s' % (e, out[:160]))
    out = call('delphi_upload', {"path": zb, "offset": 0, "chunkbase64": good, "chunksha256": 'zz'})
    check('upload: chunkSha256 con forma mala rechaza el parametro, el fichero sigue',
          mc.rechazado(out) and mc.es(out, 'SR_UPLOAD_BAD_SHA_FMT') and open(zb, 'rb').read() == b'0123456789abcdef', out[:160])
finally:
    mc.borra(tmpup)

# --- git clone: whole repo in one call (network; skipped if offline) ---
tmpcl = _fixed('clone')
try:
    dest = os.path.join(tmpcl, 'repo')
    out = call('delphi_git', {"repo": dest, "command": "clone",
        "message": "https://github.com/soporte-defontsoft/delphi-lsp-mcp-service.git"}, 600)
    if 'exit=0' in out:
        check('git clone: repo entero en una llamada',
              os.path.isdir(os.path.join(dest, 'src')), out[:150])
        out2 = call('delphi_git', {"repo": dest, "command": "clone",
            "message": "https://github.com/soporte-defontsoft/delphi-lsp-mcp-service.git"})
        check('git clone: no re-clona sobre un repo existente',
              mc.resultado(out2) == 'DENIED' and mc.abre(out2, 'SR_GIT_YA_ES_REPOSITORIO_FMT'), out2[:120])
        out3 = call('delphi_git', {"repo": dest, "command": "pull"}, 300)
        check('git pull: permitido', mc.llego_a_git(out3), out3[:120])
    else:
        print('SKIP - git clone (sin red o repo inaccesible):', out[:100])
    out = call('delphi_git', {"repo": dest, "command": "clone",
                              "message": "file:///C:/Windows"})
    check('git clone: URL no http/ssh rechazada', mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_GIT_CLONE_URLS_ACCEPTED'), out[:120])
finally:
    mc.borra(tmpcl)

# --- delphi_textedit (non-Delphi text files) ---
tmptxt = _fixed('textedit')
try:
    md = os.path.join(tmptxt, 'README.md')
    out = call('delphi_textedit', {"path": md, "create": True,
        "content": "# Titulo\r\nlinea con acentos: gestoria admision\r\nfin\r\n"})
    check('textedit: create .md', mc.abre(out, 'SK_TEXT_CREADO_ENCODING_FINALES_FMT'), out[:150])
    out = call('delphi_textedit', {"path": md, "create": True, "content": "x"})
    check('textedit: create nunca sobreescribe', mc.rechazado(out) and mc.es(out, 'SR_TEXT_YA_EXISTE_NUNCA_SOBREESCRIBE_FMT'), out[:150])
    out = call('delphi_textedit', {"path": md,
        "old": "linea con acentos: gestoria admision",
        "new": "linea EDITADA por MCP"})
    check('textedit: edit con ancla', mc.abre(out, 'SK_TEXT_OK_LINEA_FMT'), out[:200])
    body = open(md, 'rb').read().decode('utf-8')
    check('textedit: contenido correcto en disco',
          'linea EDITADA por MCP' in body and '# Titulo' in body and 'fin' in body, body[:120])
    check('textedit: CRLF preservado', '\r\n' in body, repr(body[:40]))
    # --- varias ediciones en UNA llamada, y todo o nada ---
    # Sin esto, cambiar tres lineas eran tres llamadas y tres oportunidades de
    # dejar el fichero a medias (medido el 2026-09-20 usando el servidor como
    # agente para trabajar en su propio repo).
    lote = os.path.join(tmptxt, 'lote.md')
    call('delphi_textedit', {"path": lote, "create": True,
                             "content": "uno\ndos\ntres\ncuatro\n", "eol": "lf"})
    out = call('delphi_textedit', {"path": lote, "edits": json.dumps([
        {"old": "uno", "new": "UNO"},
        {"old": "dos", "delete": True},
        {"old": "cuatro", "new": "CUATRO"}])})
    cuerpo = open(lote, 'rb').read().decode('utf-8')
    check('textedit: varias ediciones en una sola llamada',
          mc.abre(out, 'SN_PATCH_EDITS_OK_FMT') and cuerpo == 'UNO\ntres\nCUATRO\n',
          (out[:90], repr(cuerpo)))
    out = call('delphi_textedit', {"path": lote, "edits": json.dumps([
        {"old": "UNO", "new": "roto"},
        {"old": "esta linea no existe", "new": "x"}])})
    cuerpo = open(lote, 'rb').read().decode('utf-8')
    check('textedit: si una falla, el fichero vuelve byte a byte',
          mc.es(out, 'SR_PATCH_EDITS_ROLLED_FMT') and cuerpo == 'UNO\ntres\nCUATRO\n',
          (out[:90], repr(cuerpo)))
    # Ancla de BLOQUE dentro del lote: sin esto, un parrafo largo no se podia
    # tocar - TOOLS.md tiene parrafos de 3 KB en UNA linea y el ancla es "una
    # linea completa", asi que habia que pegar los 3 KB (medido el 2026-09-20
    # trabajando en el propio repo por el MCP).
    bloque = os.path.join(tmptxt, 'bloque.md')
    call('delphi_textedit', {"path": bloque, "create": True, "eol": "lf",
                             "content": "cabecera\nuno\ndos\ntres\npie\n"})
    out = call('delphi_textedit', {"path": bloque, "edits": json.dumps([
        {"old": "uno\ndos\ntres", "new": "UNO Y DOS Y TRES"}])})
    cuerpo = open(bloque, 'rb').read().decode('utf-8')
    check('textedit: un ancla de VARIAS lineas sustituye el bloque entero',
          (mc.catalogo()['SF_EDIT_OK_BLOQUE_LINEAS_FMT'] % (1, 3)).strip() in out
          and cuerpo == 'cabecera\nUNO Y DOS Y TRES\npie\n',
          (out[:90], repr(cuerpo)))
    # "occurrence" desempata donde atline no sirve: los numeros se mueven
    rep = os.path.join(tmptxt, 'repes.md')
    call('delphi_textedit', {"path": rep, "create": True, "eol": "lf",
                             "content": "x\nigual\ny\nigual\nz\n"})
    out = call('delphi_textedit', {"path": rep, "edits": json.dumps([
        {"old": "igual", "new": "SEGUNDA", "occurrence": 2}])})
    cuerpo = open(rep, 'rb').read().decode('utf-8')
    check('textedit: "occurrence" elige cual de las lineas repetidas',
          cuerpo == 'x\nigual\ny\nSEGUNDA\nz\n', (out[:90], repr(cuerpo)))
    out = call('delphi_textedit', {"path": lote, "old": "tres", "delete": True})
    cuerpo = open(lote, 'rb').read().decode('utf-8')
    check('textedit: delete quita la linea ENTERA (no la deja en blanco)',
          mc.abre(out, 'SK_TEXT_OK_BORRADA_LINEA_FMT') and cuerpo == 'UNO\nCUATRO\n',
          (out[:90], repr(cuerpo)))
    out = call('delphi_textedit', {"path": md, "old": "no existe esta linea",
                                   "new": "x"})
    check('textedit: ancla inexistente rechaza', mc.rechazado(out) and mc.es(out, 'SR_ANCLA_NO_ESTA_FMT'), out[:150])
    out = call('delphi_textedit', {"path": md, "new": "reescritura entera"})
    check('textedit: reescritura sin ancla rechaza', mc.rechazado(out) and mc.es(out, 'SR_TEXT_FALTA_ANCLA_OLD_ESTA'), out[:150])
    out = call('delphi_textedit', {"path": os.path.join(SRC, 'Lsp.Guard.pas'),
                                   "old": "interface", "new": "x"})
    check('textedit: .pas vetado (usa delphi_edit)', mc.rechazado(out) and mc.es(out, 'SR_TEXT_FICHERO_DELPHI_FUENTES_DESIGNERS_FMT') and 'delphi_edit' in out, out[:150])
    out = call('delphi_textedit', {"path": os.path.join(SRC, 'DelphiLspMcp.dproj'),
                                   "old": "x", "new": "y"})
    check('textedit: .dproj vetado', mc.rechazado(out) and mc.es(out, 'SR_TEXT_FICHERO_DELPHI_FUENTES_DESIGNERS_FMT'), out[:150])
    html = os.path.join(tmptxt, 'index.html')
    out = call('delphi_textedit', {"path": html, "create": True,
        "content": "<html><body>hola</body></html>\r\n"})
    check('textedit: crea .html (proyectos web)', mc.abre(out, 'SK_TEXT_CREADO_ENCODING_FINALES_FMT'), out[:120])
    out = call('delphi_textedit', {"path": html,
        "old": "<html><body>hola</body></html>",
        "new": "<html><body>hola MCP</body></html>"})
    check('textedit: edita .html', mc.abre(out, 'SK_TEXT_OK_LINEA_FMT'), out[:150])
    # backup exists next to the file
    bdir = os.path.join(tmptxt, '__delphi-patch')
    check('textedit: backup automatico creado', os.path.isdir(bdir), bdir)
finally:
    mc.borra(tmptxt)
out = call('delphi_git', {"repo": GIT_REPO, "command": "commit"})
check('git: commit sin message rechaza', mc.es(out, 'SR_GIT_COMMIT_NEEDS_MESSAGE'), out[:120])

servidor.cierra()
mc.fin('workspace battery')
