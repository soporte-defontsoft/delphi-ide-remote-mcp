# -*- coding: utf-8 -*-
"""LFS completo: objeto real, .lfsconfig, host unico y checkout en dos fases.
Sin skip-smudge, sin credenciales, endpoints exclusivamente propios.
LFS_SMUDGE_ONLY=1 mide el smudge por fichero: retirar la fijacion del endpoint
debe poner rojo el switch. Con filter-process ese caso es una GUARDA.
Otros mutantes: DireccionLfsAdmitida sin juez; clone sin --no-checkout.
Claude ejecuta las dos variantes; run_all usa filter-process.
"""
import atexit,hashlib,http.server,json,os,subprocess,threading
import mcp_cliente as mc
BASE=mc.carpeta('git-lfs-118');atexit.register(mc.borra,BASE);JAIL=os.path.join(BASE,'jail');os.makedirs(JAIL)
EMPTY=os.path.join(BASE,'empty.config');open(EMPTY,'w').close()
env=dict(os.environ,GIT_CONFIG_GLOBAL=EMPTY,GIT_CONFIG_NOSYSTEM='1',
  GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
env.pop('GIT_LFS_SKIP_SMUDGE',None)
data=(b'DUMMY LFS real\n'*4096);oid=hashlib.sha256(data).hexdigest()
data2=(b'DUMMY LFS future\n'*4096);oid2=hashlib.sha256(data2).hexdigest()
objects_by_oid={oid:data,oid2:data2}
hits=[]
class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self,*a,**kw):super().__init__(*a,directory=JAIL,**kw)
    def do_POST(self):
        request=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
        hits.append(('batch',self.headers.get('Host'),self.path))
        objects=[dict(oid=x['oid'],size=len(objects_by_oid[x['oid']]),actions=dict(download=dict(href=base+'/lfs/object/'+x['oid'])))
                 for x in request['objects']]
        body=json.dumps(dict(transfer='basic',objects=objects)).encode()
        self.send_response(200);self.send_header('Content-Type','application/vnd.git-lfs+json')
        self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def do_GET(self):
        if self.path.startswith('/lfs/object/'):
            hits.append(('object',self.headers.get('Host'),self.path))
            body=objects_by_oid[self.path.rsplit('/',1)[1]]
            self.send_response(200);self.send_header('Content-Length',str(len(body)))
            self.end_headers();self.wfile.write(body)
        else:super().do_GET()
    def log_message(self,*args):pass
http=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=http.serve_forever,daemon=True).start()
base='http://127.0.0.1:%d'%http.server_port
def raw(*args,cwd):
    p=subprocess.run(['git','-c','user.name=DUMMY','-c','user.email=dummy@example.invalid',
        '-c','commit.gpgsign=false',*args],cwd=cwd,env=env,capture_output=True,text=True,timeout=30)
    if p.returncode:raise RuntimeError(p.stderr)
    return p.stdout
for name,host in [('ok','127.0.0.1'),('outside-host','localhost')]:
    r=os.path.join(JAIL,name);os.makedirs(r);raw('init','-q','-b','main',cwd=r)
    open(os.path.join(r,'.gitattributes'),'w').write('DUMMY.bin filter=lfs diff=lfs merge=lfs -text\n')
    open(os.path.join(r,'DUMMY.bin'),'w',newline='\n').write('version https://git-lfs.github.com/spec/v1\noid sha256:'+oid+'\nsize '+str(len(data))+'\n')
    open(os.path.join(r,'.lfsconfig'),'w').write('[lfs]\n url = http://'+host+':'+str(http.server_port)+'/lfs\n')
    raw('add','.',cwd=r);raw('commit','-qm','DUMMY',cwd=r)
    if name=='ok':
        raw('switch','-q','-c','future',cwd=r)
        open(os.path.join(r,'.lfsconfig'),'w').write('[lfs]\n url = http://localhost:'+str(http.server_port)+'/lfs\n')
        open(os.path.join(r,'DUMMY.bin'),'w',newline='\n').write('version https://git-lfs.github.com/spec/v1\noid sha256:'+oid2+'\nsize '+str(len(data2))+'\n')
        raw('add','.',cwd=r);raw('commit','-qm','DUMMY future',cwd=r);raw('switch','-q','main',cwd=r)
    bare=os.path.join(JAIL,name+'.git');raw('clone','-q','--bare',r,bare,cwd=JAIL);raw('update-server-info',cwd=bare)
GLOBAL=os.path.join(BASE,'lfs.config')
open(GLOBAL,'w').write('[filter "lfs"]\n clean = git-lfs clean -- %f\n smudge = git-lfs smudge -- %f\n'+('' if os.environ.get('LFS_SMUDGE_ONLY')=='1' else ' process = git-lfs filter-process\n')+' required = true\n')
exe=mc.copia_exe(os.path.join(BASE,'srv'))
server_env=mc.entorno(dict(DELPHI_MCP_ROOTS=JAIL,DELPHI_MCP_GIT_REMOTES='127.0.0.1',
   GIT_CONFIG_GLOBAL=GLOBAL,GIT_CONFIG_NOSYSTEM='1'))
