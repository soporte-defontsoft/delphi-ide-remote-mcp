# -*- coding: utf-8 -*-
"""Git en cerrado: metadatos, config, remotos, entorno y firma.
Todas las cobayas y los endpoints son propios del arnes; no hay credenciales.
La latencia sola es guarda: trace2 mide las DOS variables del hijo.
Desde la 1.19.0 delphi_git no tiene args: las opciones de firma (y de
Signed-off-by) ni se pueden escribir - la forma vieja contesta GIT-068 sin
llegar a git, y un nombre de tag con '-' delante es GIT-071 -; el remoto va
por su NOMBRE (una URL en la llamada es GIT-049).
"""
import atexit, base64, hashlib, http.server, json, os, subprocess, threading, time, zipfile
import mcp_cliente as mc
from mcp_cliente import check
BASE = mc.carpeta('git-config-cerrado')
atexit.register(mc.borra, BASE)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
REPO = os.path.join(JAIL, 'repo')
os.makedirs(REPO)
GLOBAL = os.path.join(BASE, 'global.config')
TRACE = os.path.join(BASE, 'git-trace.json')
os.makedirs(os.path.join(BASE, 'gpg'))
open(GLOBAL, 'w').write('[trace2]\n envVars = GIT_TERMINAL_PROMPT,GCM_INTERACTIVE\n')
def raw(*args, cwd=REPO):
    p = subprocess.run(['git', '-c', 'user.name=DUMMY', '-c', 'user.email=dummy@example.invalid',
                        '-c', 'commit.gpgsign=false', '-c', 'tag.gpgsign=false', *args],
                       cwd=cwd, capture_output=True, text=True, timeout=30,
                       env=dict(os.environ, GIT_CONFIG_GLOBAL=GLOBAL, GIT_CONFIG_NOSYSTEM='1',
                                GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never',
                                GIT_LFS_SKIP_SMUDGE='1', GNUPGHOME=os.path.join(BASE, 'gpg')))
    assert p.returncode == 0, p.stderr
    return p.stdout
raw('init', '-q', '-b', 'main')
raw('config', 'user.name', 'DUMMY')
raw('config', 'user.email', 'dummy@example.invalid')
open(os.path.join(REPO, 'dato.txt'), 'w').write('DUMMY\n')
raw('add', '.'); raw('commit', '-qm', 'DUMMY')
CFG = os.path.join(REPO, '.git', 'config')
normal = open(CFG).read()
META = os.path.join(REPO, '.git')
ALIAS = os.path.join(JAIL, 'metadatos')
check('fixture junction al .git', mc.junction(ALIAS, META))
private = 'DUMMY_VALUE_NOT_FOR_RESPONSE'
probe = os.path.join(META, 'DUMMY.txt')
open(probe, 'w').write(private)
source = os.path.join(META, 'DUMMY.pas')
open(source, 'w').write('unit DUMMY;\ninterface\nconst Value = 1;\nimplementation\nend.\n')
entrada = os.path.join(JAIL, 'entrada.txt')
open(entrada, 'w').write('DUMMY copia')
hits = []
class Local(http.server.SimpleHTTPRequestHandler):
    def __init__(self,*a,**kw): super().__init__(*a,directory=JAIL,**kw)
    def do_GET(self):
        if self.path.startswith('/normal.git/'):
            return super().do_GET()
        hits.append(self.path)
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="DUMMY"')
        self.end_headers()
    def log_message(self, *args): pass
http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Local)
threading.Thread(target=http.serve_forever, daemon=True).start()
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL,
    'DELPHI_MCP_GIT_REMOTES': '127.0.0.1',
    'GIT_CONFIG_GLOBAL': GLOBAL, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_TRACE2_EVENT': TRACE,
    'GIT_TERMINAL_PROMPT': '1', 'GCM_INTERACTIVE': 'always',
    'GNUPGHOME': os.path.join(BASE, 'gpg'), 'GIT_LFS_SKIP_SMUDGE': '1'}),
    nombre='git-config-cerrado', t=90)
def call(cmd, args=None, message='', repo=REPO, **campos):
    # 1.19.0: sin args; solo viaja cuando se pasa (para ver que se rechaza)
    llamada = dict({'repo': repo, 'command': cmd, 'message': message}, **campos)
    if args is not None:
        llamada['args'] = args
    return srv.call('delphi_git', llamada)
