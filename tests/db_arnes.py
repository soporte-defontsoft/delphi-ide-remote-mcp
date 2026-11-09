# -*- coding: utf-8 -*-
"""El arnes de las baterias de delphi_db (1.29): las bases de PRUEBAS (el proyecto "mcp-pruebas" del json de
produccion, mcp_pruebas en un SQL Server y en el PostgreSQL de la red: David, 6-nov-2026), su copia al json
de la bateria junto a la copia del exe, y el SQL del ARNES (crear y borrar sus tablas) por el cliente de cada
motor. Las credenciales viajan por fichero o por el entorno y NUNCA se imprimen. Estaba escrito en
test_db_lecturas_129 y la segunda bateria (test_db_escrituras_129) lo necesitaba igual: un sitio.
"""
import io
import json
import os
import shutil
import socket
import subprocess
import threading
import time
import mcp_cliente as mc

PROD_JSON = r'C:\Delphi-mcp-Server\connections\databases\db-connections.json'
PROD_PG = r'C:\Delphi-mcp-Server\drivers\PG'
# el cliente de PostgreSQL de la maquina de pruebas, por la carpeta del usuario (su nombre no va en el repo)
PSQL = os.path.join(os.path.expanduser('~'), 'pgsql', 'bin', 'psql.exe')
# el proyecto del json de la bateria (el que abre DELPHI_MCP_DB_PROJECTS)
PROYECTO = 'pruebas'


def prepara(nombre, titulo):
    """La carpeta de la bateria con su copia del exe y de drivers\\PG, y las dos entradas de pruebas:
    (BASE, JAIL, SRV, EXE, MS, PG). Sin las bases en esta maquina, la bateria termina sin checks y lo dice."""
    try:
        e = json.load(io.open(PROD_JSON, encoding='utf-8-sig'))['db-connections']['projects']['mcp-pruebas'][
            'databases']
    except Exception:
        e = None
    if not e or not os.path.isdir(PROD_PG):
        print('NOTA: sin el proyecto mcp-pruebas en el json de produccion o sin drivers\\PG: no se mide nada')
        mc.fin(titulo, sin_checks='sin bases de pruebas en esta maquina')
        raise SystemExit(0)
    base = mc.carpeta(nombre)
    jail = os.path.join(base, 'jail')
    os.makedirs(jail)
    srv = os.path.join(base, 'srv')
    exe = mc.copia_exe(srv)
    shutil.copytree(PROD_PG, os.path.join(srv, 'drivers', 'PG'))
    return base, jail, srv, exe, e['mssql'], e['pg']


CLAVES_DE_CONEXION = ('engine', 'provider', 'server', 'port', 'database', 'user', 'password')


def entrada(base, **kw):
    """Una entrada del json: COMO conectar, de base (el json de produccion), y lo que diga kw; lo que se puede hacer
    (access) lo pone cada bateria. Copiaba la entrada entera, y el readonly de produccion junto al access de la
    bateria eran dos formas a la vez: la entrada no se usaba (1.29.1, medido)."""
    e = {k: v for k, v in base.items() if k in CLAVES_DE_CONEXION}
    e.update(kw)
    return e


def escribe_conexiones(srv, bases):
    """El json de conexiones de la copia del exe con el proyecto PROYECTO y estas bases (alias: entrada)."""
    d = os.path.join(srv, 'connections', 'databases')
    os.makedirs(d, exist_ok=True)
    io.open(os.path.join(d, 'db-connections.json'), 'w', encoding='utf-8').write(
        json.dumps({'db-connections': {'projects': {PROYECTO: {'databases': bases}}}}, indent=2))


def secretos(ms, pg):
    """Lo que ninguna respuesta puede traer: claves, servidores, la base real y los usuarios como los citan
    los errores de cada motor, tambien en su idioma: un PostgreSQL en espanol cita con comillas latinas
    (el usuario salia en claro y esta lista solo lo buscaba entre las inglesas: 7-nov-2026)."""
    s = [x for x in {ms['password'], pg['password'], ms['server'], pg['server'], ms['database']} if x]
    return s + ms['server'].split('\\') + ["'%s'" % ms['user'], '"%s"' % pg['user'],
                                          chr(0xAB) + pg['user'] + chr(0xBB)]


def fugas(secr, respuestas):
    """Las POSICIONES de los secretos que aparecen en alguna respuesta (nunca el secreto ni un trozo)."""
    return sorted({i for i, s in enumerate(secr) for r in respuestas if s and s.lower() in r.lower()})


