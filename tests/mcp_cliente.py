# -*- coding: utf-8 -*-
"""EL cliente de las baterias: preparar su carpeta, arrancar el servidor,
hablarle MCP (stdio o HTTP) y contar los checks.

Hasta el 26-sep-2026 cada bateria llevaba su propia copia: 82 check(), 71
call() -como mucho tres iguales-, 40 send()/recv() y 33 rpc(). Y 34 de las 37
que arrancan un servidor HTTP dormian un plazo FIJO (2,3-3 s) en vez de
esperar al puerto: con la maquina cargada, la puerta de release salio roja
por eso (test_round20, 26-sep). Un arreglo en una copia no llegaba a las
demas; aqui vive una vez.

No es una bateria (no empieza por test_): run_all no la ejecuta.
"""
import json, os, queue, shutil, socket, stat, subprocess, sys, tempfile, threading, time
import urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE_COMPILADO = os.path.join(REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
# La raiz temporal que comparten todas las baterias (run_all la barre).
RAIZ = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests')
PROTOCOLO = '2025-06-18'


# ---------------------------------------------------------------- carpeta

def exe_origen():
    """El exe bajo prueba: el primer argumento de la bateria, o el compilado."""
    return sys.argv[1] if len(sys.argv) > 1 else EXE_COMPILADO


def borra(ruta):
    """Borra un arbol aunque tenga ficheros de SOLO LECTURA (los objetos de un
    .git los son): rmtree con ignore_errors los dejaba ahi, y la pasada
    siguiente de la bateria reventaba en makedirs (medido 2026-09-26 en
    test_v012, 148 objetos). Un enlace se quita como enlace, nunca lo de detras."""
    if os.path.isjunction(ruta) or os.path.islink(ruta):
        if os.path.isdir(ruta):
            os.rmdir(ruta)
        else:
            os.remove(ruta)
        return
    if not os.path.exists(ruta):
        return

    def quita_ro(func, p, _exc):
        try:
            os.chmod(p, stat.S_IWRITE)
            func(p)
        except OSError:
            pass
    shutil.rmtree(ruta, onexc=quita_ro)


def carpeta(nombre):
    """<raiz temporal>\\<nombre>, vacia: lo que dejo una pasada anterior no
    puede sostener a esta. Si no se puede vaciar, lo dice (no sigue encima)."""
    base = os.path.join(RAIZ, nombre)
    # Unos intentos: en Windows un proceso que acaba de salir (git, el propio
    # servidor) suelta sus handles con un momento de retraso.
    for _ in range(10):
        borra(base)
        if not os.path.exists(base):
            break
        time.sleep(0.5)
    if os.path.exists(base):
        raise RuntimeError('no puedo vaciar %s (algo lo tiene abierto?)' % base)
    os.makedirs(base)
    return base


CONVERSOR = 'DelphiStyleConvert.exe'
CONVERSOR_COMPILADO = os.path.join(REPO, 'src', 'StyleConvert', 'Compiled', 'Win64', 'Release', CONVERSOR)


def copia_exe(dest_dir, src=None, con_conversor=False):
    """Copia el servidor a dest_dir y devuelve la ruta de la copia: cada
    bateria corre el suyo, con su settings.ini, sus logs y su __delphi-temp.
    con_conversor: delphi_styles necesita DelphiStyleConvert.exe AL LADO del
    servidor; va el que acompane al exe bajo prueba (run_all lo pone junto a
    su copia limpia) o, si no lo trae, el compilado de src/StyleConvert."""
    os.makedirs(dest_dir, exist_ok=True)
    origen = src or exe_origen()
    exe = os.path.join(dest_dir, 'DelphiLspMcp.exe')
    shutil.copy(origen, exe)
    if con_conversor:
        junto = os.path.join(os.path.dirname(os.path.abspath(origen)), CONVERSOR)
        shutil.copy(junto if os.path.exists(junto) else CONVERSOR_COMPILADO,
                    os.path.join(dest_dir, CONVERSOR))
    return exe


# ---------------------------------------------------------------- arranque

def puerto_libre():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def espera_puerto(puerto, proc=None, segundos=30):
    """True en cuanto 127.0.0.1:puerto acepta conexiones; False si se agota
    el plazo o si proc (el servidor) muere antes. Sustituye al sleep fijo."""
    fin = time.time() + segundos
    while time.time() < fin:
        if proc is not None and proc.poll() is not None:
            return False
        try:
            with socket.create_connection(('127.0.0.1', puerto), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def lanza_http(exe, puerto=None, env=None, args=(), segundos=30, **popen):
    """Arranca exe --http [puerto] y ESPERA a que escuche. Sin puerto, el que
    diga su settings.ini: entonces hay que pasar el que se espera en
    'espera_en'. Devuelve el proceso; si no llega a escuchar, lo mata y
    lanza RuntimeError con el motivo (la bateria lo ve, no un sleep mudo)."""
    espera_en = popen.pop('espera_en', puerto)
    cmd = [exe, '--http'] + ([str(puerto)] if puerto is not None else []) + list(args)
    popen.setdefault('stdout', subprocess.DEVNULL)
    popen.setdefault('stderr', subprocess.DEVNULL)
    proc = subprocess.Popen(cmd, env=env, **popen)
    if not espera_puerto(espera_en, proc, segundos):
        murio = proc.poll()
        try:
            proc.kill()
        except Exception:
            pass
        raise RuntimeError('el servidor no escucha en %s tras %d s (%s)' % (
            espera_en, segundos, 'murio con %s' % murio if murio is not None else 'sigue sin abrir'))
    return proc


# ---------------------------------------------------------------- contador

P = F = 0


def check(name, ok, detail=''):
    """PASS/FAIL con el formato que cuenta run_all (una linea por check)."""
    global P, F
    if ok:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        # en UNA linea: un detalle con saltos partiria el FAIL, y una linea suya
        # que empezara por PASS/FAIL le cambiaria la cuenta a run_all
        print('  FAIL', name, '|', ' '.join(str(detail).splitlines())[:300])
    return ok


def fin(titulo):
    """El recuento de la bateria y su codigo de salida: 1 si fallo algo."""
    print()
    print('== %s: %d PASS / %d FAIL ==' % (titulo, P, F))
    sys.exit(1 if F else 0)


# ---------------------------------------------------------------- respuestas

def texto(msg, respaldo_json=False):
    """El texto de una respuesta de tools/call: content[0].text; 'MCPERROR
    <error>' si el JSON-RPC trae error; '(timeout)' si no llego. Sin texto:
    '(no content)', o el mensaje entero en JSON (recortado) con respaldo_json,
    que es lo que varias baterias ensenaban en el detalle de un FAIL."""
    if msg is None:
        return '(timeout)'
    if 'error' in msg:
        return 'MCPERROR ' + json.dumps(msg['error'])[:300]
    c = (msg.get('result') or {}).get('content') or []
    if c and 'text' in c[0]:
        return c[0]['text']
    return json.dumps(msg)[:400] if respaldo_json else '(no content)'


def entorno(extra=None):
    """El entorno de un servidor de prueba: el de esta maquina SIN las
    DELPHI_MCP_* de quien lanza la bateria -una jaula, un token o una lista
    heredados cambiaban lo que se mide sin que la bateria lo supiera-, mas lo
    que la bateria ponga en extra."""
    env = {k: v for k, v in os.environ.items() if not k.upper().startswith('DELPHI_MCP_')}
    env.update(extra or {})
    return env


def como_json(t):
    """El texto de una tool como objeto; {} si no lo es."""
    try:
        v = json.loads(t, strict=False)
        return v if isinstance(v, dict) else {}
    except Exception:
        return {}


# ---------------------------------------------------------------- stdio

class Stdio:
    """Un servidor en modo terminal stdio, como lo lanza un cliente local.

    args: argumentos del exe (--readonly...). t: el plazo por defecto de cada
    peticion de ESTE cliente. protocolo: el protocolVersion que se presenta.
    lee_stderr: el log del servidor (stderr en modo terminal) se recoge en
    self.errores -una tuberia que nadie lee acaba bloqueando al servidor-.
    respaldo_json: ver texto(). self.init es la respuesta del initialize."""

    def __init__(self, exe, env=None, nombre='bateria', cwd=None, stderr=subprocess.DEVNULL,
                 inicializa=True, args=(), t=120, protocolo=None, lee_stderr=False,
                 respaldo_json=False):
        self.t = t
        self.protocolo = protocolo or PROTOCOLO
        self.respaldo_json = respaldo_json
        self.errores = []
        self.p = subprocess.Popen([exe] + list(args), env=env, cwd=cwd, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE if lee_stderr else stderr,
                                  text=True, encoding='utf-8', errors='replace')
        self.q = queue.Queue()
        self.rid = 10
        self._lock = threading.Lock()
        self.init = None
        threading.Thread(target=self._lee, daemon=True).start()
        if lee_stderr:
            threading.Thread(target=self._lee_stderr, daemon=True).start()
        if inicializa:
            self.inicializa(nombre)

    def _lee(self):
        for line in self.p.stdout:
            line = line.strip()
            if line:
                self.q.put(line)

    def _lee_stderr(self):
        for line in self.p.stderr:
            self.errores.append(line.rstrip('\r\n'))

    def send(self, o):
        self.p.stdin.write((o if isinstance(o, str) else json.dumps(o)) + '\n')
        self.p.stdin.flush()

    def recv(self, rid, t=None):
        dl = time.time() + (self.t if t is None else t)
        while time.time() < dl:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == rid:
                return m
        return None

    def inicializa(self, nombre='bateria', capacidades=None):
        self.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": self.protocolo, "capabilities": capacidades or {},
            "clientInfo": {"name": nombre, "version": "1"}}})
        self.init = self.recv(1)
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return self.init

    def request(self, method, params=None, t=None):
        """Una peticion cualquiera; devuelve el mensaje de respuesta o None.
        Cada peticion lleva y espera SU id; pero la cola es una, asi que para
        rafagas desde varios hilos, un Stdio por hilo."""
        with self._lock:
            self.rid += 1
            rid = self.rid
        o = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            o['params'] = params
        self.send(o)
        return self.recv(rid, t)

    def call_msg(self, name, args, t=None):
        return self.request('tools/call', {"name": name, "arguments": args}, t)

    def call(self, name, args, t=None):
        """El texto de la tool (ver texto())."""
        return texto(self.call_msg(name, args, t), self.respaldo_json)

    def cierra(self, t=20):
        """Fin de stdin = el cliente se fue: salida LIMPIA; si no sale, se mata."""
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(t)
        except subprocess.TimeoutExpired:
            self.p.kill()

    def mata(self):
        try:
            self.p.kill()
        except Exception:
            pass


