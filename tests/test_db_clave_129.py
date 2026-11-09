# -*- coding: utf-8 -*-
"""delphi_db (1.29), lo que la pasada en vivo como agente encontro (8-nov-2026, contra bases reales de desarrollo), en
los DOS motores enlazados (MSSQL y PostgreSQL). Las bases y su arnes, en db_arnes; el juez de cada cosa es la
tabla que el arnes crea con su SQL.

  K1  fields dice lo que la base pone sola en un insert que no lo da: autoinc en el contador de la clave, default
      en los campos con valor por defecto, y nada en los demas (el agente lo sabia a base de DB-010, uno por
      campo). ROJO contra 0b408580
  K2  un insert sin los campos con defecto: affected 1 y la base pone los suyos (el contador y los defectos que
      fields anuncia).
  K2b (P3 de la 1.29.1) ...y la respuesta trae la fila como quedo (row): la clave que puso la base, los
      defectos. En SQL Server la tabla tiene un trigger que inserta en OTRA con su identidad (desde 1000): la
      clave tiene que ser la de esta fila (lo de SCOPE_IDENTITY y no @@IDENTITY)
  K2c ...y lo que un trigger pone en la PROPIA fila (codigo = 'K-<id>': AFTER INSERT con UPDATE en SQL Server,
      BEFORE INSERT en PostgreSQL) viene en la fila devuelta, como lo ve un dataset de ADO tras su Post (David)
  K4  un null dado a un campo con valor por defecto escribe NULL, no el defecto
  K5  un insert que la base rechaza (un obligatorio sin dar): DB-010 y nada escrito
  K6  update y delete de MAS filas que su max (por defecto 100): DB-028 con cuantas, y nada cambiado (se deshace
      en su transaccion); 100 justas pasan; con max=N, si. ROJO contra 0b408580 (tocaba las 150)
  K7  max con un comando que no es update ni delete: DB-020
  K8  tables de una base sin tablas ni vistas: la nota dice el esquema que miro (DB-029); con tablas, ninguna
      nota. Lo de "sin tablas" lo dice el arnes (si otra bateria dejo las suyas, se dice y no se mide)
  K9  ningun secreto del json en ninguna respuesta
  K10 un insert en una tabla SIN clave primaria que deja un campo a su defecto: se escribe (la base pone el
      defecto), sin row y con la nota DB-031. Con la relectura de P3 FireDAC buscaba la fila por todos sus
      campos, el defecto no casaba y SQL Server contestaba DApt-400 sin escribir nada, donde la 1.29.0 la
      escribia (hallazgo 9 del revisor de la 1.29.1)

Uso:  python tests/test_db_clave_129.py [ruta-a-DelphiLspMcp.exe]
"""
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TITULO = 'delphi_db 1.29 (clave del insert, defectos, max, esquema vacio; MSSQL y PG)'
TK, TL, TN, TS = 't_db129k', 't_db129k_log', 't_db129k_n', 't_db129k_s'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_clave_129', TITULO)
SECRETOS = arnes.secretos(MS, PG)
arnes.escribe_conexiones(SRV, {
    'mssql': arnes.entrada(MS, access='write'),
    'pg': arnes.entrada(PG, access='write')})
MS_BORRA = ("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE "
            "dbo.%s; IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; "
            "IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s;" % (TK, TK, TL, TL, TN, TN, TS, TS))
MS_DDL = MS_BORRA + (
    "CREATE TABLE dbo.%s (n int IDENTITY(1000,1) PRIMARY KEY, nota nvarchar(20) NULL); "
    "CREATE TABLE dbo.%s (id int IDENTITY(1,1) PRIMARY KEY, nombre nvarchar(40) NOT NULL, "
    "estado int NOT NULL DEFAULT 5, marca nvarchar(10) NULL DEFAULT N'def', obligado int NOT NULL, "
    "codigo nvarchar(20) NULL); "
    "CREATE TABLE dbo.%s (id int PRIMARY KEY, v int NOT NULL); "
    "CREATE TABLE dbo.%s (nombre nvarchar(40) NULL, v int NULL DEFAULT 7); "
    ";WITH n AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 150) "
    "INSERT INTO dbo.%s (id, v) SELECT i, 0 FROM n OPTION (MAXRECURSION 200);" % (TL, TK, TN, TS, TN))
# CREATE TRIGGER va solo en su lote
MS_TRIGGER = ("CREATE TRIGGER dbo.%s_tr ON dbo.%s AFTER INSERT AS BEGIN SET NOCOUNT ON; "
              "INSERT INTO dbo.%s (nota) SELECT N'trigger' FROM inserted; "
              "UPDATE t SET codigo = N'K-' + CAST(t.id AS nvarchar(10)) FROM dbo.%s t JOIN inserted i ON i.id = t.id; "
              "END;" % (TK, TK, TL, TK))
