# -*- coding: utf-8 -*-
"""E2E battery: what SEVERAL agents at once do to this server.

Born from the code analysis of 2026-09-20. The HTTP host serves every request
on its own Indy worker thread, so two agents with tokens - or one agent firing
parallel tool calls - run tools CONCURRENTLY. Some paths are serialized on
purpose (msbuild, the knowledge vault, delphi_edit); several are not. This
battery MEASURES which of those actually break, instead of theorizing about
them: every probe below names the finding it is aiming at.

  A  N writers on the SAME text file    -> the temp file of the atomic write
                                           carries a FIXED name (Lsp.Patch:323)
  B  N writers on N different files     -> control: this one must be green
  C  N delphi_create into the SAME .dpr -> lost update on the project file
  D  N delphi_report at once            -> the "look for a free name" TOCTOU
  E  a broadcast message, two readers   -> is "para todos" really for everyone
  F  two delphi_package of one folder   -> deterministic zip name, no lock
  G  two delphi_desktop screenshots     -> capture files named by the SECOND
  H  a build while its exe is running   -> the build lock ends with msbuild

A probe whose environment is missing (no RAD Studio for H, no desktop node for
G) prints SKIP and counts as neither pass nor fail: a test that quietly skips
is a hole, one that fails for the environment is noise.

NOT covered here, on purpose - each needs a PAServer target or the paclient
stub with real profiles, and that is its own battery: the node deploy race in
EnsureNodeCurrent, the machine-wide SDK folder of delphi_paserver get-sdk, and
remote captures through delphi_adb_linux.

Usage:  python tests/test_concurrencia.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import glob
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE_SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

TOKEN = 'conc-token'
N = 12                      # writers firing at once

WORK = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'concurrencia')
shutil.rmtree(WORK, ignore_errors=True)
os.makedirs(WORK)

# The server reads its settings.ini next to the executable, so the battery runs
# its OWN copy in its own folder - never the build output in place.
EXE = os.path.join(WORK, 'DelphiLspMcp.exe')
shutil.copy(EXE_SRC, EXE)
# The desktop node travels beside the server (node\McpDesktopNode.exe); probe G
# needs it and skips itself when it is not there.
NODE_SRC = os.path.join(REPO, 'node', 'McpDesktopNode.exe')
NODE_DST = os.path.join(WORK, 'node', 'McpDesktopNode.exe')
if os.path.exists(NODE_SRC):
    os.makedirs(os.path.dirname(NODE_DST), exist_ok=True)
    shutil.copy(NODE_SRC, NODE_DST)

JAIL = os.path.join(WORK, 'jaula')
os.makedirs(JAIL)
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\n'
            'Token=%s\n'
            'Roots=%s\n'
            'AllowRun=1\n'
            'AllowDesktopControl=1\n' % (TOKEN, JAIL))

sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
URL = 'http://127.0.0.1:%d/mcp' % PORT

env = dict(os.environ)
# Loopback only: binding every interface makes Windows Firewall ask once per
# executable PATH, and this battery runs from a fresh temp folder every time.
env['DELPHI_MCP_BIND_IP'] = '127.0.0.1'
proc = subprocess.Popen([EXE, '--http', str(PORT)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

P = FCOUNT = SKIPPED = 0


def check(name, cond, detail=''):
    global P, FCOUNT
    if cond:
        P += 1
        print('PASS -', name)
    else:
        FCOUNT += 1
        print('FAIL -', name, '|', str(detail)[:300])


def skip(name, why):
    global SKIPPED
    SKIPPED += 1
    print('SKIP -', name, '|', str(why)[:200])


_rid = [100]
_ridlock = threading.Lock()


def next_id():
    with _ridlock:
        _rid[0] += 1
        return _rid[0]


def rpc(body, sid=None, timeout=180):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOKEN}
    if sid:
        h['Mcp-Session-Id'] = sid
    req = urllib.request.Request(URL, data=json.dumps(body).encode('utf-8'),
                                 headers=h, method='POST')
    try:
        r = urllib.request.urlopen(req, timeout=timeout)
        raw = r.read().decode('utf-8', 'replace')
        newsid = r.headers.get('Mcp-Session-Id')
    except urllib.error.HTTPError as e:
        return [{'error': {'message': 'HTTP%d %s' % (
            e.code, e.read().decode('utf-8', 'replace')[:200])}}], None
    except Exception as e:                       # noqa: BLE001 - reported, not raised
        return [{'error': {'message': repr(e)}}], None
    msgs = []
    for line in raw.splitlines():
        if line.startswith('data:'):
            try:
                msgs.append(json.loads(line[5:].strip()))
            except Exception:
                pass
    if not msgs:
        try:
            msgs = [json.loads(raw)]
        except Exception:
            msgs = [{'error': {'message': raw[:200]}}]
    return msgs, newsid


def session(name):
    _, sid = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}})
    rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return sid


def call(tool, args, sid=None, timeout=180):
    rid = next_id()
    msgs, _ = rpc({"jsonrpc": "2.0", "id": rid, "method": "tools/call",
                   "params": {"name": tool, "arguments": args}}, sid, timeout)
    for m in msgs:
        if m.get('id') == rid and 'result' in m:
            c = m['result'].get('content', [])
            return c[0].get('text', '') if c else '(sin contenido)'
    for m in msgs:
        if 'error' in m:
            return 'MCPERROR ' + json.dumps(m['error'])[:200]
    return '(sin respuesta)'


def burst(worker, n=N):
    """Fire n workers at the very same instant and collect what each got."""
    out = [None] * n
    barrier = threading.Barrier(n)

    def run(i):
        barrier.wait()          # release all at once -> maximum overlap
        try:
            out[i] = worker(i)
        except Exception as e:  # noqa: BLE001 - a worker must never kill the run
            out[i] = 'EXCEPCION ' + repr(e)

    ts = [threading.Thread(target=run, args=(i,)) for i in range(n)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    return out


def unmask(p):
    """Server paths come out as virtual units (C:\\x -> srvc:\\x) in every tool
    answer. To CHECK a file on this same machine the battery undoes that."""
    m = re.match(r'(?i)^srv([a-z]):', p or '')
    return m.group(1).upper() + ':' + p[5:] if m else p


def bad(text):
    """A tool answer that is NOT a success."""
    t = (text or '').upper()
    return ('RECHAZAD' in t or t.startswith('ERROR') or 'MCPERROR' in t or
            'EXCEPCION' in t or 'FALLID' in t or '(SIN RESPUESTA)' in t)


def wait_ready(seconds=20):
    deadline = time.time() + seconds
    while time.time() < deadline:
        msgs, _ = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                       "params": {"protocolVersion": "2025-06-18",
                                  "capabilities": {},
                                  "clientInfo": {"name": "conc", "version": "1"}}},
                      timeout=5)
        for m in msgs:
            if 'result' in m:
                return True
        time.sleep(0.5)
    return False


try:
    if not wait_ready():
        print('FAIL - el servidor no responde en el puerto %d' % PORT)
        proc.kill()
        sys.exit(1)

    # ---------------------------------------------------------------- A ----
    # N writers on the SAME file. Each one owns its line, so a correct server
    # ends with the N of them done: nobody is overwriting anybody's text, only
    # racing on the write itself.
    A = os.path.join(JAIL, 'a.txt')
    with open(A, 'w', encoding='utf-8', newline='\r\n') as f:
        f.write('\r\n'.join('SLOT-%02d pendiente' % i for i in range(N)) + '\r\n')

    ra = burst(lambda i: call('delphi_textedit', {
        "path": A, "old": 'SLOT-%02d pendiente' % i,
        "new": 'SLOT-%02d HECHO' % i}))
    ok_a = sum(1 for r in ra if not bad(r))
    disk_a = open(A, encoding='utf-8').read()
    done_a = sum(1 for i in range(N) if ('SLOT-%02d HECHO' % i) in disk_a)
    lost = [i for i in range(N) if ('SLOT-%02d HECHO' % i) not in disk_a]
    renames = sum(1 for r in ra if r and 'rename atomico' in r)
    tmp_left = glob.glob(os.path.join(JAIL, '.*delphi-patch-tmp'))

    check('A mismo fichero: los %d escritores reportan exito' % N, ok_a == N,
          '%d/%d; muestras: %s' % (ok_a, N, [r[:80] for r in ra if bad(r)][:3]))
    check('A mismo fichero: ningun "rename atomico fallido"', renames == 0,
          '%d renames fallidos' % renames)
    check('A mismo fichero: las %d ediciones estan EN DISCO' % N, done_a == N,
          '%d/%d; perdidas: %s' % (done_a, N, lost))
    check('A mismo fichero: exitos reportados == ediciones en disco',
          ok_a == done_a, 'reportados=%d disco=%d' % (ok_a, done_a))
    check('A mismo fichero: no queda temporal compartido', not tmp_left,
          tmp_left)

    # ---------------------------------------------------------------- B ----
    # Control: same burst, one file each. The temp name carries the file name,
    # so this one has nothing to collide on and must be green.
    for i in range(N):
        with open(os.path.join(JAIL, 'b%02d.txt' % i), 'w',
                  encoding='utf-8', newline='\r\n') as f:
            f.write('SLOT pendiente\r\n')
    rb = burst(lambda i: call('delphi_textedit', {
        "path": os.path.join(JAIL, 'b%02d.txt' % i),
        "old": 'SLOT pendiente', "new": 'SLOT HECHO-%02d' % i}))
    ok_b = sum(1 for r in rb if not bad(r))
    done_b = sum(1 for i in range(N)
                 if 'HECHO-%02d' % i in
                 open(os.path.join(JAIL, 'b%02d.txt' % i), encoding='utf-8').read())
    check('B ficheros distintos: los %d exitos estan en disco (control)' % N,
          ok_b == N and done_b == N,
          'exitos=%d disco=%d' % (ok_b, done_b))

    # ---------------------------------------------------------------- C ----
    # N units into the SAME project: the .dpr is read, modified and written
    # back by each call, with no lock between them.
    PRJDIR = os.path.join(JAIL, 'proj')
    rc0 = call('delphi_create', {"kind": "project-console", "dir": PRJDIR,
                                 "name": "Conc"})
    dprs = glob.glob(os.path.join(PRJDIR, '**', '*.dpr'), recursive=True)
    if not dprs:
        skip('C mismo .dpr', 'no pude crear el proyecto: ' + str(rc0)[:150])
    else:
        DPR = dprs[0]
        NU = 8
        rcu = burst(lambda i: call('delphi_create', {
            "kind": "unit", "name": "UConc%02d" % i, "project": DPR}), NU)
        ok_c = sum(1 for r in rcu if not bad(r))
        dpr_text = open(DPR, encoding='utf-8', errors='replace').read()
        in_dpr = sum(1 for i in range(NU) if 'UConc%02d' % i in dpr_text)
        on_disk = sum(1 for i in range(NU)
                      if os.path.exists(os.path.join(os.path.dirname(DPR),
                                                     'UConc%02d.pas' % i)))
        check('C mismo .dpr: las %d unidades se crean en disco' % NU,
              on_disk == NU, '%d/%d .pas' % (on_disk, NU))
        check('C mismo .dpr: las %d unidades quedan registradas en el .dpr' % NU,
              in_dpr == NU, '%d/%d en uses; faltan %s' % (
                  in_dpr, NU,
                  [i for i in range(NU) if 'UConc%02d' % i not in dpr_text]))
        check('C mismo .dpr: exitos reportados == registradas (sin falso exito)',
              ok_c == in_dpr, 'reportados=%d en .dpr=%d' % (ok_c, in_dpr))

    # ---------------------------------------------------------------- D ----
    # N reports of the same kind and title in the same second: the server picks
    # the file name with "does it exist? then the next one", which two threads
    # can answer at the same time.
    NR = 8
    rd = burst(lambda i: call('delphi_report', {
        "kind": "question", "title": "concurrencia",
        "message": "informe %02d de la rafaga" % i}), NR)
    ok_d = sum(1 for r in rd if not bad(r))
    files_d = glob.glob(os.path.join(WORK, 'reports', '*.md'))
    check('D informes: los %d se escriben sin pisarse' % NR,
          ok_d == NR and len(files_d) == NR,
          'exitos=%d ficheros=%d' % (ok_d, len(files_d)))

    # ---------------------------------------------------------------- E ----
    # A message dropped in the mailbox ROOT is addressed to everybody. Two
    # agents ask for their mail; both should see it.
    MSGS = os.path.join(WORK, 'messages')
    os.makedirs(MSGS, exist_ok=True)
    with open(os.path.join(MSGS, '20260920-0900-aviso.md'), 'w',
              encoding='utf-8') as f:
        f.write('AVISO-BROADCAST: parad todos y leed esto\n')
    alice, bob = session('alice'), session('bob')
    ea = call('delphi_messages', {"command": "read"}, alice)
    eb = call('delphi_messages', {"command": "read"}, bob)
    check('E buzon: el primer agente recibe el aviso para todos',
          'AVISO-BROADCAST' in ea, ea[:150])
    check('E buzon: el SEGUNDO agente tambien lo recibe',
          'AVISO-BROADCAST' in eb, eb[:150])

    # ---------------------------------------------------------------- F ----
    # Two packages of the same folder at once: the zip name is derived from the
    # folder, the old one is deleted first, and nothing serializes the two.
    PACK = os.path.join(JAIL, 'pack')
    os.makedirs(PACK, exist_ok=True)
    for i in range(3):
        with open(os.path.join(PACK, 'f%d.bin' % i), 'wb') as f:
            f.write(os.urandom(200000))
    rf = burst(lambda i: call('delphi_package', {"dir": PACK}), 2)
    ok_f = sum(1 for r in rf if not bad(r))
    ZIP = os.path.join(JAIL, 'pack-deploy.zip')
    zip_ok, zip_why = False, 'no existe ' + ZIP
    if os.path.exists(ZIP):
        try:
            with zipfile.ZipFile(ZIP) as z:
                zip_ok = z.testzip() is None and len(z.namelist()) == 3
                zip_why = '%d entradas' % len(z.namelist())
        except Exception as e:                   # noqa: BLE001
            zip_why = repr(e)
    check('F package x2: las dos llamadas terminan bien', ok_f == 2,
          [r[:120] for r in rf])
    check('F package x2: el zip resultante es valido y completo', zip_ok, zip_why)

    # ---------------------------------------------------------------- G ----
    # Two screenshots at the same instant. The node always writes the same
    # captura.png and the mover names the copy by the SECOND, so two captures
    # of the same second land on the same file.
    if not os.path.exists(NODE_DST):
        skip('G escritorio x2', 'no hay node\\McpDesktopNode.exe en el repo')
    else:
        SHOTS = os.path.join(JAIL, 'shots')
        rg = burst(lambda i: call('delphi_desktop',
                                  {"command": "screenshot", "out": SHOTS}), 2)
        shots, errs = [], []
        for r in rg:
            try:
                o = json.loads(r)
            except Exception:
                errs.append(str(r)[:120])
                continue
            if o.get('screenshot'):
                shots.append(o['screenshot'])
            else:
                errs.append(str(o.get('screenshotError') or o.get('hint') or r)[:120])
        if len(shots) < 2:
            skip('G escritorio x2',
                 'el escritorio no dio dos capturas (sesion bloqueada?): %s' % errs)
        else:
            check('G escritorio x2: cada llamada recibe SU propia captura',
                  shots[0] != shots[1], shots)
            reales = [unmask(s) for s in set(shots)]
            check('G escritorio x2: los dos ficheros existen y tienen bytes',
                  len(reales) == 2 and all(os.path.exists(s) and
                                           os.path.getsize(s) > 1000
                                           for s in reales), reales)

    # ---------------------------------------------------------------- H ----
    # A build while the exe of that same project is running. GBuildLock
    # serializes msbuild against msbuild, but it is released before the program
    # runs - so the compiler can find its own output file locked by a run.
    RUNDIR = os.path.join(JAIL, 'runp')
    call('delphi_create', {"kind": "project-console", "dir": RUNDIR,
                           "name": "ConcRun"})
    rdprs = glob.glob(os.path.join(RUNDIR, '**', 'ConcRun.dpr'), recursive=True)
    if not rdprs:
        skip('H build con el exe corriendo', 'no pude crear el proyecto console')
    else:
        RDPR = rdprs[0]
        RPROJ = RDPR[:-4] + '.dproj'   # msbuild builds the .dproj, not the .dpr
        # A program that stays alive long enough to still be running when the
        # second build starts. Written here, not by a tool: the battery owns
        # this folder and what matters is the .dproj the scaffold left.
        with open(RDPR, 'w', encoding='utf-8', newline='') as f:
            f.write('program ConcRun;\r\n\r\n{$APPTYPE CONSOLE}\r\n\r\n'
                    'uses\r\n  System.SysUtils;\r\n\r\n'
                    'begin\r\n  Writeln(\'vivo\');\r\n  Sleep(8000);\r\nend.\r\n')
        b1 = call('delphi_build', {"project": RPROJ, "config": "Debug"},
                  timeout=600)
        built = False
        try:
            built = json.loads(b1).get('success') is True
        except Exception:
            built = False
        exe = glob.glob(os.path.join(RUNDIR, '**', 'ConcRun.exe'), recursive=True)
        if not built or not exe:
            skip('H build con el exe corriendo',
                 'el primer build no salio (RAD Studio / msbuild?): ' + str(b1)[:200])
        else:
            res = {}

            def runner():
                res['run'] = call('delphi_run', {"path": exe[0],
                                                 "timeoutMs": 20000}, timeout=300)

            def builder():
                time.sleep(2.0)   # the program is already running by now
                res['build'] = call('delphi_build',
                                    {"project": RPROJ, "config": "Debug"},
                                    timeout=600)

            ts = [threading.Thread(target=runner), threading.Thread(target=builder)]
            for t in ts:
                t.start()
            for t in ts:
                t.join()
            ok_run = 'vivo' in str(res.get('run', ''))
            b2 = str(res.get('build', ''))
            ok_build, why_build = False, b2[:300]
            try:
                jb = json.loads(b2)
                ok_build = jb.get('success') is True
                why_build = jb.get('firstError') or b2[:300]
            except Exception:
                pass
            check('H build con el exe corriendo: el programa corre entero', ok_run,
                  str(res.get('run'))[:200])
            check('H build con el exe corriendo: el build NO falla por el exe en uso',
                  ok_build, re.sub(r'\s+', ' ', why_build)[:300])
finally:
    proc.kill()

print('\n== bateria de concurrencia: %d PASS / %d FAIL / %d SKIP ==' % (
    P, FCOUNT, SKIPPED))
sys.exit(1 if FCOUNT else 0)
