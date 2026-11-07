# -*- coding: utf-8 -*-
"""delphi_db (1.29), segunda parte: las LECTURAS contra bases reales, en los DOS motores enlazados (MSSQL y
PostgreSQL), con la misma composicion: tables, fields, rows (filters, fields, order, limit, offset, total)
y summary (group, values, n). El agente nunca escribe SQL; el servidor compone y FireDAC traduce.

Las bases: mcp_pruebas en un SQL Server y en el PostgreSQL de la red, las del proyecto
"mcp-pruebas" del json de produccion (David, 6-nov-2026). Sus credenciales se copian al json de la bateria,
junto a la copia del exe, y nunca se imprimen. La tabla t_db129 la crea y la borra el arnes.

  L1  tables: la tabla de la bateria, y en PG solo las del esquema de la conexion (no information_schema)
  L2  fields: nombres, tipo de la base, clave y nulos
  L3  rows: total, las filas con sus tipos JSON (entero, decimal exacto, booleano, fecha ISO), binario por
      su tamano y fuera por defecto
  L4  filtros: equals (tambien con el numero como texto: PG no compara entero con texto), contains con
      comodines literales (50%%, a_b, la barra), starts_with, words, greater sobre un decimal, empty, una
      fecha; contains sin mayusculas segun la collation de cada base
  L5  orden, limit y offset: la pagina pedida y el total de siempre
  L6  fields: solo los pedidos
  L7  summary por anyo con suma y n; L8 sin grupo: una fila con los totales
  L9  negativas: tabla, campo, op, valor que no cabe, contains sobre un numero, parte de fecha sobre un no
      fecha, un parametro que no es del comando
  L10 ningun secreto del json en ninguna respuesta
  L11 una base que no responde: DB-007 dentro del plazo (MSSQL tardaba 42 s con LoginTimeout=5)
  L12 una contrasena mala en PG: DB-009, enmascarado
  L13 PG SIN contrasena no conecta: libpq no lee el pgpass de la cuenta (lo leia, medido el 6-nov)
  L14 PG con el servidor por NOMBRE: la negativa no trae la direccion que resolvio libpq ni la de este
      servidor en el pg_hba de la base (salian: '(fe80::...)', CH4 de la 1.29, medido el 7-nov-2026);
      localhost en un puerto cerrado siempre, y el host de PG por su nombre si la red lo resuelve
  L15 PG no toma del ENTORNO del servidor lo que el json no dice (PGSSLMODE, PGSERVICE, PGHOSTADDR,
      PGOPTIONS): CH3 de la 1.29, medido el 7-nov-2026

Uso:  python tests/test_db_lecturas_129.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import ipaddress
import json
import os
import re
import socket
import time
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TABLA = 't_db129'
NOMBRES = ['Ana 50%', 'ana_b', 'BETO', chr(0xC1) + 'nade', 'CASA', 'casa\\x']
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_lecturas_129', 'delphi_db 1.29 (lecturas)')
SECRETOS = arnes.secretos(MS, PG)
arnes.escribe_conexiones(SRV, {
    'mssql': arnes.entrada(MS, readonly=True),
    'pg': arnes.entrada(PG, readonly=True),
    'caida': {'server': '192.0.2.1', 'database': 'x', 'user': 'x', 'password': 'x', 'engine': 'MSSQL',
              'provider': 'FIREDAC', 'readonly': True},
    'pg_mala': arnes.entrada(PG, password='clave-mal-129', readonly=True),
    'pg_sin_clave': arnes.entrada(PG, password='', readonly=True),
    'pg_local': arnes.entrada(PG, server='localhost', port='59999', readonly=True)})


def nombre_del_host(ip):
    """El nombre del host de PG si la red lo resuelve y vuelve a su IP (None si no): el caso real de L14."""
    try:
        n = socket.gethostbyaddr(ip)[0]
        return n if ip in socket.gethostbyname_ex(n)[2] else None
    except (OSError, UnicodeError):
        return None


NOMBRE_PG = nombre_del_host(PG.get('server', ''))
if NOMBRE_PG:
    arnes.escribe_conexiones(SRV, dict(json.load(io.open(os.path.join(
        SRV, 'connections', 'databases', 'db-connections.json'), encoding='utf-8'))['db-connections']['projects'][
        arnes.PROYECTO]['databases'], pg_nombrado=arnes.entrada(PG, server=NOMBRE_PG, database='nope_l14',
                                                               readonly=True)))


def direcciones(texto):
    """Las direcciones IP que hay en texto, como las lee ipaddress (con su zona %n fuera)."""
    res = []
    for c in re.findall(r'[0-9A-Fa-f.:%]+', texto):
        try:
            ipaddress.ip_address(c.rstrip('.:').partition('%')[0])
            res.append(c)
        except ValueError:
            pass
    return res


def sql_mssql(sql):
    return arnes.sql_mssql(BASE, SRV, 'mssql', sql)


def sql_pg(sql):
    return arnes.sql_pg(BASE, PG, sql)


def filas_sql(fmt_fecha, bool_lit, n_prefijo):
    v = []
    for i, n in enumerate(NOMBRES):
        nombre = n.replace("'", "''")
        v.append("(%d, %s'%s', %s, %.2f, %s)" % (i + 1, n_prefijo, nombre, fmt_fecha % (2024 + i % 2, i + 1),
                                                 (i + 1) * 1.5, bool_lit(i % 2 == 1)))
    return ', '.join(v)


MS_DDL = ("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; CREATE TABLE dbo.%s (id int PRIMARY KEY, nombre "
          "nvarchar(60) NULL, alta datetime2 NULL, importe decimal(10,2) NULL, activo bit NULL, foto varbinary(100) "
          "NULL); INSERT INTO dbo.%s (id, nombre, alta, importe, activo) VALUES %s; UPDATE dbo.%s SET foto = "
          "0x010203 WHERE id = 1;" % (TABLA, TABLA, TABLA, TABLA,
                                     filas_sql("'%d-%02d-01'", lambda b: '1' if b else '0', 'N'), TABLA))
PG_DDL = ("DROP TABLE IF EXISTS %s; CREATE TABLE %s (id int PRIMARY KEY, nombre varchar(60), alta timestamp, importe "
          "numeric(10,2), activo boolean, foto bytea); INSERT INTO %s (id, nombre, alta, importe, activo) VALUES %s; "
          "UPDATE %s SET foto = '\\x010203' WHERE id = 1;" % (TABLA, TABLA, TABLA,
                                                             filas_sql("'%d-%02d-01'", lambda b: 'true' if b else
                                                                       'false', ''), TABLA))

srv = None
respuestas = []
try:
    hay_ms, hay_pg = sql_mssql(MS_DDL), sql_pg(PG_DDL)
    if not hay_ms:
        print('NOTA: el SQL Server de la red no responde o no deja crear %s: MSSQL no se mide' % TABLA)
    if not hay_pg:
        print('NOTA: el PostgreSQL de la red no responde o no deja crear %s: PG no se mide' % TABLA)
    # L13 con la amenaza DENTRO: un pgpass con la credencial de PG que libpq encontraria por PGPASSFILE. El
    # entorno de las baterias no llega al pgpass de la cuenta, y L13 pasaba igual contra el mutante sin el
    # passfile (medido el 6-nov-2026): una verde por el motivo equivocado. Se borra con la carpeta.
    PGPASS = os.path.join(BASE, 'cuenta.pgpass')

    def esc(s):
        return str(s).replace('\\', '\\\\').replace(':', '\\:')
    io.open(PGPASS, 'w', encoding='utf-8').write('%s:%s:*:%s:%s\n' % (
        esc(PG['server']), esc(PG.get('port') or 5432), esc(PG['user']), esc(PG['password'])))
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': 'pruebas',
                                    'PGPASSFILE': PGPASS}), nombre='db-lecturas', t=120)

    def db(args, t=None):
        r = srv.call('delphi_db', args, t)
        respuestas.append(r)
        return r

    for motor, hay in (('mssql', hay_ms), ('pg', hay_pg)):
        if not hay:
            continue
        D = 'pruebas/' + motor
        r = db({'command': 'tables', 'db': D})
        tablas = mc.como_json(r).get('tables', [])
        check('L1 %s tables: la de la bateria, y ninguna de information_schema ni pg_catalog' % motor,
              TABLA in tablas and not [t for t in tablas if t.startswith(('pg_', '_pg_', 'information_schema'))]
              and 'columns' not in tablas, r[:300])
        r = db({'command': 'fields', 'db': D, 'table': TABLA})
        campos = {c['name']: c for c in mc.como_json(r).get('fields', [])}
        check('L2 %s fields: los seis, id clave, nombre con su longitud y nulos' % motor,
              list(campos) == ['id', 'nombre', 'alta', 'importe', 'activo', 'foto']
              and campos['id'].get('key') is True and campos['id'].get('nullable') is False
              and campos['nombre'].get('length') == 60 and campos['importe'].get('scale') == 2, r[:500])
        r = db({'command': 'rows', 'db': D, 'table': TABLA, 'order': 'id'})
        j = mc.como_json(r)
        filas = j.get('rows', [])
        f1 = filas[0] if filas else {}
        check('L3 %s rows: total 6, sus tipos JSON, el binario fuera por defecto' % motor,
              j.get('total') == 6 and j.get('returned') == 6 and f1.get('id') == 1 and f1.get('nombre') == 'Ana 50%'
              and f1.get('importe') == 1.5 and f1.get('activo') is False and f1.get('alta') == '2024-01-01T00:00:00'
              and 'foto' not in f1 and mc.es(j.get('note', ''), 'SN_DB_ROWS'), r[:600])
        r = db({'command': 'rows', 'db': D, 'table': TABLA, 'fields': ['id', 'foto'], 'filters': [
            {'field': 'id', 'op': 'equals', 'value': 1}]})
        check('L3 %s ...el binario pedido, por su tamano' % motor,
              (mc.como_json(r).get('rows') or [{}])[0].get('foto') == '(binary, 3 bytes)', r[:300])

        def ids(filtros, **extra):
            a = dict({'command': 'rows', 'db': D, 'table': TABLA, 'fields': ['id'], 'order': 'id',
                      'filters': filtros}, **extra)
            rr = db(a)
            return [f.get('id') for f in mc.como_json(rr).get('rows', [])], rr

        casos = [('equals 3', [{'field': 'id', 'op': 'equals', 'value': 3}], [3]),
                 ('equals "3" (texto: PG no compara entero con texto)', [{'field': 'id', 'op': 'equals', 'value': '3'}],
                  [3]),
                 ('contains "50%" literal', [{'field': 'nombre', 'op': 'contains', 'value': '50%'}], [1]),
                 ('contains "a_b" literal', [{'field': 'nombre', 'op': 'contains', 'value': 'a_b'}], [2]),
                 ('contains la barra', [{'field': 'nombre', 'op': 'contains', 'value': 'casa\\'}], [6]),
                 ('starts_with "cas"', [{'field': 'nombre', 'op': 'starts_with', 'value': 'cas'}], [5, 6]),
                 ('words "x casa"', [{'field': 'nombre', 'op': 'words', 'value': 'x casa'}], [6]),
                 ('greater importe 4.5', [{'field': 'importe', 'op': 'greater', 'value': 4.5}], [4, 5, 6]),
                 ('activo equals true', [{'field': 'activo', 'op': 'equals', 'value': True}], [2, 4, 6]),
                 ('alta >= 2025-01-01', [{'field': 'alta', 'op': 'greater_or_equal', 'value': '2025-01-01'}],
                  [2, 4, 6]),
                 # una fecha sin zona es la que se escribe: la RTL la tomaba por UTC y la pasaba a hora local
                 # (TryISO8601ToDate con AReturnUTC=False; medido el 6-nov-2026: 04:05 se guardaba como 05:05)
                 ('alta equals 2025-02-01, sin mover la hora', [{'field': 'alta', 'op': 'equals',
                                                                 'value': '2025-02-01'}], [2]),
                 ('empty foto false', [{'field': 'foto', 'op': 'empty', 'value': False}], [1]),
                 ('dos filtros (AND)', [{'field': 'activo', 'op': 'equals', 'value': 'yes'},
                                        {'field': 'importe', 'op': 'less', 'value': '7'}], [2, 4])]
        for nombre, filtros, esperado in casos:
            got, rr = ids(filtros)
            check('L4 %s %s' % (motor, nombre), got == esperado, (got, rr[:300]))
        got, rr = ids([{'field': 'nombre', 'op': 'contains', 'value': 'ana'}])
        # la collation decide: Modern_Spanish_CI_AI no distingue acentos (Anade entra), PG si (medido el 6-nov)
        check('L4 %s contains "ana" sin mayusculas, con los acentos de su collation' % motor,
              got == ([1, 2, 4] if motor == 'mssql' else [1, 2]), (got, rr[:300]))
        got, rr = ids([], limit=2, offset=2)
        check('L5 %s order id, limit 2, offset 2: [3, 4] y total 6' % motor,
              got == [3, 4] and mc.como_json(rr).get('total') == 6, rr[:300])
        got, rr = ids([], order='importe desc', limit=1)
        check('L5 %s order importe desc, limit 1: el 6' % motor, got == [6], rr[:200])
        r = db({'command': 'rows', 'db': D, 'table': TABLA, 'fields': ['nombre', 'id'], 'limit': 1, 'order': 'id'})
        check('L6 %s fields: solo los pedidos' % motor,
              (mc.como_json(r).get('rows') or [{}])[0] == {'nombre': 'Ana 50%', 'id': 1}, r[:300])
        r = db({'command': 'summary', 'db': D, 'table': TABLA, 'group': ['alta:year'],
                'values': [{'field': 'importe', 'op': 'sum'}], 'order': 'alta:year'})
        g = mc.como_json(r).get('groups', [])
        check('L7 %s summary por anyo: suma y n' % motor,
              g == [{'alta:year': 2024, 'sum_importe': 13.5, 'n': 3}, {'alta:year': 2025, 'sum_importe': 18.0, 'n': 3}],
              r[:400])
        r = db({'command': 'summary', 'db': D, 'table': TABLA, 'values': [{'field': 'importe', 'op': 'max'}],
                'filters': [{'field': 'activo', 'op': 'equals', 'value': True}]})
        check('L8 %s summary sin grupo: una fila con los totales' % motor,
              mc.como_json(r).get('groups') == [{'max_importe': 9.0, 'n': 3}], r[:300])
        negativas = [
            ({'command': 'rows', 'db': D, 'table': 'no_existe_129'}, 'SR_DB_TABLA_FMT'),
            ({'command': 'rows', 'db': D, 'table': TABLA, 'fields': ['no_existe']}, 'SR_DB_CAMPO_FMT'),
            ({'command': 'rows', 'db': D, 'table': TABLA, 'filters': [{'field': 'id', 'op': 'like', 'value': 1}]},
             'SR_DB_ENTRADA_FMT'),
            ({'command': 'rows', 'db': D, 'table': TABLA, 'filters': [{'field': 'id', 'op': 'equals',
                                                                        'value': 'abc'}]}, 'SR_DB_ENTRADA_FMT'),
            ({'command': 'rows', 'db': D, 'table': TABLA, 'filters': [{'field': 'id', 'op': 'contains',
                                                                        'value': '1'}]}, 'SR_DB_ENTRADA_FMT'),
            ({'command': 'summary', 'db': D, 'table': TABLA, 'group': ['nombre:year']}, 'SR_DB_PARTE_FMT'),
            ({'command': 'rows', 'db': D, 'table': TABLA, 'order': 'id sideways'}, 'SR_DB_ORDEN_FMT'),
            ({'command': 'tables', 'db': D, 'table': TABLA}, 'SR_DB_NO_VA_CON_COMANDO_FMT'),
            ({'command': 'rows', 'db': D}, 'SR_DB_FALTA_FMT')]
        for args, codigo in negativas:
            r = db(args)
            check('L9 %s %s -> %s' % (motor, json.dumps(args, ensure_ascii=False)[:90], codigo),
                  mc.abre(r, codigo), r[:300])

    t0 = time.time()
    r = db({'command': 'tables', 'db': 'pruebas/caida'}, 60)
    seg = time.time() - t0
    check('L11 una base que no responde: DB-007 dentro del plazo (%.1f s)' % seg,
          mc.abre(r, 'SR_DB_NO_RESPONDE_FMT') and seg < 20, (round(seg, 1), r[:300]))
    if hay_pg:
        r = db({'command': 'tables', 'db': 'pruebas/pg_mala'})
        check('L12 PG con contrasena mala: DB-009 enmascarado', mc.abre(r, 'SR_DB_NO_ABRE_FMT')
              and 'pruebas/pg_mala' in r, r[:400])
        r = db({'command': 'tables', 'db': 'pruebas/pg_sin_clave'})
        check('L13 PG SIN contrasena NO conecta (libpq no lee el pgpass de la cuenta)',
              mc.abre(r, 'SR_DB_NO_ABRE_FMT') and 'tables' not in mc.como_json(r), r[:400])
        r = db({'command': 'tables', 'db': 'pruebas/pg_local'})
        check('L14 PG por nombre (localhost, puerto cerrado): DB-009 sin las direcciones que resolvio libpq',
              mc.abre(r, 'SR_DB_NO_ABRE_FMT') and 'pruebas/pg_local' in r and not direcciones(r),
              (direcciones(r), r[:400]))
        if NOMBRE_PG:
            r = db({'command': 'tables', 'db': 'pruebas/pg_nombrado'})
            check('L14 PG por el nombre de su host: DB-009 sin su direccion ni la de este servidor',
                  mc.abre(r, 'SR_DB_NO_ABRE_FMT') and not direcciones(r), len(direcciones(r)))
        else:
            print('NOTA: L14 el host de PG no tiene un nombre que la red resuelva: solo se mide localhost')
        # L15 (CH3 de la 1.29): lo que el json no dice, libpq lo tomaba del ENTORNO del servidor. Un servidor
        # con variables PG* hostiles abre la base como uno sin ellas. ROJO contra 958be0fe: DB-009 (medido:
        # PGSSLMODE=require cambiaba la conexion; PGSERVICE pide un servicio que no existe). 192.0.2.1 es de
        # documentacion: no responde nunca.
        hostil = mc.Stdio(EXE, mc.entorno({
            'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': 'pruebas', 'PGSSLMODE': 'require',
            'PGSERVICE': 'no_existe_l15', 'PGHOSTADDR': '192.0.2.1', 'PGOPTIONS': '-c search_path=no_existe_l15'}),
            nombre='db-hostil', t=120)
        try:
            r = hostil.call('delphi_db', {'command': 'tables', 'db': 'pruebas/pg'})
            respuestas.append(r)
        finally:
            hostil.cierra()
        check('L15 PG con PGSSLMODE, PGSERVICE, PGHOSTADDR y PGOPTIONS en el entorno del servidor: abre como sin '
              'ellas (la tabla de la bateria en su esquema)', TABLA in mc.como_json(r).get('tables', []), r[:400])
    # el detalle de un fallo dice CUALES (su posicion en SECRETOS), nunca el secreto ni un trozo
    fugas = arnes.fugas(SECRETOS, respuestas)
    check('L10 ningun secreto del json en ninguna respuesta (%d respuestas)' % len(respuestas), not fugas,
          'secretos que aparecen: posiciones %s de %d' % (fugas, len(SECRETOS)))
finally:
    if srv:
        srv.cierra()
    try:
        sql_mssql("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s;" % (TABLA, TABLA))
        sql_pg('DROP TABLE IF EXISTS %s;' % TABLA)
    finally:
        mc.borra(BASE)
mc.fin('delphi_db 1.29 (lecturas, MSSQL y PG)')
