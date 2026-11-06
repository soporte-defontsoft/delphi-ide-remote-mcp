# -*- coding: utf-8 -*-
"""delphi_db (1.29), primera parte: las bases de datos con NOMBRE que define el operador en el fichero de
conexiones de la casa (connections\\databases\\db-connections.json, junto al exe) y abre a cada workspace con
DbAllowedProjects= (aqui, el modo local: DELPHI_MCP_DB_PROJECTS). El agente las usa por operaciones, nunca
por SQL (David, 6-nov-2026), y ve su nombre <proyecto>/<alias>, su motor y si es de solo lectura; nunca el
servidor, la base real, el usuario ni la contrasena.

  D1 sin proyectos: tools/list no anuncia delphi_db, delphi_help dice su clave, y la llamada DB-002
  D2 con proyectos y sin fichero: DB-001 (no hay fichero)
  D3 un fichero que no es JSON, y uno sin db-connections.projects: DB-001 con su porque
  D4 connections: las del proyecto permitido, con su motor y readonly; las declaradas mal, en unusable con
     el porque (sin motor, otro proveedor, motor que el servidor no tiene, readonly que no es true/false);
     las de un proyecto NO permitido, en ninguna parte
  D5 ...y ningun secreto del json en la respuesta (servidor, base real, usuario, contrasena, puerto)
  D6 el comodin (*) abre todos los proyectos
  D7 un comando que no existe: DB-006
  D8 con proyectos: tools/list anuncia delphi_db y tasks no dice que le falte nada

Uso:  python tests/test_db_129.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('db_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
FICHERO = os.path.join(SRV, 'connections', 'databases', 'db-connections.json')
SECRETOS = ['SERVIDOR-SECRETO-129', 'base_real_129', 'usuario_secreto_129', 'clave-secreta-129', '64129']


def entrada(**kw):
    e = {'server': SECRETOS[0] + '\\INSTANCIA', 'database': SECRETOS[1], 'readonly': True, 'user': SECRETOS[2],
         'port': SECRETOS[4], 'engine': 'MSSQL', 'provider': 'FIREDAC', 'password': SECRETOS[3]}
    e.update(kw)
    return {k: v for k, v in e.items() if v is not None}


def escribe_conexiones(datos):
    os.makedirs(os.path.dirname(FICHERO), exist_ok=True)
    texto = datos if isinstance(datos, str) else json.dumps(datos, indent=2)
    io.open(FICHERO, 'w', encoding='utf-8', newline='\n').write(texto)


CONEXIONES = {'db-connections': {'projects': {
    'pruebas': {'databases': {
        'buena': entrada(),
        'escribe': entrada(engine='PG', readonly=False),
        'sinmotor': entrada(engine=None),
        'otroprov': entrada(provider='ADO'),
        'motorraro': entrada(engine='Ora'),
        'ro_texto': entrada(readonly='yes')}},
    'ajeno': {'databases': {'oculta': entrada()}}}}}


def anunciadas(srv):
    r = srv.request('tools/list') or {}
    return {t['name'] for t in (r.get('result') or {}).get('tools', [])}


def servidor(proyectos, nombre):
    extra = {'DELPHI_MCP_ROOTS': JAIL}
    if proyectos is not None:
        extra['DELPHI_MCP_DB_PROJECTS'] = proyectos
    return mc.Stdio(EXE, mc.entorno(extra), nombre=nombre, t=60)


cat = mc.catalogo()
try:
    srv = servidor(None, 'sin-proyectos')
    try:
        a = anunciadas(srv)
        t = srv.call('delphi_help', {'command': 'tasks'})
        r = srv.call('delphi_db', {'command': 'connections'})
        check('D1 sin proyectos: tools/list no anuncia delphi_db, tasks dice su clave y la llamada DB-002',
              'delphi_help' in a and 'delphi_db' not in a and cat['SF_HELP_SIN_DESTINO_DB'] in t
              and mc.abre(r, 'SR_DB_SIN_PROYECTOS'), (sorted(a)[:5], t[-300:], r[:300]))
    finally:
        srv.cierra()

    srv = servidor('pruebas', 'pruebas')
    try:
        r = srv.call('delphi_db', {'command': 'connections'})
        check('D2 con proyectos y sin fichero: DB-001 (no hay fichero)',
              mc.abre(r, 'SR_DB_FICHERO_FMT') and cat['SF_DB_FICHERO_NO_HAY'] in r, r[:300])
        escribe_conexiones('{ esto no es json')
        r = srv.call('delphi_db', {'command': 'connections'})
        r2 = ''
        if mc.abre(r, 'SR_DB_FICHERO_FMT') and cat['SF_DB_FICHERO_NO_JSON'] in r:
            escribe_conexiones({'otra-cosa': {}})
            r2 = srv.call('delphi_db', {'command': 'connections'})
        check('D3 un fichero que no es JSON, y uno sin db-connections.projects: DB-001 con su porque',
              mc.abre(r2, 'SR_DB_FICHERO_FMT') and cat['SF_DB_FICHERO_SIN_RAIZ'] in r2, (r[:200], r2[:200]))

        escribe_conexiones(CONEXIONES)
        r = srv.call('delphi_db', {'command': 'connections'})
        j = mc.como_json(r)
        bases = {b.get('db'): b for b in j.get('databases', [])}
        malas = {u.get('db'): u.get('why', '') for u in j.get('unusable', [])}
        check('D4 connections: las buenas del proyecto permitido, con su motor y readonly',
              set(bases) == {'pruebas/buena', 'pruebas/escribe'}
              and bases['pruebas/buena'].get('engine') == 'MSSQL' and bases['pruebas/buena'].get('readonly') is True
              and bases['pruebas/escribe'].get('engine') == 'PG' and bases['pruebas/escribe'].get('readonly') is False
              and mc.es(j.get('note', ''), 'SN_DB_CONNECTIONS'), r[:600])
        check('D4 ...las declaradas mal, en unusable con su porque',
              set(malas) == {'pruebas/sinmotor', 'pruebas/otroprov', 'pruebas/motorraro', 'pruebas/ro_texto'}
              and malas['pruebas/sinmotor'] == cat['SF_DB_DEF_SIN_MOTOR']
              and 'ADO' in malas['pruebas/otroprov'] and 'Ora' in malas['pruebas/motorraro']
              and 'MSSQL' in malas['pruebas/motorraro'] and malas['pruebas/ro_texto'] == cat['SF_DB_DEF_SOLO_LECTURA'],
              malas)
        check('D4 ...las de un proyecto NO permitido, en ninguna parte', 'ajeno' not in r, r[:600])
        check('D5 ...y ningun secreto del json en la respuesta', not [s for s in SECRETOS if s.lower() in r.lower()],
              [s for s in SECRETOS if s.lower() in r.lower()])
        r = srv.call('delphi_db', {'command': 'drop'})
        check('D7 un comando que no existe: DB-006', mc.abre(r, 'SR_DB_COMANDO'), r[:300])
        a = anunciadas(srv)
        t = srv.call('delphi_help', {'command': 'tasks'})
        check('D8 con proyectos: tools/list anuncia delphi_db y tasks no dice que le falte',
              'delphi_db' in a and cat['SF_HELP_SIN_DESTINO_DB'] not in t, t[-300:])
    finally:
        srv.cierra()

    srv = servidor('*', 'comodin')
    try:
        r = srv.call('delphi_db', {'command': 'connections'})
        bases = {b.get('db') for b in mc.como_json(r).get('databases', [])}
        check('D6 el comodin (*) abre todos los proyectos', 'ajeno/oculta' in bases and 'pruebas/buena' in bases,
              r[:400])
    finally:
        srv.cierra()
finally:
    mc.borra(BASE)
mc.fin('delphi_db 1.29 (primera parte: connections)')
