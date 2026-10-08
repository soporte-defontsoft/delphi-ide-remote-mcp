# -*- coding: utf-8 -*-
"""Repositorio entero: move/papelera/restore; metadatos siguen cerrados.
Incluye RepoOf interno y prioridad de proyecto al copiar una referencia.
Mutantes: ProtegidoDenegado sin permiso de arbol; omitir juez de enlaces;
RepoOf sin permiso git; CopiaDenegada metadatos antes del proyecto.
"""
import atexit,hashlib,json,os,subprocess
import mcp_cliente as mc
BASE=mc.carpeta('git-repo-entero-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');REF=os.path.join(BASE,'reference');OUT=os.path.join(BASE,'DUMMY-outside')
for d in (JAIL,REF,OUT):os.makedirs(d)
def snap(root):
    return {os.path.relpath(os.path.join(d,n),root):hashlib.sha256(open(os.path.join(d,n),'rb').read()).hexdigest()
            for d,_,ns in os.walk(root) for n in ns}
def repo(path):
    os.makedirs(path)
    subprocess.run(['git','init','-q','-b','DUMMY-branch',path],check=True,capture_output=True)
    open(os.path.join(path,'DUMMY.txt'),'w').write('DUMMY\n')
    open(os.path.join(path,'DUMMY.dproj'),'w').write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"/>')
    return path
R=repo(os.path.join(JAIL,'repo'));REFERENCE=repo(os.path.join(REF,'repo'))
src=snap(R);ref_before=snap(REFERENCE)
outside=os.path.join(OUT,'metadata');os.makedirs(outside)
open(os.path.join(outside,'DUMMY.txt'),'w').write('DUMMY no tocar')
outside_before=snap(OUT)
srv=mc.Stdio(mc.copia_exe(os.path.join(BASE,'srv')),mc.entorno({
    'DELPHI_MCP_ROOTS':JAIL,'DELPHI_MCP_READONLY_ROOTS':REF}),nombre='whole-repo',t=60)
try:
    out=srv.call('delphi_projects',{'root':JAIL})
    repos=mc.como_json(out).get('repos',[])
    mc.check('lector interno HEAD conserva repo y rama',
        len(repos)==1 and repos[0].get('branch')=='DUMMY-branch',out[:400])
    for tool,params in [('delphi_read',{'path':os.path.join(R,'.git','HEAD')}),
                        ('delphi_textedit',{'path':os.path.join(R,'.git','HEAD'),'old':'ref: refs/heads/DUMMY-branch','new':'DUMMY'})]:
        out=srv.call(tool,params)
        mc.check(tool+' no obtiene permiso del lector interno','[GUARD-033 DENIED]' in out,out[:300])
        mc.check(tool+' HEAD intacto',snap(R)==src)
    dest=os.path.join(JAIL,'moved')
    out=srv.call('delphi_move',{'path':R,'dest':dest})
    mc.check('move repo entero permitido','[MOVE-013]' in out and os.path.isdir(dest),out[:350])
    mc.check('move viaja byte a byte',os.path.isdir(dest) and snap(dest)==src)
    actual=dest if os.path.isdir(dest) else R
    out=srv.call('delphi_delete',{'path':actual})
    mc.check('repo entero va a papelera','[FILE-021]' in out and not os.path.exists(actual),out[:350])
    copies=mc.copias(JAIL,os.path.basename(actual),cajon='CAJON_BORRADOS')
    mc.check('papelera contiene el repo intacto',len(copies)==1 and snap(copies[0])==src,copies)
    if len(copies)==1:
        out=srv.call('delphi_move',{'path':copies[0],'dest':actual})
        mc.check('repo se devuelve desde papelera','[MOVE-013]' in out and os.path.isdir(actual),out[:350])
        mc.check('repo restaurado byte a byte',os.path.isdir(actual) and snap(actual)==src)
    else:mc.check('repo se devuelve desde papelera',False)
    # Arbol sin proyecto: copiar sus metadatos se sigue negando.
    plain=os.path.join(JAIL,'plain');os.makedirs(os.path.join(plain,'.git'))
    open(os.path.join(plain,'.git','DUMMY'),'w').write('DUMMY')
    before=snap(plain);copied=os.path.join(JAIL,'copy')
    out=srv.call('delphi_move',{'path':plain,'dest':copied,'copy':True})
    mc.check('copy del arbol con .git sigue negado','[GUARD-033 DENIED]' in out and not os.path.exists(copied),out[:300])
    mc.check('copy no altera fuente',snap(plain)==before)
    for nested in (False,True):
        tree=os.path.join(JAIL,'linked-'+str(nested));os.makedirs(tree)
        if nested:
            os.makedirs(os.path.join(tree,'.git'));link=os.path.join(tree,'.git','DUMMY')
        else:link=os.path.join(tree,'.git')
        mc.check('fixture enlace metadata exterior '+str(nested),mc.junction(link,outside))
        dest_link=tree+'-moved'
        out=srv.call('delphi_move',{'path':tree,'dest':dest_link})
        mc.check('move niega enlace exterior '+str(nested),
            '[GUARD-033 DENIED]' in out and not os.path.exists(dest_link),out[:300])
        out=srv.call('delphi_delete',{'path':tree if os.path.isdir(tree) else dest_link})
        mc.check('delete niega enlace exterior '+str(nested),'[GUARD-033 DENIED]' in out,out[:300])
        mc.check('destino exterior intacto '+str(nested),snap(OUT)==outside_before)
    out=srv.call('delphi_move',{'path':REFERENCE,'dest':os.path.join(JAIL,'reference-copy'),'copy':True})
    mc.check('copy proyecto de referencia explica nunca en dos sitios',
        mc.es(out,'SR_MOVE_COPY_PROJECT_FMT') and not os.path.exists(os.path.join(JAIL,'reference-copy')),out[:350])
    mc.check('referencia intacta',snap(REFERENCE)==ref_before)
finally:
    srv.cierra();mc.borra(BASE)
mc.check('BASE borrada con exe',not os.path.exists(BASE))
mc.fin('git repo entero 118')