# ---------------------------------------------------------------- http

ACCEPT_STREAMABLE = 'application/json, text/event-stream'


def post(url, body, token=None, sid=None, accept=ACCEPT_STREAMABLE, t=120, cabeceras=None):
    """POST crudo a url: (status, cabeceras, texto). Un 4xx/5xx NO lanza: es
    una respuesta mas que la bateria mira. accept es lo que pide un cliente
    streamable-HTTP; una bateria que prueba el JSON a secas pasa el suyo."""
    h = {'Content-Type': 'application/json', 'Accept': accept}
    if token:
        h['Authorization'] = 'Bearer ' + token
    if sid:
        h['Mcp-Session-Id'] = sid
    if cabeceras:
        h.update(cabeceras)
    data = body if isinstance(body, (bytes, str)) else json.dumps(body)
    if isinstance(data, str):
        data = data.encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=h, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=t) as r:
            return r.status, r.headers, r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode('utf-8', 'replace')


# El sid por defecto de una llamada: la sesion PROPIA del cliente. Un sid
# vacio pasado a proposito (el session() de otro agente que fallo) no cae en
# silencio a la ultima sesion de este cliente -esa llamada hablaria como otro
# agente-: lanza. Visto al pasar test_identity/test_round15 (26-sep).
PROPIA = object()


