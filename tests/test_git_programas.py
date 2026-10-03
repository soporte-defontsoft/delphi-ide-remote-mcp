"""Contrato: git no ejecuta programas declarados por un repo no confiable.
Los programas testigo solo escriben una marca en otra carpeta del arnes.
"""
import os, http.server, threading
import mcp_cliente as mc
BASE=mc.carpeta('git-programas')
REPO=os.path.join(BASE,'repo');FUERA=os.path.join(BASE,'testigos')
os.makedirs(REPO);os.makedirs(FUERA)
EXE=mc.copia_exe(os.path.join(BASE,'srv'))
srv=mc.Stdio(EXE,mc.entorno({'DELPHI_MCP_ROOTS':REPO,'DELPHI_MCP_GIT_REMOTES':'127.0.0.1','GIT_TERMINAL_PROMPT':'0'}),nombre='programas')
# Endpoint propio: siempre desafia con 401 y nunca recibe datos de usuario.
class Desafio(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401);self.send_header('WWW-Authenticate','Basic realm="fixture"');self.end_headers()
    def log_message(self,*args):pass
http=http.server.ThreadingHTTPServer(('127.0.0.1',0),Desafio)
threading.Thread(target=http.serve_forever,daemon=True).start()
def git(cmd,args='',message=''):
    return srv.call('delphi_git',{'repo':REPO,'command':cmd,'args':args,'message':message})
def script(path,marker,extra=''):
    with open(path,'w',encoding='utf-8',newline='\n') as f:
        f.write("#!/bin/sh\nprintf 'fixture\\n' > '"+marker.replace('\\','/')+"'\n"+extra)
