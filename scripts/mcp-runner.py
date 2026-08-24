#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mcp-runner: la mitad remota de `delphi_run profile=<paserver>`.

Vive en la maquina DESTINO (la que corre PAServer) y ejecuta los jobs que el
servidor MCP deja por paclient en la scratch de PAServer:

    <scratch>/_mcp-runner/jobs/job-<id>.json    la orden
    <scratch>/_mcp-runner/out/result-<id>.json  el resultado (exitCode...)
    <scratch>/_mcp-runner/out/result-<id>.out   stdout+stderr (cola 200 KB)
    <scratch>/_mcp-runner/done/                 jobs ya atendidos

SEGURIDAD: solo ejecuta binarios cuyo realpath quede DENTRO de la scratch de
PAServer (la zona de deploy). Nada fuera de ella. Instalar este runner es el
opt-in de ejecucion remota: sin runner, los jobs caducan sin efecto.

Uso:    python3 mcp-runner.py [scratch-dir]
        (defecto: ~/PAServer/scratch-dir)

Como servicio de usuario (systemd):
    mkdir -p ~/.config/systemd/user
    cp mcp-runner.service ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now mcp-runner
"""
import json, os, shlex, subprocess, sys, time

SCRATCH = os.path.realpath(os.path.expanduser(
    sys.argv[1] if len(sys.argv) > 1 else '~/PAServer/scratch-dir'))
ROOT = os.path.join(SCRATCH, '_mcp-runner')
JOBS = os.path.join(ROOT, 'jobs')
OUT = os.path.join(ROOT, 'out')
DONE = os.path.join(ROOT, 'done')
TAIL = 200 * 1024

for d in (JOBS, OUT, DONE):
    os.makedirs(d, exist_ok=True)
print('mcp-runner: vigilando %s' % JOBS, flush=True)


def resolve_exe(exe):
    """Ruta del binario: absoluta o relativa a la scratch. SOLO dentro de la
    scratch (realpath, o sea los symlinks no la sacan)."""
    p = exe if os.path.isabs(exe) else os.path.join(SCRATCH, exe)
    rp = os.path.realpath(p)
    if not (rp + os.sep).startswith(SCRATCH + os.sep):
        return None, 'RECHAZADO: %s queda fuera de la scratch de PAServer (%s)' % (exe, SCRATCH)
    if not os.path.isfile(rp):
        return None, 'no existe: %s' % rp
    return rp, ''


def attend(path):
    jid = os.path.basename(path)[4:-5]  # job-<id>.json
    res = {'id': jid, 'exitCode': -1, 'durationMs': 0}
    out_bytes = b''
    try:
        job = json.load(open(path, encoding='utf-8'))
        exe, err = resolve_exe(str(job.get('exe', '')))
        timeout = min(max(int(job.get('timeoutMs', 30000)), 1000), 300000) / 1000.0
        if err:
            res['error'] = err
        else:
            os.chmod(exe, os.stat(exe).st_mode | 0o111)
            cmd = [exe] + shlex.split(str(job.get('args', '')))
            t0 = time.time()
            try:
                cp = subprocess.run(cmd, cwd=os.path.dirname(exe),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=timeout)
                res['exitCode'] = cp.returncode
                out_bytes = cp.stdout or b''
            except subprocess.TimeoutExpired as e:
                res['error'] = 'timeout: proceso matado a los %ds' % int(timeout)
                out_bytes = e.stdout or b''
            res['durationMs'] = int((time.time() - t0) * 1000)
    except Exception as e:  # un job roto j