PG_BORRA = 'DROP TABLE IF EXISTS %s, %s, %s, %s; DROP FUNCTION IF EXISTS %s_codigo() CASCADE;' % (TK, TL, TN, TS, TK)
PG_DDL = PG_BORRA + (
    " CREATE TABLE %s (id serial PRIMARY KEY, nombre varchar(40) NOT NULL, estado int NOT NULL DEFAULT 5, "
    "marca varchar(10) NULL DEFAULT 'def', obligado int NOT NULL, codigo varchar(20) NULL);"
    " CREATE FUNCTION %s_codigo() RETURNS trigger AS $$ BEGIN NEW.codigo := 'K-' || NEW.id; RETURN NEW; END $$"
    " LANGUAGE plpgsql;"
    " CREATE TRIGGER %s_tr BEFORE INSERT ON %s FOR EACH ROW EXECUTE FUNCTION %s_codigo();"
    " CREATE TABLE %s (id int PRIMARY KEY, v int NOT NULL);"
    " CREATE TABLE %s (nombre varchar(40), v int DEFAULT 7);"
    " INSERT INTO %s SELECT g, 0 FROM generate_series(1, 150) g;" % (TK, TK, TK, TK, TK, TN, TS, TN))

srv = None
respuestas = []


def llama(args, t=None):
    r = srv.call('delphi_db', args, t)
    respuestas.append(r)
    return r


