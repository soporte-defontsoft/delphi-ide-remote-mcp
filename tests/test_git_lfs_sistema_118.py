# -*- coding: utf-8 -*-
"""LFS con configuracion SYSTEM real: metadatos no juzgan endpoints.
Mutantes: GitMaterializaArbol siempre True; endpoint solo por juez de hosts.
Sin skip-smudge ni GIT_CONFIG_NOSYSTEM. HTTP exclusivamente local.
"""
import atexit,http.server,json,os,subprocess,threading
import mcp_cliente as mc
BASE=mc.carpeta('git-lfs-sistema-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');os.makedirs(JAIL)
GLOBAL=os.path.join(BASE,'empty.config');open(GLOBAL,'w').close()
TRACE=os.path.join(BASE,'trace.json')
env=dict(os.environ,GIT_CONFIG_GLOBAL=GLOBAL,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
env.pop('GIT_CONFIG_NOSYSTEM',None);env.pop('GIT_LFS_SKIP_SMUDGE',None)
def raw(*args,cwd=JAIL):
    p=subprocess.run(['git','-c','commit.gpgsign=false',*args],cwd=cwd,env=env,capture_output=True,text=True,timeout=30)
    if p.returncode:raise RuntimeError(p.stderr)
    return p.stdout
filters=raw('config','--system','--get-regexp',r'^filter\.lfs\.')
mc.check('fixture filtros LFS en SYSTEM real',all('filter.lfs.'+n in filters for n in ('clean','smudge','process','required')))
REMOTE=os.path.join(JAIL,'remote.git');raw('init','-q','--bare','-b','main',REMOTE)
repos=[]
for name,url in (('https','https://github.com/example/DUMMY.git'),('carpeta',REMOTE)):
    repo=os.path.join(JAIL,name);os.makedirs(repo)
    raw('init','-q','-b','main',cwd=repo)
    raw('config','user.name','DUMMY',cwd=repo);raw('config','user.email','dummy@example.invalid',cwd=repo)
    open(os.path.join(repo,'DUMMY.txt'),'w').write('DUMMY\n')
    raw('add','.',cwd=repo);raw('commit','-qm','DUMMY',cwd=repo)
    raw('remote','add','origin',url,cwd=repo);repos.append(repo)
hits=[]
class Local(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        hits.append(self.path);self.send_response(404);self.end_headers()
    def log_message(self,*args):pass
http=http.server.ThreadingHTTPServer(('127.0.0.1',0),Local)
threading.Thread(target=http.serve_forever,daemon=True).start()
server_env=mc.entorno(dict(DELPHI_MCP_ROOTS=JAIL,DELPHI_MCP_GIT_REMOTES='github.com',
    GIT_CONFIG_GLOBAL=GLOBAL,GIT_TRACE2_EVENT=TRACE))
server_env.pop('GIT_CONFIG_NOSYSTEM',None);server_env.pop('GIT_LFS_SKIP_SMUDGE',None)
srv=mc.Stdio(mc.copia_exe(os.path.join(BASE,'srv')),server_env,nombre='lfs-system',t=60)
def call(repo,cmd,args='',message=''):
    return srv.call('delphi_git',dict(repo=repo,command=cmd,args=args,message=message))
try:
    for repo in repos:
        for cmd,args,msg in [('status','',''),('log','',''),('diff','',''),('show','HEAD',''),
                             ('branch','',''),('tag','',''),('stash','list',''),
                             ('config','user.name','DUMMY')]:
            out=call(repo,cmd,args,msg)
            mc.check(os.path.basename(repo)+' '+cmd+' sin endpoint',out.startswith('exit=0'),out[:250])
        open(os.path.join(repo,'DUMMY.txt'),'a').write('DUMMY cambio\n')
        mc.check('add funciona',call(repo,'add','DUMMY.txt').startswith('exit=0'))
        out=call(repo,'commit',message='DUMMY second')
        mc.check(os.path.basename(repo)+' commit sin endpoint',out.startswith('exit=0'),out[:250])
    events=[json.loads(l) for l in open(TRACE,encoding='utf-8') if l.strip()]
    mc.check('se midieron procesos git',any(e.get('event')=='start' for e in events))
    mc.check('ninguna orden de metadatos lanza lfs env',
        not any('lfs' in e.get('argv',[]) and 'env' in e.get('argv',[]) for e in events))
    out=call(repos[1],'switch','main')
    mc.check('endpoint de carpeta usa puerta de carpeta',out.startswith('exit=0'),out[:250])
    url='http://127.0.0.1:%d/DUMMY.git'%http.server_port
    raw('remote','set-url','origin',url,cwd=repos[0])
    for cmd in ('ls-remote','fetch'):
        out=call(repos[0],cmd,'origin')
        mc.check(cmd+' sigue negando host fuera de GitRemotes',mc.rechazado(out),out[:250])
        mc.check(cmd+' no contacta endpoint excluido',not hits,hits)
    raw('remote','set-url','origin','https://github.com/example/DUMMY.git',cwd=repos[0])
    raw('config','lfs.url',url,cwd=repos[0])
    mc.check('status ignora endpoint local que no usa',call(repos[0],'status').startswith('exit=0'))
    out=call(repos[0],'switch','main')
    mc.check('materializar niega endpoint LFS con mensaje propio',
        mc.es(out,'SR_GIT_LFS_ENDPOINT_FMT') and 'origin' in out and 'GitRemotes' in out,out[:350])
    mc.check('endpoint rechazado no muestra valor',url not in out and '127.0.0.1' not in out,out[:350])
    mc.check('endpoint rechazado no recibe peticiones',not hits,hits)
finally:
    srv.cierra();http.shutdown();http.server_close();mc.borra(BASE)
mc.check('BASE borrada con exe',not os.path.exists(BASE))
mc.fin('git LFS sistema 118')
