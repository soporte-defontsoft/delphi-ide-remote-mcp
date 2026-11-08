# -*- coding: utf-8 -*-
"""delphi_db (1.29), lo que la pasada en vivo como agente encontro (8-nov-2026, contra las bases de Galatea), en
los DOS motores enlazados (MSSQL y PostgreSQL). Las bases y su arnes, en db_arnes; el juez de cada cosa es la
tabla que el arnes crea con su SQL.

  K1  fields dice lo que la base pone sola en un insert que no lo da: autoinc en el contador de la clave, default
      en los campos con valor por defecto, y nada en los demas (el agente lo sabia a base de DB-010, uno por
      campo). ROJO contra 0b408580
  K2  un insert sin los campos con defecto: affected 1 y la base pone los suyos (el contador y los defectos que
      fields anuncia). La clave de la fila nueva NO viene en la respuesta (medido el 8-nov-2026: por un
      dataset de FireDAC venia, pero colgaba el hilo con la red callada, P4/P6 de test_db_plazo_llamada_129;
      queda para la 1.29.1, compuesta por el generador de FireDAC)
  K4  un null dado a un campo con valor por defecto escribe NULL, no el defecto
  K5  un insert que la base rechaza (un obligatorio sin dar): DB-010 y nada escrito
  K6  update y delete de MAS filas que su max (por defecto 100): DB-028 con cuantas, y nada cambiado (se deshace
      en su transaccion); 100 justas pasan; con max=N, si. ROJO contra 0b408580 (tocaba las 150)
  K7  max con un comando que no es update ni delete: DB-020
  K8  tables de una base sin tablas ni vistas: la nota dice el esquema que miro (DB-029); con tablas, ninguna
      nota. Lo de "sin tablas" lo dice el arnes (si otra bateria dejo las suyas, se dice y no se mide)
  K9  ningun secreto del json en ninguna respuesta

Uso:  python tests/test_db_clave_129.py [ruta-a-DelphiLspMcp.exe]
"""
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TITULO = 'delphi_db 1.29 (clave del insert, defectos, max, esquema vacio; MSSQL y PG)'
TK, TL, TN = 't_db129k', 't_db129k_log', 't_db129k_n'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_clave_129', TITULO)
SECRETOS = arnes.secretos(MS, PG)
arnes.escribe_conexiones(SRV, {
    'mssql': arnes.entrada(MS, readonly=False),
    'pg': arnes.entrada(PG, readonly=False)})
MS_BORRA = ("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE "
            "dbo.%s; IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s;" % (TK, TK, TL, TL, TN, TN))
MS_DDL = MS_BORRA + (
    "CREATE TABLE dbo.%s (n int IDENTITY(1000,1) PRIMARY KEY, nota nvarchar(20) NULL); "
    "CREATE TABLE dbo.%s (id int IDENTITY(1,1) PRIMARY KEY, nombre nvarchar(40) NOT NULL, "
    "estado int NOT NULL DEFAULT 5, marca nvarchar(10) NULL DEFAULT N'def', obligado int NOT NULL); "
    "CREATE TABLE dbo.%s (id int PRIMARY KEY, v int NOT NULL); "
    ";WITH n AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 150) "
    "INSERT INTO dbo.%s (id, v) SELECT i, 0 FROM n OPTION (MAXRECURSION 200);" % (TL, TK, TN, TN))
# CREATE TRIGGER va solo en su lote
MS_TRIGGER = ("CREATE TRIGGER dbo.%s_tr ON dbo.%s AFTER INSERT AS INSERT INTO dbo.%s (nota) SELECT N'trigger' "
              "FROM inserted;" % (TK, TK, TL))
PG_BORRA = 'DROP TABLE IF EXISTS %s, %s, %s;' % (TK, TL, TN)
PG_DDL = PG_BORRA + (
    " CREATE TABLE %s (id serial PRIMARY KEY, nombre varchar(40) NOT NULL, estado int NOT NULL DEFAULT 5, "
    "marca varchar(10) NULL DEFAULT 'def', obligado int NOT NULL);"
    " CREATE TABLE %s (id int PRIMARY KEY, v int NOT NULL);"
    " INSERT INTO %s SELECT g, 0 FROM generate_series(1, 150) g;" % (TK, TN, TN))

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
                         'marca': (False, True), 'obligado': (False, False)}, j)

        r1 = mc.como_json(llama({'command': 'insert', 'db': D, 'table': TK, 'values': [
            {'field': 'nombre', 'value': 'uno'}, {'field': 'obligado', 'value': 7}]}))
        f1 = (filas(TK, filters=[{'field': 'nombre', 'op': 'equals', 'value': 'uno'}]).get('rows') or [{}])[0]
        check('K2 %s insert sin los campos con defecto: affected 1 y la base pone el contador y los defectos' % motor,
              r1.get('affected') == 1 and isinstance(f1.get('id'), int) and f1.get('estado') == 5
              and f1.get('marca') == 'def', (r1, f1))

        r = mc.como_json(llama({'command': 'insert', 'db': D, 'table': TK, 'values': [
            {'field': 'nombre', 'value': 'nulo'}, {'field': 'obligado', 'value': 1}, {'field': 'marca', 'value': None}]}))
        fn = (filas(TK, filters=[{'field': 'nombre', 'op': 'equals', 'value': 'nulo'}]).get('rows') or [{}])[0]
        check('K4 %s un null dado a un campo con defecto escribe NULL, no el defecto (y sin clave)' % motor,
              r.get('affected') == 1 and 'key' not in r and fn.get('marca', 'falta') is None, (r, fn))

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