def snap(folder):
    return {os.path.relpath(os.path.join(d,n),folder):
            hashlib.sha256(open(os.path.join(d,n),'rb').read()).hexdigest()
            for d,_,ns in os.walk(folder) for n in ns}
try:
    check('control status normal', call('status').startswith('exit=0'))
    for folder in (META, ALIAS):
        saved = {os.path.relpath(os.path.join(d,n),META): open(os.path.join(d,n),'rb').read()
                 for d,_,ns in os.walk(META) for n in ns}
        before = snap(META)
        for tool, params in (
            ('delphi_read', {'path': os.path.join(folder,'DUMMY.txt')}),
            ('delphi_fetch', {'path': os.path.join(folder,'DUMMY.txt')}),
            ('delphi_list', {'root': folder, 'pattern': '*'}),
            ('delphi_search', {'root': folder, 'query': private, 'pattern': '*'}),
            ('delphi_textedit', {'path': os.path.join(folder,'DUMMY.txt'), 'old': private, 'new': private+' cambiado'}),
            ('delphi_textedit', {'path': os.path.join(folder,'hooks','DUMMY'), 'create': True, 'content': 'DUMMY inerte'}),
            ('delphi_upload', {'path': os.path.join(folder,'DUMMY-upload.txt'), 'chunkbase64': base64.b64encode(b'DUMMY').decode()}),
            ('delphi_edit', {'path': os.path.join(folder,'DUMMY.pas'), 'old': 'const Value = 1;', 'new': 'const Value = 2;'}),
            ('delphi_create', {'kind': 'unit', 'dir': folder, 'name': 'DUMMYNew'}),
            ('delphi_changeset', {'path': os.path.join(folder,'DUMMY.txt')}),
            ('delphi_move', {'path': entrada, 'dest': os.path.join(folder,'DUMMY-move.txt'), 'copy': True}),
            ('delphi_delete', {'path': os.path.join(folder,'DUMMY.txt')}),
        ):
            if tool == 'delphi_changeset':
                ident = mc.id_changeset(srv.call(tool, {'command':'begin'}))
                try:
                    out = srv.call(tool, dict(params, command='stage', id=ident,
                        kind='edit', old=private, new=private+' cambiado'))
                    if '[GUARD-' not in out:
                        out = srv.call(tool, {'command':'preview', 'id':ident})
                    if '[GUARD-' not in out:
                        out = srv.call(tool, {'command':'commit', 'id':ident})
                finally:
                    srv.call(tool, {'command':'rollback','id':ident})
            else:
                out = srv.call(tool, params)
            check(tool+' no toca metadatos '+('directos' if folder==META else 'por junction'),
                  '[GUARD-' in out and 'delphi_git' in out and private not in out, out[:350])
            check(tool+' conserva hashes '+('directos' if folder==META else 'por junction'),
                  snap(META)==before)
            # El arnes repone SOLO su .git DUMMY: cada llamada vuelve a la misma cobaya.
            for d,ds,ns in os.walk(META, topdown=False):
                for n in ns:
                    f=os.path.join(d,n)
                    if os.path.relpath(f,META) not in saved: os.remove(f)
                for n in ds:
                    f=os.path.join(d,n)
                    if not os.listdir(f): os.rmdir(f)
            for name,data in saved.items():
                f=os.path.join(META,name)
                os.makedirs(os.path.dirname(f),exist_ok=True)
                if not os.path.isfile(f) or open(f,'rb').read()!=data:
                    open(f,'wb').write(data)
    for tool,copy in (('delphi_delete',False),('delphi_move',False),('delphi_move',True)):
        tree=os.path.join(JAIL,'padre')
        desttree=os.path.join(JAIL,'padre-dest')
        os.makedirs(os.path.join(tree,'.git'))
        sentinel=os.path.join(tree,'.git','DUMMY')
        open(sentinel,'w').write(private)
        before=snap(tree)
        params={'path':tree}
        if tool=='delphi_move': params.update(dest=desttree,copy=copy)
        out=srv.call(tool,params)
        if copy:
            check('copy del padre niega metadatos',mc.es(out,'SR_GUARD_GIT_METADATA_FMT') and 'delphi_git' in out,out[:350])
            check('copy conserva hashes',os.path.isdir(tree) and snap(tree)==before)
            check('no aparece copia de metadatos',not os.path.exists(desttree))
        elif tool=='delphi_move':
            check('move del padre permitido',mc.es(out,'SK_MOVE_MOVIDO_FMT') and os.path.isdir(desttree),out[:350])
            check('move conserva hashes',os.path.isdir(desttree) and snap(desttree)==before)
        else:
            copias=mc.copias(JAIL,'padre',cajon='CAJON_BORRADOS')
            check('delete del padre permitido',mc.es(out,'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.exists(tree),out[:350])
            check('papelera conserva hashes',len(copias)==1 and snap(copias[0])==before,copias)
        mc.borra(tree); mc.borra(desttree)
    # delphi_package de una carpeta con un .git: lo que la puerta de leer no
    # admite no va en el paquete (revisor de version de la 1.18.0: el .git
    # entero salia en el zip, con su config y sus hooks, medido)
    pk = os.path.join(JAIL, 'paquete')
    os.makedirs(os.path.join(pk, '.git', 'hooks'))
    open(os.path.join(pk, '.git', 'config'), 'w').write('[remote "x"]\n url = https://u:' + private + '@192.0.2.1/r\n')
    open(os.path.join(pk, '.git', 'hooks', 'DUMMY'), 'w').write(private)
    open(os.path.join(pk, 'App.txt'), 'w').write('contenido')
    pzip = os.path.join(JAIL, 'paquete.zip')
    out = srv.call('delphi_package', {'dir': pk, 'outfile': pzip})
    nombres = []
    if os.path.isfile(pzip):
        with zipfile.ZipFile(pzip) as z:
            nombres = z.namelist()
    check('package de una carpeta con .git: el zip lleva lo demas y nada del .git (WS-024)',
          'App.txt' in nombres and not any('.git' in n.lower().split('/') for n in nombres)
          and mc.es(out, 'SN_WS_FUERA_DEL_PAQUETE_FMT'), (nombres, out[:300]))
    mc.borra(pk); mc.borra(pzip)
    ptr = os.path.join(JAIL, 'ficha')
    os.makedirs(ptr)
    open(os.path.join(ptr,'.git'),'w').write('gitdir: '+META+'\n')
    out = srv.call('delphi_read', {'path':os.path.join(ptr,'.git')})
    check('.git fichero tampoco se lee', mc.es(out, 'SR_GUARD_GIT_METADATA_FMT') and 'delphi_git' in out, out)
    for key, stanza in (
        ('core.askpass', '[core]\n askPass = '+private+'\n'),
        ('merge.dummy.driver', '[merge "dummy"]\n driver = '+private+'\n'),
        ('dummy.unknown', '[dummy]\n unknown = '+private+'\n'),
        ('gc.recentobjectshook', '[gc]\n recentObjectsHook = '+private+'\n'),
        ('remote.origin.vcs', '[remote "origin"]\n vcs = '+private+'\n'),
        ('filter.lfs.process', '[filter "lfs"]\n process = '+private+'\n'),
        ('filter.otro.process', '[filter "otro"]\n process = git-lfs filter-process\n'),
    ):
        open(CFG,'w').write(normal+'\n'+stanza)
        out = call('status')
        check('config niega '+key+' sin enseñar valor', mc.es(out, 'SR_GIT_CONFIG_PROGRAMA_FMT') and key in out.lower()
              and private not in out, out[:350])
    # Claves de repo normales (booleanas/enum, sin programa ni ruta de lectura):
    # status NO debe romper (revisor 1.18.0, M3 -- longpaths, fscache,
    # untrackedCache, pull.rebase; aprobadas por David).
    for key, stanza in (
        ('core.longpaths', '[core]\n longpaths = true\n'),
        ('core.fscache', '[core]\n fscache = true\n'),
        ('core.untrackedcache', '[core]\n untrackedCache = keep\n'),
        ('pull.rebase', '[pull]\n rebase = false\n'),
    ):
        open(CFG,'w').write(normal+'\n'+stanza)
        out = call('status')
        check('config admite '+key+' (repo normal, M3)', out.startswith('exit=0'), out[:300])
    open(CFG,'w').write(normal+'\n[extensions]\n worktreeConfig = true\n')
    wt = os.path.join(META,'config.worktree')
    open(wt,'w').write('[dummy]\n unknown = '+private+'\n')
    out = call('status')
    check('worktree config aplica la misma lista', mc.es(out, 'SR_GIT_CONFIG_PROGRAMA_FMT') and
          'dummy.unknown' in out and private not in out, out)
    os.remove(wt)
    open(CFG,'w').write(normal+'\n[remote "no"]\n url = http://localhost:%d/DUMMY\n'%http.server_port)
    # 1.19.0: el remoto, por su NOMBRE (remote=); --dry-run ya no existe: si la
    # puerta fallara, el push llegaria al 401 propio y hits lo contaria
    for cmd,campos in (('ls-remote',{'remote':'no'}), ('fetch',{'remote':'no'}),
                       ('push',{'remote':'no','ref':'main'}), ('fetch',{}), ('push',{})):
        n = len(hits); out=call(cmd,**campos)
        check('remoto plantado '+cmd+' '+' '.join('%s=%s' % kv for kv in campos.items())+' pasa por hosts',
              mc.es(out,'SR_GIT_REMOTE_HOST_FMT') and len(hits)==n, out[:350])
    open(CFG,'w').write(normal)
    # Las dos decisiones de firma: opciones del agente y ajustes del operador.
    # 1.19.0: sin args la opcion de firma ni se puede escribir: la forma vieja
    # contesta GIT-068 sin llegar a git, y en tag la opcion como nombre no es
    # un nombre (GIT-071). Ni commit ni tag nuevos.
    antes_firma = raw('rev-parse','HEAD').strip()
    for cmd in ('commit','tag'):
        for i,flag in enumerate(('-S','-SDUMMY','--gpg-sign','--gpg-sign=DUMMY','--gpg','--g') +
                                (('-s','-uDUMMY','--local-user=DUMMY','-as','-fs','--si','--sign') if cmd=='tag' else ('-aS','-sS','-nS','-asS','-vsS'))):
            args = '--allow-empty '+flag if cmd=='commit' else flag+' dummy-sign-'+str(i)
            out=call(cmd,args,'DUMMY')
            check(cmd+' args '+flag+': GIT-068, no llega a git', mc.es(out, 'SR_GIT_ARGS_RETIRADO') and
                  not mc.llego_a_git(out), out[:350])
            if cmd=='tag':
                out=call('tag',name=flag,message='DUMMY')
                check('tag name='+flag+': GIT-071, no es un nombre', mc.es(out, 'SR_GIT_NOMBRE_NO_VALE_FMT') and
                      not mc.llego_a_git(out), out[:350])
    check('la firma pedida no hizo nada: HEAD igual y sin tags dummy-sign',
          raw('rev-parse','HEAD').strip()==antes_firma and 'dummy-sign' not in raw('tag'))
    # --signoff (y -s, y --sign en commit, su abreviatura) NO firman: solo ponen
    # "Signed-off-by" y se admitian. 1.19.0: sin args no hay opciones, ni de
    # firma ni de Signed-off-by: la forma vieja contesta GIT-068 y no hace nada.
    for flag in ('--signoff','--sign','-s'):
        out=call('commit','--allow-empty '+flag,'DUMMY signoff')
        check('commit args '+flag+': GIT-068, nada hecho',mc.es(out,'SR_GIT_ARGS_RETIRADO') and
              not mc.llego_a_git(out),out[:300])
    # Control positivo (revisor 1.18.0, A1): una S que es un VALOR no es la
    # firma. 1.19.0: sin args, el valor que queda es el mensaje: "-S" en
    # message va por -F y es el texto del commit, sin firma.
    open(os.path.join(REPO,'firma-valor.txt'),'w').write('DUMMY\n')
    call('add',paths=['firma-valor.txt'])
    out=call('commit',message='-S DUMMY')
    check('commit message="-S DUMMY" (es el texto, no la firma) se hace sin firma',
          out.startswith('exit=0') and raw('log','-1','--format=%s').strip()=='-S DUMMY' and
          'gpgsig' not in raw('cat-file','-p','HEAD'), out[:300])
    open(CFG,'w').write(normal+'\n[commit]\n gpgSign = true\n[tag]\n gpgSign = true\n')
    previous = raw('rev-parse','HEAD').strip()
    # 1.19.0: sin --allow-empty, el commit lleva un cambio
    open(os.path.join(REPO,'sin-firma.txt'),'w').write('DUMMY\n')
    call('add',paths=['sin-firma.txt'])
    out=call('commit',message='DUMMY sin firma')
    check('commit desactiva la firma del operador',out.startswith('exit=0'),out)
    out=call('tag',name='dummy-unsigned',message='DUMMY sin firma')
    check('tag desactiva la firma del operador',out.startswith('exit=0'),out)
    current = raw('rev-parse','HEAD').strip()
    check('el NUEVO commit no lleva gpgsig',current!=previous and 'gpgsig' not in raw('cat-file','-p',current))
    tagged = out.startswith('exit=0')
    check('el NUEVO tag no lleva firma',tagged and 'BEGIN PGP SIGNATURE' not in raw('cat-file','-p','refs/tags/dummy-unsigned'))
    open(CFG,'w').write(normal)
    # 1.19.0: el remoto va por su NOMBRE; una direccion escrita en la llamada
    # no es un remoto del repo (GIT-049) y no sale nada hacia ella
    n = len(hits)
    out=call('ls-remote',remote='http://127.0.0.1:%d/DUMMY'%http.server_port)
    check('ls-remote remote=<URL>: GIT-049, no es un remoto del repo',
          mc.es(out, 'SR_GIT_REMOTO_NO_ESTA_FMT') and len(hits)==n, out[:350])
    # ...y el 401 propio, por un remoto del repo con esa direccion
    open(CFG,'w').write(normal+'\n[remote "dummy"]\n url = http://127.0.0.1:%d/DUMMY\n'%http.server_port)
    start=time.monotonic()
    out=call('ls-remote',remote='dummy')
    elapsed=time.monotonic()-start
    open(CFG,'w').write(normal)
    check('401 propio contesta en menos de 10 segundos', elapsed<10 and
          mc.es(out,'SR_GIT_EXIT_FMT') and bool(hits), '%.3fs %s'%(elapsed,out[:350]))
    events=[json.loads(l) for l in open(TRACE,encoding='utf-8') if l.strip()]
    for name,value in (('GIT_TERMINAL_PROMPT','0'),('GCM_INTERACTIVE','never')):
        seen=[e.get('value') for e in events if e.get('event')=='def_param' and e.get('param')==name]
        check('entorno del hijo '+name+' fijo', bool(seen) and set(seen)=={value}, seen[-8:])
    # Valores LFS EXACTOS, no cualquier programa que empiece por git-lfs.
    for key,value in (('clean','git-lfs clean -- %f'),('smudge','git-lfs smudge -- %f'),
                      ('process','git-lfs filter-process'),('required','true')):
        raw('config','filter.lfs.'+key,value)
    check('control config LFS estándar se admite',call('status').startswith('exit=0'))
    open(os.path.join(REPO,'.gitattributes'),'w').write('DUMMY.bin filter=lfs diff=lfs merge=lfs -text\n')
    open(os.path.join(REPO,'DUMMY.bin'),'wb').write(b'DUMMY LFS\n')
    out=call('add',paths=['.gitattributes','DUMMY.bin'])
    check('control add ejecuta el filtro LFS estandar',out.startswith('exit=0') and
          raw('show',':DUMMY.bin').startswith('version https://git-lfs.github.com/spec/v1'),out)
    # El origen se prepara por el arnes aunque el exe de linea base niegue LFS.
    raw('add','.gitattributes','DUMMY.bin'); raw('commit','-qm','DUMMY LFS')
    origin=os.path.join(JAIL,'normal.git')
    raw('clone','-q','--bare',REPO,origin,cwd=JAIL)
    raw('update-server-info',cwd=origin)
    dest=os.path.join(JAIL,'clone-normal')
    out=call('clone',message='http://127.0.0.1:%d/normal.git'%http.server_port,repo=dest)
    check('control clone normal con LFS conserva dato y puntero (skip-smudge)',
          out.startswith('exit=0') and open(os.path.join(dest,'dato.txt')).read()=='DUMMY\n' and
          open(os.path.join(dest,'DUMMY.bin')).read().startswith('version https://git-lfs.github.com/spec/v1'),out)
finally:
    srv.cierra()
    http.shutdown(); http.server_close()
    if os.path.isdir(ALIAS): os.rmdir(ALIAS)
    mc.borra(BASE)
check('BASE borrada con el exe',not os.path.exists(BASE))
mc.fin('git config cerrado')
