# -*- coding: utf-8 -*-
"""delphi_db (1.29, CH11): el plazo de la llamada ENTERA. Una base que abre y despues calla (la red que se queda
muda: ni contesta ni cierra) dejaba la llamada sin volver: medido el 7-nov-2026 con un proxy que calla tras el
mensaje K de la conexion, tables no volvia en 240 s. Las ordenes de la conexion de FireDAC (BEGIN, COMMIT,
ROLLBACK, DEALLOCATE) y el parse de un comando no llevan el CmdExecTimeout de las de un comando, y cuando este
salta, la cancelacion de libpq vuelve por la misma conexion callada. El proxy (db_arnes.ProxyPg) calla en el
mensaje que se le dice.

  P0 control, por el proxy sin cortar: tables contesta, y un insert a tiempo se confirma (se lee directo)
  P1 tables con el proxy callado en el cursor del catalogo: DB-022 en los segundos que dice, no mas.
     ROJO contra 040e36bb (no vuelve)
  P2 ...y mientras su hilo sigue esperando a la base, el servidor contesta otra llamada al momento
  P3 rows callado en el BEGIN (una orden de la conexion, sin plazo de comando): DB-022
  P4 insert callado en su INSERT: DB-022; despues la red vuelve (suelta), el INSERT llega a la base y el hilo
     acaba, y la fila NO esta: lo que el hilo hace despues de contestar no se confirma (TSesionDb.Confirma).
     ROJO con el mutante que confirma con S.Conn.Commit
  P0b/P4b (P3 de la 1.29.1: el insert va por un dataset de FireDAC y devuelve la fila como quedo): en una tabla
     serial devuelve su clave; callado en su INSERT (el que relee con RETURNING), lo mismo que P4
  P7 el caso REAL de un ERP: otra sesion retiene la fila y el insert espera a su bloqueo; el plazo de la orden
     de FireDAC cancela (PQcancel, por otra conexion), la base, que SI tiene la orden, la corta y contesta: un
     error de la base a los ~30 s, sin DB-022, y la conexion sigue sirviendo. Lo que el agujero negro del proxy
     (que se traga la orden y deja vivo el TCP) no deja ver
  P5 ningun secreto del json en ninguna respuesta
  P6 con hilos todavia esperando a la base callada, el servidor sale LIMPIO al cerrarle stdin (rc 0): les cierra
     el socket (Lsp.BaseDeDatos, DespiertaLasAbandonadas). ROJO sin ello (medido con cdb): FireDAC cierra su
     conexion al destruir su gestor con el cerrojo tomado y el hilo despierto no puede soltarla (interbloqueo), o
     usa lo ya liberado (0xC0000005). Solo PostgreSQL: el ODBC de SQL Server no da el socket (limite declarado)

Uso:  python tests/test_db_plazo_llamada_129.py [ruta-a-DelphiLspMcp.exe]
"""
import re
import time
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TABLA = 't_db129p'
TABLA_S = 't_db129ps'  # con serial: el insert relee su clave (P0b, P4b)
TITULO = 'delphi_db 1.29: el plazo de la llamada entera (CH11)'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_plazo_llamada_129', TITULO)
SECRETOS = arnes.secretos(MS, PG)
PX = arnes.ProxyPg((PG['server'], int(PG.get('port') or 5432)))
arnes.escribe_conexiones(SRV, {
    'pg': arnes.entrada(PG, access='read'),
    'pgx': arnes.entrada(PG, server='127.0.0.1', port=PX.puerto, access='write'),
    # P7: la base DIRECTA y con escritura, sin el proxy (su cancelacion va por otra conexion a la base)
    'pgw': arnes.entrada(PG, access='write')})
D, DX, DW = arnes.PROYECTO + '/pg', arnes.PROYECTO + '/pgx', arnes.PROYECTO + '/pgw'
DDL = ('DROP TABLE IF EXISTS %s, %s; CREATE TABLE %s (id int PRIMARY KEY, nombre varchar(60)); '
       'CREATE TABLE %s (id serial PRIMARY KEY, nombre varchar(60));' % (TABLA, TABLA_S, TABLA, TABLA_S))

srv = None
respuestas = []


def llama(args, t=None):
    """(respuesta, segundos); una que no vuelve en t es la EXCEPCION del cliente (el rojo)."""
    t0 = time.time()
    try:
        r = srv.call('delphi_db', args, t)
    except Exception as e:
        r = 'EXCEPCION %s' % e
    respuestas.append(r)
    return r, time.time() - t0


