# -*- coding: utf-8 -*-
"""E2E battery for v0.47.0-beta - delphi_paserver command=remote-run: running
a program ON THE TARGET through PAServer's file transport (paclient has no
exec operation) with the mcp-runner script as the target half.

PAServer is NOT needed: paclient.exe is replaced by tests/paclient_stub.py
(DELPHI_MCP_PACLIENT), which copies to a local folder playing the scratch dir.

Usage:  python tests/test_remoterun.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'remoterun')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
SCRATCH = os.path.join(BASE, 'scratch'); os.makedirs(SCRATCH)

# the server ships runner/mcp-runner.py next to its exe (that is how it is
# deployed); install-runner picks it up from there
_rd = os.path.join(os.path.dirname(os.path.abspath(EXE)), 'runner')
os.makedirs(_rd, exist_ok=True)
shutil.copy(os.path.join(REPO, 'runner', 'mcp-runner.py'), _rd)

# the deploy folder the server derives: <windows user>-<profile>/<Project>/
PROFILE = 'perfil'
PROJNAME = 'Saluda'
# the runner's root IS the profile scratch folder (that is where _mcp-runner
# lives), so a deploy sits at <scratch>/<Project>/ - measured end to end
# against a real PAServer 2026-08-25
DEPLOY = os.path.join(SCRATCH, PROJNAME)
os.makedirs(DEPLOY)
# the "deployed binary": a real native executable (python itself, copied), so
# the runner's ELF/PE check passes; it prints and exits 7 through a wrapper
APP = os.path.join(DEPLOY, PROJNAME + '.exe')
shutil.copy(sys.executable, APP)
SCRIPT = os.path.join(DEPLOY, 'run.py')
open(SCRIPT, 'w', encoding='utf-8').write(
    'import sys\nprint("hola desde el target, args=", sys.argv[1:])\nsys.exit(7)\n')
# a script sitting in the same folder: must be REFUSED (not a native binary)
# the project on THIS server (remote-run takes the .dproj, not a path)
PRJDIR = os.path.join(BASE, 'proj'); os.makedirs(PRJDIR)
DPROJ = os.path.join(PRJDIR, PROJNAME + '.dproj')
open(DPROJ, 'w', encoding='utf-8').write('<Project/>')

# paclient stub: a .cmd that calls python on the stub script
STUB = os.path.join(BASE, 'paclient.cmd')
open(STUB, 'w').write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))

# the runner, watching the scratch (its folder is <scratch>/_mcp-runner)
RUNNER_DIR = os.path.join(SCRATCH, '_mcp-runner'); os.makedirs(RUNNER_DIR)
shutil.copy(os.path.join(REPO, 'runner', 'mcp-runner.py'), RUNNER_DIR)

renv = dict(os.environ)
runner = subprocess.Popen([sys.executable, os.path.join(RUNNER_DIR, 'mcp-runner.py')],
                          env=renv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'   # v0.48.1: remote execution is opt-in
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def rdr():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=rdr, daemon=True).start()
rid = [10]
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=120):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
def call(name, args, t=120):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None: return '(timeout)'
    if 'error' in r: return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "rr", "version": "1"}}}); recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

# ---- the opt-in switch (a server without AllowRemoteRun) ----
env_off = dict(env); env_off.pop('DELPHI_MCP_ALLOW_REMOTE_RUN', None)
proc_off = subprocess.Popen([EXE], env=env_off, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q_off = queue.Queue()
def rdr_off():
    for line in proc_off.stdout:
        line = line.strip()
        if line: q_off.put(line)
threading.Thread(target=rdr_off, daemon=True).start()
def call_off(name, args, t=60):
    proc_off.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 99, "method": "tools/call",
                                     "params": {"name": name, "arguments": args}}) + '\n')
    proc_off.stdin.flush()
    dl = time.time() + t
    while time.time() < dl:
        try: line = q_off.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == 99:
            c = m.get('result', {}).get('content', [])
            return c[0].get('text', '') if c else json.dumps(m)[:200]
    return '(timeout)'
proc_off.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "off", "version": "1"}}}) + '\n')
proc_off.stdin.flush(); time.sleep(1)
while not q_off.empty(): q_off.get()
proc_off.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + '\n')
proc_off.stdin.flush()

P = F = 0
def check(n, ok, d=''):
    global P, F
    if ok: P += 1; print('PASS', n)
    else: F += 1; print('FAIL', n, '--', str(d)[:300])

# 1) needs name+exe
r = call('delphi_paserver', {'command': 'remote-run'})
check('sin name/exe rechazado', 'RECHAZADO' in r, r[:150])
# 2) shell metachar refused
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'args': 'a; rm -rf /'})
check('metacaracter rechazado', 'RECHAZADO' in r and ';' in r, r[:150])
# 2b) install-runner copies the script to the target
os.remove(os.path.join(RUNNER_DIR, 'mcp-runner.py'))
r = call('delphi_paserver', {'command': 'install-runner', 'name': 'perfil'})
check('install-runner copia el script', 'RUNNER COPIADO' in r and os.path.isfile(os.path.join(RUNNER_DIR, 'mcp-runner.py')), r[:200])
check('install-runner remite a start-runner', 'start-runner' in r, r[:250])
r = call('delphi_paserver', {'command': 'install-runner'})
check('install-runner sin name rechazado', 'RECHAZADO' in r, r[:150])

# 3) happy path
# exe=<nombre simple> de la MISMA carpeta de despliegue (en Linux el binario
# no lleva extension y basta project; aqui el "binario" es un .exe de Windows)
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': PROJNAME + '.exe',
                             'args': '"%s" uno dos' % SCRIPT.replace(chr(92), '/'),
                             'timeoutms': 30000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('exitCode del programa (7)', j.get('exitCode') == 7, r[:300])
check('output capturado', 'hola desde el target' in (j.get('output') or ''), r[:300])
check('note explica el mecanismo', 'PAServer' in (j.get('note') or ''), r[:200])
# v0.85: two agents firing in the same millisecond used to collide on a
# timestamp-only jobId; now it carries a GUID fragment
import re as _re
check('jobId lleva fragmento GUID (timestamp-only colisionaba)',
      bool(_re.match(r'^\d{8}-\d{9}-[0-9a-f]{8}$', j.get('jobId') or '')),
      j.get('jobId'))
# 4) exe fuera de la scratch -> runnerError
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'exe': '..\\..\\fuera.exe', 'timeoutms': 20000})
j = json.loads(r) if r.startswith('{') else {}
check('exe con separadores rechazado por el server', 'RECHAZADO' in r, r[:250])
# 5) exe inexistente -> runnerError
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'exe': 'noexiste.exe', 'timeoutms': 20000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('exe inexistente en target', 'no existe' in json.dumps(j), r[:250])

# 5b) un SCRIPT de la misma carpeta de despliegue: rechazado (no es nativo)
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                             'exe': 'run.py', 'timeoutms': 20000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('script en la carpeta de deploy rechazado (solo binario nativo)',
      'ejecutable nativo' in json.dumps(j), r[:300])
# 5c) proyecto inexistente
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE,
                             'project': os.path.join(PRJDIR, 'NoHay.dproj')})
check('proyecto inexistente rechazado', 'RECHAZADO' in r, r[:200])
# 5d) proyecto fuera de la jaula
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE,
                             'project': 'C:\\Windows\\x.dproj'})
check('proyecto fuera de la jaula rechazado', 'RECHAZADO' in r, r[:200])

# 6) runner copiado pero NO arrancado: mensaje distinto de "no instalado"
runner.kill(); time.sleep(1)
for f in os.listdir(os.path.join(RUNNER_DIR, 'jobs')):
    os.remove(os.path.join(RUNNER_DIR, 'jobs', f))
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'timeoutms': 1000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('runner parado: dice que falta ARRANCARLO', j.get('runnerInstalled') is True and 'ARRANCARLO' in (j.get('error') or ''), r[:300])
os.remove(os.path.join(RUNNER_DIR, 'mcp-runner.py'))
r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ, 'timeoutms': 1000}, t=180)
j = json.loads(r) if r.startswith('{') else {}
check('runner ausente: dice que NO esta instalado', j.get('runnerInstalled') is False and 'NO tiene el runner' in (j.get('error') or ''), r[:300])

# 7) sin AllowRemoteRun: remote-run RECHAZADO, install-runner permitido
r = call_off('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ})
check('sin AllowRemoteRun: remote-run rechazado', 'RECHAZADO' in r and 'AllowRemoteRun' in r, r[:250])
r = call_off('delphi_paserver', {'command': 'install-runner', 'name': PROFILE})
check('sin AllowRemoteRun: install-runner sigue permitido', 'RUNNER COPIADO' in r, r[:200])
r = call_off('delphi_paserver', {'command': 'platforms'})
check('sin AllowRemoteRun: el resto del tool intacto', 'platforms' in r, r[:150])
proc_off.kill()

# 8) RemoteRunProjects: lista blanca de proyectos ejecutables
env_wl = dict(env); env_wl['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
ini = os.path.join(os.path.dirname(os.path.abspath(EXE)), 'settings.ini')
had_ini = os.path.exists(ini)
if had_ini:
    shutil.copy(ini, ini + '.bak')
open(ini, 'w', encoding='utf-8').write(
    '[Security]\nAllowRemoteRun=1\nRemoteRunProjects=OtroProyecto\n[Workspace]\nRoots=%s\n' % BASE)
proc_wl = subprocess.Popen([EXE], env=env_wl, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q_wl = queue.Queue()
def rdr_wl():
    for line in proc_wl.stdout:
        line = line.strip()
        if line: q_wl.put(line)
threading.Thread(target=rdr_wl, daemon=True).start()
proc_wl.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "wl", "version": "1"}}}) + '\n')
proc_wl.stdin.flush(); time.sleep(1)
while not q_wl.empty(): q_wl.get()
proc_wl.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + '\n')
proc_wl.stdin.flush()
def call_wl(name, args, t=60):
    proc_wl.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 98, "method": "tools/call",
                                    "params": {"name": name, "arguments": args}}) + '\n')
    proc_wl.stdin.flush()
    dl = time.time() + t
    while time.time() < dl:
        try: line = q_wl.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == 98:
            c = m.get('result', {}).get('content', [])
            return c[0].get('text', '') if c else json.dumps(m)[:200]
    return '(timeout)'
r = call_wl('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ})
check('proyecto fuera de RemoteRunProjects rechazado', 'RECHAZADO' in r and 'RemoteRunProjects' in r, r[:250])
r = call_wl('delphi_workspace', {})
check('LibraryZone=1 por defecto: zona anunciada', 'readableExtra' in r and 'RTL' in r, r[:200])
proc_wl.kill()
os.remove(ini)
if had_ini:
    shutil.move(ini + '.bak', ini)

# 9) LibraryZone=0: la lectura se limita a los roots
env_lz = dict(env); env_lz['DELPHI_MCP_LIBRARY_ZONE'] = '0'
proc_lz = subprocess.Popen([EXE], env=env_lz, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q_lz = queue.Queue()
def rdr_lz():
    for line in proc_lz.stdout:
        line = line.strip()
        if line: q_lz.put(line)
threading.Thread(target=rdr_lz, daemon=True).start()
proc_lz.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "lz", "version": "1"}}}) + '\n')
proc_lz.stdin.flush(); time.sleep(1)
while not q_lz.empty(): q_lz.get()
proc_lz.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + '\n')
proc_lz.stdin.flush()
def call_lz(name, args, t=60):
    proc_lz.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 97, "method": "tools/call",
                                    "params": {"name": name, "arguments": args}}) + '\n')
    proc_lz.stdin.flush()
    dl = time.time() + t
    while time.time() < dl:
        try: line = q_lz.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == 97:
            c = m.get('result', {}).get('content', [])
            return c[0].get('text', '') if c else json.dumps(m)[:200]
    return '(timeout)'
RTL = r'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\sys\System.SysUtils.pas'
r = call_lz('delphi_read', {'path': RTL, 'fromline': 1, 'toline': 2})
check('LibraryZone=0: la RTL deja de ser legible', 'RECHAZADO' in r, r[:200])
r = call_lz('delphi_workspace', {})
check('LibraryZone=0: se anuncia apagada y sin carpetas', 'APAGADA' in r and '"readableExtra":[]' in r.replace(' ', ''), r[:300])
r = call_lz('delphi_read', {'path': os.path.join(SCRATCH, '_mcp-runner', 'mcp-runner.py'), 'fromline': 1, 'toline': 1})
check('LibraryZone=0: el root sigue legible', 'RECHAZADO' not in r, r[:200])
proc_lz.kill()

proc.kill(); runner.kill()
print('\n== remote-run: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
