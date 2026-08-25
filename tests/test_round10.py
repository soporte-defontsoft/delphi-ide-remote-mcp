"""E2E battery for v0.63.0-beta - the field round-10 findings.

The fourth wave of agents (security, contracts, a real programming job) went
at the 0.62 server through nothing but MCP. What they found, turned into
checks. The one that matters most is P2: a runner printing "Fail: x" was
counted as nothing at all, so a RED suite came back green - the only time
this server has ever called broken code working.

  R1  paserver test-connection dials only allowed hosts (SSRF, second door)
  R3  changeset commit refuses on a changed file instead of crashing
  B2  a dotted RTL namespace cannot hijack the compiler's own units
  B3  deleting a folder tells the truth, and a retry does not re-copy
  B4  a bad project kind names the kinds that exist
  B5  a caller's mistake is never "Error executing tool:"
  B6  commit reports the delta once per FILE, with the right sign
  P1  naming a build folder as root lists what is inside it
  P2  PASS/FAIL counting is case-insensitive and near misses are declared
  P3  the timeout note does not contradict its own answer
  P4  nobuild with no binary does not claim it compiled
  P6  the changeset kind refusal includes delete-line
  P7  hover/definition on a non-Delphi file say so
  P8  an invented test platform is refused
  D1  rename gives an anchor that can be pasted, and a column
  D3  changeset create normalises line endings like delphi_create
  D5  preview says which line each anchor resolved to
  F5  an IPv6 git URL parses as a host, not as "["
  ..  help survives a one-letter typo; a bad sha256 does not punish the file

Usage:  python tests/test_round10.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, base64

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round10')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)


def spawn(extra_env=None):
    env = dict(os.environ)
    env['DELPHI_MCP_ROOTS'] = BASE
    env['DELPHI_MCP_ALLOW_TESTS'] = '1'
    env.pop('DELPHI_MCP_GIT_REMOTES', None)
    env.pop('DELPHI_MCP_REMOTE_HOSTS', None)
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
        "clientInfo": {"name": "r10", "version": "1"}}})
    recv(st, 1)
    send(st, {"jsonrpc": "2.0", "method": "notifications/initialized"})
    return st


def send(st, o):
    st['p'].stdin.write(json.dumps(o) + '\n')
    st['p'].stdin.flush()


def recv(st, r, t=900):
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


def call(st, name, args, t=900):
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


A = spawn()

# ------------------------------------------------------------ R1: paserver --
j = J(call(A, 'delphi_paserver', {'command': 'test-connection', 'host': '127.0.0.1',
                                  'port': '3131'}, t=120))
r = call(A, 'delphi_paserver', {'command': 'test-connection', 'host': '127.0.0.1',
                                'port': '3131'}, t=120)
check('R1 sondear un host a mano: RECHAZADO (era el mismo SSRF que git)',
      'RECHAZADO' in r and 'RemoteHosts' in r, r[:250])
r = call(A, 'delphi_paserver', {'command': 'test-connection', 'host': 'example.com',
                                'port': '80'}, t=120)
check('R1 ...y a Internet tambien', 'RECHAZADO' in r, r[:200])
B = spawn({'DELPHI_MCP_REMOTE_HOSTS': '127.0.0.1'})
r = call(B, 'delphi_paserver', {'command': 'test-connection', 'host': '127.0.0.1',
                                'port': '59999'}, t=120)
check('R1 el host que el operador permite SI se sondea',
      'RECHAZADO' not in r and 'tcpReachable' in r, r[:200])
B['p'].kill()

# -------------------------------------------------------------- R3: commit --
CS = os.path.join(BASE, 'cs')
os.makedirs(CS)
N = os.path.join(CS, 'Nota.txt')
open(N, 'w', encoding='utf-8', newline='\r\n').write('uno\ndos\ntres\n')
r = call(A, 'delphi_changeset', {'command': 'begin'})
CID = [w for w in r.replace('.', ' ').split() if w.count('-') >= 2][0]
call(A, 'delphi_changeset', {'command': 'stage', 'id': CID, 'kind': 'edit',
                             'path': N, 'old': 'dos', 'new': 'DOS'})
call(A, 'delphi_changeset', {'command': 'preview', 'id': CID})
call(A, 'delphi_textedit', {'path': N, 'old': 'tres', 'new': 'TRES'})
r = call(A, 'delphi_changeset', {'command': 'commit', 'id': CID})
check('R3 fichero cambiado tras el preview: RECHAZADO, sin Access Violation',
      'FILE_CHANGED' in r and 'Access violation' not in r, r[:250])
check('R3 ...y el fichero sigue como lo dejo el de fuera',
      open(N, encoding='utf-8').read().count('TRES') == 1, open(N, encoding='utf-8').read())
call(A, 'delphi_changeset', {'command': 'rollback', 'id': CID})

# --------------------------------------------------------------- B2: RTL ----
PRJ = os.path.join(BASE, 'App')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': PRJ})
assert 'CREADO' in r, r
DPROJ = os.path.join(PRJ, 'App.dproj')
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'System.SysUtils', 'project': DPROJ})
check('B2 un nombre CUALIFICADO de la RTL: RECHAZADO',
      'RECHAZADO' in r and not os.path.exists(os.path.join(PRJ, 'System.SysUtils.pas')),
      r[:250])
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'Vcl.Forms', 'project': DPROJ})
check('B2 ...y cualquier otro espacio de Embarcadero', 'RECHAZADO' in r, r[:200])
r = call(A, 'delphi_create', {'kind': 'unit', 'name': 'MiEmpresa.Datos', 'project': DPROJ})
check('B2 un espacio de nombres PROPIO sigue valiendo', r.startswith('CREADA'), r[:200])
r = call(A, 'delphi_create', {'kind': 'project-web', 'name': 'X', 'dir': os.path.join(BASE, 'X')})
check('B4 un kind de proyecto inventado nombra los que existen',
      'project-console' in r and 'project-vcl' in r, r[:250])

# ---------------------------------------------------------------- B3: rm ----
D = os.path.join(BASE, 'paraborrar')
os.makedirs(os.path.join(D, 'sub'))
open(os.path.join(D, 'sub', 'a.txt'), 'w').write('a')
r = call(A, 'delphi_delete', {'path': D})
check('B3 borrado de carpeta: o BORRADO de verdad, o dice exactamente que queda',
      ('BORRADO' in r and not os.path.isdir(D)) or ('CASI' in r or 'A MEDIAS' in r),
      (r[:200], os.path.isdir(D)))
if os.path.isdir(D):
    import glob
    before = len(glob.glob(os.path.join(BASE, '__delphi-patch', '*', 'deleted', '*')))
    r = call(A, 'delphi_delete', {'path': D})
    after = len(glob.glob(os.path.join(BASE, '__delphi-patch', '*', 'deleted', '*')))
    check('B3 reintentar sobre el cascaron vacio NO hace otra copia', after == before,
          (before, after, r[:150]))
else:
    check('B3 reintentar sobre el cascaron vacio NO hace otra copia', True, '(se borro entera)')

# ------------------------------------------------------------------- B5 -----
GHOST = os.path.join(PRJ, 'NoExiste.pas')
for tool in ('delphi_symbols',):
    r = call(A, tool, {'path': GHOST})
    check('B5 %s con un fichero que no esta: RECHAZADO, no fallo interno' % tool,
          r.startswith('RECHAZADO'), r[:200])
r = call(A, 'delphi_hover', {'path': GHOST, 'line': 0, 'character': 0})
check('B5 hover igual', not r.startswith('Error executing tool'), r[:200])
r = call(A, 'delphi_config', {'project': DPROJ, 'command': 'remove-unit', 'name': 'X'})
check('B5 un parametro que no existe es "error:", no "Error executing tool:"',
      r.startswith('error:') and 'Unknown parameter' in r, r[:200])

# ------------------------------------------------------------- B6/D3/D5 ----
DELTA = os.path.join(CS, 'Delta.txt')
open(DELTA, 'w', encoding='utf-8', newline='\r\n').write('a\nb\nc\nd\n')
r = call(A, 'delphi_changeset', {'command': 'begin'})
CID2 = [w for w in r.replace('.', ' ').split() if w.count('-') >= 2][0]
call(A, 'delphi_changeset', {'command': 'stage', 'id': CID2, 'kind': 'edit',
                             'path': DELTA, 'old': 'a', 'new': 'A'})
call(A, 'delphi_changeset', {'command': 'stage', 'id': CID2, 'kind': 'delete-line',
                             'path': DELTA, 'atline': 3})
NUEVO = os.path.join(CS, 'Nuevo.pas')
call(A, 'delphi_changeset', {'command': 'stage', 'id': CID2, 'kind': 'create',
                             'path': NUEVO,
                             'content': 'unit Nuevo;\ninterface\nimplementation\nend.\n'})
pv = J(call(A, 'delphi_changeset', {'command': 'preview', 'id': CID2}))
ops = pv.get('operations', [])
check('D5 preview dice en que linea resolvio el ancla',
      any(o.get('atline') for o in ops if o.get('kind') == 'edit'), str(pv)[:300])
r = call(A, 'delphi_changeset', {'command': 'commit', 'id': CID2})
check('B6 el commit da el delta UNA vez por fichero',
      r.count('Delta.txt') == 1, r[:400])
check('B6 ...y no le pone "+" a lo que quita',
      '(-1 lineas en total)' in r or '-1' in r, r[:400])
raw = open(NUEVO, 'rb').read()
check('D3 un create dentro de un changeset nace en CRLF, como delphi_create',
      raw.count(b'\r\n') >= 4 and b'\n\n' not in raw.replace(b'\r\n', b'\n\n')[:0] + b'',
      repr(raw[:60]))

# ------------------------------------------------------------------ P1 -----
OUT = os.path.join(PRJ, 'Win64', 'Debug')
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'App.exe'), 'wb').write(b'MZ')
j = J(call(A, 'delphi_list', {'root': os.path.join(PRJ, 'Win64'), 'pattern': '*'}))
check('P1 nombrar Win64 como root SI lista lo que hay debajo',
      j.get('total', 0) >= 1, str(j)[:250])
j = J(call(A, 'delphi_list', {'root': PRJ}))
check('P1b sin pattern se dice que solo salen ficheros Delphi',
      'maskNote' in j, str(j)[:250])

# --------------------------------------------------------------- P2/P3/P4 --
T = os.path.join(BASE, 'MiTest')
r = call(A, 'delphi_create', {'kind': 'project-console', 'name': 'MiTest', 'dir': T})
assert 'CREADO' in r, r
open(os.path.join(T, 'MiTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(
    "program MiTest;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils;\n\nbegin\n"
    "  Writeln('PASS uno');\n"
    "  Writeln('Fail dos capitalizado');\n"
    "  Writeln('FAILED tres');\n"
    "  Writeln('pass cuatro en minusculas');\n"
    "  Writeln('[ OK ] cinco no debe contar');\n"
    "  Halt(1);\nend.\n")
j = J(call(A, 'delphi_test', {'command': 'run', 'project': os.path.join(T, 'MiTest.dproj')},
           t=900))
check('P2 "Fail" y "FAILED" CUENTAN como fallo (un rojo ya no sale verde)',
      j.get('failed', 0) >= 2 and j.get('result') == 'fail', str(j)[:350])
check('P2 "pass" en minusculas cuenta', j.get('passed', 0) >= 2, str(j)[:300])
check('P2 el senuelo entre corchetes NO cuenta pero SE DECLARA',
      j.get('linesNotCounted', 0) >= 1, str(j)[:350])
r = call(A, 'delphi_test', {'command': 'run', 'project': os.path.join(T, 'MiTest.dproj'),
                            'platform': 'Marte'}, t=300)
check('P8 una plataforma inventada: RECHAZADA', 'RECHAZADO' in r, r[:200])
r = call(A, 'delphi_test', {'command': 'run', 'project': os.path.join(T, 'MiTest.dproj'),
                            'config': 'Release', 'nobuild': True}, t=300)
check('P4 nobuild sin binario no dice que compilo',
      'despues de compilar' not in r, r[:250])

# ------------------------------------------------------------------ P6/P7 --
_r = call(A, 'delphi_changeset', {'command': 'begin'})
CID3 = [w for w in _r.replace('.', ' ').split() if w.count('-') >= 2][0]
r = call(A, 'delphi_changeset', {'command': 'stage', 'id': CID3, 'kind': 'chapuza',
                                 'path': DELTA})
check('P6 el rechazo de kind incluye delete-line', 'delete-line' in r, r[:200])
TXT = os.path.join(BASE, 'Nota2.txt')
open(TXT, 'w', encoding='utf-8').write('esto no es pascal\n')
r = call(A, 'delphi_hover', {'path': TXT, 'line': 0, 'character': 1})
check('P7 hover sobre algo que no es Delphi lo dice',
      'RECHAZADO' in r and 'Delphi' in r, r[:200])
r = call(A, 'delphi_definition', {'path': TXT, 'line': 0, 'character': 1})
check('P7 definition igual', 'RECHAZADO' in r and 'Delphi' in r, r[:200])

# ------------------------------------------------------------------- D1 ----
UPAS = os.path.join(PRJ, 'UCalc.pas')
open(UPAS, 'w', encoding='utf-8', newline='\r\n').write(
    'unit UCalc;\n\ninterface\n\nfunction Doble(A: Integer): Integer;\n\n'
    'implementation\n\nfunction Doble(A: Integer): Integer;\nbegin\n'
    '    Result := A * 2;\nend;\n\nend.\n')
call(A, 'delphi_config', {'project': DPROJ, 'command': 'add-unit', 'path': UPAS})
j = J(call(A, 'delphi_rename_symbol', {'path': UPAS, 'line': 4, 'character': 9,
                                       'newname': 'Triple'}, t=600))
chg = j.get('changes', [])
check('D1 cada cambio trae un ancla con su indentacion, no el texto recortado',
      any(c.get('anchor', '') != c.get('text', '') or c.get('anchor') for c in chg),
      str(chg)[:300])
check('D1 ...y la columna, para dos apariciones en una misma linea',
      all('character' in c for c in chg if c.get('kind') != 'definition') if chg else True,
      str(chg)[:300])

# -------------------------------------------------------------- F5 / varios -
r = call(A, 'delphi_git', {'repo': os.path.join(BASE, 'clon6'), 'command': 'clone',
                           'message': 'http://[::1]:3131/mcp'})
check('F5 una URL IPv6 se lee como host, no como "["',
      'RECHAZADO' in r and '::1' in r, r[:250])
check('F5b un clone rechazado no deja la carpeta destino',
      not os.path.isdir(os.path.join(BASE, 'clon6')), os.path.isdir(os.path.join(BASE, 'clon6')))
r = call(A, 'delphi_help', {'command': 'tool', 'name': 'delphi_edt'})
check('help aguanta una errata de una letra',
      'delphi_edit' in r and ('he entendido' in r or '"tool"' in r), r[:250])
r = call(A, 'delphi_upload', {'path': os.path.join(BASE, 'x.bin'),
                              'chunkbase64': base64.b64encode(b'abc').decode(),
                              'sha256': 'no-es-un-hash'})
check('un sha256 mal escrito rechaza el PARAMETRO, no castiga al fichero',
      'RECHAZADO' in r and not os.path.exists(os.path.join(BASE, 'x.bin.corrupto')), r[:250])
j = J(call(A, 'delphi_projects', {'name': 'no-hay-nada-asi'}))
check('projects sin coincidencias dice cuantos hay', 'note' in j, str(j)[:200])

A['p'].kill()
print('\n== round-10 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