try:
    # K8 primero: lo de "sin tablas" lo dice el arnes, que acaba de borrar las suyas
    vacia = {'mssql': arnes.sql_mssql(BASE, SRV, 'mssql', MS_BORRA), 'pg': arnes.sql_pg(BASE, PG, PG_BORRA)}
    ENV = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': arnes.PROYECTO})
    srv = mc.Stdio(EXE, ENV, nombre='db-clave', t=120)
    for motor in [m for m in ('mssql', 'pg') if vacia[m]]:
        D = arnes.PROYECTO + '/' + motor
        j = mc.como_json(llama({'command': 'tables', 'db': D}))
        if j.get('tables') or j.get('views'):
            print('NOTA K8 %s: la base tiene tablas de otra bateria (%s): no se mide sin ninguna'
                  % (motor, (j.get('tables') or j.get('views'))[:3]))
        else:
            check('K8 %s tables de una base sin tablas ni vistas: la nota dice el esquema que miro (DB-029)' % motor,
                  str(j.get('note', '')).startswith('[DB-029]') and '"' in j.get('note', ''), j)
    hay = {'mssql': arnes.sql_mssql(BASE, SRV, 'mssql', MS_DDL) and arnes.sql_mssql(BASE, SRV, 'mssql', MS_TRIGGER),
           'pg': arnes.sql_pg(BASE, PG, PG_DDL)}
    for m, h in hay.items():
        if not h:
            print('NOTA: %s no responde o no deja crear %s: no se mide' % (m, TK))

    for motor in [m for m in ('mssql', 'pg') if hay[m]]:
        D = arnes.PROYECTO + '/' + motor

        def filas(tabla, **extra):
            return mc.como_json(llama(dict({'command': 'rows', 'db': D, 'table': tabla, 'order': 'id'}, **extra)))

        j = mc.como_json(llama({'command': 'tables', 'db': D}))
        check('K8 %s con tablas, ninguna nota' % motor, TK in j.get('tables', []) and 'note' not in j, j)

        j = mc.como_json(llama({'command': 'fields', 'db': D, 'table': TK}))
        marcas = {f['name']: (bool(f.get('autoinc')), bool(f.get('default'))) for f in j.get('fields', [])}
        check('K1 %s fields: autoinc en el contador, default en estado y marca, nada en nombre y obligado' % motor,
              marcas == {'id': (True, False), 'nombre': (False, False), 'estado': (False, True),
                         'marca': (False, True), 'obligado': (False, False), 'codigo': (False, False)}, j)

        r1 = mc.como_json(llama({'command': 'insert', 'db': D, 'table': TK, 'values': [
            {'field': 'nombre', 'value': 'uno'}, {'field': 'obligado', 'value': 7}]}))
        f1 = (filas(TK, filters=[{'field': 'nombre', 'op': 'equals', 'value': 'uno'}]).get('rows') or [{}])[0]
        check('K2 %s insert sin los campos con defecto: affected 1 y la base pone el contador y los defectos' % motor,
              r1.get('affected') == 1 and isinstance(f1.get('id'), int) and f1.get('estado') == 5
              and f1.get('marca') == 'def', (r1, f1))
        row1 = r1.get('row') or {}
        check('K2b %s ...y la respuesta trae la fila como quedo: su clave (no la del trigger) y los defectos' % motor,
              row1.get('id') == f1.get('id') and row1.get('estado') == 5 and row1.get('marca') == 'def'
              and row1.get('nombre') == 'uno' and row1.get('obligado') == 7, (row1, f1))
        check('K2c %s ...y lo que un trigger pone en la propia fila (codigo) viene en la fila devuelta' % motor,
              f1.get('codigo') == 'K-%s' % f1.get('id') and row1.get('codigo') == f1.get('codigo'), (row1, f1))

        r = mc.como_json(llama({'command': 'insert', 'db': D, 'table': TK, 'values': [
            {'field': 'nombre', 'value': 'nulo'}, {'field': 'obligado', 'value': 1}, {'field': 'marca', 'value': None}]}))
        fn = (filas(TK, filters=[{'field': 'nombre', 'op': 'equals', 'value': 'nulo'}]).get('rows') or [{}])[0]
        check('K4 %s un null dado a un campo con defecto escribe NULL, no el defecto (tambien en la fila devuelta)' % motor,
              r.get('affected') == 1 and fn.get('marca', 'falta') is None
              and (r.get('row') or {}).get('marca', 'falta') is None, (r, fn))

        antes = filas(TK).get('total')
        r = llama({'command': 'insert', 'db': D, 'table': TK, 'values': [{'field': 'nombre', 'value': 'sin obligado'}]})
        check('K5 %s un insert que la base rechaza: DB-010 y nada escrito' % motor,
              mc.abre(r, 'SR_DB_RESPONDE_FMT') and filas(TK).get('total') == antes, r[:300])

        TODAS = [{'field': 'id', 'op': 'greater', 'value': 0}]
        CIEN = [{'field': 'id', 'op': 'less_or_equal', 'value': 100}]

        def suma():
            g = mc.como_json(llama({'command': 'summary', 'db': D, 'table': TN,
                                    'values': [{'field': 'v', 'op': 'sum'}]})).get('groups') or [{}]
            return g[0].get('sum_v')

        r = llama({'command': 'update', 'db': D, 'table': TN, 'values': [{'field': 'v', 'value': 1}], 'filters': TODAS})
        check('K6 %s update de 150 filas sin max: DB-028 con cuantas y nada cambiado' % motor,
              mc.abre(r, 'SR_DB_TOCARIA_FMT') and '150' in r and suma() == 0, r[:300])
        r = mc.como_json(llama({'command': 'update', 'db': D, 'table': TN, 'values': [{'field': 'v', 'value': 1}],
                                'filters': CIEN}))
        check('K6 %s update de 100 justas (el tope por defecto): pasan' % motor,
              r.get('affected') == 100 and suma() == 100, (r, suma()))
        r = mc.como_json(llama({'command': 'update', 'db': D, 'table': TN, 'values': [{'field': 'v', 'value': 2}],
                                'filters': TODAS, 'max': 150}))
        check('K6 %s update de 150 con max=150: pasan' % motor, r.get('affected') == 150 and suma() == 300, (r, suma()))
        r = llama({'command': 'delete', 'db': D, 'table': TN, 'filters': TODAS})
        check('K6 %s delete de 150 sin max: DB-028 y ninguna borrada' % motor,
              mc.abre(r, 'SR_DB_TOCARIA_FMT') and filas(TN).get('total') == 150, r[:300])
        r = mc.como_json(llama({'command': 'delete', 'db': D, 'table': TN, 'filters': TODAS, 'max': 200}))
        check('K6 %s delete de 150 con max=200: borradas' % motor,
              r.get('affected') == 150 and filas(TN).get('total') == 0, r)

        r = llama({'command': 'insert', 'db': D, 'table': TK, 'max': 5,
                   'values': [{'field': 'nombre', 'value': 'x'}, {'field': 'obligado', 'value': 1}]})
        check('K7 %s max con insert: DB-020' % motor, mc.abre(r, 'SR_DB_NO_VA_CON_COMANDO_FMT'), r[:300])

        r = mc.como_json(llama({'command': 'insert', 'db': D, 'table': TS,
                                'values': [{'field': 'nombre', 'value': 'sin clave'}]}))
        fs = (mc.como_json(llama({'command': 'rows', 'db': D, 'table': TS})).get('rows') or [{}])[0]
        check('K10 %s insert en una tabla SIN clave con un defecto sin dar: escrito, sin row y DB-031' % motor,
              r.get('affected') == 1 and 'row' not in r and str(r.get('rowNote', '')).startswith('[DB-031]')
              and fs.get('nombre') == 'sin clave' and fs.get('v') == 7, (r, fs))

    fug = arnes.fugas(SECRETOS, respuestas)
    check('K9 ningun secreto del json en ninguna respuesta (%d respuestas)' % len(respuestas), not fug,
          'secretos que aparecen: posiciones %s de %d' % (fug, len(SECRETOS)))
finally:
    if srv:
        srv.cierra()
    try:
        arnes.sql_mssql(BASE, SRV, 'mssql', MS_BORRA)
        arnes.sql_pg(BASE, PG, PG_BORRA)
    finally:
        mc.borra(BASE)
mc.fin(TITULO)
