# -*- coding: utf-8 -*-
"""Las capacidades de la 1.25, una por una, de punta a punta por el protocolo.

V39: delphi_docs search pagina como las demas listas.
V44: delphi_search con contexto alrededor de cada acierto y con ficheros que se dejan fuera, por el
mismo juez de mascaras que el paseo.
V42: delphi_desktop con el PAServer caido, sin parametro nuevo: paclient se rinde solo y --timeout no lo acorta
(medido: 21 s contra una IP que no contesta, con y sin el), asi que lo que sobraba era lo nuestro: subir el nodo
despues de saber que no hay conexion, y retener a los demas perfiles mientras tanto. Contra paclient_stub, sin red.

Usage:  python tests/test_capacidades_125.py [path-to-DelphiLspMcp.exe]
"""
import glob, json, os, shutil, threading, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('capacidades-125')
EXE = mc.copia_exe(BASE)
RAIZ = os.path.join(BASE, 'raiz')
os.makedirs(RAIZ)
with open(os.path.join(RAIZ, 'UNo.pas'), 'w', newline='') as f:
    f.write('unit UNo;\r\n// uno\r\n// dos\r\n// AGUJA\r\n// cuatro\r\n// cinco\r\nend.\r\n')
with open(os.path.join(RAIZ, 'UDos_test.pas'), 'w', newline='') as f:
    f.write('unit UDos_test;\r\n// AGUJA\r\nend.\r\n')
with open(os.path.join(RAIZ, 'Vieja.pas'), 'w', newline='') as f:
    f.write('unit Vieja;\r\n// AGUJA\r\nend.\r\n')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ}), nombre='capacidades')
call = srv.call


def hits(d):
    return {x['name']: x['hits'] for g in d.get('folders', []) for x in g['files']}


try:
    # V39 - delphi_docs search
    t = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'limit': 3})
    if mc.es(t, 'SR_DOCS_SIN_AYUDA_FMT'):
        print('NOTA: sin ayuda instalada: V39 no se mide aqui')
    else:
        a = json.loads(t)
        check('V39 search da su pagina: total, shown, hasMore y nextOffset',
              a.get('shown') == 3 and a.get('hasMore') is True and a.get('nextOffset') == 3 and a.get('total', 0) > 3, t[:300])
        t2 = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'limit': 3, 'offset': a.get('nextOffset', 3)})
        b = json.loads(t2) if t2.startswith('{') else {}
        ids_a, ids_b = [r['id'] for r in a.get('results', [])], [r['id'] for r in b.get('results', [])]
        check('V39 la pagina siguiente trae otras, sin repetir', len(ids_b) == 3 and not set(ids_a) & set(ids_b), t2[:300])
        check('V39 y dice su offset', b.get('offset') == 3, t2[:200])
        t3 = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'offset': 100000})
        c = json.loads(t3) if t3.startswith('{') else {}
        check('V39 un offset mas alla del final: lista vacia, hasMore false', c.get('results') == [] and c.get('hasMore') is False, t3[:200])
        t4 = call('delphi_docs', {'command': 'search', 'query': 'TStringList', 'limit': 99})
        check('V39 limit sigue con su tope de 25', json.loads(t4).get('shown', 0) <= 25, t4[:200])

    # V44 - delphi_search: contexto
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'context': 2}))
    h = hits(d).get('UNo.pas', [{}])[0]
    check('V44 context: las dos de antes y las dos de despues, tal cual',
          h.get('before') == ['// uno', '// dos'] and h.get('after') == ['// cuatro', '// cinco'] and h.get('text') == '// AGUJA', d)
    check('V44 y el acierto sigue en su sitio', h.get('line') == 4 and h.get('line0') == 3, h)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'unit UNo', 'context': 3}))
    h = hits(d)['UNo.pas'][0]
    check('V44 context en la primera linea: before vacio', h.get('before') == [] and len(h.get('after', [])) == 3, h)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'context': 500}))
    check('V44 context tiene su tope', len(hits(d)['UNo.pas'][0].get('before', [])) == 3, d)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA'}))
    check('V44 sin context, ni before ni after', 'before' not in hits(d)['UNo.pas'][0] and 'after' not in hits(d)['UNo.pas'][0], d)

    # V44 - delphi_search: exclude
    d = json.loads(call('delphi_search', {'root': RAIZ, 'query': 'AGUJA'}))
    check('V44 sin exclude, los tres', sorted(hits(d)) == ['UDos_test.pas', 'UNo.pas', 'Vieja.pas'], d)
    d = json.loads(call('delphi_search', {'root': RAIZ, 'query': 'AGUJA', 'exclude': '*_test.pas;Vie*.pas'}))
    check('V44 exclude deja fuera lo suyo y lo cuenta', sorted(hits(d)) == ['UNo.pas'] and d.get('excluded') == 2 and d.get('filesScanned') == 1, d)
    t = call('delphi_search', {'root': RAIZ, 'query': 'AGUJA', 'exclude': '..\\*.pas'})
    check('V44 exclude que no es una mascara: su negativa', mc.es(t, 'SR_WS_PATTERN_DEBE_SER_MASCARA'), t[:200])
    t = call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'exclude': '*.pas'})
    check('V44 exclude con UN fichero por raiz: SEARCH-010', mc.es(t, 'SR_SEARCH_EXCLUDE_CON_FICHERO_FMT'), t[:200])
    d = json.loads(call('delphi_search', {'root': RAIZ, 'query': 'AGUJA', 'exclude': '*.pas', 'pattern': '*.pas'}))
    check('V44 todo fuera: no dice que la mascara no casa', d.get('excluded') == 3 and 'maskNote' not in d, d)
