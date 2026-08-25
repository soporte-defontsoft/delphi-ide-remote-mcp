"""E2E battery for v0.74.0-beta - round 10 sweep (agent sweep10).

The data-loss trap sweep10 found: deleting a FOLDER whose content is locked (a
running .exe, a git process, the IDE) reported "A MEDIAS - the recoverable copy
IS made, the original could not be removed" - but the content had ALREADY been
moved into that copy and the original gutted, and every retry made another full
copy. A human reading "half done, retry" who purged those "leftover" copies
deleted real code.

Root cause: TDirectory.Move falls back to a recursive copy+delete of its own
accord when the atomic rename fails. The fix uses the raw Windows MoveFile,
which never copies: same-volume it renames atomically, and on a locked tree it
fails with everything untouched. Move or nothing.

  D1  a locked folder is NOT deleted and NOTHING is touched - no partial copy in
      the trash, the original intact, and a retry does not duplicate
  D2  the same folder, once unlocked, deletes cleanly

Usage:  python tests/test_round14.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob, msvcrt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round14')
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


def recv(r, t=30):
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


def call(tool, args):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": tool, "arguments": args}})
    r = recv(rid[0])
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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:280])


def copies():
    return [c for c in glob.glob(os.path.join(BASE, '**', '__delphi-patch', '**', 'proj-*'),
                                 recursive=True) if not c.endswith('.by')]


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "round14", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
time.sleep(0.3)

sub = os.path.join(BASE, 'proj')
os.makedirs(sub)
open(os.path.join(sub, 'a.txt'), 'w').write('a' * 100)
lh = open(os.path.join(sub, 'locked.exe'), 'w')          # keep the handle open
lh.write('x' * 50)
lh.flush()

# D1 - locked folder: nothing touched, nothing copied, retry does not duplicate
r1 = call('delphi_delete', {'path': sub})
r2 = call('delphi_delete', {'path': sub})
intact = (os.path.exists(os.path.join(sub, 'a.txt')) and
          os.path.exists(os.path.join(sub, 'locked.exe')) and
          open(os.path.join(sub, 'a.txt')).read() == 'a' * 100)
check('D1 carpeta bloqueada: no la borra y NO toca nada',
      'NO he tocado NADA' in r1 and intact, r1)
check('D1 no deja copia a medias en la papelera (ni al reintentar)',
      len(copies()) == 0, copies())
check('D1 el reintento tampoco duplica ni gutea', 'NO he tocado NADA' in r2 and intact, r2)

# D2 - once unlocked, it deletes cleanly
lh.close()
r3 = call('delphi_delete', {'path': sub})
check('D2 sin lock, borra limpio', 'BORRADO' in r3 and not os.path.exists(sub), r3)
check('D2 y AHORA si hay una copia recuperable', len(copies()) == 1, copies())

proc.kill()
print('\n== round-14 battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
