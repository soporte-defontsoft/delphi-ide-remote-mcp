# -*- coding: utf-8 -*-
"""delphi_db (1.29), tercera parte: las ESCRITURAS (insert, update, delete) contra bases reales, en los DOS
motores enlazados (MSSQL y PostgreSQL), solo donde el json de conexiones dice readonly:false. El agente nunca
escribe SQL: nombra la tabla y los campos (del catalogo), da los valores (parametros tipados por su campo) y
los filtros; el servidor compone y FireDAC traduce. Las bases y su arnes, en db_arnes.

  E1  insert: la fila con sus tipos (texto con acento y comodines, fecha y hora, decimal, booleano) y leida
      despues tal cual; affected 1
  E2  insert con numeros como texto y null (tambien en un binario): NULL en la base
  E3  insert de una clave repetida: DB-010 de la base, y nada escrito
  E4  update de una fila por su clave: affected 1, la otra intacta
  E5  update de varias: affected 2
  E6  delete por filtro: affected 1
  E7  update y delete SIN filters, y con filters = [] (sin WHERE tocarian todas): DB-011 y ninguna fila tocada
  E8  una base readonly: insert, update y delete DB-017 y nada escrito; y ANTES de conectar (una readonly
      que no responde contesta al momento, no a los 12 s del plazo)
  E9  values mal: campo que no existe (DB-013, tambien uno con SQL en el nombre), valor que no cabe, binario
      no nulo, entrada sin value (DB-014), values que no es una lista (DB-015), values vacio (DB-011)
  E10 un parametro que no es del comando: insert con filters, delete con values (DB-020)
  E11 un valor con SQL dentro se escribe tal cual (es un parametro) y la tabla sigue ahi
  E12 una credencial de solo lectura (--readonly): insert, update y delete negados en la puerta (READ-002);
      rows si
  E13 ningun secreto del json en ninguna respuesta

Uso:  python tests/test_db_escrituras_129.py [ruta-a-DelphiLspMcp.exe]
"""
import time
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TABLA = 't_db129w'
TITULO = 'delphi_db 1.29 (escrituras, MSSQL y PG)'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_escrituras_129', TITULO)
SECRETOS = arnes.secretos(MS, PG)
arnes.escribe_conexiones(SRV, {
    'mssql': arnes.entrada(MS, readonly=False),
    'pg': arnes.entrada(PG, readonly=False),
    'mssql_ro': arnes.entrada(MS, readonly=True),
    'pg_ro': arnes.entrada(PG, readonly=True),
    'ro_caida': {'server': '192.0.2.1', 'database': 'x', 'user': 'x', 'password': 'x', 'engine': 'MSSQL',
                 'provider': 'FIREDAC', 'readonly': True}})
MS_DDL = ("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; CREATE TABLE dbo.%s (id int PRIMARY KEY, nombre "
          "nvarchar(60) NULL, alta datetime2 NULL, importe decimal(10,2) NULL, activo bit NULL, foto varbinary(100) "
          "NULL);" % (TABLA, TABLA, TABLA))
PG_DDL = ("DROP TABLE IF EXISTS %s; CREATE TABLE %s (id int PRIMARY KEY, nombre varchar(60), alta timestamp, importe "
          "numeric(10,2), activo boolean, foto bytea);" % (TABLA, TABLA))
NOMBRE = chr(0xC1) + 'nade 50%_x'
TRAMPA = "x'); DROP TABLE " + TABLA + "; --"
UNO = [{'field': 'id', 'op': 'equals', 'value': 1}]

srv = None
respuestas = []


def llama(s, args, t=None):
    r = s.call('delphi_db', args, t)
    respuestas.append(r)
    return r