finally:
    srv.mata()

# V42 - delphi_desktop con el PAServer caido
HERE = os.path.dirname(os.path.abspath(__file__))
SRV = os.path.join(BASE, 'srv')
EXE2 = mc.copia_exe(SRV)
shutil.copytree(os.path.join(os.path.dirname(HERE), 'node'), os.path.join(SRV, 'node'))
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
STUB = os.path.join(BASE, 'paclient.cmd')
with open(STUB, 'w') as f:
    f.write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))
LOG = os.path.join(BASE, 'paclient.log')
for perfil in ('caido', 'otro', 'vivo'):
    ad, host = mc.appdata_perfil(BASE, perfil, '127.0.0.1')
TOKEN = 'capacidades-125'
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\nAllowRemoteRun=1\nRemoteRunProjects=all\nRemoteHosts=%s\n' % (TOKEN, RAIZ, host))
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE2, PORT, mc.entorno({
    'DELPHI_MCP_ROOTS': RAIZ, 'DELPHI_MCP_BIND_IP': '127.0.0.1', 'APPDATA': ad, 'DELPHI_MCP_PACLIENT': STUB,
    'MCP_STUB_SCRATCH': SCRATCH, 'MCP_STUB_LOG': LOG}))


def cliente(nombre):
    c = mc.Http(PORT, TOKEN, t=120)
    c.session(nombre)
    return c


def status(c, perfil):
    return c.call('delphi_desktop', {'command': 'status', 'profile': perfil}, 120)


def caido(perfil, segundos):
    with open(os.path.join(SCRATCH, '_caido_' + perfil), 'w') as f:
        f.write(str(segundos))


def peticiones(perfil):
    with open(LOG, encoding='utf-8') as f:
        return [x for x in f.read().splitlines() if x.endswith(' ' + perfil)]


try:
    uno, dos = cliente('v42-uno'), cliente('v42-dos')
    caido('caido', 0)
    r = status(uno, 'caido')
    j = mc.como_json(r)
    check('V42 status con el PAServer caido: reachable=false con el motivo, sin error',
          j.get('reachable') is False and 'E0003' in (j.get('hint') or '') and 'error' not in j, r[:300])
    pet = peticiones('caido')
    check('V42 sin conexion no se intenta subir el nodo: UNA espera de paclient, no dos',
          len(pet) == 1 and pet[0].startswith('--get='), pet)
    check('V42 la carpeta de esa comprobacion no se queda en la casa',
          not glob.glob(os.path.join(SRV, mc.TEMPORALES, 'remoterun', 'ver-*')),
          glob.glob(os.path.join(SRV, mc.TEMPORALES, 'remoterun', '*')))
    r = uno.call('delphi_desktop', {'command': 'tap', 'profile': 'caido', 'x': '1', 'y': '1'}, 120)
    check('V42 un gesto contra ese destino: su negativa, con lo que dijo paclient', mc.es(r, 'SR_FETCHTARGET_FAIL_FMT') and 'E0003' in r, r[:300])

    # un perfil caido no retiene a otro
    caido('caido', 6)
    caido('otro', 0)
    fuera = []
    hilo = threading.Thread(target=lambda: fuera.append(status(uno, 'caido')))
    hilo.start()
    time.sleep(1.5)
    t0 = time.time()
    r = status(dos, 'otro')
    tardo = time.time() - t0
    sigue = hilo.is_alive()
    hilo.join()
    check('V42 un perfil caido no retiene a otro: contesta mientras el primero sigue esperando a paclient',
          sigue and tardo < 3 and mc.como_json(r).get('reachable') is False, (sigue, tardo, r[:200]))

    # el control: un sello que no esta NO es falta de conexion, y el nodo se sube
    with open(os.path.join(SCRATCH, '_sin_trabajos'), 'w') as f:
        f.write('x')
    status(uno, 'vivo')
    pet = peticiones('vivo')
    subidas = [x for x in pet if x.startswith('--put=') and 'McpDesktopNode' in x and '.job' not in x]
    check('V42 control: sin sello y con conexion, el nodo y su sello se suben', len(subidas) >= 2 and pet[0].startswith('--get='), pet)
    antes = len([x for x in peticiones('vivo') if x.startswith('--get=') and 'node.ver' in x])
    status(uno, 'vivo')
    check('V42 control: la comprobacion del nodo sigue siendo una por perfil y proceso',
          len([x for x in peticiones('vivo') if x.startswith('--get=') and 'node.ver' in x]) == antes == 1, peticiones('vivo'))
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('capacidades 1.25 battery')
