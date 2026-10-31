# -*- coding: utf-8 -*-
"""V60 de la 1.25: el protocolo MCP 2026-07-28, sin handshake ni sesiones, junto al de siempre.

Lo que dice la revision y aqui se mira: server/discover existe (es un MUST); una peticion con la
version moderna en su _meta se sirve sin estado, con version, capacidades y cabeceras juzgadas; un
initialize sigue dando su sesion, y una sesion muerta sigue contestando 404. La identidad de una
peticion moderna es el nombre que trae, saneado, y sin nombre (o con uno que el saneado vacia) es
una identidad propia, NUNCA la del operador: la misma regla de V111 y V159. Antes de este punto el
sondeo server/discover de Claude Code y de Hermes oia -32601 y caian a initialize (medido el 25-oct).

Usage:  python tests/test_protocolo_2026.py [path-to-DelphiLspMcp.exe]
"""
import base64, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('protocolo-2026')
EXE = mc.copia_exe(BASE)
for name in ('a.txt', 'b.txt', 'c.txt'):
    with open(os.path.join(BASE, name), 'w') as f:
        f.write(name)

PORT = mc.puerto_libre()
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_BIND_IP': '127.0.0.1'})
TOKEN = 'bateria-2026'
with open(os.path.join(BASE, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
proc = mc.lanza_http(EXE, PORT, env)
cli = mc.Http(PORT, TOKEN)


def error(msg):
    return (msg or {}).get('error') or {}


def resultado(msg):
    return (msg or {}).get('result') or {}


def sin_sesion(h):
    return not (h.get('Mcp-Session-Id') if h else None)


def trashed(name):
    return mc.copias(BASE, name, 'CAJON_BORRADOS')


try:
    # D - server/discover: un MUST de la revision
    st, h, m = cli.moderna('server/discover', nombre='alice')
    r = resultado(m)
    check('D1 server/discover contesta, sin sesion', st == 200 and bool(r) and sin_sesion(h), '%s %s' % (st, m))
    check('D2 dice las versiones: la moderna y la del handshake',
          mc.PROTOCOLO_MODERNO in r.get('supportedVersions', []) and mc.PROTOCOLO in r.get('supportedVersions', []), r)
    check('D3 dice sus capacidades', 'tools' in r.get('capabilities', {}), r)
    check('D4 resultType complete y su serverInfo en _meta',
          r.get('resultType') == 'complete' and
          bool(r.get('_meta', {}).get(mc.META_SERVIDOR, {}).get('version')), r)
    check('D5 las pistas de cache: ttlMs >= 0 y private (lo que ve depende del token)',
          r.get('ttlMs', -1) >= 0 and r.get('cacheScope') == 'private', r)

    # V - version y campos obligatorios
    st, h, m = cli.moderna('server/discover', version='1900-01-01')
    e = error(m)
    check('V1 una version que no existe: 400, -32022, con las que hay y la pedida',
          st == 400 and e.get('code') == -32022 and mc.es(e.get('message', ''), 'SR_SYS_VERSION_NO_SOPORTADA_FMT') and
          mc.PROTOCOLO_MODERNO in e.get('data', {}).get('supported', []) and
          e.get('data', {}).get('requested') == '1900-01-01', '%s %s' % (st, m))
    st, h, m = cli.moderna('tools/list', capacidades=False)
    e = error(m)
    check('V2 sin clientCapabilities: 400, -32602, y lo nombra',
          st == 400 and e.get('code') == -32602 and mc.es(e.get('message', ''), 'SR_SYS_META_FALTA_FMT') and
          mc.META_CAPACIDADES in e.get('message', ''), '%s %s' % (st, m))
    st, h, m = cli.moderna('server/discover', version=None, sin=('MCP-Protocol-Version',))
    e = error(m)
    check('V3 server/discover sin version en ninguna parte: 400, y un error de esta revision',
          st == 400 and e.get('code') == -32020, '%s %s' % (st, m))

    # H - cabeceras (solo HTTP): -32020 con 400, y nada se ejecuta
    args = {'name': 'delphi_workspace', 'arguments': {}}
    for c, q in (('MCP-Protocol-Version', 'H1'), ('Mcp-Method', 'H2'), ('Mcp-Name', 'H3')):
        st, h, m = cli.moderna('tools/call', args, sin=(c,))
        e = error(m)
        check('%s sin %s: 400, -32020, y la nombra' % (q, c),
              st == 400 and e.get('code') == -32020 and mc.es(e.get('message', ''), 'SR_SYS_CABECERA_FALTA_FMT') and
              c in e.get('message', ''), '%s %s' % (st, m))
    for c, v, q in (('Mcp-Method', 'tools/list', 'H4'), ('Mcp-Name', 'delphi_read', 'H5')):
        st, h, m = cli.moderna('tools/call', args, cabeceras={c: v})
        e = error(m)
        check('%s %s distinta del cuerpo: 400, -32020' % (q, c),
              st == 400 and e.get('code') == -32020 and mc.es(e.get('message', ''), 'SR_SYS_CABECERA_DISTINTA_FMT'),
              '%s %s' % (st, m))
    st, h, m = cli.moderna('tools/call', args, cabeceras={'MCP-Protocol-Version': mc.PROTOCOLO})
    check('H6 la cabecera de version distinta de la del _meta: -32020', error(m).get('code') == -32020, '%s %s' % (st, m))
    # el nombre de la cabecera no distingue mayusculas; su valor si
    st, h, m = cli.moderna('tools/call', args, sin=('Mcp-Name', 'Mcp-Method'),
                           cabeceras={'mcp-name': 'delphi_workspace', 'MCP-METHOD': 'tools/call'})
    check('H7 los nombres de cabecera no distinguen mayusculas', st == 200 and bool(resultado(m)), '%s %s' % (st, m))
    b64 = '=?base64?%s?=' % base64.b64encode(b'delphi_workspace').decode()
    st, h, m = cli.moderna('tools/call', args, cabeceras={'Mcp-Name': b64})
    check('H8 Mcp-Name en Base64 se decodifica antes de comparar', st == 200 and bool(resultado(m)), '%s %s' % (st, m))
    st, h, m = cli.moderna('tools/call', args, cabeceras={'Mcp-Name': '=?base64?***?='})
    check('H9 un Base64 que no lo es: -32020', error(m).get('code') == -32020, '%s %s' % (st, m))
    # la cabecera dice moderno y el cuerpo no trae su _meta: no pasa como una peticion sin sesion
    st, _, raw = mc.post(cli.url, {'jsonrpc': '2.0', 'id': 91, 'method': 'tools/call', 'params': args}, cli.token, cabeceras={
        'MCP-Protocol-Version': mc.PROTOCOLO_MODERNO, 'Mcp-Method': 'tools/call', 'Mcp-Name': 'delphi_workspace'})
    check('H10 cabecera moderna y cuerpo sin su _meta: 400, -32020', st == 400 and '-32020' in raw, '%s %s' % (st, raw[:200]))

    # T - resultados
    st, h, m = cli.moderna('tools/list')
    r = resultado(m)
    check('T1 tools/list sin sesion, con resultType, ttlMs y cacheScope',
          st == 200 and sin_sesion(h) and len(r.get('tools', [])) > 10 and r.get('resultType') == 'complete' and
          r.get('ttlMs', -1) >= 0 and r.get('cacheScope') == 'private', str(r)[:300])
    st2, _, m2 = cli.moderna('tools/list')
    check('T2 tools/list en orden determinista',
          [t['name'] for t in r.get('tools', [])] == [t['name'] for t in resultado(m2).get('tools', [])])
    st, h, m = cli.moderna('tools/call', args)
    r = resultado(m)
    check('T3 tools/call sin sesion: resultType, serverInfo y su contenido',
          st == 200 and sin_sesion(h) and r.get('resultType') == 'complete' and
          bool(r.get('_meta', {}).get(mc.META_SERVIDOR)) and 'roots' in mc.texto(m), str(r)[:300])
    check('T4 tools/call no lleva pistas de cache', 'ttlMs' not in r and 'cacheScope' not in r, str(r)[:200])
    st, h, m = cli.moderna('resources/list')
    r = resultado(m)
    check('T5 resources/list lleva sus pistas', r.get('resultType') == 'complete' and 'ttlMs' in r, str(m)[:200])
    st, h, m = cli.moderna('resources/read', {'uri': 'no://existe'})
    check('T6 un recurso que no existe: -32602 (la revision retira -32002)', error(m).get('code') == -32602, str(m)[:200])
    st, h, m = cli.moderna('no/existe')
    check('T7 un metodo que no existe: 404 con -32601',
          st == 404 and error(m).get('code') == -32601, '%s %s' % (st, m))
    st, h, m = cli.moderna('ping')
    check('T8 ping lo retira la revision: 404 con -32601',
          st == 404 and error(m).get('code') == -32601, '%s %s' % (st, m))
    # un error de la TOOL no es un error del protocolo: su 200 de siempre
    st, h, m = cli.moderna('tools/call', {'name': 'delphi_read', 'arguments': {'path': os.path.join(BASE, 'no.txt')}})
    check('T9 lo que niega una tool sigue siendo un 200', st == 200, '%s %s' % (st, m))

    # I - identidad: el nombre de cada peticion, nunca el operador
    def llama(nombre, tool, argumentos):
        return mc.texto(cli.moderna('tools/call', {'name': tool, 'arguments': argumentos}, nombre=nombre)[2])

    r = llama('alice', 'delphi_messages', {'command': 'check'})
    check('I1 el buzon usa el nombre de la peticion', 'alice' in r, r[:150])
    llama('alice', 'delphi_delete', {'path': os.path.join(BASE, 'a.txt')})
    ca = trashed('a.txt')
    check('I2 la copia lleva su marca de duena',
          bool(ca) and open(mc.marca_dueno(ca[0])).read().strip().endswith('alice'), ca)
    r = llama('bob', 'delphi_delete', {'path': ca[0], 'purge': True})
    check('I3 otro nombre no purga esa copia',
          mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_NOT_YOURS_FMT') and os.path.exists(ca[0]), r[:200])
    for nombre, q in ((None, 'I4 sin nombre'), ('', 'I5 con nombre vacio'), ('...', 'I6 con un nombre que el saneado vacia')):
        r = llama(nombre, 'delphi_delete', {'path': ca[0], 'purge': True})
        check('%s NO es el operador: no purga la copia de otro' % q,
              mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_NOT_YOURS_FMT') and os.path.exists(ca[0]), r[:200])
    r = llama('alice', 'delphi_delete', {'path': ca[0], 'purge': True})
    check('I7 su duena si la purga, sin sesion ninguna', mc.abre(r, 'SN_FILE_PURGED_FMT') and not os.path.exists(ca[0]), r[:200])

    # L - el de siempre, intacto, a la vez y en el mismo sitio
    sid = cli.session('carol')
    check('L1 initialize sigue dando su sesion', bool(sid) and 'protocolVersion' in resultado(cli.init), cli.init)
    r = cli.call('delphi_messages', {'command': 'check'})
    check('L2 la sesion sigue diciendo quien eres', 'carol' in r, r[:150])
    st, h, _ = cli.moderna('tools/list', sid=sid)
    check('L3 una peticion moderna ni repite ni usa la sesion', st == 200 and sin_sesion(h), st)
    st, h, m = cli.moderna('tools/list', sid='{MUERTA-2026}')
    check('L4 una moderna con una sesion muerta en la cabecera: se ignora, no 404', st == 200 and sin_sesion(h), st)
    st, _, raw = cli.post({'jsonrpc': '2.0', 'id': 92, 'method': 'tools/list'}, sid='{MUERTA-2026}')
    check('L5 una de las de siempre con esa sesion: sigue el 404', st == 404, '%s %s' % (st, raw[:200]))
    # un _meta con una version del handshake es una peticion de las de siempre
    p = mc.params_modernos(args, 'carol', mc.PROTOCOLO)
    st, h, raw = cli.post({'jsonrpc': '2.0', 'id': 93, 'method': 'tools/call', 'params': p}, sid=sid)
    check('L6 _meta con una version anterior: la sesion manda', st == 200 and h.get('Mcp-Session-Id') == sid, st)
    check('L7 un resultado de la sesion no lleva resultType', 'resultType' not in raw, raw[:200])
    # un initialize elige la era de la sesion, aunque la cabecera diga la moderna
    st, h, raw = mc.post(cli.url, {'jsonrpc': '2.0', 'id': 94, 'method': 'initialize', 'params': {
        'protocolVersion': mc.PROTOCOLO, 'capabilities': {}, 'clientInfo': {'name': 'carol', 'version': '1'}}},
        cli.token, cabeceras={'MCP-Protocol-Version': mc.PROTOCOLO_MODERNO})
    check('L8 initialize con la cabecera moderna: abre su sesion', st == 200 and bool(h.get('Mcp-Session-Id')), '%s %s' % (st, raw[:200]))
    # A - el token sigue siendo la puerta, antes que nada
    st, h, m = mc.Http(PORT, 'token-que-no-vale').moderna('tools/list')
    check('A1 sin un token que valga: 401, tambien sin sesion', st == 401, st)
finally:
    proc.kill()

# S - stdio: el mismo juicio, sin cabeceras, y el proceso sigue siendo del operador
STDIO = os.path.join(BASE, 'stdio')
srv = mc.Stdio(mc.copia_exe(STDIO), mc.entorno({'DELPHI_MCP_ROOTS': BASE}), inicializa=False)
try:
    m = srv.moderna('server/discover', nombre='dora')
    check('S1 server/discover por stdio, sin initialize', mc.PROTOCOLO_MODERNO in resultado(m).get('supportedVersions', []), m)
    m = srv.moderna('tools/list', version='1900-01-01')
    check('S2 una version que no existe: -32022', error(m).get('code') == -32022, m)
    m = srv.moderna('server/discover', version=None)
    check('S2b server/discover sin version en _meta: -32602 y lo nombra',
          error(m).get('code') == -32602 and mc.es(error(m).get('message', ''), 'SR_SYS_META_FALTA_FMT'), m)
    m = srv.moderna('tools/list', capacidades=False)
    check('S2c sin clientCapabilities: -32602', error(m).get('code') == -32602, m)
    m = srv.moderna('tools/call', {'name': 'delphi_messages', 'arguments': {'command': 'check'}}, nombre='dora')
    check('S3 tools/call con su nombre', 'dora' in mc.texto(m) and resultado(m).get('resultType') == 'complete', m)
    m = srv.moderna('tools/call', {'name': 'delphi_delete', 'arguments': {'path': os.path.join(BASE, 'b.txt')}}, nombre='dora')
    cb = trashed('b.txt')
    check('S4 la copia es de quien la peticion dice', bool(cb) and open(mc.marca_dueno(cb[0])).read().strip().endswith('dora'), cb)
    m = srv.moderna('tools/call', {'name': 'delphi_delete', 'arguments': {'path': cb[0], 'purge': True}}, nombre=None)
    check('S5 sin nombre, stdio es el operador: la purga', mc.abre(mc.texto(m), 'SN_FILE_PURGED_FMT') and not os.path.exists(cb[0]), m)
finally:
    srv.mata()

# S6 - y el de siempre por stdio
srv = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'stdio2')), mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='erin')
try:
    check('S6 initialize por stdio sigue igual', 'protocolVersion' in resultado(srv.init), srv.init)
    check('S7 y su nombre sigue valiendo para las siguientes', 'erin' in srv.call('delphi_messages', {'command': 'check'}))
finally:
    srv.mata()

mc.borra(BASE)
mc.fin('protocolo 2026 battery')