def sql_mssql(base, srv, alias, sql):
    """El arnes en SQL Server: PowerShell con SqlClient y la credencial de la entrada alias del json de la
    bateria (no se imprime). True si se ejecuto."""
    ps = os.path.join(base, 'arnes.ps1')
    io.open(os.path.join(base, 'arnes.sql'), 'w', encoding='utf-8-sig').write(sql)
    io.open(ps, 'w', encoding='utf-8-sig').write(
        "$ErrorActionPreference='Stop'\n"
        "$j = Get-Content -Raw -Encoding UTF8 '%s' | ConvertFrom-Json\n"
        "$e = $j.'db-connections'.projects.'%s'.databases.'%s'\n"
        "$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder\n"
        "$b['Data Source'] = $e.server; $b['Initial Catalog'] = $e.database; $b['User ID'] = $e.user\n"
        "$b['Password'] = $e.password; $b['Connect Timeout'] = 15\n"
        "$c = New-Object System.Data.SqlClient.SqlConnection($b.ConnectionString); $c.Open()\n"
        "$q = $c.CreateCommand(); $q.CommandText = Get-Content -Raw -Encoding UTF8 '%s'\n"
        "[void]$q.ExecuteNonQuery(); $c.Close(); 'ok'\n"
        % (os.path.join(srv, 'connections', 'databases', 'db-connections.json'), PROYECTO, alias,
           os.path.join(base, 'arnes.sql')))
    r = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps],
                       capture_output=True, text=True, timeout=120)
    return r.returncode == 0 and 'ok' in r.stdout


def _psql(base, pg, sql, fichero):
    """La orden de psql y su entorno: la credencial por el entorno (no se imprime), sin el pgpass, y el SQL en
    un fichero UTF-8 de la carpeta de la bateria. UNA para sql_pg y sql_pg_fondo."""
    env = dict(os.environ, PGPASSWORD=pg['password'], PGPASSFILE=os.path.join(base, 'no-existe.pgpass'),
               PGCLIENTENCODING='UTF8')
    f = os.path.join(base, fichero)
    io.open(f, 'w', encoding='utf-8').write(sql)
    return [PSQL, '-h', pg['server'], '-p', str(pg.get('port') or 5432), '-U', pg['user'], '-d',
            pg['database'], '-w', '-v', 'ON_ERROR_STOP=1', '-q', '-f', f], env


def sql_pg_fondo(base, pg, sql):
    """El mismo psql sin esperarlo: para retener un bloqueo mientras se mide otra cosa (P7 de
    test_db_plazo_llamada_129). El proceso, o None sin psql; quien lo lanza lo espera o lo mata."""
    if not os.path.isfile(PSQL):
        return None
    orden, env = _psql(base, pg, sql, 'arnes_pg_fondo.sql')
    return subprocess.Popen(orden, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)


def sql_pg(base, pg, sql):
    """El arnes en PostgreSQL: psql con la credencial por el entorno (no se imprime) y sin el pgpass. El SQL
    en un fichero UTF-8 (-f): por la linea de ordenes Windows lo pasa en su pagina ANSI y la A con tilde
    llegaba como 0xC1 a un cliente UTF8 (medido el 6-nov-2026). True si se ejecuto."""
    if not os.path.isfile(PSQL):
        print('  (arnes PG: no hay psql en la carpeta del usuario)')
        return False
    orden, env = _psql(base, pg, sql, 'arnes_pg.sql')
    r = subprocess.run(orden, capture_output=True, text=True, encoding='utf-8', env=env, timeout=120)
    if r.returncode != 0:
        print('  (arnes PG: %s)' % r.stderr.strip()[:200].replace(pg['password'], '***'))
    return r.returncode == 0


def sql_de_mensaje(msg):
    """El SQL de un mensaje del cliente de PG: Q (consulta simple: el texto) y P (parse: nombre y texto); ''
    en los demas."""
    tipo = chr(msg[0])
    trozos = msg[5:].split(b'\x00')
    if tipo == 'Q':
        return trozos[0].decode('utf-8', 'replace')
    if tipo == 'P' and len(trozos) > 1:
        return trozos[1].decode('utf-8', 'replace')
    return ''


