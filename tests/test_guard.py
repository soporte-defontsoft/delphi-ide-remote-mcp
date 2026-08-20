"""E2E battery for the workspace jail (DELPHI_MCP_ROOTS / settings.ini
[Workspace] Roots): with roots configured, every disk-touching tool must
refuse paths outside them - reads, edits, scaffolding, builds, git, search.

Usage:  python tests/test_guard.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'guard')
shutil.rmtree(BASE, ignore_errors=True)
INSIDE = os.path.join(BASE, 'permitido')
OUTSIDE = os.path.join(BASE, 'prohibido')
os.makedirs(INSIDE, exist_ok=True)
os.makedirs(OUTSIDE, exist_ok=True)

SRC = 'unit Dentro;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'
open(os.path.join(INSIDE, 'Dentro.pas'), 'wb').write(SRC.encode('cp1252'))
open(os.path.join(OUTSIDE, 'Fuera.pas'), 'wb').write(SRC.replace('Dentro', 'Fuera').encode('cp1252'))

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = INSIDE  # the jail
# This battery exercises the RUN MECHANISM (jail + low-integrity sandbox), so
# it opts into execution. Run is OFF by default (a compile-only server); the
# default-off behaviour is verified separately below with its own instance.
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

def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()

def recv(r, t=90):
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

def call(name, args, t=90):
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

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "guard-battery", "version": "1"}}})
assert recv(1, 20), 'no initialize response'
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0
def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:170])

def denied(out):
    return 'FUERA de los workspaces' in out or ('MCPERROR' in out and 'FUERA' in out)

IN_PAS = os.path.join(INSIDE, 'Dentro.pas')
OUT_PAS = os.path.join(OUTSIDE, 'Fuera.pas')

# inside: allowed
out = call('delphi_read', {"path": IN_PAS})
check('dentro: read permitido', 'unit Dentro' in out, out)
out = call('delphi_edit', {"path": IN_PAS, "old": "unit Dentro;", "new": "unit Dentro; // ok"})
check('dentro: edit permitido', out.startswith('ESCRITO'), out)

# outside: every door closed
out = call('delphi_read', {"path": OUT_PAS})
check('fuera: read vetado', denied(out), out)
out = call('delphi_edit', {"path": OUT_PAS, "old": "unit Fuera;", "new": "x"})
check('fuera: edit vetado', denied(out), out)
out = call('delphi_edit', {"path": os.path.join(OUTSIDE, 'Nueva.pas'), "createunit": True})
check('fuera: createunit vetado', denied(out), out)
out = call('delphi_create', {"kind": "project-console", "dir": OUTSIDE, "name": "Malo"})
check('fuera: crear proyecto vetado', denied(out), out)
out = call('delphi_build', {"project": os.path.join(OUTSIDE, 'Malo.dproj')})
check('fuera: build vetado', denied(out), out)
out = call('delphi_search', {"root": OUTSIDE, "query": "unit"})
check('fuera: search vetado', denied(out), out)
out = call('delphi_list', {"root": OUTSIDE})
check('fuera: list vetado', denied(out), out)
out = call('delphi_git', {"repo": OUTSIDE, "command": "status"})
check('fuera: git vetado', denied(out), out)
out = call('delphi_symbols', {"path": OUT_PAS})
check('fuera: symbols (LSP) vetado', denied(out), out)

# escape attempts
out = call('delphi_read', {"path": os.path.join(INSIDE, '..', 'prohibido', 'Fuera.pas')})
check('fuera: escape con ..\\ vetado', denied(out), out)
sneaky = INSIDE + '2'  # prefix cousin: permitido2
os.makedirs(sneaky, exist_ok=True)
open(os.path.join(sneaky, 'Primo.pas'), 'wb').write(SRC.encode('cp1252'))
out = call('delphi_read', {"path": os.path.join(sneaky, 'Primo.pas')})
check('fuera: primo de prefijo (permitido2) vetado', denied(out), out)

# --- delphi_run is OFF BY DEFAULT (compile-only server) ---------------------
# A fresh instance WITHOUT DELPHI_MCP_ALLOW_RUN must refuse delphi_run even
# for the full read-write stdio client, pointing to the download path instead.
def run_disabled_by_default():
    e = dict(os.environ)
    e['DELPHI_MCP_ROOTS'] = INSIDE
    e.pop('DELPHI_MCP_ALLOW_RUN', None)  # default: execution off
    p = subprocess.Popen([EXE], env=e, stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                         text=True, encoding='utf-8')
    try:
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1,
            "method": "initialize", "params": {"protocolVersion": "2025-06-18",
            "capabilities": {}, "clientInfo": {"name": "x", "version": "1"}}}) + '\n')
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "delphi_run",
                       "arguments": {"path": os.path.join(INSIDE, 'whatever.exe')}}}) + '\n')
        p.stdin.flush()
        dl = time.time() + 20
        while time.time() < dl:
            line = p.stdout.readline()
            if not line:
                break
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == 2:
                c = m.get('result', {}).get('content', [])
                return c[0].get('text', '') if c else ''
        return '(timeout)'
    finally:
        p.terminate()

out = run_disabled_by_default()
check('run: DESHABILITADO por defecto (server de compilacion)',
      'deshabilitada por diseno' in out and 'delphi_package' in out, out[:200])

# delphi_run: inside allowed (real console exe built on the fly), outside denied
out = call('delphi_create', {"kind": "project-console", "dir": os.path.join(INSIDE, 'Hola'),
                             "name": "Hola"})
check('run: proyecto de prueba creado', out.startswith('CREADO'), out)
out = call('delphi_build', {"project": os.path.join(INSIDE, 'Hola', 'Hola.dproj'),
                            "platform": "Win64", "config": "Debug", "target": "Build"}, 600)
try:
    ok = json.loads(out)['success']
except Exception:
    ok = False
check('run: proyecto de prueba compila', ok, out[:150])
out = call('delphi_run', {"path": os.path.join(INSIDE, 'Hola', 'Win64', 'Debug', 'Hola.exe')}, 120)
check('run: dentro ejecuta y captura salida', out.startswith('exit=0') and 'funcionando' in out, out[:150])
out = call('delphi_run', {"path": os.path.join(OUTSIDE, 'Fuera.exe')})
check('run: fuera vetado', denied(out), out[:150])

# --- filesystem sandbox (B0b): a run program cannot write outside its folder ---
_q = chr(39)
_pub = r'C:\Users\Public\PWNED_guard_test.txt'
if os.path.exists(_pub):
    os.remove(_pub)
call('delphi_create', {"kind": "project-console", "dir": os.path.join(INSIDE, 'Sbx'), "name": "Sbx"})
_body = ['program Sbx;', '{$APPTYPE CONSOLE}', 'uses System.SysUtils, System.IOUtils;', 'begin',
         '  try TFile.WriteAllText(' + _q + _pub + _q + ', ' + _q + 'x' + _q + '); Writeln('
         + _q + 'SYSWRITE-OK' + _q + '); except Writeln(' + _q + 'sys-blocked' + _q + '); end;',
         '  try TFile.WriteAllText(' + _q + 'out.txt' + _q + ', ' + _q + 'y' + _q + '); Writeln('
         + _q + 'LOCAL-OK' + _q + '); except Writeln(' + _q + 'local-blocked' + _q + '); end;', 'end.']
open(os.path.join(INSIDE, 'Sbx', 'Sbx.dpr'), 'w', encoding='utf-8-sig', newline='').write('\r\n'.join(_body) + '\r\n')
out = call('delphi_build', {"project": os.path.join(INSIDE, 'Sbx', 'Sbx.dproj'),
                            "platform": "Win64", "config": "Debug", "target": "Build"}, 600)
try:
    sbok = json.loads(out)['success']
except Exception:
    sbok = False
check('sandbox: proyecto de prueba compila', sbok, out[:150])
if sbok:
    # R6-C: pre-create out.txt at MEDIUM integrity (this test process) in the
    # run's own folder. Without the tree relabel, the low-IL run cannot
    # overwrite a pre-existing medium file -> "local-blocked".
    _rundir = os.path.join(INSIDE, 'Sbx', 'Win64', 'Debug')
    os.makedirs(_rundir, exist_ok=True)
    open(os.path.join(_rundir, 'out.txt'), 'w').write('preexisting-medium-integrity')
    out = call('delphi_run', {"path": os.path.join(_rundir, 'Sbx.exe'), "timeoutms": 10000}, 60)
    check('sandbox: escritura al SISTEMA bloqueada (low integrity)',
          'sys-blocked' in out and not os.path.exists(_pub), out[:200])
    check('sandbox: escritura en su propia carpeta permitida', 'LOCAL-OK' in out, out[:200])
    check('R6-C: sobrescribe un fichero MEDIO pre-existente en su cwd', 'LOCAL-OK' in out, out[:200])
    check('sandbox: la respuesta declara sandbox=low-integrity', 'sandbox=low-integrity' in out, out[:120])
if os.path.exists(_pub):
    os.remove(_pub)
out = call('delphi_fetch', {"path": OUT_PAS})
check('fetch: fuera vetado', denied(out), out[:150])
out = call('delphi_upload', {"path": os.path.join(OUTSIDE, 'Subido.bin'),
                             "offset": 0, "chunkbase64": "AAAA"})
check('upload: fuera vetado', denied(out), out[:150])
out = call('delphi_upload', {"path": os.path.join(INSIDE, 'Subido.bin'),
                             "offset": 0, "chunkbase64": "AAAA"})
check('upload: dentro permitido', 'written' in out, out[:150])
out = call('delphi_git', {"repo": os.path.join(OUTSIDE, 'clonado'),
                          "command": "clone",
                          "message": "https://example.com/x.git"})
check('clone: destino fuera vetado', denied(out), out[:150])

# --- R7 CRITICAL: upload a .dproj with an <Exec> hook, then build must NOT run
#     it (the "compile-only, never execute" guarantee). Reproduces Fable's R7.
#     The build refusal is the DEFAULT posture (AllowRun off), so the build half
#     runs in a fresh instance WITHOUT AllowRun - this battery sets AllowRun=1 to
#     exercise the sandbox, which by design also permits build hooks. ---
import base64 as _b64, glob as _glob
_holad = os.path.join(INSIDE, 'Hola', 'Hola.dproj')
_marker = os.path.join(INSIDE, 'Hola', 'R7MARKER.txt')
if os.path.exists(_marker):
    os.remove(_marker)

def build_no_allowrun(project):
    e = dict(os.environ); e['DELPHI_MCP_ROOTS'] = INSIDE; e.pop('DELPHI_MCP_ALLOW_RUN', None)
    p = subprocess.Popen([EXE], env=e, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    try:
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "x", "version": "1"}}}) + '\n')
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "delphi_build", "arguments": {"project": project,
            "platform": "Win64", "config": "Debug", "target": "Build"}}}) + '\n')
        p.stdin.flush()
        dl = time.time() + 120
        while time.time() < dl:
            line = p.stdout.readline()
            if not line:
                break
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == 2:
                if 'error' in m:
                    return 'MCPERROR ' + json.dumps(m['error'])[:300]
                c = m.get('result', {}).get('content', [])
                return c[0].get('text', '') if c else ''
        return '(timeout)'
    finally:
        p.terminate()

def oneshot(tool, args, env_extra=None, t=120):
    """One fresh server instance (AllowRun OFF), one tool call, its text back.
    env_extra lets a test flip a single security knob (e.g. AllowBuildScripts)."""
    e = dict(os.environ); e['DELPHI_MCP_ROOTS'] = INSIDE
    e.pop('DELPHI_MCP_ALLOW_RUN', None)
    if env_extra:
        e.update(env_extra)
    p = subprocess.Popen([EXE], env=e, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    try:
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "x", "version": "1"}}}) + '\n')
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": tool, "arguments": args}}) + '\n')
        p.stdin.flush()
        dl = time.time() + t
        while time.time() < dl:
            line = p.stdout.readline()
            if not line:
                break
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == 2:
                if 'error' in m:
                    return 'MCPERROR ' + json.dumps(m['error'])[:300]
                c = m.get('result', {}).get('content', [])
                return c[0].get('text', '') if c else ''
        return '(timeout)'
    finally:
        p.terminate()

if os.path.exists(_holad):
    _evil = open(_holad, encoding='utf-8-sig').read().replace('</Project>',
        '<Target Name="R7Probe" BeforeTargets="Build"><Exec Command="cmd /c echo '
        'pwned &gt; R7MARKER.txt" /></Target></Project>')
    _b = _b64.b64encode(_evil.encode('utf-8')).decode()
    out = call('delphi_upload', {"path": _holad, "offset": 0, "chunkbase64": _b})
    check('R7: upload del .dproj llega (no hay filtro de extension)', 'written' in out, out[:150])
    # R7 HIGH: upload backed the original up before truncating it
    _bk = _glob.glob(os.path.join(INSIDE, 'Hola', '__delphi-patch', '**', 'Hola.dproj'), recursive=True)
    check('R7 HIGH: upload respaldo el .dproj antes de pisarlo', len(_bk) > 0, _bk)
    # R7 CRITICAL: a compile-only server (no AllowRun) refuses the hazardous
    # project and never runs the injected <Exec>.
    if os.path.exists(_marker):
        os.remove(_marker)
    out = build_no_allowrun(_holad)
    check('R7 CRITICAL: build (sin AllowRun) RECHAZA un .dproj con <Target>/<Exec>',
          'RECHAZADO' in out, out[:200])
    check('R7 CRITICAL: el <Exec> inyectado NO se ejecuto (sin marcador)',
          not os.path.exists(_marker), _marker)

    # Evasions of the same guard: odd casing, build events, and the INDIRECT
    # route (a clean .dproj importing an evil .targets dropped beside it).
    _clean = open(_holad, encoding='utf-8-sig').read().replace(
        '<Target Name="R7Probe" BeforeTargets="Build"><Exec Command="cmd /c echo '
        'pwned &gt; R7MARKER.txt" /></Target>', '')
    def upload_dproj(xml):
        return call('delphi_upload', {"path": _holad, "offset": 0,
                                      "chunkbase64": _b64.b64encode(xml.encode()).decode()})
    for payload, label in (
        ('<target name="x" beforetargets="Build"><exec command="cmd /c echo x" /></target>',
         'minusculas'),
        ('<PropertyGroup><PostBuildEvent>cmd /c echo x &gt; M.txt</PostBuildEvent></PropertyGroup>',
         'PostBuildEvent'),
        ('<PropertyGroup><prebuildevent>cmd /c echo x</prebuildevent></PropertyGroup>',
         'prebuildevent en minusculas'),
        ('<Import Project="evil.targets" />', 'Import relativo (targets al lado)'),
        ('<import project="evil.targets" />', 'import relativo en minusculas'),
        ('<Import Project="$(BDS)\\..\\..\\evil.targets" />', 'Import con .. tras macro'),
        ('<Import Project="\\\\servidor\\share\\evil.targets" />', 'Import UNC'),
    ):
        upload_dproj(_clean.replace('</Project>', payload + '</Project>'))
        out = build_no_allowrun(_holad)
        check('R7 evasion (%s): build RECHAZADO' % label, 'RECHAZADO' in out, out[:160])
    # R8 CRITICAL (Fable): the payload one file away. A macro-based <Import>
    # that resolves NEXT TO the project - macro-based, so a naive macro check
    # passed it - pulling in a .targets uploaded there. Imports are now
    # followed and scanned recursively.
    _tgt = os.path.join(INSIDE, 'Hola', 'r8payload.targets')
    _m8 = os.path.join(INSIDE, 'Hola', 'R8MARKER.txt')
    for _f in (_m8,):
        if os.path.exists(_f):
            os.remove(_f)
    _payload_xml = ('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
                    '<Target Name="R8Payload" BeforeTargets="Build">'
                    '<Exec Command="cmd /c echo pwned &gt; R8MARKER.txt" /></Target></Project>')
    call('delphi_upload', {"path": _tgt, "offset": 0,
                           "chunkbase64": _b64.b64encode(_payload_xml.encode()).decode()})
    check('R8: el .targets con el payload se sube (upload no filtra extensiones)',
          os.path.exists(_tgt), _tgt)
    for macro, label in (
        ('$(MSBuildProjectDirectory)\\r8payload.targets', 'MSBuildProjectDirectory'),
        ('$(MSBuildThisFileDirectory)r8payload.targets', 'MSBuildThisFileDirectory'),
        ('r8payload.targets', 'relativo simple'),
    ):
        upload_dproj(_clean.replace('</Project>',
            '<Import Project="%s" />' % macro + '</Project>'))
        out = build_no_allowrun(_holad)
        check('R8 CRITICAL (%s): build RECHAZADO' % label, 'RECHAZADO' in out, out[:180])
        check('R8 CRITICAL (%s): el payload importado NO se ejecuto' % label,
              not os.path.exists(_m8), _m8)
    # namespace-prefixed element must not slip past the literal check
    upload_dproj(_clean.replace('</Project>',
        '<msb:Target xmlns:msb="http://schemas.microsoft.com/developer/msbuild/2003" '
        'Name="X" BeforeTargets="Build"><msb:Exec Command="cmd /c echo x" /></msb:Target></Project>'))
    out = build_no_allowrun(_holad)
    check('R8: <msb:Target> con namespace tambien RECHAZADO', 'RECHAZADO' in out, out[:180])
    os.remove(_tgt)

    # and the untouched project still builds fine (no false positive)
    upload_dproj(_clean)
    out = build_no_allowrun(_holad)
    check('R7: un .dproj NORMAL sigue compilando (sin falso positivo)',
          'RECHAZADO' not in out, out[:200])

    # --- R9 (field): the hazard scanner no longer refuses an INERT custom
    #     <Target>. Refusing EVERY target was a false positive as serious as a
    #     hole - it broke legitimate projects (post-build copy, Authenticode
    #     signing). Only tasks that EXECUTE or PLANT/DELETE files are refused. ---
    upload_dproj(_clean.replace('</Project>',
        '<Target Name="R9Info" AfterTargets="Build">'
        '<Message Text="solo un mensaje" Importance="high" /></Target></Project>'))
    out = build_no_allowrun(_holad)
    check('R9 FP: <Target> INERTE (solo <Message>) NO se rechaza',
          'el proyecto contiene' not in out, out[:200])
    # a <Target> that PLANTS/DELETES a file by arbitrary path IS still refused,
    # target wrapper or not - those are the real "runs/writes during build".
    for task, label in (
        ('<Copy SourceFiles="a.txt" DestinationFolder="C:\\Windows" />', 'copy'),
        ('<WriteLinesToFile File="C:\\evil.bat" Lines="calc" />', 'writelinestofile'),
        ('<MakeDir Directories="C:\\pwn" />', 'makedir'),
        ('<Delete Files="C:\\Windows\\notepad.exe" />', 'delete'),
    ):
        upload_dproj(_clean.replace('</Project>',
            '<Target Name="Plant" BeforeTargets="Build">' + task + '</Target></Project>'))
        out = build_no_allowrun(_holad)
        check('R9: <Target> con <%s> (planta/borra) RECHAZADO' % label,
              'RECHAZADO' in out and 'contiene' in out, out[:180])
    # AllowBuildScripts is a SEPARATE opt-in from AllowRun: a trusted project
    # with an <Exec> (e.g. signing) may build WITHOUT enabling delphi_run.
    _sign = _clean.replace('</Project>',
        '<Target Name="Sign" AfterTargets="Build">'
        '<Exec Command="cmd /c echo firmado" /></Target></Project>')
    upload_dproj(_sign)
    out = oneshot('delphi_build', {"project": _holad, "platform": "Win64",
                                   "config": "Debug", "target": "Build"},
                  {'DELPHI_MCP_ALLOW_BUILD_SCRIPTS': '1'}, 600)
    check('R9: AllowBuildScripts deja compilar un <Target><Exec> de confianza',
          'el proyecto contiene' not in out, out[:200])
    # ...but AllowBuildScripts is NOT AllowRun: delphi_run stays OFF with it.
    out = oneshot('delphi_run', {"path": os.path.join(INSIDE, 'Hola', 'Win64', 'Debug', 'Hola.exe')},
                  {'DELPHI_MCP_ALLOW_BUILD_SCRIPTS': '1'}, 30)
    check('R9: AllowBuildScripts NO enciende delphi_run (sigue deshabilitado)',
          'deshabilitada por diseno' in out, out[:200])
    upload_dproj(_clean)  # leave a clean project for later sections

# --- B0c: Windows name-normalization bypasses (trailing dot/space, ADS) ---
for probe, label in ((INSIDE + '\\Evade.pas.', 'punto final'),
                     (INSIDE + '\\Evade2.pas ', 'espacio final'),
                     (INSIDE + '\\Evade3.pas::$DATA', 'flujo ADS')):
    out = call('delphi_textedit', {"path": probe, "create": True, "content": "x"})
    check('bypass %s: textedit lo rechaza' % label, 'RECHAZADO' in out, out[:120])
check('bypass: ningun .pas colado en disco',
      not any(f.startswith('Evade') for f in os.listdir(INSIDE)),
      os.listdir(INSIDE))
out = call('delphi_fetch', {"path": IN_PAS})
check('fetch: dentro permitido', 'chunkBase64' in out, out[:120])

# --- library read zone: RTL/component sources are READABLE despite the jail,
#     but NEVER writable ---
RTL = None
for cand in (r'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\sys\System.SysUtils.pas',
             r'C:\Program Files (x86)\Embarcadero\Studio\23.0\source\rtl\sys\System.SysUtils.pas'):
    if os.path.exists(cand):
        RTL = cand
        break
if RTL:
    out = call('delphi_read', {"path": RTL, "fromline": 1, "toline": 5})
    check('lib: leer fuente RTL permitido pese a la jaula', not denied(out) and '|' in out, out[:150])
    out = call('delphi_edit', {"path": RTL, "old": "interface", "new": "x"})
    check('lib: EDITAR fuente RTL vetado siempre', denied(out), out[:150])
    out = call('delphi_search', {"root": os.path.dirname(RTL), "query": "SysUtils",
                                 "maxresults": 3})
    check('lib: buscar en fuentes RTL permitido', not denied(out), out[:150])
else:
    print('SKIP - lib: fuentes RTL no encontradas en esta maquina')

# --- GetIt packages / catalog repository: the library zone must cover them
#     (the Library Search Path uses $(BDSCatalogRepository*) macros, and the
#     useful material - sources, SDKs - hangs off the repository root) ---
CAT = None
for cand in (r'C:\Users\Public\Documents\Embarcadero\Studio\37.0\CatalogRepository',
             r'C:\Users\Public\Documents\Embarcadero\Studio\23.0\CatalogRepository'):
    if os.path.isdir(cand):
        CAT = cand
        break
if CAT:
    out = call('delphi_list', {"root": CAT, "pattern": "*"})
    check('lib: repositorio de catalogo (paquetes GetIt) legible', not denied(out), out[:150])
    pkg = None
    for d in os.listdir(CAT):
        src = os.path.join(CAT, d)
        if os.path.isdir(src) and d.lower().startswith('fmxlinux'):
            pkg = src
            break
    if pkg:
        out = call('delphi_list', {"root": pkg, "pattern": "*.pas"})
        check('lib: fuentes de un paquete GetIt (FmxLinux) legibles',
              not denied(out) and '.pas' in out, out[:150])
        out = call('delphi_edit', {"path": os.path.join(pkg, 'x.pas'), "createunit": True})
        check('lib: ESCRIBIR en un paquete GetIt vetado', denied(out), out[:150])
    else:
        print('SKIP - lib: FmxLinux no instalado en esta maquina')
else:
    print('SKIP - lib: repositorio de catalogo no encontrado')

# --- git args: file-writing / path-reading options rejected on read commands
#     (a jail escape usable even read-only; found in the field audit) ---
def gitclean(out):
    return 'RECHAZADO' in out and 'opcion de git' in out

# --output writes a file: even a "read" command (diff/show) must refuse it,
# whether the target is inside the jail or an absolute path outside it.
for tgt, label in ((os.path.join(INSIDE, 'PWNED.txt'), 'dentro jaula'),
                   (os.path.join(OUTSIDE, 'PWNED.txt'), 'fuera jaula (absoluto)')):
    out = call('delphi_git', {"repo": INSIDE, "command": "diff",
                              "args": "--output=" + tgt})
    check('git escape: diff --output %s rechazado' % label, gitclean(out), out[:150])
    check('git escape: %s no se escribio' % label, not os.path.exists(tgt), tgt)
out = call('delphi_git', {"repo": INSIDE, "command": "show",
                          "args": "--output=" + os.path.join(INSIDE, 'PWNED2.txt')})
check('git escape: show --output rechazado', gitclean(out), out[:150])
check('git escape: show output no escrito',
      not os.path.exists(os.path.join(INSIDE, 'PWNED2.txt')), 'PWNED2')
# --no-index reads two arbitrary paths (content leak outside the repo)
out = call('delphi_git', {"repo": INSIDE, "command": "diff",
                          "args": "--no-index " + OUT_PAS + " " + IN_PAS})
check('git escape: diff --no-index rechazado', gitclean(out), out[:150])
# -c arbitrary config (core.pager/sshCommand -> RCE) stays refused
out = call('delphi_git', {"repo": INSIDE, "command": "log", "args": "-c core.pager=calc"})
check('git escape: -c config rechazado', gitclean(out), out[:150])
# --config is -c's long form on clone: must be refused too (third-party review)
out = call('delphi_git', {"repo": INSIDE, "command": "clone",
                          "message": "https://example.com/x.git",
                          "args": "--config core.sshCommand=calc.exe"})
check('git escape: clone --config rechazado', gitclean(out), out[:150])
# --separate-git-dir / --template / --git-dir / --work-tree redirect git I/O
for opt in ('--separate-git-dir=C:\\evil', '--template=C:\\evil',
            '--git-dir=C:\\evil', '--work-tree=C:\\evil'):
    out = call('delphi_git', {"repo": INSIDE, "command": "clone",
                              "message": "https://example.com/x.git", "args": opt})
    check('git escape: %s rechazado' % opt.split('=')[0], gitclean(out), out[:120])
# a legitimate read still works (no false positive)
out = call('delphi_git', {"repo": INSIDE, "command": "log", "args": "--oneline -5"})
check('git: log --oneline sigue permitido (sin falso positivo)', not gitclean(out), out[:120])

# --- the gate must read an argument the way the BINDER resolves it ----------
# The gate used TJSONObject.TryGetValue (case-SENSITIVE) while the RTTI binder
# normalizes (lower-case, '_' ignored): sending "Args" made the gate inspect
# nothing and the handler receive the real value. Every gate decision was
# bypassable by spelling the parameter differently.
for spelling in ('Args', 'ARGS', 'a_rgs'):
    _p = os.path.join(INSIDE, 'PWNED_case_%s.txt' % spelling)
    out = call('delphi_git', {"repo": INSIDE, "command": "diff",
                              spelling: "--output=" + _p})
    check('gate: escape por mayusculas en "%s" rechazado' % spelling,
          gitclean(out), out[:130])
    check('gate: "%s" no escribio el fichero' % spelling,
          not os.path.exists(_p), _p)

# Two keys that normalize the SAME: the binder probes the declared casing
# first, so one value gets vetted and the other executed. Refused outright.
_dup = os.path.join(INSIDE, 'PWNED_dup.txt')
out = call('delphi_git', {"repo": INSIDE, "command": "diff",
                          "args": "--oneline", "Args": "--output=" + _dup})
check('gate: parametro duplicado (args + Args) rechazado',
      'RECHAZADO' in out and 'dos veces' in out, out[:150])
check('gate: el duplicado no escribio el fichero', not os.path.exists(_dup), _dup)

# --- delphi_build: platform/config/target reach a cmd.exe line -------------
# Unquoted in "rsvars.bat && msbuild ... /p:Platform=%s", so a metacharacter
# there is arbitrary execution that skips AllowRun, the jail AND the sandbox.
_holad = os.path.join(INSIDE, 'Hola', 'Hola.dproj')
for param, payload in (('platform', 'Win64 && cmd /c echo x > '),
                       ('config', 'Debug > '),
                       ('target', 'Build & cmd /c echo x > ')):
    _m = os.path.join(INSIDE, 'PWNED_build_%s.txt' % param)
    args = {"project": _holad, "platform": "Win64", "config": "Debug",
            "target": "Build"}
    args[param] = payload + _m
    out = call('delphi_build', args, 300)
    check('build: inyeccion por "%s" rechazada' % param, 'RECHAZADO' in out, out[:130])
    check('build: inyeccion por "%s" no ejecuto nada' % param,
          not os.path.exists(_m), _m)

# anti-over-tightening: a project may declare its OWN configuration names
out = call('delphi_build', {"project": _holad, "platform": "Win64",
                            "config": "Release Demo", "target": "Make"}, 300)
check('build: una configuracion propia con espacio NO se rechaza',
      'RECHAZADO' not in out, out[:130])

# --- the workspace ROOT is the jail, not a file ----------------------------
# delete/move park their target in a trash folder created NEXT TO it: for a
# root that lands in the root's PARENT, outside the jail, taking the whole
# workspace with it.
for tool, args in (('delphi_delete', {"path": INSIDE}),
                   ('delphi_move', {"path": INSIDE, "dest": INSIDE + '2'})):
    out = call(tool, args)
    check('%s: el root mismo rechazado' % tool,
          'RECHAZADO' in out and 'WORKSPACE ROOT' in out, out[:150])
check('root: el workspace sigue existiendo', os.path.isdir(INSIDE), INSIDE)
check('root: no se creo papelera FUERA de la jaula',
      not os.path.exists(os.path.join(BASE, '__delphi-patch')), BASE)
# and deleting something INSIDE still works (no over-refusal)
_victim = os.path.join(INSIDE, 'Borrame.pas')
open(_victim, 'wb').write(SRC.replace('Dentro', 'Borrame').encode('cp1252'))
out = call('delphi_delete', {"path": _victim})
check('root: borrar un fichero DENTRO sigue permitido',
      'RECHAZADO' not in out and not os.path.exists(_victim), out[:130])

print()
print('== guard battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
