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
  E  a notice for everyone, two readers -> one copy per agent box, each read and deleted
  F  two delphi_package of one folder   -> deterministic zip name, no lock
  G  (retired in 1.0.16: the LOCAL desktop tool is gone, the desktop goes
     through a PAServer profile and needs a live target - not measured here)
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
import subprocess
import threading
import time
import zipfile
import mcp_cliente as mc
from mcp_cliente import check

TOKEN = 'conc-token'
N = 12                      # writers firing at once

WORK = mc.carpeta('concurrencia')

# The server reads its settings.ini next to the executable, so the battery runs
# its OWN copy in its own folder - never the build output in place.
EXE = mc.copia_exe(WORK)

JAIL = os.path.join(WORK, 'jaula')
os.makedirs(JAIL)
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\n'
            'Token=%s\n'
            'Roots=%s\n'
            'AllowTests=1\n' % (TOKEN, JAIL))

PORT = mc.puerto_libre()

# Loopback only: binding every interface makes Windows Firewall ask once per
# executable PATH, and this battery runs from a fresh temp folder every time.
env = mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'})
# espera a que ESCUCHE; si no llega, RuntimeError con el motivo
proc = mc.lanza_http(EXE, PORT, env)
# seguro entre hilos (cada peticion lleva y busca SU id): burst() lo comparte
cli = mc.Http(PORT, TOKEN, t=180)

SKIPPED = 0


def skip(name, why):
    global SKIPPED
    SKIPPED += 1
    print('SKIP -', name, '|', str(why)[:200])


def session(name):
    """El session-id de un agente con ese nombre (clientInfo), para sid=."""
    return mc.Http(PORT, TOKEN).session(name)


call = cli.call


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


def bad(text):
    """A tool answer that is NOT a success."""
    t = (text or '').upper()
    # (TIMEOUT) / (NO CONTENT): lo que mc.texto() dice cuando no llega nada
    return ('RECHAZAD' in t or t.startswith('ERROR') or 'MCPERROR' in t or
            'EXCEPCION' in t or 'FALLID' in t or '(TIMEOUT)' in t or '(NO CONTENT)' in t)


try:
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
          'exitos=%d ficheros=%d; los que no: %s' % (
              ok_d, len(files_d), [str(r)[:160] for r in rd if bad(r)]))

    # ---------------------------------------------------------------- E ----
    # A notice for everyone is the SAME message dropped in each agent's box:
    # there is no box "for everyone" since 2026-09-25 (David). Two agents ask
    # for their mail; each gets its own copy, and reading it deletes it.
    MSGS = os.path.join(WORK, 'messages')
    for quien in ('alice', 'bob'):
        os.makedirs(os.path.join(MSGS, quien), exist_ok=True)
        with open(os.path.join(MSGS, quien, '20260920-0900-aviso.md'), 'w',
                  encoding='utf-8') as f:
            f.write('AVISO-BROADCAST: parad todos y leed esto\n')
    alice, bob = session('alice'), session('bob')
    ea = call('delphi_messages', {"command": "read"}, sid=alice)
    eb = call('delphi_messages', {"command": "read"}, sid=bob)
    check('E buzon: el primer agente recibe su copia del aviso',
          'AVISO-BROADCAST' in ea, ea[:150])
    check('E buzon: el SEGUNDO agente tambien recibe la suya',
          'AVISO-BROADCAST' in eb, eb[:150])
    check('E buzon: leidas, las dos copias se han borrado',
          not any(os.path.exists(os.path.join(MSGS, q, '20260920-0900-aviso.md'))
                  for q in ('alice', 'bob')), os.listdir(MSGS))

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
    # Retired in 1.0.16: delphi_desktop no longer runs the node locally (the
    # desktop is the one behind a PAServer profile, Linux or Windows), so two
    # captures at once need a live target. The per-profile lock that names
    # each capture by its profile is the same code round 30 exercises.
    skip('G escritorio x2', 'delphi_desktop local retirado en 1.0.16: el '
         'escritorio va por perfil PAServer y no hay destino en la bateria')

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
                  t=600)
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
                # The battery itself keeps the exe alive (delphi_run was
                # retired 2026-09-23): what matters is the file being OPEN
                # while msbuild wants to write it.
                pr = subprocess.run([exe[0]], capture_output=True, text=True, timeout=300)
                res['run'] = pr.stdout

            def builder():
                time.sleep(2.0)   # the program is already running by now
                res['build'] = call('delphi_build',
                                    {"project": RPROJ, "config": "Debug"},
                                    t=600)

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

print('\n%d SKIP' % SKIPPED)
mc.fin('bateria de concurrencia')