server_env.pop('GIT_LFS_SKIP_SMUDGE',None)
srv=mc.Stdio(exe,server_env,nombre='lfs-facts',t=90)
try:
    for name in ['ok','outside-host']:
        dest=os.path.join(JAIL,'clone-'+name);hits.clear()
        out=srv.call('delphi_git',dict(repo=dest,command='clone',message=base+'/'+name+'.git'))
        f=os.path.join(dest,'DUMMY.bin')
        got=hashlib.sha256(open(f,'rb').read()).hexdigest() if os.path.isfile(f) else ''
        if name=='ok':
            mc.check('clone LFS completo funciona',out.startswith('exit=0'),out)
            mc.check('objeto descargado con SHA-256 propio',got==oid)
            mc.check('control batch y objeto reales',any(h[0]=='batch' for h in hits) and any(h[0]=='object' for h in hits),hits)
            mc.check('hosts del control permitidos',all(h[1].startswith('127.0.0.1:') for h in hits),hits)
            mc.check('clone queda limpio',srv.call('delphi_git',dict(repo=dest,command='status')).startswith('exit=0'))
        else:
            mc.check('LFS exterior se niega por su clave','[GIT-051 DENIED]' in out and 'lfs.url' in out,out)
            mc.check('rechazo nunca muestra valor','localhost' not in out and '/lfs' not in out,out)
            mc.check('rechazo antes de batch y objeto',not hits and got!=oid,hits)
    hits.clear();dest=os.path.join(JAIL,'clone-ok')
    out=srv.call('delphi_git',dict(repo=dest,command='switch',args='future'))
    f=os.path.join(dest,'DUMMY.bin')
    got=hashlib.sha256(open(f,'rb').read()).hexdigest() if os.path.isfile(f) else ''
    mc.check('switch descarga segundo objeto real',out.startswith('exit=0') and got==oid2,out)
    mc.check('switch mantiene endpoint juzgado',bool(hits) and all(h[1].startswith('127.0.0.1:') for h in hits),hits)
    # El nuevo fichero no puede decidir el endpoint de la siguiente llamada.
    next_out=srv.call('delphi_git',dict(repo=dest,command='status'))
    mc.check('nuevo .lfsconfig se juzga de nuevo','[GIT-051 DENIED]' in next_out and 'lfs.url' in next_out,next_out)
    # Precedencia real: trabajo > indice > HEAD, sin descargar objetos.
    lfs_path=os.path.join(dest,'.lfsconfig')
    open(lfs_path,'w').write('[lfs]\n url = '+base+'/lfs\n')
    mc.check('fichero permitido prevalece sobre HEAD excluido',
             srv.call('delphi_git',dict(repo=dest,command='status')).startswith('exit=0'))
    raw('add','.lfsconfig',cwd=dest);os.remove(lfs_path)
    mc.check('indice permitido prevalece sobre HEAD excluido',
             srv.call('delphi_git',dict(repo=dest,command='status')).startswith('exit=0'))
    raw('rm','--cached','-q','.lfsconfig',cwd=dest)
    out=srv.call('delphi_git',dict(repo=dest,command='status'))
    mc.check('sin fichero ni indice se juzga HEAD','[GIT-051 DENIED]' in out and 'lfs.url' in out,out)
    repo=os.path.join(JAIL,'ok')
    raw('config','lfs.url','http://localhost:%d/lfs'%http.server_port,cwd=repo)
    out=srv.call('delphi_git',dict(repo=repo,command='status'))
    mc.check('local lfs.url usa la misma puerta','[GIT-051 DENIED]' in out and 'lfs.url' in out,out)
    raw('config','lfs.url',base+'/lfs',cwd=repo)
    mc.check('control local lfs.url permitido',srv.call('delphi_git',dict(repo=repo,command='status')).startswith('exit=0'))
    raw('config','remote.origin.lfsurl','http://localhost:%d/lfs'%http.server_port,cwd=repo)
    out=srv.call('delphi_git',dict(repo=repo,command='status'))
    mc.check('remote.*.lfsurl tambien usa hosts','[GIT-051 DENIED]' in out and 'remote.origin.lfsurl' in out,out)
    raw('config','--unset','remote.origin.lfsurl',cwd=repo)
    raw('config','extensions.worktreeConfig','true',cwd=repo)
    open(os.path.join(repo,'.git','config.worktree'),'w').write('[lfs]\n url = http://localhost:%d/lfs\n'%http.server_port)
    out=srv.call('delphi_git',dict(repo=repo,command='status'))
    mc.check('worktree lfs.url tambien usa hosts','[GIT-051 DENIED]' in out and 'lfs.url' in out,out)
    mc.check('servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
finally:
    srv.cierra();http.shutdown();http.server_close();mc.borra(BASE)
mc.check('BASE borrada con el exe',not os.path.exists(BASE))
mc.fin('git LFS 118')
