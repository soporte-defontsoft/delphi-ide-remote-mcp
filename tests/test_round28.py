# -*- coding: utf-8 -*-
"""Round 28 - insert:"metodo" ante un metodo que YA existe (hermes, campo
2026-09-17): la tool escribia las dos mitades a ciegas y una clase con la
declaracion ya preparada acababa con declaracion duplicada o rota (E2254/
E2067). Desde v0.94 mira cada mitad: solo escribe la que falta, y un metodo
entero se rechaza con las dos lineas y el camino (old/new).

Usage:  python tests/test_round28.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
DIR = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round28')
shutil.rmtree(DIR, ignore_errors=True)
os.makedirs(DIR)

P = F = 0

def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:260])

CRLF = '\r\n'
BASE = CRLF.join([
    'unit Round28;', '',
    'interface', '',
    'type',
    '  TCosa = class',
    '  private',
    '    FValor: Integer;',
    '  public',
    '    procedure Existente;',
    '    procedure Preparada(Sender: TObject);',
    '  end;', '',
    'implementation', '',
    'procedure TCosa.Existente;',
    'begin',
    '  FValor := 1;',
    'end;', '',
    'end.', ''])

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = DIR
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()

def rdr():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)

threading.Thread(target=rdr, daemon=True).start()
rid = [10]

def send(o):
    proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()

def recv(r, t=60):
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

def call(name, args, t=60):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                 "clientInfo": {"name": "r28", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

def fresh(name, content=BASE):
    pas = os.path.join(DIR, name)
    open(pas, 'w', encoding='utf-8', newline='').write(content)
    return pas

def edit(pas, firma, cuerpo, vis='public'):
    return call('delphi_edit', {"path": pas, "insert": "metodo",
                                "inclass": "TCosa", "visibility": vis,
                                "code": firma + CRLF + 'begin' + CRLF + cuerpo + CRLF + 'end;'})

# ---- 1. metodo NUEVO: las dos mitades, como siempre ----
pas = fresh('Caso1.pas')
out = edit(pas, 'procedure Nueva;', '  FValor := 2;')
check('nuevo: las DOS mitades', 'DOS mitades' in out, out[:200])
t = open(pas, encoding='utf-8').read()
check('nuevo: 1 declaracion + 1 implementacion',
      t.count('procedure Nueva;') == 1 and t.count('procedure TCosa.Nueva;') == 1, t[:400])

# ---- 2. declaracion YA preparada (el caso de hermes) ----
pas = fresh('Caso2.pas')
out = edit(pas, 'procedure Preparada(Sender: TObject);', '  FValor := 3;')
check('preparada: lo dice claro',
      'YA declaraba' in out and 'Solo se ha escrito la implementacion' in out, out[:300])
t = open(pas, encoding='utf-8').read()
check('preparada: UNA sola declaracion (no duplica)',
      t.count('procedure Preparada(Sender: TObject);') == 1, t.count('procedure Preparada(Sender: TObject);'))
check('preparada: la implementacion SI se escribio',
      t.count('procedure TCosa.Preparada(Sender: TObject);') == 1, t[:600])

# ---- 3. metodo ENTERO: rechazo con las dos lineas y el camino ----
pas = fresh('Caso3.pas')
out = edit(pas, 'procedure Existente;', '  FValor := 4;')
check('entero: RECHAZADO', out.startswith('RECHAZADO') and 'ya existe ENTERO' in out, out[:250])
check('entero: da las dos lineas y el camino old/new',
      'declaracion en linea' in out and 'old/new' in out, out[:300])
t = open(pas, encoding='utf-8', newline='').read()
check('entero: el fichero NO cambio', t == BASE, len(t))

# ---- 4. implementacion huerfana: fichero incoherente, rechazo honesto ----
HUERFANA = BASE.replace('end.' + CRLF, CRLF.join([
    'procedure TCosa.Huerfana;', 'begin', 'end;', '', 'end.', '']))
pas = fresh('Caso4.pas', HUERFANA)
out = edit(pas, 'procedure Huerfana;', '  FValor := 5;')
check('huerfana: RECHAZADO incoherente',
      out.startswith('RECHAZADO') and 'no la declara' in out, out[:250])

proc.stdin.close()
proc.wait(timeout=10)
print('\n== round28 (insert metodo idempotente): %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