try:
    hay = {'mssql': arnes.sql_mssql(BASE, SRV, 'mssql', MS_DDL), 'pg': arnes.sql_pg(BASE, PG, PG_DDL)}
    for m, h in hay.items():
        if not h:
            print('NOTA: %s no responde o no deja crear %s: no se mide' % (m, TABLA))
    ENV = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': arnes.PROYECTO})
    srv = mc.Stdio(EXE, ENV, nombre='db-escrituras', t=120)

    def db(args, t=None):
        return llama(srv, args, t)

    for motor in [m for m in ('mssql', 'pg') if hay[m]]:
        D = arnes.PROYECTO + '/' + motor

        def filas(**extra):
            return mc.como_json(db(dict({'command': 'rows', 'db': D, 'table': TABLA, 'order': 'id'}, **extra)))

        def ids():
            return [x.get('id') for x in filas(fields=['id']).get('rows', [])]

        def afectadas(r):
            return mc.como_json(r).get('affected')

        r = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': [
            {'field': 'id', 'value': 1}, {'field': 'nombre', 'value': NOMBRE},
            {'field': 'alta', 'value': '2025-02-03T04:05:06'}, {'field': 'importe', 'value': 12.34},
            {'field': 'activo', 'value': True}]})
        f = (filas().get('rows') or [{}])[0]
        check('E1 %s insert: affected 1 y la fila tal cual (acento, comodines, fecha y hora, decimal, booleano)'
              % motor, afectadas(r) == 1 and f == {'id': 1, 'nombre': NOMBRE, 'alta': '2025-02-03T04:05:06',
                                                    'importe': 12.34, 'activo': True}, (r[:300], f))
        r = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': [
            {'field': 'id', 'value': '2'}, {'field': 'importe', 'value': '7.50'}, {'field': 'nombre', 'value': None},
            {'field': 'foto', 'value': None}]})
        f = (filas(filters=[{'field': 'id', 'op': 'equals', 'value': 2}]).get('rows') or [{}])[0]
        check('E2 %s insert con numeros como texto y null (tambien en un binario): NULL en la base' % motor,
              afectadas(r) == 1 and f == {'id': 2, 'nombre': None, 'alta': None, 'importe': 7.5, 'activo': None},
              (r[:300], f))
        r = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': [{'field': 'id', 'value': 1}]})
        # el texto del motor acaba en punto y el mensaje pone el suyo: "exists.. Nothing" (medido en vivo)
        check('E3 %s insert de una clave repetida: DB-010 sin doble punto, y nada escrito' % motor,
              mc.abre(r, 'SR_DB_RESPONDE_FMT') and '..' not in r and ids() == [1, 2], r[:400])
        r = db({'command': 'update', 'db': D, 'table': TABLA, 'values': [{'field': 'importe', 'value': 99.99}],
                'filters': UNO})
        fs = filas(fields=['id', 'importe']).get('rows')
        check('E4 %s update de una fila por su clave: affected 1, la otra intacta' % motor,
              afectadas(r) == 1 and fs == [{'id': 1, 'importe': 99.99}, {'id': 2, 'importe': 7.5}], (r[:300], fs))
        r = db({'command': 'update', 'db': D, 'table': TABLA, 'values': [
            {'field': 'activo', 'value': False}, {'field': 'alta', 'value': '2026-11-06'}],
            'filters': [{'field': 'id', 'op': 'greater', 'value': 0}]})
        fs = filas(fields=['activo', 'alta']).get('rows')
        check('E5 %s update de varias filas: affected 2' % motor,
              afectadas(r) == 2 and fs == [{'activo': False, 'alta': '2026-11-06T00:00:00'}] * 2, (r[:300], fs))
        # sin filters lo niega la tool antes de conectar; con filters = [] llega la lista vacia (su texto JSON) y
        # lo niega la segunda barrera, la del WHERE vacio: sin ella, la fila 2 se iria
        for cmd, extra in (('update', {'values': [{'field': 'importe', 'value': 0}]}), ('delete', {})):
            for filtros in (None, []):
                a = dict({'command': cmd, 'db': D, 'table': TABLA}, **extra)
                if filtros is not None:
                    a['filters'] = filtros
                r = db(a)
                fs = filas(fields=['id', 'importe']).get('rows')
                check('E7 %s %s %s: DB-011 y ninguna fila tocada' % (
                    motor, cmd, 'sin filters' if filtros is None else 'con filters = []'),
                    mc.abre(r, 'SR_DB_FALTA_FMT') and fs == [{'id': 1, 'importe': 99.99}, {'id': 2, 'importe': 7.5}],
                    (r[:300], fs))
        # CH6 del revisor del paisaje de la 1.29: un filtro de texto SIN nada que buscar (contains sin value, words de
        # blancos) casaba con todas las filas no nulas (LIKE '%%') y pasaba la guarda del WHERE: un delete borraba la
        # fila 1 (su nombre no es nulo). Negado antes de tocar nada
        for filtro in ({'field': 'nombre', 'op': 'contains'}, {'field': 'nombre', 'op': 'words', 'value': '  '}):
            r = db({'command': 'delete', 'db': D, 'table': TABLA, 'filters': [filtro]})
            check('E7b %s delete con %s sin nada que buscar: negado y ninguna fila tocada' % (motor, filtro['op']),
                  mc.abre(r, 'SR_DB_ENTRADA_FMT') and ids() == [1, 2], (r[:300], ids()))
        r = db({'command': 'delete', 'db': D, 'table': TABLA, 'filters': [{'field': 'id', 'op': 'equals', 'value': 2}]})
        check('E6 %s delete por filtro: affected 1, queda la otra' % motor, afectadas(r) == 1 and ids() == [1], r[:300])
        DR = D + '_ro'
        for a in ({'command': 'insert', 'db': DR, 'table': TABLA, 'values': [{'field': 'id', 'value': 9}]},
                  {'command': 'update', 'db': DR, 'table': TABLA, 'values': [{'field': 'importe', 'value': 1}],
                   'filters': UNO},
                  {'command': 'delete', 'db': DR, 'table': TABLA, 'filters': UNO}):
            r = db(a)
            fs = filas(fields=['id', 'importe']).get('rows')
            check('E8 %s %s en una base readonly: DB-017 y nada escrito' % (motor, a['command']),
                  mc.abre(r, 'SR_DB_SOLO_LECTURA_FMT') and fs == [{'id': 1, 'importe': 99.99}], (r[:300], fs))
        cat = mc.catalogo()
        malas = [
            ([{'field': 'no_existe', 'value': 1}], 'SR_DB_CAMPO_FMT', ''),
            ([{'field': 'nombre) VALUES (5); --', 'value': 1}], 'SR_DB_CAMPO_FMT', ''),
            ([{'field': 'id', 'value': 'abc'}], 'SR_DB_ENTRADA_FMT', ''),
            ([{'field': 'id', 'value': 5}, {'field': 'foto', 'value': 'AQID'}], 'SR_DB_ENTRADA_FMT',
             cat['SF_DB_VALOR_BINARIO_FMT'] % 'foto'),
            ([{'field': 'id'}], 'SR_DB_ENTRADA_FMT', cat['SF_DB_VALOR_FORMA']),
            (['id', 5], 'SR_DB_ENTRADA_FMT', cat['SF_DB_VALOR_FORMA']),
            ([], 'SR_DB_FALTA_FMT', '')]
        for valores, codigo, texto in malas:
            r = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': valores})
            check('E9 %s insert values=%s -> %s, nada escrito' % (motor, str(valores)[:60], codigo),
                  mc.abre(r, codigo) and texto in r and ids() == [1], r[:300])
        r1 = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': [{'field': 'id', 'value': 7}],
                 'filters': UNO})
        r2 = db({'command': 'delete', 'db': D, 'table': TABLA, 'values': [{'field': 'id', 'value': 7}],
                 'filters': UNO})
        check('E10 %s insert con filters y delete con values: DB-020, nada tocado' % motor,
              mc.abre(r1, 'SR_DB_NO_VA_CON_COMANDO_FMT') and mc.abre(r2, 'SR_DB_NO_VA_CON_COMANDO_FMT')
              and ids() == [1], (r1[:200], r2[:200]))
        r = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': [
            {'field': 'id', 'value': 3}, {'field': 'nombre', 'value': TRAMPA}]})
        fs = filas(fields=['id', 'nombre']).get('rows')
        check('E11 %s un valor con SQL dentro se escribe tal cual y la tabla sigue ahi' % motor,
              afectadas(r) == 1 and fs == [{'id': 1, 'nombre': NOMBRE}, {'id': 3, 'nombre': TRAMPA}], (r[:300], fs))

    t0 = time.time()
    r = db({'command': 'insert', 'db': arnes.PROYECTO + '/ro_caida', 'table': 'x',
            'values': [{'field': 'id', 'value': 1}]}, 60)
    seg = time.time() - t0
    check('E8 una readonly que no responde: DB-017 al momento, antes de conectar (%.1f s)' % seg,
          mc.abre(r, 'SR_DB_SOLO_LECTURA_FMT') and seg < 5, (round(seg, 1), r[:300]))
    srv.cierra()
    srv = None
    medidos = [m for m in ('mssql', 'pg') if hay[m]]
    if medidos:
        D = arnes.PROYECTO + '/' + medidos[0]
        srv = mc.Stdio(EXE, ENV, nombre='db-escrituras-ro', args=('--readonly',), t=120)
        for a in ({'command': 'insert', 'db': D, 'table': TABLA, 'values': [{'field': 'id', 'value': 8}]},
                  {'command': 'update', 'db': D, 'table': TABLA, 'values': [{'field': 'importe', 'value': 1}],
                   'filters': UNO},
                  {'command': 'delete', 'db': D, 'table': TABLA, 'filters': UNO}):
            r = llama(srv, a)
            check('E12 --readonly: %s negado en la puerta (READ-002)' % a['command'], mc.abre(r, 'SR_READ_ONLY_FMT'),
                  r[:300])
        r = llama(srv, {'command': 'rows', 'db': D, 'table': TABLA, 'fields': ['id'], 'order': 'id'})
        check('E12 --readonly: rows si, y la tabla como estaba',
              [x.get('id') for x in mc.como_json(r).get('rows', [])] == [1, 3], r[:300])
    fug = arnes.fugas(SECRETOS, respuestas)
    check('E13 ningun secreto del json en ninguna respuesta (%d respuestas)' % len(respuestas), not fug,
          'secretos que aparecen: posiciones %s de %d' % (fug, len(SECRETOS)))
finally:
    if srv:
        srv.cierra()
    try:
        arnes.sql_mssql(BASE, SRV, 'mssql', "IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s;" % (TABLA, TABLA))
        arnes.sql_pg(BASE, PG, 'DROP TABLE IF EXISTS %s;' % TABLA)
    finally:
        mc.borra(BASE)
mc.fin(TITULO)
