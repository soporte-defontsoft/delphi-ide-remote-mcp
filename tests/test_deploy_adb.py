"""E2E battery for the remote-deploy half: delphi_build target=Deploy and
the delphi_adb tool (v0.34).

Covers: the gate's vetting of profile/deviceid/address/device (one identifier
rule, both access levels), target=Deploy in the whitelist, the minimal
.deployproj + .dproj import generation for PAServer platforms (and that a
second run never duplicates the import), the Android deploy generation
(full apk staging map, AndroidManifest.template.xml seed, VerInfo fallback
in the .dproj), delphi_adb's read commands answering, its functional
refusals (no address / no apk / bad lines), and the read-only split
(discover/devices/logcat read, connect/disconnect/install write).

The apk itself (signing needs a healthy debug keystore) and the install on
a live device are field-validated, not battery-validated.

The happy deploy path (live PAServer / live device) is exercised in the
field, like the paserver battery does.

Usage:  python tests/test_deploy_adb.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green. Scaffolds into %TEMP%\\delphi-mcp-tests\\deploy-adb.
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, '..', 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'deploy-adb')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE, exist_ok=True)


class Server:
    def __init__(self, extra_args=None, env=None):
        e = dict(os.environ)
        e.update(env or {})
        self.proc = subprocess.Popen([EXE] + (extra_args or []), env=e,
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True,
                                     encoding='utf-8')
        self.q = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()
        self.rid = 10
        self.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "deploy-adb-battery", "version": "1"}}})
        assert self.recv(1, 20), 'no initialize response'
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _reader(self):
        for line in self.proc.stdout:
            line = line.strip()
            if line:
                self.q.put(line)

    def send(self, o):
        self.proc.stdin.write(json.dumps(o) + '\n')
        self.proc.stdin.flush()

    def recv(self, r, t=90):
        dl = time.time() + t
        while time.time() < dl:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == r:
                return m
        return None

    def call(self, name, args, t=90):
        self.rid += 1
        self.send({"jsonrpc": "2.0", "id": self.rid, "method": "tools/call",
                   "params": {"name": name, "arguments": args}})
        r = self.recv(self.rid, t)
        if r is None:
            return '(timeout)'
        if 'error' in r:
            return 'MCPERROR ' + json.dumps(r['error'])[:150]
        c = r['result'].get('content', [])
        return c[0].get('text', '') if c else '(no content)'

    def close(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


P = F = 0

def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:200])


srv = Server()

# ====================== delphi_adb: read commands ======================
out = srv.call('delphi_adb', {"command": "devices"}, t=60)
try:
    d = json.loads(out)
    check('adb devices: JSON con lista', isinstance(d.get('devices'), list), out[:200])
    check('adb devices: note guia connect y el deploy por build',
          'connect' in d.get('note', '') and 'delphi_build' in d.get('note', ''),
          out[:300])
except Exception:
    check('adb devices: parsea', False, out[:250])

out = srv.call('delphi_adb', {"command": "discover"}, t=60)
try:
    d = json.loads(out)
    check('adb discover: JSON con lista discovered',
          isinstance(d.get('discovered'), list), out[:200])
    check('adb discover: note explica el flujo connect / ip:port del developer',
          'connect' in d.get('note', ''), out[:300])
except Exception:
    check('adb discover: parsea', False, out[:250])

# logcat answers (with no device attached adb's own error text comes back;
# either way it must NOT be a refusal nor a protocol error)
out = srv.call('delphi_adb', {"command": "logcat", "lines": "50"}, t=90)
check('adb logcat: responde sin rechazo',
      'RECHAZADO' not in out and not out.startswith('MCPERROR'), out[:200])

# ====================== delphi_adb: dispatcher + functional refusals ======
out = srv.call('delphi_adb', {"command": "nonsense"})
check('adb command invalido: lista los diez comandos',
      'command debe ser' in out and 'discover' in out and 'run' in out
      and 'screenshot' in out and 'tap' in out and 'key' in out, out[:250])

out = srv.call('delphi_adb', {"command": "run"})
check('adb run sin app: rechazo con el nombre de paquete como camino',
      'RECHAZADO' in out and '"app"' in out, out[:250])

out = srv.call('delphi_adb', {"command": "screenshot"})
check('adb screenshot sin out: rechazo que guia a delphi_fetch',
      'RECHAZADO' in out and '"out"' in out and 'delphi_fetch' in out, out[:250])
out = srv.call('delphi_adb', {"command": "screenshot",
                              "out": os.path.join(BASE, 'captura.txt')})
check('adb screenshot out sin .png: rechazado', 'RECHAZADO' in out and '.png' in out,
      out[:200])
out = srv.call('delphi_adb', {"command": "tap"})
check('adb tap sin x/y: rechazo que guia al screenshot',
      'RECHAZADO' in out and 'screenshot' in out, out[:250])
out = srv.call('delphi_adb', {"command": "key", "key": "poweroff"})
check('adb key fuera de whitelist: rechazada con el vocabulario',
      'RECHAZADO' in out and 'back' in out and 'appswitch' in out, out[:250])

out = srv.call('delphi_adb', {"command": "connect"})
check('adb connect sin address: rechazo con formato ip:puerto',
      'RECHAZADO' in out and 'address' in out, out[:250])

out = srv.call('delphi_adb', {"command": "install"})
check('adb install sin apk: rechazo con camino (delphi_build)',
      'RECHAZADO' in out and 'apk' in out and 'delphi_build' in out, out[:250])

out = srv.call('delphi_adb', {"command": "install",
                              "apk": os.path.join(BASE, 'no-such.apk')})
check('adb install apk inexistente: error honesto',
      'no existe el .apk' in out, out[:250])

# a lost/absent device must SAY so with the recovery path, never look like
# an empty log (field: the EDA51's wifi adb drops itself after idle)
out = srv.call('delphi_adb', {"command": "logcat", "device": "ZZZ-NO-EXISTE",
                              "lines": "5"}, t=60)
check('adb dispositivo perdido: aviso SIN CONEXION con camino de reconexion',
      'SIN CONEXION' in out and 'connect' in out and 'discover' in out,
      out[:300])

out = srv.call('delphi_adb', {"command": "logcat", "lines": "0"})
check('adb logcat lines=0: rechazado (1-5000)', 'RECHAZADO' in out and '5000' in out,
      out[:200])
out = srv.call('delphi_adb', {"command": "logcat", "lines": "99999"})
check('adb logcat lines=99999: rechazado', 'RECHAZADO' in out, out[:200])

# ====================== gate: the device-token rule (both sinks) ==========
out = srv.call('delphi_adb', {"command": "connect", "address": "10.0.0.1:5555; rm -rf /"})
check('gate: address con metacaracteres rechazada',
      'RECHAZADO' in out and 'serial' in out, out[:250])

out = srv.call('delphi_adb', {"command": "logcat", "device": "ser ial\"x"})
check('gate: device sucio rechazado TAMBIEN en comando read',
      'RECHAZADO' in out and 'serial' in out, out[:250])

out = srv.call('delphi_adb', {"command": "connect", "address": "a" * 65})
check('gate: address de mas de 64 chars rechazada', 'RECHAZADO' in out, out[:200])

out = srv.call('delphi_adb', {"command": "run", "app": "com.x; rm -rf /"})
check('gate: app (paquete) con metacaracteres rechazada',
      'RECHAZADO' in out and 'paquete' in out, out[:250])

out = srv.call('delphi_adb', {"command": "tap", "x": "100; reboot", "y": "5"})
check('gate: coordenada con metacaracteres rechazada',
      'RECHAZADO' in out and 'coordenada' in out, out[:250])
out = srv.call('delphi_adb', {"command": "key", "key": "back;reboot"})
check('gate: key con metacaracteres rechazada', 'RECHAZADO' in out, out[:200])

out = srv.call('delphi_build', {"project": "x.dproj", "platform": "Win64",
                                "profile": "bad name!"})
check('gate build: profile sucio rechazado (misma regla que paserver name)',
      'RECHAZADO' in out and 'nombre' in out, out[:250])

out = srv.call('delphi_build', {"project": "x.dproj", "platform": "Win64",
                                "deviceid": "x;y"})
check('gate build: deviceid sucio rechazado (misma regla que adb)',
      'RECHAZADO' in out and 'serial' in out, out[:250])

out = srv.call('delphi_build', {"project": "x.dproj", "platform": "Win64",
                                "target": "Deploy;Evil"})
check('gate build: target compuesto rechazado (whitelist exacta)',
      'RECHAZADO' in out and 'target' in out, out[:250])

# ====================== deploy: manifest + import generation ==============
CDIR = os.path.join(BASE, 'DeployCli')
out = srv.call('delphi_create', {"kind": "project-console", "dir": CDIR,
                                 "name": "DeployCli"})
check('create: proyecto console para deploy', out.startswith('CREADO'), out[:150])

DPROJ = os.path.join(CDIR, 'DeployCli.dproj')
DEPLOYPROJ = os.path.join(CDIR, 'DeployCli.deployproj')

# Deploy to a PAServer platform with a profile that does not exist: msbuild
# fails (no live PAServer here), but the manifest half must happen BEFORE.
out = srv.call('delphi_build', {"project": DPROJ, "platform": "Linux64",
                                "config": "Debug", "target": "Deploy",
                                "profile": "mcp-e2e-noprof"}, t=600)
check('deploy Linux64: genera el .deployproj minimo',
      os.path.isfile(DEPLOYPROJ), out[:200])
if os.path.isfile(DEPLOYPROJ):
    m = open(DEPLOYPROJ, encoding='ascii').read()
    check('deployproj: ProjectOutput + Deployment.targets + exec (Operation 1)',
          'ProjectOutput' in m and 'CodeGear.Deployment.targets' in m
          and '<Operation>1</Operation>' in m, m[:300])
    check('deployproj: ambos configs (Debug y Release)',
          "'Debug'" in m and "'Release'" in m, m[:300])
dproj = open(DPROJ, encoding='utf-8-sig').read()
check('dproj: linea de import del deployproj (la que escribe el IDE)',
      'MSBuildProjectName).deployproj' in dproj, dproj[-500:])
n_first = dproj.count('MSBuildProjectName).deployproj')

# second run: import NOT duplicated, existing manifest NOT touched
before = open(DEPLOYPROJ, 'rb').read() if os.path.isfile(DEPLOYPROJ) else b''
out = srv.call('delphi_build', {"project": DPROJ, "platform": "Linux64",
                                "config": "Debug", "target": "Deploy",
                                "profile": "mcp-e2e-noprof"}, t=600)
dproj2 = open(DPROJ, encoding='utf-8-sig').read()
check('deploy repetido: el import NO se duplica',
      dproj2.count('MSBuildProjectName).deployproj') == n_first,
      'antes=%d ahora=%d' % (n_first, dproj2.count('MSBuildProjectName).deployproj')))
check('deploy repetido: el .deployproj existente NO se toca',
      open(DEPLOYPROJ, 'rb').read() == before, DEPLOYPROJ)

# ====================== deploy Android: full staging generation ===========
FDIR = os.path.join(BASE, 'DeployFmx')
out = srv.call('delphi_create', {"kind": "project-fmx", "dir": FDIR,
                                 "name": "DeployFmx"})
check('create: proyecto FMX para el caso Android', out.startswith('CREADO'), out[:150])

# Android64 must be a declared platform for msbuild to compile it
out = srv.call('delphi_config', {"command": "add-platform",
                                 "project": os.path.join(FDIR, 'DeployFmx.dproj'),
                                 "platform": "Android64"})
check('config: Android64 anadida al proyecto FMX', 'ANADIDA' in out, out[:200])

# the run itself may or may not sign (machine keystore state) - the battery
# asserts the GENERATED artifacts, the apk is field-validated
out = srv.call('delphi_build', {"project": os.path.join(FDIR, 'DeployFmx.dproj'),
                                "platform": "Android64", "config": "Debug",
                                "target": "Deploy"}, t=600)
FDEPLOY = os.path.join(FDIR, 'DeployFmx.deployproj')
check('deploy Android: genera el .deployproj con el mapa de staging completo',
      os.path.isfile(FDEPLOY), out[:250])
if os.path.isfile(FDEPLOY):
    m = open(FDEPLOY, encoding='ascii').read()
    check('deployproj Android: manifest + so en arm64-v8a + iconos',
          'ProjectAndroidManifest' in m and 'arm64-v8a' in m
          and 'ic_launcher.png' in m, m[:300])
    check('deployproj Android: los stubs libnative salen de $(BDS), no inventados',
          m.count('libnative-activity.so') ==
          m.count('$(BDS)\\lib\\android\\debug\\'), m[:300])
check('deploy Android: siembra AndroidManifest.template.xml (semilla ObjRepos)',
      os.path.isfile(os.path.join(FDIR, 'AndroidManifest.template.xml')), out[:200])
fdproj = open(os.path.join(FDIR, 'DeployFmx.dproj'), encoding='utf-8-sig').read()
check('dproj Android: fallback VerInfo (package/minSdk) condicionado a vacio',
      'minSdkVersion' in fdproj and "'$(VerInfo_Keys)'==''" in fdproj, fdproj[-600:])
check('dproj Android: import del deployproj presente',
      'MSBuildProjectName).deployproj' in fdproj, fdproj[-400:])
try:
    d = json.loads(out)
    check('deploy Android: resultado declara el manifiesto generado',
          'deployManifest' in d and 'Android' in d.get('deployManifest', ''),
          out[:300])
except Exception:
    check('deploy Android: resultado parsea', False, out[:300])

srv.close()

# ====================== read-only split ===================================
ro = Server(['--readonly'])
out = ro.call('delphi_adb', {"command": "devices"}, t=60)
check('readonly: devices sigue abierto',
      'SOLO LECTURA' not in out and 'devices' in out, out[:200])
out = ro.call('delphi_adb', {"command": "logcat", "lines": "20"}, t=90)
check('readonly: logcat sigue abierto (debug del dispositivo es lectura)',
      'SOLO LECTURA' not in out, out[:200])
out = ro.call('delphi_adb', {"command": "connect", "address": "127.0.0.1:5555"})
check('readonly: connect rechazado', 'RECHAZADO' in out and 'SOLO LECTURA' in out,
      out[:250])
out = ro.call('delphi_adb', {"command": "disconnect", "address": "127.0.0.1:5555"})
check('readonly: disconnect rechazado', 'RECHAZADO' in out and 'SOLO LECTURA' in out,
      out[:250])
out = ro.call('delphi_adb', {"command": "install", "apk": "x.apk"})
check('readonly: install rechazado', 'RECHAZADO' in out and 'SOLO LECTURA' in out,
      out[:250])
out = ro.call('delphi_adb', {"command": "run", "app": "com.embarcadero.X"})
check('readonly: run rechazado (ejecutar en el dispositivo es write)',
      'RECHAZADO' in out and 'SOLO LECTURA' in out, out[:250])
out = ro.call('delphi_adb', {"command": "screenshot"})
check('readonly: screenshot sigue abierto (mirar es lectura)',
      'SOLO LECTURA' not in out and 'RECHAZADO' in out and '"out"' in out,
      out[:250])
out = ro.call('delphi_adb', {"command": "tap", "x": "1", "y": "1"})
check('readonly: tap rechazado', 'RECHAZADO' in out and 'SOLO LECTURA' in out,
      out[:250])
out = ro.call('delphi_adb', {"command": "key", "key": "back"})
check('readonly: key rechazada', 'RECHAZADO' in out and 'SOLO LECTURA' in out,
      out[:250])
ro.close()

# ====================== device allowlist ([Adb] AllowedDevices) ===========
# configured -> ONLY those targets, and every device-addressing command must
# name its device explicitly (an implicit target could be an unlisted one)
al = Server(env={'DELPHI_MCP_ADB_DEVICES': '10.9.9.9;SERIALX'})
out = al.call('delphi_adb', {"command": "devices"}, t=60)
check('allowlist: devices (listar) sigue abierto',
      'lista permitida' not in out and 'devices' in out, out[:200])
out = al.call('delphi_adb', {"command": "connect", "address": "192.168.1.163:5556"})
check('allowlist: connect a IP fuera de lista rechazado',
      'RECHAZADO' in out and 'lista permitida' in out, out[:250])
out = al.call('delphi_adb', {"command": "disconnect", "address": "10.9.9.9:5555"})
check('allowlist: address de la lista pasa la puerta (matchea por host)',
      'lista permitida' not in out and 'RECHAZADO' not in out, out[:200])
out = al.call('delphi_adb', {"command": "run", "app": "com.embarcadero.X"})
check('allowlist: comando sin device explicito rechazado',
      'RECHAZADO' in out and 'AllowedDevices' in out and 'device' in out,
      out[:250])
out = al.call('delphi_adb', {"command": "logcat", "device": "SERIALX", "lines": "5"},
              t=60)
check('allowlist: device serial de la lista pasa la puerta',
      'lista permitida' not in out and 'SOLO LECTURA' not in out, out[:200])
out = al.call('delphi_adb', {"command": "logcat", "device": "SERIAL-OTRO",
                             "lines": "5"})
check('allowlist: device fuera de lista rechazado TAMBIEN en comando read',
      'RECHAZADO' in out and 'lista permitida' in out, out[:250])
al.close()

# without the setting nothing changes (regression: the whole battery above
# ran unrestricted); one explicit probe that an arbitrary target passes
noal = Server()
out = noal.call('delphi_adb', {"command": "run", "app": "com.embarcadero.X"})
check('sin allowlist: device implicito sigue permitido (compatibilidad)',
      'AllowedDevices' not in out, out[:200])
noal.close()

print()
print('TOTAL: %d PASS, %d FAIL' % (P, F))
sys.exit(1 if F else 0)
