"""E2E battery for v0.84.0-beta - hermes' P2.9: startup/repeat work.

Two internal costs removed, with the ONE risk each removal introduces pinned
by a check:

  - The low-integrity labeling of a run's workdir used to re-walk and relabel
    the whole tree on EVERY delphi_run. Now once per root per process - the
    SDDL label carries OICI inheritance, so children born after the first
    labeling arrive Low already. The risk: a MEDIUM file created BETWEEN runs
    by the server/agent (not by the confined program). If inheritance did not
    cover it, the second run would hit "local-blocked" where the first said
    LOCAL-OK. Measured here, not assumed.
  - The designer fact tables (~14k facts, 14 dictionaries) used to be built
    in initialization even when no designer tool was ever called. Now lazy on
    the first designer call. The risk: the first call after startup breaking.
    Covered by calling designer FIRST thing on a fresh server.

  Z1  fresh server: the FIRST call is delphi_designer -> lazy tables work
  Z2  run #1: sandboxed, writes its own folder (labels the tree, caches it)
  Z3  a NEW medium-integrity file created BETWEEN runs is still writable by
      run #2 (OICI inheritance covers post-label children - the cache is safe)

Usage:  python tests/test_round21.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round21')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

# a text .dfm for the lazy-designer check
open(os.path.join(BASE, 'Main.dfm'), 'w').write(
    "object Form1: TForm1\r\n  Left = 0\r\n  Top = 0\r\n"
    "  Caption = 'Hola'\r\n  ClientHeight = 300\r\n  ClientWidth = 400\r\n"
    "  object Boton1: TButton\r\n    Left = 10\r\n    Top = 10\r\n"
    "    Width = 75\r\n    Height = 25\r\n    Caption = 'Pulsa'\r\n  end\r\nend\r\n")

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_ALLOW_RUN'] = '1'
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


def recv(r, t=600):
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


def call(tool, args, t=600):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": tool, "arguments": args}})
    r = recv(rid[0], t)
    if not r:
        return '(sin respuesta)'
    return r.get('result', {}).get('content', [{}])[0].get('text', 'ERR')


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:240])


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round21", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

# Z1: the VERY FIRST tool call is a designer one - lazy tables must build now
r = call('delphi_designer', {'command': 'tree', 'path': os.path.join(BASE, 'Main.dfm')})
check('Z1 primera llamada del proceso = designer: tablas lazy funcionan',
      'TButton' in r and 'Boton1' in r, r[:200])
r = call('delphi_designer', {'command': 'lint', 'path': os.path.join(BASE, 'Main.dfm')})
check('Z1b lint del designer tambien (segunda entrada a las tablas)',
      'ERR' not in r[:4] and '(sin' not in r, r[:160])

# Z2/Z3: the label cache vs a medium file created BETWEEN runs
_q = chr(39)
call('delphi_create', {"kind": "project-console", "dir": os.path.join(BASE, 'Sbx'), "name": "Sbx"})
_body = ['program Sbx;', '{$APPTYPE CONSOLE}', 'uses System.SysUtils, System.IOUtils;', 'begin',
         '  try TFile.WriteAllText(' + _q + 'entre.txt' + _q + ', ' + _q + 'y' + _q + '); Writeln('
         + _q + 'LOCAL-OK' + _q + '); except Writeln(' + _q + 'local-blocked' + _q + '); end;', 'end.']
open(os.path.join(BASE, 'Sbx', 'Sbx.dpr'), 'w', encoding='utf-8-sig', newline='').write('\r\n'.join(_body) + '\r\n')
out = call('delphi_build', {"project": os.path.join(BASE, 'Sbx', 'Sbx.dproj'),
                            "platform": "Win64", "config": "Debug", "target": "Build"})
try:
    sbok = json.loads(out)['success']
except Exception:
    sbok = False
check('Z2 proyecto de prueba compila', sbok, out[:150])
if sbok:
    rundir = os.path.join(BASE, 'Sbx', 'Win64', 'Debug')
    exe = os.path.join(rundir, 'Sbx.exe')
    out = call('delphi_run', {"path": exe, "timeoutms": 10000}, 60)
    check('Z2 run #1 sandboxed escribe en su carpeta',
          'LOCAL-OK' in out and 'sandbox=low-integrity' in out, out[:200])
    # BETWEEN runs: this test process (MEDIUM integrity) creates the file the
    # program will overwrite. With the label cache, run #2 does NOT relabel -
    # only OICI inheritance can make this writable. Measure it.
    open(os.path.join(rundir, 'entre.txt'), 'w').write('medium-file-created-between-runs')
    out = call('delphi_run', {"path": exe, "timeoutms": 10000}, 60)
    check('Z3 fichero MEDIUM creado ENTRE runs: run #2 lo sobrescribe '
          '(la herencia OICI cubre a los hijos nuevos; el cache es seguro)',
          'LOCAL-OK' in out and 'sandbox=low-integrity' in out, out[:220])

proc.kill()
print('\n== round-21 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
