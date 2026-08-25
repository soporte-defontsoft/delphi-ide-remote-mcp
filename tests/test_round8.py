"""E2E battery for v0.60.0-beta - the field round-8 findings.

Three agents worked the server through nothing but MCP on 2026-08-25 (a
security auditor, a contract prober and one doing a real programming job) and
came back with 30+ findings. This battery is those findings turned into
checks, so none of them can come back quietly.

What it covers, by the number the reports used:
  #1  delphi_create is atomic (no orphan .dpr when a file is in the way)
  #2  reserved words refused as unit names
  #3  RTL unit names refused
  #4  a form of the wrong framework refused
  #5  delphi_upload with no chunk NEVER truncates
  #6  delphi_config view on a bare .dpr says what it cannot know
  #7  the real drive letter does not leak through a JSON-escaped newline
  #8  vault_read's footer reports the range it actually showed
  #9  the mailbox notice never names another agent's box
  #10 a missing required parameter is a refusal, not an internal error
  #11 remove-platform is idempotent and will not leave a project with none
  #12 delphi_styles set refuses a value the file could not hold
  #13 renaming a style to a name already there is refused
  #17 delphi_designer prop gives the members of a SET
  #22 delphi_fetch's maxbytes parameter tells the truth about itself
  #26 an upload whose sha does not match is quarantined, not published
  #27 vault_search refuses a target it does not know
  M1  changeset stage validates against the BATCH, not just the disk
  M1b changeset unstage takes one operation back out
  C1  delphi_create kind=unit content=... creates AND fills in one call

Usage:  python tests/test_round8.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, base64, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round8')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
VAULT = os.path.join(BASE, 'vault')
os.makedirs(os.path.join(VAULT, 'projects'))
open(os.path.join(VAULT, 'projects', 'nota.md'), 'w', encoding='utf-8').write(
    ''.join('linea %d\n' % i for i in range(1, 41)))


def spawn(extra_env=None):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = BASE
    env['DELPHI_MCP_VAULT_PATH'] = VAULT
    env['DELPHI_MCP_VAULT_READONLY'] = '0'
    if extra_env:
        env.update(extra_env)
    p = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    q = queue.Queue()

    def rd():
        for line in p.stdout:
            line = line.strip()
            if line:
                q.put(line)
    threading.Thread(target=rd, daemon=True).start()
    st = {'p': p, 'q': q, 'id': 10}
    send(st, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "r8", "version": "1"}}})
    recv(st, 1)
    send(st, {"jsonrpc": "2.0", "method": "notifications/initialized"})
    return st


def send(st, o):
    st['p'].stdin.write(json.dumps(o) + '\n')
    st['p'].stdin.flush()


def recv(st, r, t=600):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = st['q'].get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None


def call(st, name, args, t=600):
    st['id'] += 1
    send(st, {"jsonrpc": "2.0", "id": st['id'], "method": "tools/call",
              "params": {"name": name, "arguments": args}})
    r = recv(st, st['id'], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:300]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'


def raw_result(st, name, args, t=600):
    """The whole tools/call result as it travels: what the client really sees."""
    st['id'] += 1
    send(st, {"jsonrpc": "2.0", "id": st['id'], "method": "tools/call",
              "params": {"name": name, "arguments": args}})
    r = recv(st, st['id'], t)
    return json.dumps(r) if r else '(timeout)'


P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:300])


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def tools_schema(st):
    st['id'] += 1
    send(st, {"jsonrpc": "2.0", "id": st['id'], "method": "tools/list", "params": {}})
    r = recv(st, st['id'])
    return {t['name']: t for t in r['result']['tools']}


A = spawn()

# ---------------------------------------------------------------- #5, #26 --
UP = os.path.join(BASE, 'subida')
os.makedirs(UP)
VICTIM = os.path.join(UP, 'victima.pas')
open(VICTIM, 'w', encoding='utf-8').write('unit victima;\ninterface\nimplementation\nend.\n')
ORIG = open(VICTIM, 'rb').read()

r = call(A, 'delphi_upload', {'path': VICTIM})
check('#5 upload sin chunk: RECHAZADO, no truncado',
      'RECHAZADO' in r and open(VICTIM, 'rb').read() == ORIG, r[:200])
r = call(A, 'delphi_upload', {'path': VICTIM, 'chunkbase64': ''})
check('#5 chunk vacio explicito tampoco vacia el fichero',
      'RECHAZADO' in r and open(VICTIM, 'rb').read() == ORIG, r[:200])
r = call(A, 'delphi_upload', {'path': os.path.join(UP, 'nuevo.bin')})
check('#5 sin chunk sobre fichero que no existe: tambien rechazado',
      'RECHAZADO' in r and not os.path.exists(os.path.join(UP, 'nuevo.bin')), r[:200])

j = J(call(A, 'delphi_upload', {'path': VICTIM,
                                'chunkbase64': base64.b64encode(b'X').decode(), 'offset': 0}))
check('upload que sustituye lo DICE y dice donde esta la copia',
      j.get('replaced') is True and j.get('previousSize') == len(ORIG) and bool(j.get('backup')),
      str(j)[:300])
backups = glob.glob(os.path.join(UP, '__delphi-patch', '*', 'victima.pas'))
check('la copia recuperable existe y es el contenido de antes',
      len(backups) == 1 and open(backups[0], 'rb').read() == ORIG, backups)

BAD = os.path.join(UP, 'corrupto.bin')
j = J(call(A, 'delphi_upload', {'path': BAD, 'chunkbase64': base64.b64encode(b'abc').decode(),
                                'offset': 0, 'sha256': '0' * 64}))
check('#26 sha que no cuadra: NO queda publicado con su nombre',
      j.get('verified') is False and not os.path.exists(BAD), str(j)[:300])
check('#26 ...y se dice donde ha quedado apartado',
      str(j.get('quarantined', '')).endswith('.corrupto') and os.path.exists(BAD + '.corrupto'),
      str(j)[:300])

# -------------------------------------------------------------------- #7 --
# A build error carries the IDE's own path at the START of a line. Inside the
# JSON string that newline is the two chars \ and n, which used to make the
# masker treat the drive letter as part of a word.
PROJ = os.path.join(BASE, 'FugaTest')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'FugaTest', 'dir': PROJ})
assert 'CREADO' in r, r
DPR = os.path.join(PROJ, 'FugaTest.dpr')
open(DPR, 'w', encoding='utf-8-sig', newline='\r\n').write(
    'program FugaTest;\n\n{$APPTYPE CONSOLE}\n\nbegin\n  esto no compila;\nend.\n')
raw = raw_result(A, 'delphi_build', {'project': os.path.join(PROJ, 'FugaTest.dproj'),
                                     'platform': 'Win64', 'config': 'Debug'}, t=900)
import re as _re
low = _re.sub('srv[a-z]:', '', raw.lower())   # the virtual form CONTAINS "c:"
leaked = _re.findall(r'[a-z]:\\', low) + _re.findall(r'[a-z]%3a', low)
check('#7 ninguna unidad REAL viaja en la respuesta del build (ni tras un \\n)',
      not leaked, (leaked, raw[:400]))
check('#7 ...y las virtuales si estan (la respuesta no viene vacia)',
      'srv' in raw.lower(), raw[:300])

# ------------------------------------------------------------- #1 #2 #3 #4 --
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'begin',
                              'project': os.path.join(PROJ, 'FugaTest.dproj')})
check('#2 palabra reservada como nombre de unit: RECHAZADO',
      'RECHAZADO' in r and 'reservada' in r, r[:200])
check('#2 ...y no ha creado el fichero', not os.path.exists(os.path.join(PROJ, 'begin.pas')))
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'System',
                              'project': os.path.join(PROJ, 'FugaTest.dproj')})
check('#3 nombre de unit de la RTL: RECHAZADO',
      'RECHAZADO' in r and 'RTL' in r, r[:200])
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'MiApp.Datos',
                              'project': os.path.join(PROJ, 'FugaTest.dproj')})
check('un nombre con espacio de nombres SI se acepta', r.startswith('CREADA'), r[:200])

VCLDIR = os.path.join(BASE, 'ProyVcl')
r = call(A, 'delphi_create', {'kind': 'project-vcl', 'name': 'ProyVcl', 'dir': VCLDIR})
assert 'CREADO' in r, r
r = call(A, 'delphi_create', {'kind': 'project-fmx', 'name': 'OtroFmx', 'dir': VCLDIR})
check('#1 colision: RECHAZADO y NADA creado',
      'RECHAZADO' in r and not os.path.exists(os.path.join(VCLDIR, 'OtroFmx.dpr')), r[:250])
check('#1 ...y el mensaje dice que no ha creado nada', 'NADA' in r.upper(), r[:250])
r = call(A, 'delphi_create', {'kind': 'form-fmx', 'name': 'UCruzado',
                              'project': os.path.join(VCLDIR, 'ProyVcl.dproj')})
check('#4 form FMX en un proyecto VCL: RECHAZADO',
      'RECHAZADO' in r and 'VCL' in r, r[:250])
check('#4 ...y no ha dejado el .pas', not os.path.exists(os.path.join(VCLDIR, 'UCruzado.pas')))
r = call(A, 'delphi_create', {'kind': 'form-vcl', 'name': 'UBueno',
                              'project': os.path.join(VCLDIR, 'ProyVcl.dproj')})
check('#4 el form del framework que toca SI entra', r.startswith('CREADO'), r[:200])

# ------------------------------------------------------------------- #10 --
r = call(A, 'delphi_package', {})
check('#10 delphi_package sin dir: refusal, no error interno',
      'necesita "dir"' in r and 'Error executing tool' not in r, r[:200])
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'Suelto'})
check('#10 delphi_create de proyecto sin dir: refusal con la pista',
      'RECHAZADO' in r and 'dir' in r and 'Error executing tool' not in r, r[:200])

# -------------------------------------------------------------------- #C1 --
SANO = os.path.join(BASE, 'Sano')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'Sano', 'dir': SANO})
assert 'CREADO' in r, r
SANODPROJ = os.path.join(SANO, 'Sano.dproj')
CONT = 'unit ULlena;\r\n\r\ninterface\r\n\r\nfunction Doble(A: Integer): Integer;\r\n\r\n' \
       'implementation\r\n\r\nfunction Doble(A: Integer): Integer;\r\nbegin\r\n' \
       '  Result := A * 2;\r\nend;\r\n\r\nend.\r\n'
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'ULlena', 'content': CONT,
                              'project': SANODPROJ})
disk = open(os.path.join(SANO, 'ULlena.pas'), 'rb').read().decode('utf-8-sig')
check('#C1 create con content: crea CON el contenido y lo registra',
      r.startswith('CREADA') and 'Result := A * 2;' in disk and 'NO se pudo registrar' not in r,
      (r[:200], disk[:80]))
check('#C1 el contenido llega entero y en CRLF', disk.count('\r\n') >= 10 and disk.endswith('end.\r\n'),
      repr(disk[-20:]))
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'UOtra', 'content': 'unit NoCoincide;\nend.\n',
                              'project': os.path.join(PROJ, 'FugaTest.dproj')})
check('#C1 content cuyo "unit" no casa con el nombre: RECHAZADO',
      'RECHAZADO' in r and not os.path.exists(os.path.join(SANO, 'UOtra.pas')), r[:200])
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'UCorta', 'content': 'unit UCorta;\ninterface\n',
                              'project': os.path.join(PROJ, 'FugaTest.dproj')})
check('#C1 content cortado (sin end.): RECHAZADO', 'RECHAZADO' in r, r[:200])

# -------------------------------------------------------------------- #6 --
SOLO = os.path.join(BASE, 'soloDpr')
os.makedirs(SOLO)
SOLODPR = os.path.join(SOLO, 'Solo.dpr')
open(SOLODPR, 'w', encoding='utf-8').write(
    "program Solo;\r\n\r\nuses\r\n  System.SysUtils,\r\n  UAlgo in 'UAlgo.pas';\r\n\r\nbegin\r\nend.\r\n")
open(os.path.join(SOLO, 'UAlgo.pas'), 'w', encoding='utf-8').write(
    'unit UAlgo;\r\ninterface\r\nimplementation\r\nend.\r\n')
j = J(call(A, 'delphi_config', {'project': SOLODPR}))
check('#6 view de un .dpr suelto: dice que NO hay .dproj', j.get('hasDproj') is False, str(j)[:300])
check('#6 ...no inventa framework ni plataformas',
      'frameworkType' not in j and 'platforms' not in j and 'crossPlatform' not in j, str(j)[:300])
check('#6 ...pero SI da las units', any(u.get('unit') == 'UAlgo' for u in j.get('units', [])), str(j)[:300])
r = call(A, 'delphi_config', {'project': SOLODPR, 'command': 'add-platform', 'platform': 'Win64'})
check('#6 un comando que necesita .dproj sobre un .dpr: refusal clara',
      'RECHAZADO' in r and '.dproj' in r, r[:250])
j = J(call(A, 'delphi_config', {'project': os.path.join(VCLDIR, 'ProyVcl.dpr')}))
check('#6 con .dproj al lado, el .dpr se resuelve solo',
      j.get('frameworkType', '') != '' and j.get('hasDproj') is not False, str(j)[:250])

# ------------------------------------------------------------------- #11 --
r = call(A, 'delphi_config', {'project': os.path.join(VCLDIR, 'ProyVcl.dproj'),
                              'command': 'add-platform', 'platform': 'Win32'})
r = call(A, 'delphi_config', {'project': os.path.join(VCLDIR, 'ProyVcl.dproj'),
                              'command': 'remove-platform', 'platform': 'Win32'})
check('#11 remove-platform funciona con otra habilitada', 'DESHABILITADA' in r, r[:200])
r2 = call(A, 'delphi_config', {'project': os.path.join(VCLDIR, 'ProyVcl.dproj'),
                               'command': 'remove-platform', 'platform': 'Win32'})
check('#11 repetirlo es idempotente y NO hace copia de un no-op',
      'YA estaba' in r2 and 'no he tocado nada' in r2.lower(), r2[:200])
r = call(A, 'delphi_config', {'project': os.path.join(VCLDIR, 'ProyVcl.dproj'),
                              'command': 'remove-platform', 'platform': 'Win64'})
check('#11 quitar la ULTIMA plataforma: RECHAZADO',
      'RECHAZADO' in r and 'ULTIMA' in r, r[:250])

# ---------------------------------------------------------------- #12 #13 --
STY = os.path.join(BASE, 'estilos')
os.makedirs(STY)
open(os.path.join(STY, 'Mi.style'), 'w', encoding='utf-8').write(
    "object TStyleContainer\r\n"
    "  object TRectangle\r\n"
    "    StyleName = 'cardstyle'\r\n"
    "    Fill.Color = xFF2A2A2A\r\n"
    "  end\r\n"
    "  object TRectangle\r\n"
    "    StyleName = 'buttonstyle'\r\n"
    "    Fill.Color = xFF3A3A3A\r\n"
    "  end\r\n"
    "end\r\n")
SFILE = os.path.join(STY, 'Mi.style')
r = call(A, 'delphi_styles', {'command': 'set', 'path': SFILE, 'style': 'cardstyle',
                              'prop': 'Fill.Color', 'value': 'no soy un color'})
check('#12 valor imposible en un .style: RECHAZADO antes de escribir',
      'RECHAZADO' in r and 'no soy un color' not in open(SFILE, encoding='utf-8').read(), r[:250])
r = call(A, 'delphi_styles', {'command': 'set', 'path': SFILE, 'style': 'cardstyle',
                              'prop': 'Fill.Color', 'value': 'xFF112233'})
check('#12 un valor legal SI se escribe', 'CAMBIADA' in r, r[:200])
r = call(A, 'delphi_styles', {'command': 'set', 'path': SFILE, 'style': 'cardstyle',
                              'prop': 'StyleName', 'value': "'buttonstyle'"})
check('#13 renombrar a un StyleName que ya existe: RECHAZADO',
      'RECHAZADO' in r and open(SFILE, encoding='utf-8').read().count("'buttonstyle'") == 1, r[:250])
r = call(A, 'delphi_styles', {'command': 'set', 'path': SFILE, 'style': 'cardstyle',
                              'prop': 'StyleName', 'value': "'tarjeta'"})
check('#13 un rename limpio se permite y se DICE que es un rename',
      'RENOMBRADO' in r and "'tarjeta'" in open(SFILE, encoding='utf-8').read(), r[:250])

# ------------------------------------------------------------------- #17 --
j = J(call(A, 'delphi_designer', {'command': 'prop', 'class': 'TStringGrid', 'prop': 'Options'}))
check('#17 prop de un SET trae sus miembros',
      j.get('kind') == 'set' and 'goEditing' in j.get('members', ''), str(j)[:300])
j = J(call(A, 'delphi_designer', {'command': 'prop', 'class': 'TButton', 'prop': 'Align'}))
check('#17 los enums siguen igual', 'alNone' in j.get('members', ''), str(j)[:200])

# -------------------------------------------------------------- designer --
DFM = os.path.join(BASE, 'Form1.dfm')
open(DFM, 'w', encoding='utf-8').write(
    "object Form1: TForm1\r\n"
    "  Caption = 'x'\r\n"
    "  object Grid: TNoExisteJamas\r\n"
    "    Left = 8\r\n"
    "  end\r\n"
    "end\r\n")
r = call(A, 'delphi_designer', {'command': 'lint', 'path': DFM})
check('#15 lint nombra la clase que no conoce',
      'TNoExisteJamas' in r, r[:300])
check('#15 ...y no acusa a la clase del propio form', 'TForm1' not in r, r[:300])
FMX = os.path.join(BASE, 'Vista.fmx')
open(FMX, 'w', encoding='utf-8').write(
    "object Vista: TVista\r\n"
    "  object Lista: TVertScrollBox\r\n"
    "    Viewport.Width = 530.000000000000000000\r\n"
    "    Viewport.Height = 200.000000000000000000\r\n"
    "  end\r\n"
    "end\r\n")
r = call(A, 'delphi_designer', {'command': 'lint', 'path': FMX})
check('#16 Viewport.* (lo escribe el propio IDE) NO se denuncia',
      'Viewport' not in r, r[:300])

# ---------------------------------------------------------------- #8 #27 --
r = call(A, 'vault_read', {'path': 'projects/nota.md', 'offset': 5, 'limit': 3})
check('#8 el pie dice el rango REAL mostrado', 'lineas 5..7 de 41' in r, r[-200:])
check('#8 ...y el cuerpo es ese rango', 'linea 5' in r and 'linea 8' not in r, r[:300])
r = call(A, 'vault_read', {'path': 'projects/nota.md', 'offset': 99999})
check('#28 offset pasado del final: se explica, no se calla',
      'mas alla del final' in r and '41 lineas' in r, r[:200])
r = call(A, 'vault_search', {'target': 'contents', 'pattern': 'linea'})
check('#27 target invalido: RECHAZADO en vez de caer a files en silencio',
      'no existe' in r and 'files' in r and 'content' in r, r[:250])
r = call(A, 'vault_search', {'target': 'content', 'pattern': 'linea 3'})
check('#27 el target bueno sigue funcionando', 'nota.md' in r, r[:200])

# ------------------------------------------------------------------- #22 --
schema = tools_schema(A)
desc = json.dumps(schema['delphi_fetch']['inputSchema'])
check('#22 maxbytes documenta el limite REAL de los trozos inline',
      '1048576' in desc and '4' in desc, desc[:400])

# ---------------------------------------------------------- M1 / unstage --
CS = os.path.join(BASE, 'tanda')
os.makedirs(CS)
UNO = os.path.join(CS, 'Uno.pas')
open(UNO, 'w', encoding='utf-8').write('unit Uno;\r\ninterface\r\nimplementation\r\nend.\r\n')
r = call(A, 'delphi_changeset', {'command': 'begin'})
CID = r.split()[-1].strip('.') if r else ''
CID = [w for w in r.replace('.', ' ').split() if '-' in w][0]
r = call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'delete', 'path': UNO})
check('M1 delete se apila', 'apilada' in r.lower() or 'stage' in r.lower() or 'borra' in r.lower(), r[:200])
r = call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'create', 'path': UNO,
                                 'content': 'unit Uno;\r\ninterface\r\nimplementation\r\nend.\r\n'})
check('M1 create del MISMO fichero tras el delete: se acepta (la tanda es un plan)',
      'RECHAZADO' not in r, r[:250])
r = call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'create',
                                 'path': os.path.join(CS, 'Dos.pas'), 'content': 'unit Dos;\r\nend.\r\n'})
r = call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'create',
                                 'path': os.path.join(CS, 'Dos.pas'), 'content': 'x'})
check('M1 crear DOS veces el mismo fichero en la misma tanda: RECHAZADO',
      'RECHAZADO' in r, r[:250])
r = call(A, 'delphi_changeset', {'command': 'unstage', 'id': CID})
check('M1b unstage quita la ultima y dice cuantas quedan',
      'Quitada' in r and 'Quedan 2' in r, r[:250])
r = call(A, 'delphi_changeset', {'command': 'unstage', 'id': CID, 'n': 99})
check('M1b unstage con n imposible: RECHAZADO con el numero bueno',
      'RECHAZADO' in r and '2' in r, r[:250])
r = call(A, 'delphi_changeset', {'command': 'preview', 'id': CID})
check('M1 preview aguanta una operacion sobre algo que aun no existe',
      'RECHAZADO' not in r and 'error' not in r[:40].lower(), r[:250])
r = call(A, 'delphi_changeset', {'command': 'commit', 'id': CID})
check('M1 la tanda delete+create se aplica entera',
      os.path.exists(UNO) and 'RECHAZADO' not in r, r[:250])

# --------------------------------------------------------------------- #9 --
MBOX = os.path.join(BASE, 'messages')
os.makedirs(os.path.join(MBOX, 'otro'), exist_ok=True)
open(os.path.join(MBOX, 'otro', '20260825-privado.md'), 'w', encoding='utf-8').write(
    '# privado\n\nsolo para otro\n')
MSG = spawn()
t = call(MSG, 'delphi_workspace', {})
check('#9 el aviso NO nombra el buzon ajeno', 'otro' not in t, t[-250:])
check('#9 ...pero SI dice que hay correo dirigido a alguien',
      'dirigidos a agentes concretos' in t, t[-250:])
open(os.path.join(MBOX, '20260825-general.md'), 'w', encoding='utf-8').write(
    '# general\n\npara todos\n')
t = call(MSG, 'delphi_workspace', {})
check('#9 el correo para TODOS si se anuncia como tuyo',
      'para TODOS' in t, t[-250:])
# El aviso se pegaba DETRAS del resultado: con correo esperando, cualquier
# respuesta JSON dejaba de poder parsearse (json.loads reventaba de la nada,
# y solo mientras hubiera correo). Ahora entra DENTRO del objeto.
jw = J(t)
check('#9 con correo esperando, una respuesta JSON SIGUE siendo JSON',
      jw != {} and 'roots' in jw, t[:120])
check('#9 ...y el aviso viaja dentro, en "mailbox"',
      'para TODOS' in jw.get('mailbox', ''), str(jw.get('mailbox'))[:150])
MSG['p'].kill()

# ------------------------------------------------- M4: delphi_help ---------
r = call(A, 'delphi_help', {})
check('M4 help por defecto: la tabla tarea -> tool',
      'delphi_edit' in r and 'delphi_test' in r and 'delphi_changeset' in r, r[:200])
check('M4 ...y cabe en poco: es un atajo, no el catalogo', len(r) < 4000, len(r))
r = call(A, 'delphi_help', {'command': 'conventions'})
check('M4 conventions dice lo que vale para todas',
      'srvd:' in r and 'ancla' in r.lower() and '__delphi-patch' in r, r[:200])
j = J(call(A, 'delphi_help', {'command': 'tool', 'name': 'edit'}))
check('M4 una tool suelta: descripcion + parametros',
      j.get('tool') == 'delphi_edit' and 'properties' in j.get('parameters', {}), str(j)[:200])
j = J(call(A, 'delphi_help', {'name': 'delphi_changeset'}))
check('M4 con solo name, la intencion es obvia', j.get('tool') == 'delphi_changeset', str(j)[:200])
r = call(A, 'delphi_help', {'command': 'tool', 'name': 'noexiste'})
check('M4 tool inventada: RECHAZADO diciendo cuales hay',
      'RECHAZADO' in r and 'delphi_edit' in r, r[:200])
r = call(A, 'delphi_help', {'command': 'volar'})
check('M4 command invalido: los tres validos', 'tasks' in r and 'conventions' in r, r[:200])

# ------------------------------------------------ C2/C4/F2 del campo -------
j = J(call(A, 'delphi_projects', {}))
proj = [p for p in j.get('projects', []) if p.get('name') == 'Sano']
check('C2 delphi_projects dice el repo y la rama cuando los hay',
      all(('repo' in p) == ('branch' in p) for p in j.get('projects', [])), str(j)[:200])
raw = raw_result(A, 'delphi_build', {'project': os.path.join(PROJ, 'FugaTest.dproj'),
                                     'platform': 'Win64', 'config': 'Debug'}, t=900)
b = json.loads(raw)['result']['content'][0]['text']
jb = J(b)
check('F2 un build con varios errores nombra el PRIMERO',
      (len(jb.get('errors', [])) < 2) or (bool(jb.get('firstError')) and bool(jb.get('firstErrorNote'))),
      str(jb)[:250])

A['p'].kill()
print('\n== round-8 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
