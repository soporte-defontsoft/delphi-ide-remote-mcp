# -*- coding: utf-8 -*-
"""Humo del modo SERVICIO: el unico de los tres modos que no tenia ni una prueba.

El repo publica tres formas de correr el servidor - consola, bandeja y servicio
de Windows - y produccion ES un servicio. Medido el 2026-09-20: stdio 39
baterias, --http 12, bandeja 0, servicio 0.

Instalar un servicio pide elevacion y una bateria no la tiene, asi que esta NO
instala nada: mide el servicio que YA esta instalado en la maquina
(DelphiLspMcp). Donde no lo hay, lo DICE y no cuenta como fallo - las baterias
tienen que poder correr en cualquier maquina.

Ojo con lo que mide: el exe DESPLEGADO, no el que se acaba de compilar. Es una
prueba del despliegue, no del build; la version que contesta sale en una NOTA.

  Sin token (siempre que haya servicio):
    V1 el SCM lo da por RUNNING
    V2 contesta por HTTP en su puerto
    V3 y a un anonimo le cierra la puerta (ni initialize sin Bearer)
  Con token (variable de entorno DELPHI_MCP_TOKEN; nunca se imprime):
    V4 initialize + delphi_workspace dice mode=servicio, transport=http
    V5 dice con que CUENTA corre, y no es LocalSystem (el IDE guarda su
       configuracion en HKCU: como LocalSystem todo "funciona" y no ve nada)
    V6 una lectura de verdad (delphi_list de la primera raiz)
    V7 una escritura de verdad, y su limpieza (delphi_textedit create + delete)
"""
import json
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check


SERVICIO = 'DelphiLspMcp'
URL = os.environ.get('DELPHI_MCP_URL', 'http://127.0.0.1:3131/mcp')
TOK = os.environ.get('DELPHI_MCP_TOKEN', '')

q = subprocess.run(['sc.exe', 'query', SERVICIO], capture_output=True, text=True)
if q.returncode != 0:
    print('NOTA: en esta maquina no hay servicio %s instalado; el modo servicio '
          'no se mide aqui.' % SERVICIO)
    mc.fin('test_service_smoke')

check('V1 el SCM da el servicio por RUNNING', 'RUNNING' in q.stdout,
      q.stdout.strip()[:200])


def post(body, tok='', sid=None):
    # (status, texto, session-id); status 0 si ni conecta: V2 mira eso, y
    # mc.post lanza en ese caso (solo un 4xx/5xx es una respuesta)
    try:
        st, h, raw = mc.post(URL, body, tok, sid, t=60)
    except Exception as e:
        return 0, str(e), None
    return st, raw, (h.get('Mcp-Session-Id') if 200 <= st < 300 else None)


INIT = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                   'clientInfo': {'name': 'humo-servicio', 'version': '1'}}}

st, raw, _ = post(INIT)
check('V2 contesta por HTTP en su puerto', st != 0, raw[:200])
check('V3 ...y a un anonimo le cierra la puerta',
      st in (401, 403) or ('"error"' in raw and '"result"' not in raw),
      'status=%s %s' % (st, raw[:160]))

if not TOK:
    print('NOTA: sin DELPHI_MCP_TOKEN en el entorno solo se mide desde fuera '
          '(V1-V3). Con el, tambien identidad, lectura y escritura (V4-V7).')
else:
    st, raw, sid = post(INIT, TOK)
    post({'jsonrpc': '2.0', 'method': 'notifications/initialized'}, TOK, sid)
    rid = [10]

    def call(tool, args):
        rid[0] += 1
        _, raw, _ = post({'jsonrpc': '2.0', 'id': rid[0],
                          'method': 'tools/call',
                          'params': {'name': tool, 'arguments': args}}, TOK, sid)
        for l in raw.splitlines():
            if l.startswith('data:'):
                raw = l[5:].strip()
        try:
            return json.loads(raw)['result']['content'][0]['text']
        except Exception:
            return raw[:400]

    w = call('delphi_workspace', {})
    try:
        j = json.loads(w)
    except Exception:
        j = {}
    srv = j.get('server', {})
    print('NOTA: contesta la version %s (pid %s).' % (srv.get('version'),
                                                      srv.get('pid')))
    check('V4 delphi_workspace dice mode=servicio, transport=http',
          srv.get('mode') == 'servicio' and srv.get('transport') == 'http',
          json.dumps(srv)[:240])
    if 'account' not in srv:
        print('NOTA: el servidor desplegado es anterior a "account"; V5 no se '
              'mide hasta desplegar este build.')
    else:
        check('V5 dice con que cuenta corre, y NO es LocalSystem',
              bool(srv.get('account')) and 'accountWarning' not in srv,
              json.dumps(srv)[:240])
    roots = j.get('roots') or []
    escribible = j.get('access') == 'read-write'
    if roots:
        l = call('delphi_list', {'root': roots[-1], 'dirs': True})
        check('V6 una lectura de verdad (delphi_list de una raiz)',
              '"ok":true' in l.replace(' ', ''), l[:200])
    if roots and escribible:
        f = roots[-1] + '\\__humo-servicio.txt'
        c = call('delphi_textedit', {'path': f, 'create': True,
                                     'content': 'humo\r\n'})
        d = call('delphi_delete', {'path': f})
        check('V7 una escritura de verdad, y su limpieza',
              c.startswith('CREADO') and 'RECHAZ' not in d.upper(),
              c[:120] + ' | ' + d[:120])
    else:
        print('NOTA: token de solo lectura; V7 no se mide.')

mc.fin('test_service_smoke')
