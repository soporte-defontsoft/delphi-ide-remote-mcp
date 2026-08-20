"""E2E battery for delphi_paserver over MCP stdio - the network half (v0.32).

Covers: the three read commands, the gate's argument vetting (name, host,
port, platform, password), add-profile writing a REAL profile via paclient
--local (password encrypted, never plaintext on disk), test-connection in its
two forms (profile handshake / raw TCP probe), read-only refusal of the write
commands, and the log masker (a password in the request body never reaches
the stderr log).

Usage:  python tests/test_paserver.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green. Creates ONE throwaway profile (mcp-e2e-paserver) in
%APPDATA%\\Embarcadero\\BDS\\<ver>\\ and deletes it at the end.
"""
import json, subprocess, threading, queue, time, os, sys, socket, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = os.path.join(REPO, 'src')
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

PROF_NAME = 'mcp-e2e-paserver'
PROF_PASSWORD = 'dummySecretE2E123'
# nothing must be listening here (refused fast = the failure path we want)
DEAD_PORT = '64219'


def profile_files():
    base = os.path.join(os.environ['APPDATA'], 'Embarcadero', 'BDS')
    return glob.glob(os.path.join(base, '*', PROF_NAME + '.profile'))


def cleanup_profile():
    for f in profile_files():
        try:
            os.remove(f)
        except OSError:
            pass


class Server:
    """One stdio MCP server process with its stderr captured for log checks."""
    def __init__(self, extra_args=None):
        self.proc = subprocess.Popen([EXE] + (extra_args or []),
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, encoding='utf-8')
        self.q = queue.Queue()
        self.stderr_lines = []
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._err_reader, daemon=True).start()
        self.rid = 10
        self.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "paserver-battery", "version": "1"}}})
        assert self.recv(1, 20), 'no initialize response'
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _reader(self):
        for line in self.proc.stdout:
            line = line.strip()
            if line:
                self.q.put(line)

    def _err_reader(self):
        for line in self.proc.stderr:
            self.stderr_lines.append(line.rstrip())

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
        print('FAIL -', name, '|', str(detail)[:170])


cleanup_profile()
srv = Server()

# --- the three read commands still answer (regression) ---
out = srv.call('delphi_paserver', {"command": "platforms"})
try:
    d = json.loads(out)
    check('platforms: JSON con lista', isinstance(d.get('platforms'), list), out[:150])
except Exception:
    check('platforms: parsea', False, out[:200])

out = srv.call('delphi_paserver', {"command": "packages"})
check('packages: lista el PAServer de Linux', 'LinuxPAServer' in out, out[:200])

out = srv.call('delphi_paserver', {"command": "profiles"})
try:
    d = json.loads(out)
    check('profiles: JSON con lista', isinstance(d.get('profiles'), list), out[:150])
except Exception:
    check('profiles: parsea', False, out[:200])

# --- dispatcher: unknown command names the two new ones ---
out = srv.call('delphi_paserver', {"command": "nonsense"})
check('command invalido: menciona add-profile y test-connection',
      'add-profile' in out and 'test-connection' in out, out[:200])

# --- gate vetting (argument filter, BOTH access levels) ---
out = srv.call('delphi_paserver', {"command": "add-profile", "name": "bad name!",
                                   "host": "127.0.0.1", "password": "x"})
check('gate: nombre con espacio/simbolo rechazado', 'RECHAZADO' in out and 'nombre' in out, out[:200])

out = srv.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                   "host": "127.0.0.1; rm -rf /", "password": "x"})
check('gate: host con metacaracteres rechazado', 'RECHAZADO' in out and 'host' in out, out[:200])

out = srv.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                   "host": "127.0.0.1", "port": "99999", "password": "x"})
check('gate: puerto fuera de rango rechazado', 'RECHAZADO' in out and 'puerto' in out, out[:200])

out = srv.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                   "host": "127.0.0.1", "platform": "Commodore64", "password": "x"})
check('gate: plataforma desconocida rechazada', 'RECHAZADO' in out and 'paclient' in out, out[:200])

out = srv.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                   "host": "127.0.0.1", "password": 'has"quote'})
check('gate: password con comillas rechazada', 'RECHAZADO' in out and 'password' in out, out[:200])

# --- add-profile: functional validation of required params ---
out = srv.call('delphi_paserver', {"command": "add-profile", "host": "127.0.0.1",
                                   "password": "x"})
check('add-profile sin name: pide name', 'RECHAZADO' in out and '"name"' in out, out[:200])

out = srv.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                   "host": "127.0.0.1"})
check('add-profile sin password: pide password', 'RECHAZADO' in out and '"password"' in out, out[:200])

