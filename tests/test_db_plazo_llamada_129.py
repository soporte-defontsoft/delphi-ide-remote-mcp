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
TITULO = 'delphi_db 1.29: el plazo de la llamada entera (CH11)'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_plazo_llamada_129', TITULO)
SECRETOS = arnes.secretos(MS, PG)
PX = arnes.ProxyPg((PG['server'], int(PG.get('port') or 5432)))
arnes.escribe_conexiones(SRV, {
    'pg': arnes.entrada(PG, readonly=True),
    'pgx': arnes.entrada(PG, server='127.0.0.1', port=PX.puerto, readonly=False)})
D, DX = arnes.PROYECTO + '/pg', arnes.PROYECTO + '/pgx'
DDL = 'DROP TABLE IF EXISTS %s; CREATE TABLE %s (id int PRIMARY KEY, nombre varchar(60));' % (TABLA, TABLA)

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


def ids_directos():
    """Los id de la tabla leidos por la base directa (sin el proxy)."""
    r, _ = llama({'command': 'rows', 'db': D, 'table': TABLA, 'order': 'id'})
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
    arnes.sql_pg(BASE, PG, 'DROP TABLE IF EXISTS %s;' % TABLA)
    mc.borra(BASE)
mc.fin(TITULO)
