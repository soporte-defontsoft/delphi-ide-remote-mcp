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
import subprocess
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


def entrada(base, **kw):
    """Una entrada del json: la de base con lo que cambie kw."""
    e = dict(base)
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


def sql_pg(base, pg, sql):
    """El arnes en PostgreSQL: psql con la credencial por el entorno (no se imprime) y sin el pgpass. El SQL
    en un fichero UTF-8 (-f): por la linea de ordenes Windows lo pasa en su pagina ANSI y la A con tilde
    llegaba como 0xC1 a un cliente UTF8 (medido el 6-nov-2026). True si se ejecuto."""
    if not os.path.isfile(PSQL):
        print('  (arnes PG: no hay psql en la carpeta del usuario)')
        return False
    env = dict(os.environ, PGPASSWORD=pg['password'], PGPASSFILE=os.path.join(base, 'no-existe.pgpass'),
               PGCLIENTENCODING='UTF8')
    f = os.path.join(base, 'arnes_pg.sql')
    io.open(f, 'w', encoding='utf-8').write(sql)
    r = subprocess.run([PSQL, '-h', pg['server'], '-p', str(pg.get('port') or 5432), '-U', pg['user'], '-d',
                        pg['database'], '-w', '-v', 'ON_ERROR_STOP=1', '-q', '-f', f],
                       capture_output=True, text=True, encoding='utf-8', env=env, timeout=120)
    if r.returncode != 0:
        print('  (arnes PG: %s)' % r.stderr.strip()[:200].replace(pg['password'], '***'))
    return r.returncode == 0