try:
    mc.check('fixture: init','exit=0' in git('init'))
    git('config','user.name','Fixture');git('config','user.email','fixture@example.com')
    config=os.path.join(REPO,'.git','config')
    with open(config,encoding='utf-8') as f:normal=f.read()
    archivo=os.path.join(REPO,'a.txt')
    with open(archivo,'w') as f:f.write('fixture\n')
    git('add','a.txt')
    mc.check('fixture: commit ordinario','exit=0' in git('commit',message='fixture'))
    for case in ('fsmonitor','hook','filter','filter-importado','diff-externo','diff-driver','textconv','firma','ssh','credencial','gitproxy','uploadpack','receivepack','clone-config','clone-config-grupo','clone-config-prefijo'):
        marker=os.path.join(FUERA,case+'.txt')
        program=os.path.join(REPO,'.git','hooks','pre-commit' if case=='hook' else 'fixture-'+case)
        script(program,marker,'cat\n' if case.startswith('filter') else 'cat "$1"\n' if case=='textconv' else 'printf "username=fixture\\npassword=fixture-only\\n"\n' if case=='credencial' else '')
        with open(config,'w',encoding='utf-8') as f:
            f.write(normal)
            if case=='fsmonitor':f.write('\n[core]\n\tfsmonitor = "'+program.replace('\\','/')+'"\n')
            if case=='filter':f.write('\n[filter "fixture"]\n\tclean = "'+program.replace('\\','/')+'"\n')
            if case=='diff-externo':f.write('\n[diff]\nexternal = "'+program.replace('\\','/')+'"\n')
            if case in ('diff-driver','textconv'):f.write('\n[diff "fixture"]\n'+('command' if case=='diff-driver' else 'textconv')+' = "'+program.replace('\\','/')+'"\n')
            if case=='firma':f.write('\n[gpg]\nprogram = "'+program.replace('\\','/')+'"\n[commit]\ngpgSign = true\n')
            if case=='ssh':f.write('\n[core]\nsshCommand = "'+program.replace('\\','/')+'"\n')
            if case=='gitproxy':f.write('\n[core]\ngitProxy = "'+program.replace('\\','/')+'"\n')
            if case in ('uploadpack','receivepack'):f.write('\n[remote "fixture"]\nurl = "'+os.path.join(REPO,'fixture-remoto').replace('\\','/')+'"\n'+case+' = "'+program.replace('\\','/')+'"\n')
            # El valor vacio borra los helpers heredados; solo queda el testigo.
            if case=='credencial':f.write('\n[credential]\nhelper = \nhelper = "'+program.replace('\\','/')+'"\n')
            if case=='filter-importado':
                included=os.path.join(REPO,'.git','fixture.cfg')
                with open(included,'w') as inc:inc.write('[filter "fixture"]\n\tclean = "'+program.replace('\\','/')+'"\n')
                f.write('\n[include]\n\tpath = fixture.cfg\n')
        if case.startswith('filter'):
            with open(os.path.join(REPO,'.gitattributes'),'w') as f:f.write('*.txt filter=fixture\n')
        if case in ('diff-driver','textconv'):
            with open(os.path.join(REPO,'.gitattributes'),'w') as f:f.write('*.txt diff=fixture\n')
        with open(archivo,'a') as f:f.write(case+'\n')
        if case in ('hook','firma'):
            git('add','a.txt');r=git('commit',message='fixture-hook')
        elif case.startswith('filter'):r=git('add','a.txt')
        elif case in ('diff-externo','diff-driver','textconv'):r=git('diff')
        elif case=='ssh':r=git('fetch','ssh://fixture@127.0.0.1:9/fixture')
        elif case=='credencial':r=git('fetch','http://127.0.0.1:'+str(http.server_port)+'/fixture')
        elif case=='gitproxy':r=git('fetch','git://127.0.0.1:9/fixture')
        elif case in ('uploadpack','receivepack'):
            remote=os.path.join(REPO,'fixture-remoto');os.makedirs(remote,exist_ok=True)
            srv.call('delphi_git',{'repo':remote,'command':'init','args':'--bare'})
            r=git('fetch','fixture') if case=='uploadpack' else git('push','fixture HEAD:refs/heads/fixture')
        elif case.startswith('clone-config'):
            flag={'clone-config':'-nc','clone-config-grupo':'-vqnc','clone-config-prefijo':'--conf'}[case]
            r=srv.call('delphi_git',{'repo':os.path.join(REPO,case),'command':'clone','args':flag+' core.sshCommand='+program.replace('\\','/'),'message':'ssh://fixture@127.0.0.1:9/fixture'})
        else:r=git('status')
        mc.check(case+': el programa del repo no se activa',not os.path.exists(marker),r[:400])
        if os.path.isfile(program):os.remove(program)
        attrs=os.path.join(REPO,'.gitattributes')
        if os.path.isfile(attrs):os.remove(attrs)
    with open(config,'w',encoding='utf-8') as f:f.write(normal)
    mc.check('control: status ordinario sigue funcionando','exit=0' in git('status'))
    with open(config,'w',encoding='utf-8') as f:f.write(normal+'\n[extensions]\nworktreeConfig = true\n')
    mc.check('worktree: extension activa sin fichero opcional','exit=0' in git('status'))
    wtconfig=os.path.join(REPO,'.git','config.worktree')
    with open(wtconfig,'w',encoding='utf-8') as f:f.write('[fixture]\nboolean\n')
    mc.check('worktree: fichero con booleano sin valor','exit=0' in git('status'))
    marker=os.path.join(FUERA,'filter-worktree.txt')
    program=os.path.join(REPO,'.git','hooks','fixture-worktree')
    script(program,marker,'cat\n')
    with open(wtconfig,'w',encoding='utf-8') as f:f.write('[filter "fixture"]\nclean = "'+program.replace('\\','/')+'"\n')
    with open(os.path.join(REPO,'.gitattributes'),'w') as f:f.write('*.txt filter=fixture\n')
    with open(archivo,'a') as f:f.write('worktree\n')
    r=git('add','a.txt')
    mc.check('worktree: el filtro local no se activa',not os.path.exists(marker) and '[GIT-051 DENIED]' in r,r[:400])
finally:
    http.shutdown();http.server_close();srv.cierra();mc.borra(BASE)
mc.fin('git programas del repositorio')
