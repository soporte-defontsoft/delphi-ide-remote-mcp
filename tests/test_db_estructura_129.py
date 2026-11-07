# -*- coding: utf-8 -*-
"""delphi_db 1.29 (C5, DB-P6): create-table y create-view, en MSSQL y PostgreSQL, solo donde el json de conexiones
da allowCreate:true (y readonly:false). El SQL de una tabla lo compone EL generador de FireDAC para cada motor
(GenerateCreateTable, sin goSkipUnsupTypes: un tipo que el motor no tiene lo niega el, no se salta); el de una
vista es CREATE VIEW <vista> AS SELECT <campos> FROM <tabla>, sin filtros (un WHERE pediria literales y las macros
de texto de FireDAC dejan el SQL sin cerrar con una comilla: medido el 7-nov-2026 con la sonda MideDdl129). Nunca
DROP ni ALTER: un nombre que ya existe se niega.

  S1  create-table tipica (clave autoincremental, texto con tamano y obligatorio, decimal, fecha, booleano, memo y
      una columna 'real' - palabra reservada que el generador cita -): la respuesta da el SQL ejecutado, tables la
      lista, fields la lee como la nombra la base, y un insert sin id le da su clave. ROJO contra 166bea8b (no habia
      create-table: DB-006)
  S2  el permiso: sin allowCreate DB-023; con readonly:true DB-017 (el de leer manda); allowCreate que no es
      true/false = la entrada no se usa (unusable); connections dice allowCreate como vale
  S3  un nombre que ya es una tabla o una vista: DB-024, nada cambia
  S4  un tipo que el motor no tiene (MSSQL: dtTimeIntervalFull; PG: dtCursorRef): DB-010 con el -353 de FireDAC y
      la tabla no existe (tampoco su otra columna)
  S5  la forma, antes de abrir la base: nombres que no son identificadores (DB-025), un tipo que FireDAC no tiene,
      una clave de entrada desconocida, numeros y si/no de otro tipo, una columna repetida (DB-014), la lista (DB-015)
  S6  create-view con fields y sin ellos (todas): rows por la vista lee la fila; filters no va con create-view (DB-020)
  S7  mayusculas: la tabla y la vista nuevas siguen LA regla del generador (PG: en minusculas, como sin comillas;
      MSSQL: tal cual)
  S8  un servidor --readonly niega create-table y create-view en la puerta (READ-002)
  S9  ningun secreto del json en ninguna respuesta

Uso:  python tests/test_db_estructura_129.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TABLA = 't_db129c'
VISTA = 'v_db129c'
VISTA_TODA = 'v_db129c_toda'
RARA = 't_db129c_rara'
MIXTA = 'TDb129Mixta'
VISTA_MIXTA = 'VDb129Mixta'
TITULO = 'delphi_db 1.29 (create-table y create-view, MSSQL y PG)'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_estructura_129', TITULO)
SECRETOS = arnes.secretos(MS, PG)
arnes.escribe_conexiones(SRV, {
    'mssql': arnes.entrada(MS, readonly=False, allowCreate=True),
    'pg': arnes.entrada(PG, readonly=False, allowCreate=True),
    'mssql_sin': arnes.entrada(MS, readonly=False),
    'pg_sin': arnes.entrada(PG, readonly=False),
    'mssql_ro': arnes.entrada(MS, readonly=True, allowCreate=True),
    'pg_ro': arnes.entrada(PG, readonly=True, allowCreate=True),
    'mala': arnes.entrada(MS, readonly=False, allowCreate='si')})
LIMPIA_MS = ''.join("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP VIEW dbo.%s; " % (v, v)
                    for v in (VISTA, VISTA_TODA, VISTA_MIXTA)) + \
    ''.join("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; " % (t, t) for t in (TABLA, RARA, MIXTA))
LIMPIA_PG = 'DROP VIEW IF EXISTS %s, %s, %s; DROP TABLE IF EXISTS %s, %s, %s;' % (
    VISTA, VISTA_TODA, VISTA_MIXTA.lower(), TABLA, RARA, MIXTA.lower())
COLUMNAS = [{'name': 'id', 'type': 'dtInt32', 'key': True, 'autoinc': True},
            {'name': 'nombre', 'type': 'dtWideString', 'size': 60, 'required': True},
            {'name': 'importe', 'type': 'dtFmtBCD', 'precision': 10, 'scale': 2},
            {'name': 'alta', 'type': 'dtDateTime'},
            {'name': 'activo', 'type': 'dtBoolean'},
            {'name': 'nota', 'type': 'dtWideMemo'},
            {'name': 'real', 'type': 'dtDouble'}]
NOMBRE = chr(0xC1) + 'nade ' + chr(0x0416) + " O'Brien"
SIN_MOTOR = {'mssql': 'dtTimeIntervalFull', 'pg': 'dtCursorRef'}

srv = None
respuestas = []


def llama(s, args, t=None):
    r = s.call('delphi_db', args, t)
    respuestas.append(r)
    return r


try:
    hay = {'mssql': arnes.sql_mssql(BASE, SRV, 'mssql', LIMPIA_MS), 'pg': arnes.sql_pg(BASE, PG, LIMPIA_PG)}
    for m, h in hay.items():
        if not h:
            print('NOTA: %s no responde o no deja limpiar: no se mide' % m)
    ENV = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': arnes.PROYECTO})
    srv = mc.Stdio(EXE, ENV, nombre='db-estructura', t=120)

    def db(args, t=None):
        return llama(srv, args, t)

    con = mc.como_json(db({'command': 'connections'})) or {}
    bases = {b.get('db'): b for b in con.get('databases') or []}
    P = arnes.PROYECTO + '/'
    check('S2 connections: allowCreate como vale (si con permiso; no sin el, ni con readonly:true)',
          bases.get(P + 'mssql', {}).get('allowCreate') is True and bases.get(P + 'pg', {}).get('allowCreate') is True
          and bases.get(P + 'mssql_sin', {}).get('allowCreate') is False
          and bases.get(P + 'pg_ro', {}).get('allowCreate') is False, json.dumps(con)[:600])
    malas = {u.get('db'): u.get('why', '') for u in con.get('unusable') or []}
    check('S2 allowCreate que no es true/false: la entrada no se usa y dice por que',
          mc.catalogo()['SF_DB_DEF_CREAR'] in malas.get(P + 'mala', ''), json.dumps(con)[:600])

    for motor in [m for m in ('mssql', 'pg') if hay[m]]:
        D = P + motor

        def tablas():
            j = mc.como_json(db({'command': 'tables', 'db': D})) or {}
            return [t.lower() for t in j.get('tables') or []], [v.lower() for v in j.get('views') or []]

        def crea(nombre, columnas, d=D):
            return db({'command': 'create-table', 'db': d, 'table': nombre, 'columns': columnas})

        # ------------------------------------------------------------------ S1
        r = crea(TABLA, COLUMNAS)
        j = mc.como_json(r) or {}
        sql = ' '.join(j.get('sql') or [])
        check('S1 %s create-table: la tabla y el SQL que se ejecuto (DB-026). ROJO contra 166bea8b' % motor,
              (j.get('table') or '').lower() == TABLA and 'CREATE TABLE' in sql.upper() and
              mc.abre(j.get('note', ''), 'SN_DB_CREADO'), r[:600])
        check('S1 %s ...tables la lista' % motor, TABLA in tablas()[0], tablas())
        f = mc.como_json(db({'command': 'fields', 'db': D, 'table': TABLA})) or {}
        campos = {c.get('name', '').lower(): c for c in f.get('fields') or []}
        check('S1 %s ...fields: las 7 columnas, id clave, nombre obligatorio de 60, importe 10,2, real citada y creada'
              % motor, sorted(campos) == sorted(c['name'] for c in COLUMNAS) and campos['id'].get('key') is True
              and campos['nombre'].get('nullable') is False and campos['nombre'].get('length') == 60
              and campos['importe'].get('precision') == 10 and campos['importe'].get('scale') == 2
              and campos['activo'].get('nullable') is True, json.dumps(f)[:900])
        r = db({'command': 'insert', 'db': D, 'table': TABLA, 'values': [
            {'field': 'nombre', 'value': NOMBRE}, {'field': 'importe', 'value': 12.5},
            {'field': 'activo', 'value': True}, {'field': 'real', 'value': 1.25}]})
        fs = (mc.como_json(db({'command': 'rows', 'db': D, 'table': TABLA,
                                'fields': ['id', 'nombre', 'importe', 'activo', 'real']})) or {}).get('rows')
        check('S1 %s ...un insert sin id: su clave la pone la base (1) y la fila tal cual (acentos, cirilico, comilla)'
              % motor, fs == [{'id': 1, 'nombre': NOMBRE, 'importe': 12.5, 'activo': True, 'real': 1.25}],
              (r[:300], fs))

        # ------------------------------------------------------------------ S2
        r = crea('t_db129c_sin', [{'name': 'id', 'type': 'dtInt32'}], D + '_sin')
        check('S2 %s sin allowCreate: DB-023 y no existe' % motor,
              mc.abre(r, 'SR_DB_SIN_CREAR_FMT') and 't_db129c_sin' not in tablas()[0], r[:300])
        r = crea('t_db129c_ro', [{'name': 'id', 'type': 'dtInt32'}], D + '_ro')
        check('S2 %s readonly:true aunque diga allowCreate: DB-017 y no existe' % motor,
              mc.abre(r, 'SR_DB_SOLO_LECTURA_FMT') and 't_db129c_ro' not in tablas()[0], r[:300])

        # ------------------------------------------------------------------ S3
        antes = json.dumps(f)
        r = crea(TABLA, [{'name': 'otra', 'type': 'dtInt32'}])
        despues = json.dumps(mc.como_json(db({'command': 'fields', 'db': D, 'table': TABLA})) or {})
        check('S3 %s create-table de una que ya existe: DB-024 y la tabla como estaba' % motor,
              mc.abre(r, 'SR_DB_YA_EXISTE_FMT') and antes == despues, r[:300])
        r = db({'command': 'create-view', 'db': D, 'table': TABLA, 'view': TABLA})
        check('S3 %s create-view con el nombre de una tabla: DB-024' % motor, mc.abre(r, 'SR_DB_YA_EXISTE_FMT'),
              r[:300])

        # ------------------------------------------------------------------ S4
        r = crea(RARA, [{'name': 'buena', 'type': 'dtInt32'}, {'name': 'rara', 'type': SIN_MOTOR[motor]}])
        check('S4 %s un tipo que %s no tiene (%s): DB-010 con el -353 de FireDAC, y la tabla no existe' % (
              motor, motor, SIN_MOTOR[motor]),
              mc.abre(r, 'SR_DB_RESPONDE_FMT') and '353' in r and SIN_MOTOR[motor] in r and RARA not in tablas()[0],
              r[:400])

        # ------------------------------------------------------------------ S6
        r = db({'command': 'create-view', 'db': D, 'table': TABLA, 'view': VISTA, 'fields': ['id', 'nombre']})
        j = mc.como_json(r) or {}
        check('S6 %s create-view con fields: la vista, sus campos y su SQL (una lista, como la de create-table)' % motor,
              (j.get('view') or '').lower() == VISTA and [x.lower() for x in j.get('fields') or []] == ['id', 'nombre']
              and isinstance(j.get('sql'), list) and 'CREATE VIEW' in ' '.join(j.get('sql')).upper()
              and VISTA in tablas()[1], r[:500])
        fs = (mc.como_json(db({'command': 'rows', 'db': D, 'table': VISTA})) or {}).get('rows')
        check('S6 %s ...rows por la vista lee la fila' % motor, fs == [{'id': 1, 'nombre': NOMBRE}], fs)
        r = db({'command': 'create-view', 'db': D, 'table': TABLA, 'view': VISTA_TODA})
        j = mc.como_json(r) or {}
        check('S6 %s create-view sin fields: todas las columnas' % motor,
              sorted(x.lower() for x in j.get('fields') or []) == sorted(c['name'] for c in COLUMNAS), r[:500])
        r = db({'command': 'create-view', 'db': D, 'table': TABLA, 'view': 'v_db129c_filtro',
                'filters': [{'field': 'id', 'op': 'equals', 'value': 1}]})
        check('S6 %s create-view con filters: DB-020 y no existe' % motor,
              mc.abre(r, 'SR_DB_NO_VA_CON_COMANDO_FMT') and 'v_db129c_filtro' not in tablas()[1], r[:300])

        # ------------------------------------------------------------------ S7
        r1 = crea(MIXTA, [{'name': 'Codigo', 'type': 'dtInt32'}])
        r2 = db({'command': 'create-view', 'db': D, 'table': (mc.como_json(r1) or {}).get('table', MIXTA),
                 'view': VISTA_MIXTA})
        t1, t2 = (mc.como_json(r1) or {}).get('table'), (mc.como_json(r2) or {}).get('view')
        esperado = (MIXTA, VISTA_MIXTA) if motor == 'mssql' else (MIXTA.lower(), VISTA_MIXTA.lower())
        check('S7 %s mayusculas: tabla y vista nuevas por LA regla del generador (%s, %s)' % ((motor,) + esperado),
              (t1, t2) == esperado, (r1[:300], r2[:300]))

    # ---------------------------------------------------------------------- S5 (sin abrir la base)
    D = P + 'mssql'
    cat = mc.catalogo()
    formas = [
        ({'table': 't x', 'columns': [{'name': 'id', 'type': 'dtInt32'}]}, 'SR_DB_NOMBRE_NUEVO_FMT', ''),
        ({'table': 't;drop', 'columns': [{'name': 'id', 'type': 'dtInt32'}]}, 'SR_DB_NOMBRE_NUEVO_FMT', ''),
        ({'table': 't_db129c_f', 'columns': [{'name': 'a b', 'type': 'dtInt32'}]}, 'SR_DB_NOMBRE_NUEVO_FMT', ''),
        ({'table': 't_db129c_f', 'columns': [{'name': 'id', 'type': 'varchar'}]}, 'SR_DB_ENTRADA_FMT',
         cat['SF_DB_COLUMNA_TIPO_FMT'] % 'varchar'),
        ({'table': 't_db129c_f', 'columns': [{'name': 'id', 'type': 'dtInt32', 'nombre': 'x'}]}, 'SR_DB_ENTRADA_FMT',
         'nombre'),
        ({'table': 't_db129c_f', 'columns': [{'name': 'id', 'type': 'dtWideString', 'size': '50'}]},
         'SR_DB_ENTRADA_FMT', 'size'),
        ({'table': 't_db129c_f', 'columns': [{'name': 'id', 'type': 'dtInt32', 'key': 'yes'}]}, 'SR_DB_ENTRADA_FMT',
         'key'),
        ({'table': 't_db129c_f', 'columns': [{'name': 'id', 'type': 'dtInt32'}, {'name': 'ID', 'type': 'dtInt64'}]},
         'SR_DB_ENTRADA_FMT', 'ID'),
        ({'table': 't_db129c_f', 'columns': [{'type': 'dtInt32'}]}, 'SR_DB_ENTRADA_FMT', ''),
        ({'table': 't_db129c_f', 'columns': []}, 'SR_DB_LISTA_FMT', ''),
        ({'table': 't_db129c_f', 'columns': 'no es una lista'}, 'SR_DB_LISTA_FMT', ''),
        ({'table': 't_db129c_f'}, 'SR_DB_FALTA_FMT', ''),
    ]
    for args, codigo, texto in formas:
        r = db(dict({'command': 'create-table', 'db': D}, **args))
        check('S5 create-table %s -> %s' % (json.dumps(args)[:70], codigo), mc.abre(r, codigo) and texto in r, r[:300])
    r = db({'command': 'create-view', 'db': D, 'table': TABLA, 'view': 'v x'})
    check('S5 create-view con un nombre que no es un identificador: DB-025', mc.abre(r, 'SR_DB_NOMBRE_NUEVO_FMT'),
          r[:300])
    r = db({'command': 'create-view', 'db': D, 'table': TABLA})
    check('S5 create-view sin view: DB-011', mc.abre(r, 'SR_DB_FALTA_FMT'), r[:300])

    srv.cierra()
    srv = None
    # ---------------------------------------------------------------------- S8
    srv = mc.Stdio(EXE, ENV, nombre='db-estructura-ro', args=('--readonly',), t=120)
    for a in ({'command': 'create-table', 'db': D, 'table': 't_db129c_ro2', 'columns': [{'name': 'id',
                                                                                       'type': 'dtInt32'}]},
              {'command': 'create-view', 'db': D, 'table': TABLA, 'view': 'v_db129c_ro2'}):
        r = llama(srv, a)
        check('S8 --readonly: %s negado en la puerta (READ-002)' % a['command'], mc.abre(r, 'SR_READ_ONLY_FMT'),
              r[:300])
    fug = arnes.fugas(SECRETOS, respuestas)
    check('S9 ningun secreto del json en ninguna respuesta (%d respuestas)' % len(respuestas), not fug,
          'secretos que aparecen: posiciones %s de %d' % (fug, len(SECRETOS)))
finally:
    if srv:
        srv.cierra()
    try:
        arnes.sql_mssql(BASE, SRV, 'mssql', LIMPIA_MS)
        arnes.sql_pg(BASE, PG, LIMPIA_PG)
    finally:
        mc.borra(BASE)
mc.fin(TITULO)