class ProxyPg:
    """Un proxy TCP entre el servidor y el PostgreSQL de pruebas que CALLA a mitad de una llamada: la red que
    se queda muda (ni contesta ni cierra), CH11 de la 1.29. arma(calla_en) prepara el corte: la primera
    conexion que mande un mensaje con calla_en(tipo, sql) verdadero deja de pasar al servidor desde ese mensaje
    (lo retiene, no cierra) y queda en self.callada; suelta() le deja pasar lo retenido y lo que siga. Lo del
    servidor pasa siempre, y las demas conexiones (la cancelacion de libpq, otra llamada) pasan enteras. Lee
    el protocolo de PG: tras el arranque, sin tipo, cada mensaje es su tipo y su longitud."""

    def __init__(self, destino):
        self.destino = destino
        self.ls = socket.socket()
        self.ls.bind(('127.0.0.1', 0))
        self.ls.listen(16)
        self.puerto = self.ls.getsockname()[1]
        self.lock = threading.Lock()
        self.calla_en = None
        self.callada = None
        self.socks = []
        threading.Thread(target=self._acepta, daemon=True).start()

    def arma(self, calla_en):
        with self.lock:
            self.calla_en = calla_en
            self.callada = None

    def _acepta(self):
        while True:
            try:
                c, _ = self.ls.accept()
            except OSError:
                return
            s = socket.create_connection(self.destino, timeout=10)
            s.settimeout(None)
            self.socks += [c, s]
            t = Tramo(self, s)
            threading.Thread(target=t.del_cliente, args=(c,), daemon=True).start()
            threading.Thread(target=t.del_servidor, args=(s, c), daemon=True).start()

    def cierra(self):
        for x in [self.ls] + self.socks:
            try:
                x.close()
            except OSError:
                pass


def _cierra_escritura(sock):
    """El FIN de TCP hacia el otro lado (shutdown de escritura); sin error si ya estaba cerrado."""
    try:
        sock.shutdown(socket.SHUT_WR)
    except OSError:
        pass


class Tramo:
    """Una conexion a traves de ProxyPg: si callo (orden: el mensaje en que callo), lo retenido, y cuando
    la cerro el cliente (cerrada: su hora)."""

    def __init__(self, proxy, s):
        self.proxy, self.s = proxy, s
        self.retenido = []
        self.callado = False
        self.orden = ''
        self.cerrada = None

    def suelta(self):
        with self.proxy.lock:
            self.callado = False
            for m in self.retenido:
                self.s.sendall(m)
            self.retenido = []

    def del_cliente(self, c):
        buf, arranque = b'', True
        try:
            while True:
                b = c.recv(65536)
                if not b:
                    return
                buf += b
                while True:
                    if arranque:
                        if len(buf) < 8 or len(buf) < int.from_bytes(buf[:4], 'big'):
                            break
                        n = int.from_bytes(buf[:4], 'big')
                        # SSLRequest y GSSENCRequest van antes del arranque, tambien sin tipo
                        arranque = int.from_bytes(buf[4:8], 'big') in (80877103, 80877104)
                        tipo, sql = '', ''
                    else:
                        if len(buf) < 5 or len(buf) < int.from_bytes(buf[1:5], 'big') + 1:
                            break
                        n = int.from_bytes(buf[1:5], 'big') + 1
                        tipo, sql = chr(buf[0]), sql_de_mensaje(buf[:n])
                    msg, buf = buf[:n], buf[n:]
                    with self.proxy.lock:
                        p = self.proxy
                        if tipo and not self.callado and p.calla_en and p.calla_en(tipo, sql):
                            p.calla_en = None
                            p.callada = self
                            self.callado = True
                            self.orden = '%s %s' % (tipo, sql[:80])
                        if self.callado:
                            self.retenido.append(msg)
                        else:
                            self.s.sendall(msg)
        except OSError:
            return
        finally:
            self.cerrada = time.time()
            # el cierre del cliente llega al servidor, como en TCP
            _cierra_escritura(self.s)

    def del_servidor(self, s, c):
        try:
            while True:
                b = s.recv(65536)
                if not b:
                    return
                c.sendall(b)
        except OSError:
            return
        finally:
            # ...y el del servidor al cliente: PQcancel espera a que la base CIERRE la conexion de la
            # cancelacion, y sin esto el proxy la dejaba abierta y libpq esperaba para siempre (medido el
            # 9-nov-2026: era el "cuelgue" del dataset de FireDAC del 8-nov, P4/P4b/P6, y no FireDAC)
            _cierra_escritura(c)
