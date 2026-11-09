# -*- coding: utf-8 -*-
"""Los ejemplos de conexiones que viajan en el zip (1.29, F5 del cierre): connections\\databases\\
db-connections.example.json y connections\\apis\\api-connections.example.json, la forma real con valores
inventados. El operador copia uno a su lado sin ".example" y lo rellena; esta bateria hace eso mismo con
el ejemplo tal cual y lo pasa por EL lector (Lsp.Conexiones, por delphi_db y delphi_api connections), de
modo que un ejemplo que el servidor no usaria entero, o que se aleja de lo que lee, es un FAIL aqui y no
una sorpresa del operador. No se conecta a nada: las direcciones son de example.internal / example.com.

  X1 los dos ejemplos son JSON y estan en el repo donde el zip los toma
  X2 delphi_db connections: todas las bases del ejemplo usables (ninguna en unusable), con su motor y
     readonly, y la que lo declara con allowCreate
  X3 delphi_api connections: todas las APIs del ejemplo usables, con sus metodos
  X4 ningun valor del ejemplo que el agente no debe ver sale en las respuestas (servidor, base, usuario,
     contrasena, URL base, credenciales)
  X5 lo que el ejemplo declara son TODAS las claves que el lector lee (una clave nueva del lector sin su
     linea en el ejemplo es un ejemplo que se queda atras)

Uso:  python tests/test_ejemplos_conexiones_129.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import json
import os
import re
import shutil
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
EJ_DB = os.path.join(REPO, 'connections', 'databases', 'db-connections.example.json')
EJ_API = os.path.join(REPO, 'connections', 'apis', 'api-connections.example.json')
BASE = mc.carpeta('ejemplos_conexiones_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)


def lee(ruta):
    try:
        return json.load(io.open(ruta, encoding='utf-8'))
    except (OSError, ValueError) as e:
        return 'no se lee: %s' % e


db, api = lee(EJ_DB), lee(EJ_API)
check('X1 los dos ejemplos son JSON y estan donde el zip los toma', isinstance(db, dict) and isinstance(api, dict),
      (str(db)[:200], str(api)[:200]))
try:
    for ej, rel in ((EJ_DB, ('databases', 'db-connections.json')), (EJ_API, ('apis', 'api-connections.json'))):
        destino = os.path.join(SRV, 'connections', *rel)
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        shutil.copy(ej, destino)
    proyectos_db = sorted((db.get('db-connections') or {}).get('projects') or {}) if isinstance(db, dict) else []
    proyectos_api = sorted((api.get('api-connections') or {}).get('projects') or {}) if isinstance(api, dict) else []
    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': ';'.join(proyectos_db),
                                    'DELPHI_MCP_API_PROJECTS': ';'.join(proyectos_api)}), nombre='ejemplos', t=60)
    try:
        r = srv.call('delphi_db', {'command': 'connections'})
        j = mc.como_json(r)
        bases = {b.get('db'): b for b in j.get('databases', [])}
        declaradas = {}
        for p in proyectos_db:
            for alias, e in ((db['db-connections']['projects'][p] or {}).get('databases') or {}).items():
                declaradas['%s/%s' % (p, alias)] = e
        check('X2 delphi_db connections: todas las bases del ejemplo usables, con su motor y readonly',
              declaradas and set(bases) == set(declaradas) and not j.get('unusable')
              and all(bases[n].get('engine') == e.get('engine') and bases[n].get('readonly') is e.get('readonly')
                      for n, e in declaradas.items()), r[:600])
        check('X2 ...y el ejemplo ensena allowCreate en una base que escribe',
              any(e.get('allowCreate') is True and e.get('readonly') is False for e in declaradas.values()),
              list(declaradas))
        r2 = srv.call('delphi_api', {'command': 'connections'})
        j2 = mc.como_json(r2)
        apis = {x.get('api'): x for x in j2.get('apis', [])}
        declaradas_api = {}
        for p in proyectos_api:
            for alias, e in ((api['api-connections']['projects'][p] or {}).get('apis') or {}).items():
                declaradas_api['%s/%s' % (p, alias)] = e
        check('X3 delphi_api connections: todas las APIs del ejemplo usables, con sus metodos',
              declaradas_api and set(apis) == set(declaradas_api) and not j2.get('unusable')
              and all(sorted(m.upper() for m in e.get('methods', [])) == sorted(apis[n].get('methods') or [])
                      for n, e in declaradas_api.items()), r2[:600])
        secretos = []
        for e in list(declaradas.values()) + list(declaradas_api.values()):
            for k in ('server', 'database', 'user', 'password', 'baseUrl', 'token', 'value'):
                if isinstance(e.get(k), str) and e[k]:
                    secretos.append(e[k])
            for a in (e.get('auth') if isinstance(e.get('auth'), list) else [e.get('auth')]):
                if isinstance(a, dict):
                    secretos += [v for k, v in a.items() if k in ('user', 'password', 'token', 'value') and v]
        fuera = [s for s in secretos if s.lower() in (r + r2).lower()]
        check('X4 ningun valor del ejemplo que el agente no ve sale en las respuestas', secretos and not fuera, fuera)
    finally:
        srv.cierra()
    # X5: las claves que lee Lsp.Conexiones (Campo / GetValue de un literal), contra las del ejemplo
    fuente = io.open(os.path.join(REPO, 'src', 'Server', 'Lsp.Conexiones.pas'), encoding='utf-8-sig').read()
    leidas = set(re.findall(r"(?:Campo\([A-Za-z]+(?:\([A-Za-z]+\))?, |GetValue\()'([A-Za-z]+)'\)", fuente))
    en_ejemplo = set()

    def claves(o):
        if isinstance(o, dict):
            for k, v in o.items():
                en_ejemplo.add(k)
                claves(v)
        elif isinstance(o, list):
            for v in o:
                claves(v)
    claves(db)
    claves(api)
    check('X5 el ejemplo declara todas las claves que el lector lee (%d)' % len(leidas),
          len(leidas) > 10 and not (leidas - en_ejemplo), sorted(leidas - en_ejemplo))
finally:
    mc.borra(BASE)
mc.fin('los ejemplos de conexiones del zip, por el lector (1.29)')