class Http:
    """Cliente Streamable HTTP contra http://127.0.0.1:<puerto>/mcp.

    t: plazo por defecto de cada peticion de ESTE cliente. protocolo: el
    protocolVersion que se presenta. respaldo_json: ver texto(). self.init
    es la respuesta del initialize (session()). sid=... en una llamada usa
    otra sesion solo para esa llamada."""

    def __init__(self, puerto, token=None, ruta='/mcp', host='127.0.0.1', t=120,
                 protocolo=None, respaldo_json=False):
        self.url = 'http://%s:%d%s' % (host, puerto, ruta)
        self.token = token
        self.sid = None
        self.rid = 100
        self.t = t
        self.protocolo = protocolo or PROTOCOLO
        self.respaldo_json = respaldo_json
        self.init = None
        self._lock = threading.Lock()

    def _sid(self, sid):
        if sid is PROPIA:
            return self.sid
        if not sid:
            raise RuntimeError('sid vacio: el session() de ese agente no dio sesion')
        return sid

    def post(self, body, sid=PROPIA, token=None, t=None, cabeceras=None, accept=ACCEPT_STREAMABLE):
        """POST crudo a este servidor (ver post()); el token y la sesion de
        este cliente salvo que se pasen otros."""
        return post(self.url, body, self.token if token is None else token,
                    self._sid(sid), accept, self.t if t is None else t, cabeceras)

    @staticmethod
    def mensajes(raw):
        """Los mensajes JSON-RPC de una respuesta (SSE 'data:' o JSON suelto)."""
        msgs = []
        for l in raw.splitlines():
            if l.startswith('data:'):
                try:
                    msgs.append(json.loads(l[5:].strip()))
                except Exception:
                    pass
        if not msgs:
            try:
                v = json.loads(raw)
                msgs = v if isinstance(v, list) else [v]
            except Exception:
                pass
        return msgs

    def rpc(self, body, sid=PROPIA, t=None):
        """(mensajes, session-id) como las baterias de siempre."""
        st, h, raw = self.post(body, sid, t=t)
        return self.mensajes(raw), (h.get('Mcp-Session-Id') if h else None)

    def session(self, nombre='bateria', capacidades=None):
        """initialize + initialized; deja el session-id puesto y lo devuelve
        (la respuesta del initialize queda en self.init)."""
        self.sid = None
        msgs, sid = self.rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": self.protocolo, "capabilities": capacidades or {},
            "clientInfo": {"name": nombre, "version": "1"}}})
        self.init = next((m for m in msgs if m.get('id') == 1), None)
        self.sid = sid
        self.rpc({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return sid

    def request(self, method, params=None, t=None, sid=PROPIA):
        """Seguro entre hilos: cada peticion lleva y busca SU id."""
        with self._lock:
            self.rid += 1
            rid = self.rid
        o = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            o['params'] = params
        msgs, _ = self.rpc(o, sid=sid, t=t)
        for m in msgs:
            if m.get('id') == rid:
                return m
        return None

    def call_msg(self, name, args, t=None, sid=PROPIA):
        return self.request('tools/call', {"name": name, "arguments": args}, t, sid)

    def call(self, name, args, t=None, sid=PROPIA):
        return texto(self.call_msg(name, args, t, sid), self.respaldo_json)

    def toolnames(self, sid=PROPIA):
        m = self.request('tools/list', sid=sid)
        return {x['name'] for x in ((m or {}).get('result') or {}).get('tools', [])}
