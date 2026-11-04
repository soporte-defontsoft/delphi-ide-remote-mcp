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
V12: delphi_build da los hints en su lista, sin gastar de mas: nada en quiet, sin repetirlos en la cola, con tope y
cuenta.
V132b: delphi_rename_symbol niega si una unidad que no escribe cambiaria de destino en silencio: la que usa las dos,
con la renombrada DESPUES (medido con dcc: gana la ultima del uses, y las de implementation van despues), una global
del interface. Ni un metodo, ni una rutina solo de implementation, ni una declaracion local, ni un nombre calificado.
V224 (visto en vivo al probar V132b): de una llamada a una rutina con la cabecera en VARIAS lineas, el motor contesta una
linea interior de la cabecera, que no la nombra: definition apuntaba ahi, references la rechazaba y rename se bloqueaba.
V190b: delphi_definition dice que hay en el destino (name y text), sin otra llamada a delphi_read.
V40: una local de nombre comun se puede renombrar: su alcance es su rutina (cada I de otra rutina la bloqueaba como
homonimo, y el tope de candidatos se gastaba en todo el proyecto).

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
        # el tope, no 'como mucho': <= 25 pasaba con limit ignorado (10 por defecto) o con 0 (revisor de
        # baterias de la 1.27). Con mas de 25 resultados, 25 justos
        d4 = json.loads(t4)
        check('V39 limit sigue con su tope de 25', d4.get('total', 0) > 25 and d4.get('shown') == 25, t4[:200])

    # V44 - delphi_search: contexto
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'AGUJA', 'context': 2}))
    h = hits(d).get('UNo.pas', [{}])[0]
    check('V44 context: las dos de antes y las dos de despues, tal cual',
          h.get('before') == ['// uno', '// dos'] and h.get('after') == ['// cuatro', '// cinco'] and h.get('text') == '// AGUJA', d)
    check('V44 y el acierto sigue en su sitio', h.get('line') == 4 and h.get('line0') == 3, h)
    d = json.loads(call('delphi_search', {'root': os.path.join(RAIZ, 'UNo.pas'), 'query': 'unit UNo', 'context': 3}))
    h = hits(d)['UNo.pas'][0]
    check('V44 context en la primera linea: before vacio', h.get('before') == [] and len(h.get('after', [])) == 3, h)
    # el tope de VERDAD: 12 lineas antes del acierto. Con AGUJA en la linea 4 solo habia 3,
    # y len == 3 pasaba con cualquier tope (revisor de baterias de la 1.27). Se planta y se
    # quita aqui: las de abajo cuentan los ficheros de RAIZ
    larga = os.path.join(RAIZ, 'ULarga.pas')
    with open(larga, 'w', newline='') as f:
        f.write('unit ULarga;\r\n' + ''.join('// l%d\r\n' % i for i in range(12)) + '// TOPEHIT\r\nend.\r\n')
    d = json.loads(call('delphi_search', {'root': larga, 'query': 'TOPEHIT', 'context': 500}))
    os.remove(larga)
    check('V44 context tiene su tope (10, el que dice su esquema)',
          len(hits(d).get('ULarga.pas', [{}])[0].get('before', [])) == 10, d)
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
    # git contesto (exit=0): "no sale Primero" pasaba tambien con la orden negada (revisor de baterias de la 1.27)
    check('V45 log grep es texto, no una expresion',
          mc.llego_a_git(t) and not mc.fallo(t) and 'Primero' not in t, t[:300])
    t = git('log', grep='x" --output=fuera.txt "')
    check('V45 log grep con comillas sigue siendo un solo argumento',
          mc.llego_a_git(t) and not mc.fallo(t) and not os.path.exists(os.path.join(REPO, 'fuera.txt')), t[:300])
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
    check('V41 ops: las cuatro apiladas, y dice cada una', mc.ids(t).count(mc.id_de('SN_CHANGESET_STAGED_FMT')) == 4 and not mc.fallo(t), t[:400])
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

    # V12 - los hints de delphi_build
    call('delphi_create', {'kind': 'project-console', 'name': 'Pistas', 'dir': os.path.join(RAIZ, 'pistas')})
    DPR = os.path.join(RAIZ, 'pistas', 'Pistas.dpr')
    PROY = os.path.join(RAIZ, 'pistas', 'Pistas.dproj')
    with open(DPR, newline='') as f:
        LIMPIO = f.read()


    def con_rutinas(n):
        rutinas = ''.join('procedure P%d;\r\nvar\r\n  X: Integer;\r\nbegin\r\n  X := %d;\r\nend;\r\n\r\n' % (i, i) for i in range(n))
        with open(DPR, 'w', newline='') as f:
            f.write(LIMPIO.replace('begin', rutinas + 'begin', 1))


    def compila(verbosidad):
        return mc.como_json(call('delphi_build', {'project': PROY, 'platform': 'Win64', 'config': 'Debug', 'verbosity': verbosidad}, t=180))


    j = compila('normal')
    check('V12 sin hints, sin lista', j.get('success') is True and 'hints' not in j, str(j)[:300])
    con_rutinas(1)
    j = compila('normal')
    h = j.get('hints') or []
    check('V12 normal: el hint en su lista, con su sitio', len(h) == 1 and 'H2077' in h[0] and 'Pistas.dpr(' in h[0] and 'hintsTotal' not in j, str(j)[:400])
    check('V12 ...ni entre los warnings ni repetido en la cola', not any('H2077' in w for w in j.get('warnings', [])) and 'H2077' not in (j.get('outputTail') or ''), str(j)[:400])
    j = compila('quiet')
    check('V12 quiet: nada, ni lista ni cola', j.get('success') is True and 'hints' not in j and 'H2077' not in json.dumps(j), str(j)[:400])
    j = compila('verbose')
    check('V12 verbose: tambien en su lista', any('H2077' in x for x in j.get('hints') or []), str(j)[:300])
    con_rutinas(60)
    j = compila('normal')
    h = j.get('hints') or []
    check('V12 con muchos: su tope y la cuenta de todos', len(h) == 50 and j.get('hintsTotal') == 60, (len(h), j.get('hintsTotal')))
    check('V12 ...y los que no caben tampoco van a la cola', 'H2077' not in (j.get('outputTail') or ''), (j.get('outputTail') or '')[:300])

    # V132b - la tercera unidad del rename
    RN = os.path.join(RAIZ, 'rn')
    call('delphi_create', {'kind': 'project-console', 'name': 'Rn', 'dir': RN})
    RDPR = os.path.join(RN, 'Rn.dpr')


    def unit(nombre, de_int='', uses_int='', uses_imp='', cuerpo=''):
        with open(os.path.join(RN, nombre + '.pas'), 'w', newline='') as f:
            f.write('unit %s;\r\n\r\ninterface\r\n\r\n%s%s\r\nimplementation\r\n\r\n%s%s\r\nend.\r\n' % (
                nombre, 'uses\r\n  %s;\r\n\r\n' % uses_int if uses_int else '', de_int,
                'uses\r\n  %s;\r\n\r\n' % uses_imp if uses_imp else '', cuerpo))


    PIDE = 'procedure Pide;\r\nbegin\r\n  Sumar;\r\nend;\r\n'
    unit('UCalc', 'procedure Sumar;\r\n', cuerpo='procedure Sumar;\r\nbegin\r\nend;\r\n')
    unit('UPatch', 'procedure MarcarNuevo;\r\n\r\ntype\r\n  TC = class\r\n    procedure Otro;\r\n  end;\r\n',
         cuerpo='procedure MarcarNuevo;\r\nbegin\r\nend;\r\n\r\nprocedure Oculto;\r\nbegin\r\nend;\r\n\r\nprocedure TC.Otro;\r\nbegin\r\nend;\r\n')
    unit('UCambia', uses_int='UCalc, UPatch', cuerpo=PIDE)
    unit('UCambiaImp', uses_int='UCalc', uses_imp='UPatch', cuerpo=PIDE)
    unit('USeQueda', uses_int='UPatch, UCalc', cuerpo=PIDE)
    unit('USeQuedaImp', uses_int='UPatch', uses_imp='UCalc', cuerpo=PIDE)
    unit('ULocal', uses_int='UCalc, UPatch', cuerpo='procedure Sumar;\r\nbegin\r\nend;\r\n\r\n' + PIDE)
    unit('UCalificada', uses_int='UCalc, UPatch', cuerpo='procedure Pide;\r\nbegin\r\n  UCalc.Sumar;\r\nend;\r\n')
    unit('USinOtra', uses_int='UPatch', cuerpo='procedure Pide;\r\nbegin\r\n  UPatch.MarcarNuevo;\r\nend;\r\n')
    with open(RDPR, encoding='utf-8-sig', newline='') as f:
        DE_RDPR = f.read()
    NOMBRES = ['UCalc', 'UPatch', 'UCambia', 'UCambiaImp', 'USeQueda', 'USeQuedaImp', 'ULocal', 'UCalificada', 'USinOtra']
    with open(RDPR, 'w', encoding='utf-8', newline='') as f:
        f.write(DE_RDPR.replace('uses\r\n', 'uses\r\n  %s,\r\n' % ', '.join("%s in '%s.pas'" % (n, n) for n in NOMBRES), 1))
    UPATCH = os.path.join(RN, 'UPatch.pas')


    def renombra(ident, nuevo='Sumar', modo='preview'):
        lineas = open(UPATCH, newline='').read().split('\r\n')
        i = next(k for k, l in enumerate(lineas) if ident in l and ('procedure' in l or 'TC.' in l))
        return mc.como_json(call('delphi_rename_symbol', {'path': UPATCH, 'line': i, 'character': lineas[i].index(ident) + 1,
                                                          'newname': nuevo, 'mode': modo}, t=240))


    j = renombra('MarcarNuevo')
    bl = ' '.join(j.get('blockers', []))
    cambia = sorted(os.path.basename(x.get('path', '')) for x in j.get('retargeted', []))
    check('V132b una global que tomaria los usos de otra unidad: RENAME-023, con los que cambian de destino',
          j.get('applicable') is False and mc.es(bl, 'SR_RENAME_CAMBIA_DESTINO_FMT') and cambia == ['UCambia.pas', 'UCambiaImp.pas'], str(j)[:700])
    check('V132b ...y dice a donde resuelven hoy', all('UCalc' in x.get('resolvedTo', '') for x in j.get('retargeted', [])) and j.get('retargeted'), str(j.get('retargeted'))[:400])
    j = renombra('Otro')
    check('V132b un metodo no entra en el ambito de nadie: sin RENAME-023', not mc.es(' '.join(j.get('blockers', [])), 'SR_RENAME_CAMBIA_DESTINO_FMT') and j.get('applicable') is True, str(j)[:500])
    j = renombra('Oculto')
    # aplicable, como el metodo: sin respuesta, "sin RENAME-023" pasaba igual (revisor de baterias de la 1.27)
    check('V132b una rutina solo de implementation tampoco',
          not mc.es(' '.join(j.get('blockers', [])), 'SR_RENAME_CAMBIA_DESTINO_FMT') and j.get('applicable') is True, str(j)[:500])
    j = renombra('MarcarNuevo', 'NombreLibre')
    check('V132b un nombre que nadie usa: aplicable', j.get('applicable') is True and 'retargeted' not in j, str(j)[:500])
    # sin las dos que cambian, el rename es aplicable y compila: los demas siguen con su destino
    for n in ('UCambia', 'UCambiaImp'):
        os.remove(os.path.join(RN, n + '.pas'))
    with open(RDPR, encoding='utf-8-sig', newline='') as f:
        d_ = f.read()
    with open(RDPR, 'w', encoding='utf-8', newline='') as f:
        f.write(d_.replace("UCambia in 'UCambia.pas', UCambiaImp in 'UCambiaImp.pas', ", ''))
    j = renombra('MarcarNuevo')
    check('V132b sin ellas: aplicable', j.get('applicable') is True and 'retargeted' not in j, str(j)[:600])
    j = renombra('MarcarNuevo', modo='apply')
    b = mc.como_json(call('delphi_build', {'project': os.path.join(RN, 'Rn.dproj'), 'platform': 'Win64', 'config': 'Debug'}, t=180))
    check('V132b ...y lo que queda compila (el juez de que no era colision)', b.get('success') is True, str(b)[:500])

    # V224 - las cabeceras en varias lineas
    LM = os.path.join(RAIZ, 'lm')
    call('delphi_create', {'kind': 'project-console', 'name': 'Lm', 'dir': LM})


    def fuente(nombre, texto):
        with open(os.path.join(LM, nombre), 'w', newline='') as f:
            f.write(texto.replace('\n', '\r\n'))


    fuente('UDef.pas', 'unit UDef;\n\ninterface\n\nprocedure Larga(A: Integer;\n  B: Integer;\n  C: Integer);\n\nprocedure Corta(A: Integer);\n\n'
           'type\n  TK = class\n    procedure Met(A: Integer;\n      B: Integer);\n  end;\n\nimplementation\n\n'
           'procedure Larga(A: Integer;\n  B: Integer;\n  C: Integer);\nbegin\nend;\n\nprocedure Corta(A: Integer);\nbegin\nend;\n\n'
           'procedure TK.Met(A: Integer;\n  B: Integer);\nbegin\nend;\n\nend.\n')
    fuente('UOtra.pas', 'unit UOtra;\n\ninterface\n\nprocedure Larga(A: Integer;\n  B: Integer);\n\nimplementation\n\nprocedure Larga(A: Integer;\n  B: Integer);\nbegin\nend;\n\nend.\n')
    fuente('UUsa.pas', 'unit UUsa;\n\ninterface\n\nprocedure Pide;\n\nimplementation\n\nuses\n  UDef, UOtra;\n\nprocedure Pide;\nvar\n  K: TK;\nbegin\n'
           '  UDef.Larga(1, 2, 3);\n  Corta(1);\n  K := TK.Create;\n  K.Met(1, 2);\n  UOtra.Larga(1, 2);\nend;\n\nend.\n')
    LDPR = os.path.join(LM, 'Lm.dpr')
    with open(LDPR, encoding='utf-8-sig', newline='') as f:
        d_ = f.read()
    with open(LDPR, 'w', encoding='utf-8', newline='') as f:
        f.write(d_.replace('uses\r\n', "uses\r\n  UDef in 'UDef.pas', UOtra in 'UOtra.pas', UUsa in 'UUsa.pas',\r\n", 1))
    UDEF, UUSA = os.path.join(LM, 'UDef.pas'), os.path.join(LM, 'UUsa.pas')


    def donde(ruta, trozo, nombre):
        ls = open(ruta, newline='').read().split('\r\n')
        i = next(k for k, l in enumerate(ls) if trozo in l)
        return i, ls[i].index(nombre) + 1


    def definicion(ruta, trozo, nombre):
        i, c = donde(ruta, trozo, nombre)
        return mc.como_json(call('delphi_definition', {'path': UUSA if ruta == UUSA else ruta, 'line': i, 'character': c}, t=120))


    lineas_def = open(UDEF, newline='').read().split('\r\n')
    impl_larga = next(k for k, l in enumerate(lineas_def) if l.startswith('procedure Larga') and k > 10)
    impl_met = next(k for k, l in enumerate(lineas_def) if l.startswith('procedure TK.Met'))
    j = definicion(UUSA, 'UDef.Larga', 'Larga')
    check('V224 definition de una llamada: la cabecera, no una linea de dentro', j.get('line0') == impl_larga and j.get('character0') == 10, j)
    j = definicion(UUSA, 'K.Met', 'Met')
    check('V224 ...tambien de un metodo', j.get('line0') == impl_met and j.get('character0') == 13, j)
    j = definicion(UUSA, 'Corta(1)', 'Corta')
    check('V224 control: una cabecera de una linea, igual que siempre', 'Corta' in lineas_def[j.get('line0', 0)], j)
    i, c = donde(UDEF, 'procedure Larga', 'Larga')
    j = mc.como_json(call('delphi_references', {'path': UDEF, 'line': i, 'character': c}, t=240))
    textos = json.dumps(j.get('confirmed', ''))
    # el homonimo rechazado, por su clave de verdad: 'rejectedCount' no lo emite el servidor (Lsp.References
    # escribe rejectedHomonyms) y get(..., 1) lo daba siempre por bueno (revisor de baterias de la 1.27)
    check('V224 references confirma la llamada, y no la de otra unidad',
          'UDef.Larga' in textos and 'UOtra.Larga' not in textos and j.get('rejectedHomonyms', 0) >= 1, str(j)[:500])
    i, c = donde(UUSA, 'UDef.Larga', 'Larga')
    j = mc.como_json(call('delphi_rename_symbol', {'path': UUSA, 'line': i, 'character': c, 'newname': 'LargaNueva'}, t=240))
    rej = json.dumps(j.get('lookalikes', ''))
    check('V224 rename desde la llamada: la de la otra unidad es homonima, la propia no',
          'UDef.Larga' not in rej and 'UOtra.Larga' in rej and j.get('occurrences') == 3, str(j)[:600])
    i, c = donde(UDEF, 'procedure TK.Met', 'Met')
    j = mc.como_json(call('delphi_rename_symbol', {'path': UDEF, 'line': i, 'character': c, 'newname': 'MetNuevo'}, t=240))
    check('V224 rename de un metodo con la cabecera en dos lineas: aplicable', j.get('applicable') is True, str(j)[:600])
    j = mc.como_json(call('delphi_rename_symbol', {'path': UDEF, 'line': i, 'character': c, 'newname': 'MetNuevo', 'mode': 'apply'}, t=240))
    b = mc.como_json(call('delphi_build', {'project': os.path.join(LM, 'Lm.dproj'), 'platform': 'Win64', 'config': 'Debug'}, t=180))
    check('V224 ...y aplicado compila', b.get('success') is True, str(b)[:500])

    # V190b - lo que hay en el destino de delphi_definition
    j = definicion(UUSA, 'Corta(1)', 'Corta')
    check('V190b definition: name y text del destino', j.get('name') == 'Corta' and j.get('text') == 'procedure Corta(A: Integer);', j)
    j = definicion(UUSA, 'UDef.Larga', 'Larga')
    check('V190b ...en una cabecera de varias lineas, su primera', j.get('name') == 'Larga' and j.get('text') == 'procedure Larga(A: Integer;', j)
    with open(UDEF, encoding='utf-8-sig', newline='') as f:
        d_ = f.read()
    with open(UDEF, 'w', newline='') as f:
        f.write(d_.replace('type\r\n', "const\r\n  RUTA_C = 'D:\\x\\y.txt';\r\n\r\ntype\r\n", 1))
    with open(UUSA, encoding='utf-8-sig', newline='') as f:
        d_ = f.read()
    with open(UUSA, 'w', newline='') as f:
        f.write(d_.replace('  Corta(1);', '  Corta(Length(RUTA_C));', 1))
    i, c = donde(UUSA, 'Length(RUTA_C)', 'RUTA_C')
    j = mc.como_json(call('delphi_definition', {'path': UUSA, 'line': i, 'character': c}, t=120))
    check('V190b text es el fuente tal cual: una ruta dentro no se enmascara', "RUTA_C = 'D:\\x\\y.txt'" in (j.get('text') or ''), j)
    i, c = donde(UUSA, 'TK.Create', 'Create')
    j = mc.como_json(call('delphi_definition', {'path': UUSA, 'line': i, 'character': c}, t=120))
    check('V190b en la biblioteca, tambien (lo que el motor puede ensenar)', 'Create' in (j.get('text') or '') and j.get('name') == 'Create', str(j)[:300])

    # V40 - una local de nombre comun
    LC = os.path.join(RAIZ, 'lc')
    call('delphi_create', {'kind': 'project-console', 'name': 'Lc', 'dir': LC})
    with open(os.path.join(LC, 'UOtro.pas'), 'w', newline='') as f:
        f.write('unit UOtro;\r\n\r\ninterface\r\n\r\nprocedure Fuera;\r\n\r\nimplementation\r\n\r\nprocedure Fuera;\r\nvar\r\n  I: Integer;\r\nbegin\r\n  I := 1;\r\n'
                + '  I := I + 1;\r\n' * 450 + 'end;\r\n\r\nend.\r\n')
    ULOC = os.path.join(LC, 'ULoc.pas')
    TEXTO_LOC = ('unit ULoc;\r\n\r\ninterface\r\n\r\nprocedure Uno;\r\nprocedure Dos(I: Integer);\r\n\r\nimplementation\r\n\r\nvar\r\n  Otro: Integer;\r\n\r\n'
                 "procedure Uno;\r\nvar\r\n  I, J: Integer;\r\n\r\n  procedure Dentro;\r\n  begin\r\n    I := 2; // I\r\n  end;\r\n\r\nbegin\r\n  I := 1;\r\n  J := I + Length('I');\r\n  Dentro;\r\nend;\r\n\r\n"
                 'procedure Dos(I: Integer);\r\nvar\r\n  J: Integer;\r\nbegin\r\n  J := I;\r\n  Otro := J;\r\nend;\r\n\r\nprocedure Tres;\r\nvar\r\n  I: Integer;\r\nbegin\r\n  I := 1;\r\n  Otro := I;\r\nend;\r\n\r\nend.\r\n')
    with open(ULOC, 'w', newline='') as f:
        f.write(TEXTO_LOC)
    with open(os.path.join(LC, 'Lc.dpr'), encoding='utf-8-sig', newline='') as f:
        d_ = f.read()
    with open(os.path.join(LC, 'Lc.dpr'), 'w', encoding='utf-8', newline='') as f:
        f.write(d_.replace('uses\r\n', "uses\r\n  UOtro in 'UOtro.pas', ULoc in 'ULoc.pas',\r\n", 1))


    def renombra_local(trozo, nombre, nuevo, modo='preview'):
        i, c = donde_en(ULOC, trozo, nombre)
        return mc.como_json(call('delphi_rename_symbol', {'path': ULOC, 'line': i, 'character': c, 'newname': nuevo, 'mode': modo}, t=240))


    def donde_en(ruta, trozo, nombre):
        # en el primer caracter: con un nombre de una letra, uno mas cae fuera de el
        ls = open(ruta, newline='').read().split('\r\n')
        i = next(k for k, l in enumerate(ls) if trozo in l)
        return i, ls[i].index(trozo) + trozo.index(nombre)


    j = renombra_local('I, J: Integer', 'I', 'Cuenta')
    check('V40 una local: aplicable, solo en su rutina, con las de la anidada (su declaracion y tres usos)', j.get('applicable') is True and j.get('occurrences') == 4 and j.get('filesTouched') == 1, str(j)[:700])
    check('V40 ...y dice su alcance, sin homonimos de otras rutinas ni de otras unidades', j.get('localTo', {}).get('routine') == 'Uno' and 'lookalikes' not in j and j.get('filesScanned') == 1, str(j)[:500])
    check('V40 una cadena con su nombre no bloquea: a una local no se llega por ahi, y se avisa', not any(mc.es(b, 'SR_RENAME_STRINGS_FMT') for b in j.get('blockers', [])) and j.get('mentionsCount', 0) >= 1, str(j)[:500])
    j = renombra_local('I, J: Integer', 'I', 'Otro')
    check('V40 un nombre libre en su rutina pero usado fuera: aplicable', j.get('applicable') is True, str(j)[:500])
    j = renombra_local('I, J: Integer', 'I', 'J')
    check('V40 un nombre que ya esta en su rutina: choca', j.get('applicable') is False and any(mc.es(b, 'SR_RENAME_COLLISION_FMT') for b in j.get('blockers', [])), str(j)[:500])
    # desde un USO en el cuerpo: en la cabecera el motor no resuelve un parametro (LSP-003)
    ls_ = open(ULOC, newline='').read().split('\r\n')
    i = next(k for k, l in enumerate(ls_) if l == '  J := I;' and k > next(n for n, x in enumerate(ls_) if x.startswith('procedure Dos') and n > 10))
    t = call('delphi_references', {'path': ULOC, 'line': i, 'character': ls_[i].index('I')}, t=240)
    check('V40 un parametro no es una local: su cabecera vive en dos sitios', mc.como_json(t).get('identifier') == 'I' and 'localTo' not in t, t[:500])
    j = renombra_local('I, J: Integer', 'I', 'Cuenta', 'apply')
    with open(ULOC, newline='') as f:
        final = f.read()
    check('V40 apply: la de Uno y la anidada; Dos y Tres como estaban', 'Cuenta, J: Integer' in final and 'Cuenta := 2; // I' in final and 'Cuenta := 1;' in final and
          "J := Cuenta + Length('I');" in final and 'procedure Dos(I: Integer);' in final and final.count('  I: Integer;') == 1 and 'Otro := I;' in final, final[:700])
    b = mc.como_json(call('delphi_build', {'project': os.path.join(LC, 'Lc.dproj'), 'platform': 'Win64', 'config': 'Debug'}, t=180))
    check('V40 ...y compila', b.get('success') is True, str(b)[:500])
