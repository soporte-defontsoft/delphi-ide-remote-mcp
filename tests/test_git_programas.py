"""Contrato: git no ejecuta programas declarados por un repo no confiable.
Los programas testigo solo escriben una marca en otra carpeta del arnes.
Desde la 1.19.0 delphi_git no tiene args: los remotos van por su NOMBRE (el
arnes los declara en la config del repo) y el clone con -c de la llamada ni se
puede escribir (GIT-068, el clone no se hace).
"""
import os, http.server, threading, subprocess
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
def git(cmd,args=None,message='',**campos):
    # 1.19.0: sin args; solo viaja cuando se pasa (para ver que se rechaza)
    llamada=dict({'repo':REPO,'command':cmd,'message':message},**campos)
    if args is not None:llamada['args']=args
    return srv.call('delphi_git',llamada)
# la clave que planta cada caso, como la nombra la negativa (en minusculas)
CLAVES={'fsmonitor':'core.fsmonitor','filter':'filter.fixture.clean','filter-importado':'include.path',
        'diff-externo':'diff.external','diff-driver':'diff.fixture.command','textconv':'diff.fixture.textconv',
        'firma':'gpg.program','ssh':'core.sshcommand','credencial':'credential.helper',
        'gitproxy':'core.gitproxy','uploadpack':'remote.fixture.uploadpack','receivepack':'remote.fixture.receivepack'}
# git a pelo para el control positivo: sin la config global ni la del sistema
GIT_A_PELO=dict(os.environ,GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull,GIT_TERMINAL_PROMPT='0')
def script(path,marker,extra=''):
    with open(path,'w',encoding='utf-8',newline='\n') as f:
        f.write("#!/bin/sh\nprintf 'fixture\\n' > '"+marker.replace('\\','/')+"'\n"+extra)
try:
    mc.check('fixture: init','exit=0' in git('init'))
    git('config',name='user.name',message='Fixture');git('config',name='user.email',message='fixture@example.com')
    config=os.path.join(REPO,'.git','config')
    with open(config,encoding='utf-8') as f:normal=f.read()
    archivo=os.path.join(REPO,'a.txt')
    with open(archivo,'w') as f:f.write('fixture\n')
    git('add',paths=['a.txt'])
    mc.check('fixture: commit ordinario','exit=0' in git('commit',message='fixture'))
    # 1.19.0: push envia UN nombre de rama de aqui (la del arnes)
    RAMA=subprocess.run(['git','-C',REPO,'branch','--show-current'],capture_output=True,text=True).stdout.strip()
    # 1.19.0: el remoto va por su NOMBRE; el de ssh, http y git:// se declara
    # en la config del repo, con el programa del caso
    remotos={'ssh':'ssh://fixture@127.0.0.1:9/fixture',
             'credencial':'http://127.0.0.1:'+str(http.server_port)+'/fixture',
             'gitproxy':'git://127.0.0.1:9/fixture'}
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
            if case in remotos:f.write('\n[remote "fixture"]\nurl = '+remotos[case]+'\n')
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
            git('add',paths=['a.txt']);r=git('commit',message='fixture-hook')
        elif case.startswith('filter'):r=git('add',paths=['a.txt'])
        elif case in ('diff-externo','diff-driver','textconv'):r=git('diff')
        elif case in remotos:r=git('fetch',remote='fixture')
        elif case in ('uploadpack','receivepack'):
            remote=os.path.join(REPO,'fixture-remoto');os.makedirs(remote,exist_ok=True)
            # 1.19.0: init no tiene opciones (ni --bare): un repo normal sirve de remoto
            srv.call('delphi_git',{'repo':remote,'command':'init'})
            r=git('fetch',remote='fixture') if case=='uploadpack' else git('push',remote='fixture',ref=RAMA)
        elif case.startswith('clone-config'):
            flag={'clone-config':'-nc','clone-config-grupo':'-vqnc','clone-config-prefijo':'--conf'}[case]
            r=srv.call('delphi_git',{'repo':os.path.join(REPO,case),'command':'clone','args':flag+' core.sshCommand='+program.replace('\\','/'),'message':'ssh://fixture@127.0.0.1:9/fixture'})
            # 1.19.0: el -c de la llamada ni se puede escribir: GIT-068 y el clone no se hace
            mc.check(case+': args GIT-068, el clone no se hace','GIT-068' in r and not mc.llego_a_git(r)
                     and not os.path.exists(os.path.join(REPO,case)),r[:400])
        else:r=git('status')
        mc.check(case+': el programa del repo no se activa',not os.path.exists(marker),r[:400])
        # (revisor de baterias, 18-oct-2026) la ausencia del testigo pasaba
        # aunque git ni corriera: cada caso dice POR QUE no se activo. La
        # clave del repo, negada por su nombre (GIT-051) antes de lanzar git...
        if case in CLAVES:
            mc.check(case+': negado por su clave (%s)'%CLAVES[case],
                     mc.es(r,'SR_GIT_CONFIG_PROGRAMA_FMT') and '"'+CLAVES[case]+'"' in r.lower(),r[:400])
        # ...y el hook, con git corriendo: el commit se hace sin el, y el
        # mismo hook a pelo SI corre (si no, la ausencia no mediria nada)
        if case=='hook':
            mc.check('hook: git corre y el commit se hace',mc.llego_a_git(r) and r.startswith('exit=0'),r[:400])
            with open(archivo,'a') as f:f.write('a pelo\n')
            subprocess.run(['git','-C',REPO,'add','a.txt'],env=GIT_A_PELO,capture_output=True,timeout=60)
            subprocess.run(['git','-C',REPO,'commit','-m','a pelo'],env=GIT_A_PELO,capture_output=True,timeout=60)
            mc.check('hook: control positivo, el mismo hook a pelo se activa',os.path.exists(marker),marker)
            if os.path.exists(marker):os.remove(marker)
        if os.path.isfile(program):os.remove(program)
        attrs=os.path.join(REPO,'.gitattributes')
        if os.path.isfile(attrs):os.remove(attrs)
    with open(config,'w',encoding='utf-8') as f:f.write(normal)
    mc.check('control: status ordinario sigue funcionando','exit=0' in git('status'))
    with open(config,'w',encoding='utf-8') as f:f.write(normal+'\n[extensions]\nworktreeConfig = true\n')
    mc.check('worktree: extension activa sin fichero opcional','exit=0' in git('status'))
    wtconfig=os.path.join(REPO,'.git','config.worktree')
    with open(wtconfig,'w',encoding='utf-8') as f:f.write('[fixture]\nboolean\n')
    r=git('status')
    mc.check('worktree: clave desconocida sin valor se niega','[GIT-051 DENIED]' in r and 'fixture.boolean' in r,r)
    marker=os.path.join(FUERA,'filter-worktree.txt')
    program=os.path.join(REPO,'.git','hooks','fixture-worktree')
    script(program,marker,'cat\n')
    with open(wtconfig,'w',encoding='utf-8') as f:f.write('[filter "fixture"]\nclean = "'+program.replace('\\','/')+'"\n')
    with open(os.path.join(REPO,'.gitattributes'),'w') as f:f.write('*.txt filter=fixture\n')
    with open(archivo,'a') as f:f.write('worktree\n')
    r=git('add',paths=['a.txt'])
    mc.check('worktree: el filtro local no se activa',not os.path.exists(marker) and '[GIT-051 DENIED]' in r,r[:400])
finally:
    http.shutdown();http.server_close();srv.cierra();mc.borra(BASE)
mc.fin('git programas del repositorio')