def segundos_de(r):
    """Los segundos que dice DB-022 (el plazo del servidor, sin copiarlo aqui); None si no es DB-022."""
    if not mc.abre(r, 'SR_DB_CALLA_FMT'):
        return None
    m = re.search(r'within (\d+) seconds', r)
    return int(m.group(1)) if m else None


def a_tiempo(r, dt):
    """DB-022 y en su plazo: ni antes (no corto lo que iba bien) ni mucho despues."""
    n = segundos_de(r)
    return n is not None and n - 1 <= dt <= n + 15


def ids_directos(tabla=TABLA):
    """Los id de la tabla leidos por la base directa (sin el proxy)."""
    r, _ = llama({'command': 'rows', 'db': D, 'table': tabla, 'order': 'id'})
    j = mc.como_json(r)
    return [f.get('id') for f in j.get('rows', [])] if j else None


def callado_en(tipo, texto):
    return lambda t, sql: t == tipo and sql.lstrip().upper().startswith(texto)


try:
    if not arnes.sql_pg(BASE, PG, DDL):
        print('NOTA: el PostgreSQL de pruebas no responde o no deja crear %s: no se mide' % TABLA)
        mc.fin(TITULO, sin_checks='sin el PostgreSQL de pruebas')
        raise SystemExit(0)
    ENV = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': arnes.PROYECTO})
    srv = mc.Stdio(EXE, ENV, nombre='db-plazo', t=150)

    # P0 -------------------------------------------------------------------------------------------------
    r, dt = llama({'command': 'tables', 'db': DX})
    j = mc.como_json(r)
    check('P0 por el proxy sin cortar, tables contesta', TABLA in j.get('tables', []), r[:300])
    r, dt = llama({'command': 'insert', 'db': DX, 'table': TABLA, 'values': [{'field': 'id', 'value': 1},
                                                                             {'field': 'nombre', 'value': 'uno'}]})
    check('P0 ...y un insert a tiempo se confirma', '"affected":1' in r.replace(' ', '') and ids_directos() == [1],
          r[:300])
    r, dt = llama({'command': 'insert', 'db': DX, 'table': TABLA_S, 'values': [{'field': 'nombre', 'value': 'uno'}]})
    fila = (mc.como_json(r) or {}).get('row') or {}
    ids_s = ids_directos(TABLA_S)
    check('P0b en una tabla serial el insert devuelve la fila con la clave que puso la base',
          isinstance(fila.get('id'), int) and fila.get('nombre') == 'uno' and ids_s == [fila.get('id')],
          (r[:300], ids_s))

    # P1 -------------------------------------------------------------------------------------------------
    PX.arma(callado_en('P', 'DECLARE'))
    r, dt = llama({'command': 'tables', 'db': DX})
    t1 = PX.callada
    check('preparacion P1: el proxy callo en el cursor del catalogo', t1 is not None and 'DECLARE' in t1.orden,
          t1.orden if t1 else 'no callo')
    check('P1 tables con la base callada: DB-022 en los segundos que dice. ROJO contra 040e36bb',
          a_tiempo(r, dt), '%.1f s: %s' % (dt, r[:300]))

    # P2 -------------------------------------------------------------------------------------------------
    r, dt = llama({'command': 'tables', 'db': D}, 30)
    j = mc.como_json(r)
    check('P2 con ese hilo esperando a la base, otra llamada contesta al momento',
          TABLA in j.get('tables', []) and dt < 10, '%.1f s: %s' % (dt, r[:300]))

    # P3 -------------------------------------------------------------------------------------------------
    PX.arma(callado_en('Q', 'BEGIN'))
    r, dt = llama({'command': 'rows', 'db': DX, 'table': TABLA})
    t3 = PX.callada
    check('preparacion P3: el proxy callo en el BEGIN', t3 is not None and 'BEGIN' in t3.orden,
          t3.orden if t3 else 'no callo')
    check('P3 rows callado en el BEGIN (sin plazo de comando): DB-022 en su plazo', a_tiempo(r, dt),
          '%.1f s: %s' % (dt, r[:300]))

    # P4 -------------------------------------------------------------------------------------------------
    PX.arma(callado_en('P', 'INSERT'))
    r, dt = llama({'command': 'insert', 'db': DX, 'table': TABLA, 'values': [{'field': 'id', 'value': 2},
                                                                             {'field': 'nombre', 'value': 'dos'}]})
    t4 = PX.callada
    check('preparacion P4: el proxy callo en el INSERT', t4 is not None and 'INSERT' in t4.orden,
          t4.orden if t4 else 'no callo')
    check('P4 insert callado: DB-022 en su plazo', a_tiempo(r, dt), '%.1f s: %s' % (dt, r[:300]))
    if t4 is not None:
        t4.suelta()
        hasta = time.time() + 30
        while t4.cerrada is None and time.time() < hasta:
            time.sleep(0.5)
        check('preparacion P4: vuelta la red, el hilo acabo y cerro su conexion', t4.cerrada is not None,
              'sigue abierta a los 30 s')
        ids = ids_directos()
        check('P4 ...y la fila no esta: despues de contestar no se confirma nada. ROJO con el mutante de Commit',
              ids == [1], 'ids=%s' % ids)

    # P4b ------------------------------------------------------------------------------------------------
    # el INSERT del dataset que relee (RETURNING); se calla en el mensaje que lo lleve, sea P o Q
    PX.arma(lambda t, sql: t in ('P', 'Q') and sql.lstrip().upper().startswith('INSERT'))
    r, dt = llama({'command': 'insert', 'db': DX, 'table': TABLA_S, 'values': [{'field': 'nombre', 'value': 'callado'}]})
    t4b = PX.callada
    check('preparacion P4b: el proxy callo en el INSERT de la tabla serial', t4b is not None and 'INSERT' in t4b.orden,
          t4b.orden if t4b else 'no callo')
    check('P4b insert que relee, callado: DB-022 en su plazo', a_tiempo(r, dt), '%.1f s: %s' % (dt, r[:300]))
    if t4b is not None:
        t4b.suelta()
        hasta = time.time() + 30
        while t4b.cerrada is None and time.time() < hasta:
            time.sleep(0.5)
        check('P4b vuelta la red, el hilo acabo y cerro su conexion', t4b.cerrada is not None, 'sigue abierta a los 30 s')
        check('P4b ...y la fila no esta', ids_directos(TABLA_S) == ids_s, ids_directos(TABLA_S))

    # P7 -------------------------------------------------------------------------------------------------
    bloqueo = arnes.sql_pg_fondo(BASE, PG, "BEGIN; INSERT INTO %s (id, nombre) VALUES (70, 'retenida'); "
                                           "SELECT pg_sleep(50); ROLLBACK;" % TABLA)
    if bloqueo is None:
        print('NOTA P7: sin psql no se retiene el bloqueo: no se mide')
    else:
        try:
            time.sleep(3)  # que tome el bloqueo de la clave 70
            r, dt = llama({'command': 'insert', 'db': DW, 'table': TABLA,
                           'values': [{'field': 'id', 'value': 70}, {'field': 'nombre', 'value': 'espera'}]})
            check('P7 un insert que espera a un bloqueo: el plazo de la orden lo cancela y contesta la base, sin DB-022',
                  dt < 45 and mc.fallo(r) and not mc.abre(r, 'SR_DB_CALLA_FMT'), '%.1f s: %s' % (dt, r[:300]))
            r, dt = llama({'command': 'tables', 'db': DW}, 30)
            check('P7 ...y la base sigue sirviendo al momento', TABLA in (mc.como_json(r) or {}).get('tables', []) and dt < 10,
                  '%.1f s: %s' % (dt, r[:200]))
        finally:
            bloqueo.kill()
            bloqueo.wait(10)

    # P5 -------------------------------------------------------------------------------------------------
    f = arnes.fugas(SECRETOS, respuestas)
    check('P5 ningun secreto del json en ninguna respuesta', not f, 'posiciones %s' % f)

    # P6 -------------------------------------------------------------------------------------------------
    t0 = time.time()
    srv.p.stdin.close()
    try:
        rc = srv.p.wait(20)
    except Exception:
        rc = None
    dt = time.time() - t0
    check('P6 con hilos esperando a la base callada, el servidor sale limpio al cerrarle stdin',
          rc == 0 and dt < 15, 'rc=%s en %.1f s' % (rc, dt))
finally:
    if srv is not None:
        srv.cierra()
    PX.cierra()
    arnes.sql_pg(BASE, PG, 'DROP TABLE IF EXISTS %s, %s;' % (TABLA, TABLA_S))
    mc.borra(BASE)
mc.fin(TITULO)
