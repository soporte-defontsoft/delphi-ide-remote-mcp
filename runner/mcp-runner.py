#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mcp-runner - the target half of delphi_paserver command=remote-run.

The MCP server has no way to launch a process through PAServer (paclient.exe
only copies files), so it drops a job file and this script executes it and
writes the result back. It runs ON THE TARGET (the Linux/macOS box with
PAServer), inside PAServer's scratch dir, and it ONLY executes binaries that
live inside that scratch dir - never the rest of the machine.

Layout, all relative to this script's own folder (PAServer puts it under
<scratch>/_mcp-runner/ when the server sends a job):

    _mcp-runner/
        mcp-runner.py     this
        jobs/             job-*.json   arrive here (server --put)
        out/              result-*.json + result-*.out  written here (server --get)
        done/            processed jobs are moved here

Install on the target (one time), from the scratch dir:
    mkdir -p _mcp-runner/jobs _mcp-runner/out _mcp-runner/done
    # copy this file into _mcp-runner/  (delphi_fetch it from the server)
    nohup python3 _mcp-runner/mcp-runner.py >> _mcp-runner/runner.log 2>&1 &

A job is {"id","exe","allowDir","args","timeoutMs"}. TWO rules decide whether
anything runs at all, and both are enforced here, not by the sender:

  1. the exe must live inside <scratch>/<allowDir>/ - the folder ONE project's
     deploy writes. Nothing else of the scratch dir is reachable, and neither
     is the rest of the machine (symlinks resolved before comparing).
  2. it must be a NATIVE executable (ELF / Mach-O / PE magic bytes). Scripts
     are refused: a shebang would turn "run the deployed program" into "run
     any interpreter with any arguments".

The result is {"id","exitCode","durationMs"} (+ "error" on a rejection); the
program's combined stdout/stderr goes to result-<id>.out.
"""
import json, os, subprocess, sys, time, shlex

HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH = os.path.dirname(HERE)                 # the deploy root
JOBS = os.path.join(HERE, 'jobs')
OUT = os.path.join(HERE, 'out')
DONE = os.path.join(HERE, 'done')
for d in (JOBS, OUT, DONE):
    os.makedirs(d, exist_ok=True)


def inside_scratch(path):
    ap = os.path.realpath(path)
    root = os.path.realpath(SCRATCH) + os.sep
    return (ap + os.sep).startswith(root)


NATIVE_MAGIC = (b'\x7fELF',            # Linux
                b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe',   # Mach-O 64/32
                b'\xca\xfe\xba\xbe',                        # Mach-O fat
                b'MZ')                 # Windows targets


def is_native_executable(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(4)
    except OSError:
        return False
    return any(head.startswith(m) for m in NATIVE_MAGIC)


def run_job(job):
    jid = job.get('id', 'noid')
    exe = job.get('exe', '')
    allow = job.get('allowDir', '')
    args = job.get('args', '')
    timeout = max(1, min(300, int(job.get('timeoutMs', 30000)) // 1000))
    res = {'id': jid, 'exitCode': -1, 'durationMs': 0}
    out_text = ''
    target = exe if os.path.isabs(exe) else os.path.join(SCRATCH, exe)
    allow_root = os.path.realpath(os.path.join(SCRATCH, allow)) + os.sep if allow else ''
    if not inside_scratch(target):
        res['error'] = 'exe fuera de la scratch dir de PAServer: %s' % exe
    elif not allow_root:
        res['error'] = 'job sin allowDir: solo se ejecuta el programa desplegado de un proyecto'
    elif not (os.path.realpath(target) + os.sep).startswith(allow_root):
        res['error'] = ('exe fuera de la carpeta de despliegue del proyecto (%s): %s'
                        % (allow, exe))
    elif not os.path.isfile(target):
        res['error'] = 'no existe en el target: %s' % target
    elif not is_native_executable(target):
        res['error'] = ('no es un ejecutable nativo (ELF/Mach-O/PE): %s. Solo se ejecuta '
                        'el binario que produce delphi_build, nunca scripts.' % exe)
    else:
        try:
            os.chmod(target, 0o755)
        except OSError:
            pass
        cmd = [target] + (shlex.split(args) if args else [])
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=os.path.dirname(target),
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=timeout)
            res['exitCode'] = p.returncode
            out_text = p.stdout.decode('utf-8', 'replace')
        except subprocess.TimeoutExpired as e:
            res['error'] = 'timeout tras %ss' % timeout
            out_text = (e.stdout or b'').decode('utf-8', 'replace')
        except Exception as e:            # noqa
            res['error'] = 'fallo al lanzar: %s' % e
        res['durationMs'] = int((time.time() - t0) * 1000)
    # tail: keep the last ~64 KB
    if len(out_text) > 65536:
        out_text = '...(truncado)...\n' + out_text[-65536:]
    with open(os.path.join(OUT, 'result-%s.out' % jid), 'w', encoding='utf-8') as f:
        f.write(out_text)
    with open(os.path.join(OUT, 'result-%s.json' % jid), 'w', encoding='utf-8') as f:
        json.dump(res, f)


def main():
    print('mcp-runner vigilando %s (scratch=%s)' % (JOBS, SCRATCH), flush=True)
    while True:
        for name in sorted(os.listdir(JOBS)):
            if not name.endswith('.json'):
                continue
            path = os.path.join(JOBS, name)
            try:
                with open(path, encoding='utf-8-sig') as f:  # tolerate a BOM
                    job = json.load(f)
            except Exception as e:        # noqa
                print('job ilegible %s: %s' % (name, e), flush=True)
                os.replace(path, os.path.join(DONE, name))
                continue
            print('ejecutando job %s: %s' % (job.get('id'), job.get('exe')), flush=True)
            run_job(job)
            os.replace(path, os.path.join(DONE, name))
        time.sleep(1)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
