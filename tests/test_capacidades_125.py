# -*- coding: utf-8 -*-
"""Las capacidades de la 1.25, una por una, de punta a punta por el protocolo.

V39: delphi_docs search pagina como las demas listas.
V44: delphi_search con contexto alrededor de cada acierto y con ficheros que se dejan fuera, por el
mismo juez de mascaras que el paseo.
V42: delphi_desktop con el PAServer caido, sin parametro nuevo: paclient se rinde solo y --timeout no lo acorta
(medido: 21 s contra una IP que no contesta, con y sin el), asi que lo que sobraba era lo nuestro: subir el nodo
despues de saber que no hay conexion, y retener a los demas perfiles mientras tanto. Contra paclient_stub, sin red.
V45: delphi_git por campos: format name-only, log grep, add/commit/fetch action, clone branch. La enmienda de un
commit que un remoto ya tiene se niega.
V46: los nombres que un agente manda a delphi_build (friccion de Hermes del 22-oct): configuration y command, por la
tabla de alias de siempre, sin coste en el contrato.
V41: delphi_changeset stage con ops: varias operaciones en una llamada, todas o ninguna, y cada una por la misma
puerta que una suelta (una ruta de dentro de ops no tiene otra).

Usage:  python tests/test_capacidades_125.py [path-to-DelphiLspMcp.exe]
"""
import functools, glob, http.server, json, os, shutil, subprocess, threading, time
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

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': RAIZ, 'DELPHI_MCP_GIT_REMOTES': '127.0.0.1'}), nombre='capacidades')
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

    # V45 - delphi_git por campos
    REPO = os.path.join(RAIZ, 'g')
    os.makedirs(os.path.join(REPO, 'sub'))


    def git(cmd, **kw):
        return call('delphi_git', dict({'repo': REPO, 'command': cmd}, **kw))


    def crudo(*args, cwd=REPO):
        return subprocess.run(['git'] + list(args), cwd=cwd, capture_output=True, text=True).stdout.strip()


    def escribe(nombre, texto):
        with open(os.path.join(REPO, nombre), 'w') as f:
            f.write(texto)


    git('init')
    git('config', name='user.name', message='Bateria')
    git('config', name='user.email', message='bateria@example.com')
    escribe('a.txt', 'uno\n')
    escribe(os.path.join('sub', 'b.txt'), 'uno\n')
    git('add', paths=['.'])
    git('commit', message='Primero con AGUJA')
    escribe('a.txt', 'dos\n')
    git('add', paths=['a.txt'])
    git('commit', message='Segundo')

    # format name-only
    escribe('a.txt', 'tres\n')
    t = git('diff', format='name-only')
    check('V45 diff format=name-only: los nombres, sin el cambio', 'a.txt' in t and '@@' not in t and 'tres' not in t, t[:300])
    t = git('diff', format='xx')
    check('V45 un format que no va lo dice, name-only incluido', mc.es(t, 'SR_GIT_FORMATO_FMT') and 'name-only' in t, t[:200])
    # log grep
    t = git('log', grep='aguja')
    check('V45 log grep: por el mensaje, sin distinguir mayusculas', 'Primero con AGUJA' in t and 'Segundo' not in t, t[:300])
    t = git('log', grep='AG.JA')
    check('V45 log grep es texto, no una expresion', 'Primero' not in t, t[:300])
    t = git('log', grep='x" --output=fuera.txt "')
    check('V45 log grep con comillas sigue siendo un solo argumento', not os.path.exists(os.path.join(REPO, 'fuera.txt')), t[:300])
    t = git('status', grep='x')
    check('V45 grep no va con otro comando', mc.es(t, 'SR_GIT_NO_VA_CON_COMANDO_FMT'), t[:200])
    # add action=update
    escribe('nuevo.txt', 'x\n')
    t = git('add')
    check('V45 add sin paths ni action sigue pidiendo paths', mc.es(t, 'SR_GIT_ADD_NEEDS_PATHS'), t[:200])
    t = git('add', action='xx')
    check('V45 add con otra action: GIT-085', mc.es(t, 'SR_GIT_ACTION_NO_VA_FMT') and 'update' in t, t[:200])
    t = git('add', action='update')
    st = crudo('status', '--porcelain')
    check('V45 add action=update: lo seguido que cambio, lo nuevo no', 'M  a.txt' in st and '?? nuevo.txt' in st, (st, t[:200]))
    crudo('reset', '-q')
    escribe(os.path.join('sub', 'b.txt'), 'dos\n')
    t = call('delphi_git', {'repo': os.path.join(REPO, 'sub'), 'command': 'add', 'action': 'update'})
    st = crudo('status', '--porcelain')
    check('V45 add action=update desde una subcarpeta: el repo entero', 'M  a.txt' in st and 'M  sub/b.txt' in st, (st, t[:200]))
    crudo('reset', '-q')
    crudo('checkout', '-q', '--', 'sub/b.txt')
    t = git('add', action='update', paths=['a.txt'])
    check('V45 add action=update con paths: solo esos', 'M  a.txt' in crudo('status', '--porcelain'), t[:200])
    # commit action=amend
    antes = crudo('rev-list', '--count', 'HEAD')
    t = git('commit', action='amend')
    check('V45 amend sin message: con lo preparado y el mismo mensaje',
          crudo('rev-list', '--count', 'HEAD') == antes and crudo('log', '-1', '--format=%s') == 'Segundo' and
          crudo('show', 'HEAD:a.txt').strip() == 'tres', (t[:200], crudo('log', '-2', '--oneline')))
    t = git('commit', action='amend', message='Segundo, corregido')
    check('V45 amend con message: lo cambia', crudo('rev-list', '--count', 'HEAD') == antes and crudo('log', '-1', '--format=%s') == 'Segundo, corregido', t[:200])
    t = git('commit', action='xx', message='m')
    check('V45 commit con otra action: GIT-085', mc.es(t, 'SR_GIT_ACTION_NO_VA_FMT') and 'amend' in t, t[:200])
    t = git('commit')
    check('V45 commit sin message ni amend sigue pidiendolo', mc.es(t, 'SR_GIT_COMMIT_NEEDS_MESSAGE'), t[:200])
    # la enmienda de lo que un remoto ya tiene
    cabeza = crudo('rev-parse', 'HEAD')
    crudo('update-ref', 'refs/remotes/origin/main', 'HEAD')
    t = git('commit', action='amend', message='no')
    check('V45 amend de un commit que un remoto tiene: GIT-086, y el commit sigue', mc.es(t, 'SR_GIT_AMEND_YA_ENVIADO') and crudo('rev-parse', 'HEAD') == cabeza, t[:300])
    crudo('update-ref', '-d', 'refs/remotes/origin/main')

    # fetch action=prune y clone branch, contra un remoto de verdad
    BARE = os.path.join(RAIZ, 'rem.git')
    crudo('init', '-q', '--bare', BARE)
    crudo('remote', 'add', 'origin', BARE)
    crudo('push', '-q', 'origin', 'HEAD:refs/heads/principal', 'HEAD:refs/heads/vieja')
    t = git('fetch', remote='origin')
    check('V45 control: fetch trae las ramas', 'origin/vieja' in crudo('branch', '-r'), t[:200])
    crudo('update-ref', '-d', 'refs/heads/vieja', cwd=BARE)
    t = git('fetch', remote='origin')
    check('V45 fetch sin prune la deja', 'origin/vieja' in crudo('branch', '-r'), t[:200])
    t = git('fetch', remote='origin', action='xx')
    check('V45 fetch con otra action: GIT-085', mc.es(t, 'SR_GIT_ACTION_NO_VA_FMT') and 'prune' in t, t[:200])
    t = git('fetch', remote='origin', action='prune')
    ramas = crudo('branch', '-r')
    check('V45 fetch action=prune la quita, y la otra sigue', 'origin/vieja' not in ramas and 'origin/principal' in ramas, (t[:200], ramas))
    # un refspec de espejo: --prune borraria ramas LOCALES que el remoto no tiene
    crudo('branch', 'solo-aqui')
    crudo('config', '--add', 'remote.origin.fetch', '+refs/heads/*:refs/heads/*')
    t = git('fetch', remote='origin', action='prune')
    check('V45 prune con un refspec que escribe en ramas locales: GIT-087, y la rama sigue',
          mc.es(t, 'SR_GIT_PRUNE_RAMAS_FMT') and 'solo-aqui' in crudo('branch'), (t[:300], crudo('branch')))
    crudo('config', '--unset', 'remote.origin.fetch', r'\+refs/heads/\*:refs/heads/\*')
    crudo('update-ref', 'refs/heads/otra', cabeza, cwd=BARE)
    crudo('update-server-info', cwd=BARE)
    web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(
        type('Callado', (http.server.SimpleHTTPRequestHandler,), {'log_message': lambda *a: None}), directory=RAIZ))
    threading.Thread(target=web.serve_forever, daemon=True).start()
    URL = 'http://127.0.0.1:%d/rem.git' % web.server_port
    CL = os.path.join(RAIZ, 'cl')
    t = call('delphi_git', {'repo': CL, 'command': 'clone', 'message': URL, 'branch': 'otra'})
    check('V45 clone branch: esa rama, con el arbol', os.path.exists(os.path.join(CL, 'a.txt')) and crudo('branch', '--show-current', cwd=CL) == 'otra', t[:300])
    CL2 = os.path.join(RAIZ, 'cl2')
    t = call('delphi_git', {'repo': CL2, 'command': 'clone', 'message': URL, 'branch': 'no..vale'})
    check('V45 clone con un nombre que git no admite: su negativa, sin carpeta', mc.es(t, 'SR_GIT_NOMBRE_NO_VALE_FMT') and not os.path.exists(CL2), t[:300])
    t = call('delphi_git', {'repo': CL2, 'command': 'clone', 'message': URL, 'branch': 'noexiste'})
    check('V45 clone de una rama que no esta: lo dice git, sin carpeta', 'noexiste' in t and not os.path.exists(CL2), t[:300])
    web.shutdown()

    # V46 - los nombres que Hermes mando a delphi_build
    t = call('delphi_create', {'kind': 'project-console', 'name': 'Alias', 'dir': os.path.join(RAIZ, 'alias')})
    DPROJ = os.path.join(RAIZ, 'alias', 'Alias.dproj')
    check('V46 fixture: el proyecto', os.path.exists(DPROJ), t[:200])
    t = call('delphi_build', {'project': DPROJ, 'command': 'build', 'configuration': 'Release', 'platform': 'Win64'}, t=180)
    check('V46 build con command y configuration: compila, en esa configuracion',
          mc.como_json(t).get('success') is True and os.path.exists(os.path.join(RAIZ, 'alias', 'Win64', 'Release', 'Alias.exe')), t[:300])
    t = call('delphi_build', {'project': DPROJ, 'configuration': 'NoExiste', 'platform': 'Win64'}, t=60)
    check('V46 configuration llega a su juez: una que el proyecto no declara se niega', 'NoExiste' in t and mc.como_json(t).get('success') is not True, t[:300])
    t = call('delphi_build', {'project': DPROJ, 'configuration': 'Release', 'config': 'Debug'}, t=60)
    check('V46 el alias con otro valor que el real: la negativa de siempre', mc.es(t, 'SR_ARG_ALIAS_OTRO_VALOR_FMT'), t[:300])
    d = json.loads(call('delphi_list', {'path': RAIZ, 'pattern': 'UNo.pas'}))
    check('V46 control: path ya valia en delphi_list', d.get('total', 0) >= 1 or d.get('folders'), d)

    # V41 - delphi_changeset stage con ops
    CS = os.path.join(RAIZ, 'cs')
    os.makedirs(CS)
    A, B, M1, M2, N = [os.path.join(CS, x) for x in ('a.txt', 'b.txt', 'm1.txt', 'm2.txt', 'n.txt')]
    for ruta in (A, B, M1):
        with open(ruta, 'w', newline='') as f:
            f.write('uno\r\ndos\r\n')


    def cs(comando, **kw):
        return call('delphi_changeset', dict({'command': comando}, **kw))


    def nuevo():
        return mc.id_changeset(cs('begin'))


    ID = nuevo()
    t = cs('stage', id=ID, ops=[{'kind': 'edit', 'path': A, 'old': 'uno', 'new': 'UNO'},
                                {'kind': 'edit', 'path': mc.virtual(B), 'old': 'dos', 'new': 'DOS'},
                                {'kind': 'create', 'path': N, 'content': 'nuevo'},
                                {'kind': 'move', 'path': M1, 'dest': M2}])
    check('V41 ops: las cuatro apiladas, y dice cada una', t.count('CHSET-021') == 4 and mc.es(t, 'SN_CHANGESET_STAGED_FMT') and not mc.fallo(t), t[:400])
    check('V41 ops: lo que vale para todas, una vez', t.count('MANDATORY') == 1, t[:600])
    p = cs('preview', id=ID)
    check('V41 ops: el preview las ve, con la unidad virtual ya traducida', not mc.fallo(p), p[:400])
    t = cs('commit', id=ID)
    with open(A, 'rb') as f:
        de_a = f.read()
    with open(B, 'rb') as f:
        de_b = f.read()
    check('V41 ops: el commit las aplica todas, en su orden',
          de_a == b'UNO\r\ndos\r\n' and de_b == b'uno\r\nDOS\r\n' and os.path.exists(N) and os.path.exists(M2) and not os.path.exists(M1), (t[:300], de_a, de_b))

    # todas o ninguna, y cada una por la puerta de una suelta
    FUERA = os.path.join(BASE, 'fuera-de-la-raiz.txt')
    ID = nuevo()
    t = cs('stage', id=ID, ops=[{'kind': 'edit', 'path': A, 'old': 'dos', 'new': 'X'}, {'kind': 'create', 'path': FUERA, 'content': 'x'}])
    check('V41 una ruta fuera de la jaula dentro de ops: su negativa, la de siempre', mc.es(t, 'SR_CHANGESET_OP_NEGADA_FMT') and 'GUARD-' in t, t[:300])
    p = cs('preview', id=ID)
    check('V41 ...y la que iba delante no se queda apilada', 'a.txt' not in p, p[:300])
    cs('commit', id=ID)
    with open(A, 'rb') as f:
        check('V41 ...ni el fichero cambia, ni fuera hay nada', f.read() == de_a and not os.path.exists(FUERA), FUERA)
    t = cs('stage', id=ID, ops=[{'kind': 'edit', 'path': '\\\\192.0.2.1\\s\\x.pas', 'old': 'a', 'new': 'b'}])
    check('V41 un UNC ajeno dentro de ops: negado por texto, como uno suelto', mc.es(t, 'SR_CHANGESET_OP_NEGADA_FMT') and 'GUARD-' in t, t[:300])
    t = cs('stage', id=ID, ops=[{'kind': 'edit', 'path': A, 'old': 'dos', 'new': 'X', 'noexiste': 1}])
    check('V41 un campo que no existe dentro de una op: SYS-015', mc.es(t, 'SR_CHANGESET_OP_NEGADA_FMT') and mc.es(t, 'SR_SYS_UNKNOWN_PARAM_FMT'), t[:300])
    t = cs('stage', id=ID, ops=[{'kind': 'delete', 'path': A, 'old': 'dos'}])
    check('V41 lo que no es de su kind, como en una suelta', mc.es(t, 'SR_CHANGESET_NO_ES_DE_KIND_FMT'), t[:300])
    for malo in ({'command': 'commit'}, {'id': 'otro'}, {'ops': []}):
        t = cs('stage', id=ID, ops=[dict({'kind': 'edit', 'path': A}, **malo)])
        check('V41 una op no lleva %s' % list(malo)[0], mc.es(t, 'SR_CHANGESET_OP_CAMPO_FMT'), t[:300])
    for malo in ([], ['texto'], [{'kind': 'delete', 'path': A}] * 51):
        t = cs('stage', id=ID, ops=malo)
        check('V41 ops de %d: su negativa' % len(malo), mc.es(t, 'SR_CHANGESET_OPS_LISTA_FMT') or (malo == ['texto'] and mc.es(t, 'SR_CHANGESET_OP_NEGADA_FMT')), t[:300])
    t = cs('stage', id=ID, kind='edit', ops=[{'kind': 'delete', 'path': A}])
    check('V41 ops con kind: no se mezclan', mc.es(t, 'SR_CHANGESET_NO_VA_CON_COMANDO_FMT'), t[:300])
    t = cs('preview', id=ID, ops=[{'kind': 'delete', 'path': A}])
    check('V41 ops solo va con stage', mc.es(t, 'SR_CHANGESET_NO_VA_CON_COMANDO_FMT'), t[:300])
    cs('rollback', id=ID)
    # una sola sigue valiendo
    ID = nuevo()
    t = cs('stage', id=ID, kind='edit', path=A, old='dos', new='DOS')
    check('V41 control: stage suelto sigue igual', not mc.fallo(t) and mc.es(t, 'SN_CHANGESET_STAGED_FMT'), t[:300])
    cs('rollback', id=ID)
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