finally:
    srv.mata()

# V42 - delphi_desktop con el PAServer caido
HERE = os.path.dirname(os.path.abspath(__file__))
SRV = os.path.join(BASE, 'srv')
EXE2 = mc.copia_exe(SRV)
shutil.copytree(os.path.join(os.path.dirname(HERE), 'node'), os.path.join(SRV, 'node'))
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
STUB = mc.paclient_falso('capacidades_125')  # el de la casa (revisor de baterias de la 1.27)
REMOTERUN_SUB = mc.cadena_del_fuente('Server/Lsp.RemoteRun.pas', 'REMOTERUN_SUB')
REMOTERUN_VER = mc.cadena_del_fuente('Server/Lsp.RemoteRun.pas', 'REMOTERUN_VER_PREFIJO')
LOG = os.path.join(BASE, 'paclient.log')
for perfil in ('caido', 'otro', 'vivo'):
    ad, host = mc.appdata_perfil(BASE, perfil, '127.0.0.1')
TOKEN = 'capacidades-125'
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\nAllowRemoteRun=1\nRemoteRunProjects=all\nRemoteHosts=%s\nDesktopAllowedHosts=%s\n' % (TOKEN, RAIZ, host, host))
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
          # sus nombres, del fuente (mc.cadena_del_fuente): a mano no caian si cambiaban
          not glob.glob(os.path.join(SRV, mc.TEMPORALES, REMOTERUN_SUB, REMOTERUN_VER + '*')),
          glob.glob(os.path.join(SRV, mc.TEMPORALES, REMOTERUN_SUB, '*')))
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
    # lo mide el EVENTO: el otro contesta con el primero aun esperando a su paclient de 6 s (sigue). El
    # 'tardo < 3' de antes no anadia nada a eso y con la maquina cargada fallaba solo
    check('V42 un perfil caido no retiene a otro: contesta mientras el primero sigue esperando a paclient',
          sigue and mc.como_json(r).get('reachable') is False, (sigue, tardo, r[:200]))

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