# --- add-profile happy path: real profile written by paclient --local ---
out = srv.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                   "host": "127.0.0.1", "port": DEAD_PORT,
                                   "password": PROF_PASSWORD, "platform": "Linux64"},
               t=60)
try:
    d = json.loads(out)
    check('add-profile: responde JSON con profile/platform',
          d.get('profile') == PROF_NAME and d.get('platform') == 'Linux64', out[:250])
    check('add-profile: note guia el siguiente paso', 'test-connection' in d.get('note', ''), out[:250])
except Exception:
    check('add-profile: parsea', False, out[:300])

files = profile_files()
check('add-profile: el .profile existe en APPDATA', len(files) == 1, files)
if files:
    content = open(files[0], encoding='utf-8-sig').read()
    check('add-profile: password CIFRADA (no plaintext)',
          PROF_PASSWORD not in content and 'Profile_password' in content, content[:300])
    check('add-profile: host y puerto en el perfil',
          '127.0.0.1' in content and DEAD_PORT in content, content[:300])

# --- profiles now lists it ---
out = srv.call('delphi_paserver', {"command": "profiles"})
check('profiles: lista el perfil nuevo', PROF_NAME in out, out[:200])

# --- test-connection with profile: dead port -> connected false, E0003 ---
out = srv.call('delphi_paserver', {"command": "test-connection", "name": PROF_NAME}, t=90)
try:
    d = json.loads(out)
    check('test-connection perfil muerto: connected=false', d.get('connected') is False, out[:250])
    check('test-connection: trae el output de paclient', 'E0003' in d.get('paclientOutput', ''), out[:300])
except Exception:
    check('test-connection: parsea', False, out[:300])

# --- test-connection with unknown profile ---
out = srv.call('delphi_paserver', {"command": "test-connection", "name": "no-such-profile"})
check('test-connection perfil inexistente: rechazo con camino',
      'RECHAZADO' in out and 'add-profile' in out, out[:250])

# --- raw TCP probe: closed port ---
out = srv.call('delphi_paserver', {"command": "test-connection", "host": "127.0.0.1",
                                   "port": DEAD_PORT}, t=60)
try:
    d = json.loads(out)
    check('probe TCP puerto cerrado: tcpReachable=false', d.get('tcpReachable') is False, out[:250])
    check('probe TCP: note con diagnostico NAT/firewall', 'NAT' in d.get('note', ''), out[:300])
except Exception:
    check('probe TCP: parsea', False, out[:300])

# --- raw TCP probe: open port (throwaway local listener) ---
lst = socket.socket()
lst.bind(('127.0.0.1', 0))
lst.listen(1)
open_port = str(lst.getsockname()[1])
out = srv.call('delphi_paserver', {"command": "test-connection", "host": "127.0.0.1",
                                   "port": open_port}, t=60)
lst.close()
try:
    d = json.loads(out)
    check('probe TCP puerto abierto: tcpReachable=true', d.get('tcpReachable') is True, out[:250])
except Exception:
    check('probe TCP abierto: parsea', False, out[:300])

# --- log masker: the password must NOT appear in the stderr log ---
time.sleep(0.5)
leaked = [l for l in srv.stderr_lines if PROF_PASSWORD in l]
masked = [l for l in srv.stderr_lines if '"password":"***"' in l.replace(' ', '')]
check('log: la password NUNCA aparece en el log', not leaked, leaked[:2])
check('log: la peticion se loguea enmascarada', len(masked) >= 1,
      [l[:120] for l in srv.stderr_lines if 'add-profile' in l][:2])

srv.close()

# --- read-only process: write commands refused, reads pass ---
ro = Server(['--readonly'])
out = ro.call('delphi_paserver', {"command": "platforms"})
check('readonly: platforms sigue abierto', 'platforms' in out and 'RECHAZADO' not in out, out[:150])
out = ro.call('delphi_paserver', {"command": "add-profile", "name": PROF_NAME,
                                  "host": "127.0.0.1", "password": "x"})
check('readonly: add-profile rechazado', 'RECHAZADO' in out and 'SOLO LECTURA' in out, out[:250])
out = ro.call('delphi_paserver', {"command": "test-connection", "host": "127.0.0.1",
                                  "port": DEAD_PORT})
check('readonly: test-connection rechazado', 'RECHAZADO' in out and 'SOLO LECTURA' in out, out[:250])
ro.close()

cleanup_profile()
check('cleanup: perfil de prueba eliminado', not profile_files(), profile_files())

print()
print('TOTAL: %d PASS, %d FAIL' % (P, F))
sys.exit(1 if F else 0)
