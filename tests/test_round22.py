# -*- coding: utf-8 -*-
"""E2E battery for v0.86.0-beta - the Linux64 outputTail over-masking.

sweep10 reported Linux64 build tails collapsed into "srvhost" everywhere;
reproduced 2026-08-26 with a real Linux64 link: 227 masks in one tail. Root
cause: the Linux64 linker echoes its command line with backslashes ALREADY
doubled; the JSON encoding doubles them again, and the masker's JSON-UNC rule
(four backslashes + letter) fired on EVERY re-doubled separator because its
look-behind only required "not a backslash". A genuine UNC never starts glued
to a letter - the rule now requires a delimiter before it, same as the raw
form.

  M1  linker-style re-doubled paths survive legibly (no srvhost cascade)
  M2  a genuine UNC host is still masked (after quote, raw and JSON forms)
  M3  drive letters still masked in the same text
  M4  (live, only if this machine holds the Linux64 SDK) a real Linux64 link:
      outputTail carries ZERO srvhost and a legible "Linker command line"

Usage:  python tests/test_round22.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round22')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
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


def recv(r, t=300):
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


def call(tool, args, t=300):
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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round22", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

# The masker runs on every textual result, so delphi_read of a crafted file
# exercises it machine-independently. The file reproduces the linker-echo
# shape: paths with backslashes ALREADY doubled in the raw text.
BS = chr(92)
D2 = BS + BS          # doubled separator, as the linker echoes it
lines = [
    'Linker command line: -o .' + D2 + 'Linux64' + D2 + 'Debug' + D2 + 'App'
    + ' --sysroot C:' + D2 + 'Users' + D2 + 'yo' + D2 + 'Documents' + D2 + 'SDKs'
    + ' -L "C:' + D2 + 'Program Files (x86)' + D2 + 'Embarcadero' + D2 + 'lib"',
    'copia real en "' + BS + BS + 'nas01' + BS + 'backups' + BS + 'x.dcu"',
]
probe = os.path.join(BASE, 'echo.txt')
open(probe, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')

# delphi_read is EXEMPT from masking (file text travels verbatim), so the
# machine-independent probe goes through delphi_search, whose hit lines ARE
# masked like any other tool output.
r = call('delphi_search', {'root': probe, 'query': 'sysroot'})
check('M1 rutas re-dobladas del linker legibles (cero cascada srvhost)',
      r.count('srvhost') == 0 and 'Linux64' in r and 'Users' in r and
      'Embarcadero' in r, 'srvhost x%d | %s' % (r.count('srvhost'), r[:220]))
r2 = call('delphi_search', {'root': probe, 'query': 'copia real'})
check('M2 el UNC de verdad SI se enmascara (nas01 desaparece)',
      'nas01' not in r2 and 'srvhost' in r2, r2[:220])
check('M3 las unidades siguen enmascaradas (srvc:)',
      'srvc:' in r and 'C:' + D2 not in r, r[:220])

# M4 live: a real Linux64 link on machines that hold the SDK
r = call('delphi_create', {'kind': 'project-console', 'name': 'TailM', 'dir': BASE})
dpr = glob.glob(os.path.join(BASE, '**', 'TailM.dpr'), recursive=True)
if dpr:
    dproj = dpr[0][:-4] + '.dproj'
    call('delphi_config', {'project': dproj, 'command': 'add-platform',
                           'platform': 'Linux64'})
    out = call('delphi_build', {'project': dproj, 'platform': 'Linux64',
                                'config': 'Debug'}, 600)
    try:
        j = json.loads(out)
    except Exception:
        j = {}
    if j.get('success') is True:
        tail = j.get('outputTail') or ''
        check('M4 link Linux64 real: outputTail sin srvhost y linker legible',
              'srvhost' not in tail and 'Linker command line' in tail
              and 'sysroot' in tail, 'srvhost x%d' % tail.count('srvhost'))
    else:
        print('SKIP M4: esta maquina no linka Linux64 (sin SDK); M1-M3 cubren el masker')

proc.kill()
print('\n== round-22 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
