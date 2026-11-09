# -*- coding: utf-8 -*-
"""delphi_db 1.29 (CH13, CH14, CH15 del revisor del paisaje): los nombres que un agente da y los que compone el
servidor, en MSSQL y PostgreSQL.

  (Contra 166bea8b: 5 de 10 en rojo, N1, N3 y N5; N3 contestaba {"n":5,"n":2}.)
  N1  CH13 order de un campo con un espacio en el nombre ("Fecha Alta desc"): se ordena por el. Partir por
      espacios lo negaba con DB-016. ROJO contra 166bea8b
  N2  ...y un espacio que no es de un campo sigue siendo la forma de order: 'id sideways' es DB-016 (lo de antes)
  N3  CH15 summary agrupando por un campo llamado n: la cuenta tambien es n, dos claves iguales en cada grupo ->
      DB-027 la nombra. ROJO contra 166bea8b (contestaba con la clave repetida)
  N4  ...un summary sin choque (grupo, sum_n y n) contesta como siempre (control)
  N5  CH15 una entrada del fichero de conexiones con el separador en su nombre (mal/alias): no se usa, y dice por
      que (a/b + c y a + b/c eran el mismo nombre). ROJO contra 166bea8b
  N6  CH14 el contrato dice los topes del codigo: limit (rows, summary y el maximo) son PAGINA_DB_ROWS,
      PAGINA_DB_SUMMARY y TOPE_DB de Lsp.Texts, los que pasa Mcp.Tools.Db a PaginaDe (desde F1-8 de la 1.29
      el texto se compone con ellos y viven alli: antes eran LIMITE_*_DB de Mcp.Tools.Db)

Uso:  python tests/test_db_nombres_129.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import db_arnes as arnes
import mcp_cliente as mc
from mcp_cliente import check

TABLA = 't_db129n'
TITULO = 'delphi_db 1.29 (nombres: order con espacios, etiquetas de summary, entradas)'
BASE, JAIL, SRV, EXE, MS, PG = arnes.prepara('db_nombres_129', TITULO)
arnes.escribe_conexiones(SRV, {
    'mssql': arnes.entrada(MS, access='read'),
    'pg': arnes.entrada(PG, access='read'),
    'mal/alias': arnes.entrada(MS, access='read')})
FILAS = "(1, '2026-01-10', 5, 'a'), (2, '2026-03-01', 7, 'b'), (3, '2026-02-15', 5, 'a')"
CREA_MS = ("IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s; CREATE TABLE dbo.%s (id int PRIMARY KEY, "
           "[Fecha Alta] date, n int, grupo nvarchar(10)); INSERT INTO dbo.%s VALUES %s;"
           % (TABLA, TABLA, TABLA, TABLA, FILAS))
CREA_PG = ('DROP TABLE IF EXISTS %s; CREATE TABLE %s (id int PRIMARY KEY, "Fecha Alta" date, n int, grupo '
           'varchar(10)); INSERT INTO %s VALUES %s;' % (TABLA, TABLA, TABLA, FILAS))
LIMPIA_MS = "IF OBJECT_ID('dbo.%s') IS NOT NULL DROP TABLE dbo.%s;" % (TABLA, TABLA)
LIMPIA_PG = 'DROP TABLE IF EXISTS %s;' % TABLA

srv = None
try:
    hay = {'mssql': arnes.sql_mssql(BASE, SRV, 'mssql', CREA_MS), 'pg': arnes.sql_pg(BASE, PG, CREA_PG)}
    for m, h in hay.items():
        if not h:
            print('NOTA: %s no responde o no deja crear la tabla: no se mide' % m)
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': arnes.PROYECTO}),
                   nombre='db-nombres', t=120)
    P = arnes.PROYECTO + '/'

    def db(args):
        return srv.call('delphi_db', args, 120)

    for motor in [m for m in ('mssql', 'pg') if hay[m]]:
        D = P + motor
        r = db({'command': 'rows', 'db': D, 'table': TABLA, 'order': 'Fecha Alta desc'})
        ids = [f.get('id') for f in (mc.como_json(r) or {}).get('rows', [])]
        check('N1 %s: order por un campo con un espacio ("Fecha Alta desc"). ROJO contra 166bea8b' % motor,
              ids == [2, 3, 1], r[:400])
        r = db({'command': 'rows', 'db': D, 'table': TABLA, 'order': 'id sideways'})
        check('N2 %s: un espacio que no es de un campo, la forma de order (DB-016), como antes' % motor,
              mc.abre(r, 'SR_DB_ORDEN_FMT'), r[:300])
        r = db({'command': 'summary', 'db': D, 'table': TABLA, 'group': ['n']})
        check('N3 %s: agrupar por un campo n choca con la cuenta n: DB-027 la nombra. ROJO contra 166bea8b' % motor,
              mc.abre(r, 'SR_DB_ETIQUETA_REPETIDA_FMT') and '"n"' in r, r[:300])
        r = db({'command': 'summary', 'db': D, 'table': TABLA, 'group': ['grupo'],
                'values': [{'field': 'n', 'op': 'sum'}]})
        grupos = (mc.como_json(r) or {}).get('groups', [])
        check('N4 %s: sin choque (grupo, sum_n, n), como siempre' % motor,
              not mc.fallo(r) and {(g.get('grupo'), g.get('sum_n'), g.get('n')) for g in grupos} ==
              {('a', 10, 2), ('b', 7, 1)}, r[:400])
    r = db({'command': 'connections'})
    malas = {u.get('db'): u.get('why', '') for u in (mc.como_json(r) or {}).get('unusable') or []}
    check('N5 una entrada con el separador en su nombre: no se usa y dice por que. ROJO contra 166bea8b',
          malas.get(P + 'mal/alias') == mc.catalogo()['SF_CONEXIONES_NOMBRE_FMT'] % '/', json.dumps(malas)[:400])
    contrato = mc.catalogo()['SP_DB_LIMIT']
    topes = [int(mc.cadena_del_fuente('Server/Lsp.Texts.pas', n))
             for n in ('PAGINA_DB_ROWS', 'PAGINA_DB_SUMMARY', 'TOPE_DB')]
    with open(os.path.join(mc.REPO, 'src', 'Server', 'Mcp.Tools.Db.pas'), encoding='utf-8-sig') as fh:
        db_pas = fh.read()
    check('N6 el contrato de limit dice los topes del codigo (%s), los que rows y summary pasan a PaginaDe' % topes,
          [int(x) for x in re.findall(r'\d+', contrato)] == topes and
          'PAGINA_DB_ROWS, TOPE_DB)' in db_pas and 'PAGINA_DB_SUMMARY, TOPE_DB)' in db_pas, contrato)
finally:
    if srv:
        srv.cierra()
    try:
        arnes.sql_mssql(BASE, SRV, 'mssql', LIMPIA_MS)
        arnes.sql_pg(BASE, PG, LIMPIA_PG)
    finally:
        mc.borra(BASE)
mc.fin(TITULO)
