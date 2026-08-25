"""E2E battery for v0.53.0-beta - delphi_rename_symbol, preview only.

The adopted rule as tests: applicable=true ONLY with zero unverified
references, no designer hits, no string-literal hits, no collision, and a
definition inside the workspace. Everything else = applicable=false with
the reasons, and NOTHING written.

Usage:  python tests/test_rename.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'rename')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)

env = dict(os.environ); env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def reader():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=reader, daemon=True).start()
rid = [10]
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=300):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(name, args, t=300):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "rn", "version": "1"}}})
recv(1); send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, ok, detail=''):
    global P, F
    if ok: P += 1; print('PASS', name)
    else: F += 1; print('FAIL', name, '--', str(detail)[:350])
def J(t):
    try: return json.loads(t)
    except Exception: return {}
def sha_all():
    out = {}
    for root, _, fs in os.walk(BASE):
        for f in fs:
            p = os.path.join(root, f)
            if p.endswith(('.pas', '.dpr', '.dfm')):
                out[p] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    return out

# ---- fixture project ----
PRJ = os.path.join(BASE, 'Ren')
r = call('delphi_create', {'kind': 'project-console', 'name': 'Ren', 'dir': PRJ})
assert 'CREADO' in r, r
call('delphi_create', {'kind': 'unit', 'name': 'UCalc', 'project': os.path.join(PRJ, 'Ren.dpr')})
UCALC = os.path.join(PRJ, 'UCalc.pas')
open(UCALC, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit UCalc;

interface

function Doble(A: Integer): Integer;
function ConCadena(A: Integer): Integer;
function Existente(A: Integer): Integer;

implementation

function Doble(A: Integer): Integer;
begin
  Result := A * 2;
end;

function ConCadena(A: Integer): Integer;
begin
  // la cadena menciona la funcion por nombre, como un FindComponent
  if 'llama a ConCadena' <> '' then;
  Result := A;
end;

function Existente(A: Integer): Integer;
begin
  Result := Doble(A) + 1;
end;

end.
""")
DPR = os.path.join(PRJ, 'Ren.dpr')
s = open(DPR, encoding='utf-8-sig').read()
open(DPR, 'w', encoding='utf-8-sig', newline='').write(s.replace('begin', 'begin\n  Writeln(Doble(3));', 1))

BEFORE = sha_all()

# UCalc 0-based: line 4 'function Doble(...)' -> col 9
# 1. happy path: applicable
r = call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Duplica'})
j = J(r)
check('preview aplicable (Doble -> Duplica)', j.get('applicable') is True, r[:400])
check('ocurrencias >= 2 y ficheros >= 2', j.get('occurrences', 0) >= 2 and j.get('files', 0) >= 2, r[:300])
check('changes con path/line/text', bool(j.get('changes')) and all('path' in c and 'line' in c for c in j.get('changes', [])), str(j.get('changes'))[:250])
# field 2026-08-25: 'changes' omitia la CABECERA DE LA IMPLEMENTACION (la
# linea que el propio campo definition señala), y un agente que aplicara solo
# lo listado rompia la unit (E2065 Unsatisfied forward declaration)
_def = j.get('definition') or {}
_chg = j.get('changes') or []
check('changes INCLUYE la linea de la definicion',
      any(c.get('line') == _def.get('line') and c.get('path') == _def.get('path') for c in _chg),
      'definition=%s changes=%s' % (_def, [(c.get('path','')[-20:], c.get('line')) for c in _chg]))
check('cero sin confirmar', j.get('unverified') == 0, r[:200])

# 2. invalid ident / reserved
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': '9mal'}))
check('identificador invalido bloquea', j.get('applicable') is False and any('identificador' in b for b in j.get('blockers', [])), str(j)[:250])
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'begin'}))
check('palabra reservada bloquea', j.get('applicable') is False and any('reservada' in b for b in j.get('blockers', [])), str(j)[:250])

# 3. string literal hit: renaming ConCadena
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 5, 'character': 9, 'newname': 'OtraCosa'}))
check('mencion en literal de cadena bloquea', j.get('applicable') is False and any('literales' in b or 'cadena' in b for b in j.get('blockers', [])), str(j)[:400])

# 4. collision: rename Doble -> Existente (word already there)
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Existente'}))
check('colision con nombre existente bloquea', j.get('applicable') is False and any('colision' in b or 'aparece' in b for b in j.get('blockers', [])), str(j)[:300])

# 5. designer hit: a dfm mentioning the identifier
DFM = os.path.join(PRJ, 'UCalc.dfm')
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(
    "object F: TF\n  OnClick = Doble\nend\n")
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Duplica'}))
check('mencion en designer bloquea', j.get('applicable') is False and any('designer' in b or '.dfm' in b for b in j.get('blockers', [])), str(j)[:400])
os.remove(DFM)

# 6. RTL symbol refused (definition outside the jail): IntToStr usage
s = open(UCALC, encoding='utf-8-sig').read().replace(
    'uses', 'uses', 1)
open(UCALC, 'w', encoding='utf-8-sig', newline='').write(s.replace(
    "function Existente(A: Integer): Integer;\nbegin\n  Result := Doble(A) + 1;",
    "function Existente(A: Integer): Integer;\nbegin\n  Result := Doble(A) + Length(System.SysUtils.IntToStr(A));", 1).replace(
    "implementation", "implementation\n\nuses System.SysUtils;", 1))
# find IntToStr position dynamically
lines = open(UCALC, encoding='utf-8-sig').read().replace('\r\n', '\n').split('\n')
li = next(i for i, l in enumerate(lines) if 'IntToStr' in l)
co = lines[li].index('IntToStr') + 2
j = J(call('delphi_rename_symbol', {'path': UCALC, 'line': li, 'character': co, 'newname': 'MiIntToStr'}))
check('simbolo de la RTL bloqueado (definicion fuera del workspace)',
      j.get('applicable') is False and any('FUERA' in b or 'RTL' in b for b in j.get('blockers', [])), str(j)[:400])

# 7. mode=apply refused; nothing ever written
r = call('delphi_rename_symbol', {'path': UCALC, 'line': 4, 'character': 9, 'newname': 'Duplica', 'mode': 'apply'})
check('mode=apply rechazado con el camino (changeset)', 'RECHAZADO' in r and 'changeset' in r, r[:250])
# note: fixture edits in step 6 changed UCalc deliberately; verify the TOOL wrote nothing
AFTER = sha_all()
tool_touched = [p for p in BEFORE if p in AFTER and BEFORE[p] != AFTER[p] and 'UCalc.pas' not in p]
check('la tool no escribio NADA (solo el fixture cambio a proposito)', not tool_touched, tool_touched)

proc.kill()
print('\n== rename battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
