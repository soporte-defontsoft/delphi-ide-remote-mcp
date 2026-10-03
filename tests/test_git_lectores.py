"""Contrato de git: los args no pueden pedir lectores de ficheros externos.
Todos los ficheros testigo pertenecen al arnes, nunca son datos del usuario.
"""
import os
import mcp_cliente as mc
BASE=mc.carpeta('git-lectores')
REPO=os.path.join(BASE,'repo')
FUERA=os.path.join(BASE,'testigos')
os.makedirs(REPO);os.makedirs(FUERA)
EXE=mc.copia_exe(os.path.join(BASE,'srv'))
srv=mc.Stdio(EXE,mc.entorno({'DELPHI_MCP_ROOTS':REPO}),nombre='lect')
def git(command,args='',message=''):
    return srv.call('delphi_git',{'repo':REPO,'command':command,'args':args,'message':message})
try:
    mc.check('fixture: init', 'exit=0' in git('init'))
    git('config','user.name','Fixture')
    git('config','user.email','fixture@example.com')
    with open(os.path.join(REPO,'a.txt'),'w') as f:f.write('fixture')
    git('add','.')
    mc.check('fixture: commit','exit=0' in git('commit',message='fixture'))
    testigo=os.path.join(FUERA,'mensaje.txt')
    with open(testigo,'w') as f:f.write('CONTRACTO_TESTIGO_EXTERNO')
    casos=(
        ('add', '--pathspec-from-file="%s"' % testigo, ''),
        ('add', '--pathspec-from-fi="%s"' % testigo, ''),
        ('tag', '--fil="%s" fixture-file-abbrev' % testigo, ''),
        ('diff', '-O"%s"' % testigo, ''),
        ('tag', '-F"%s" fixture-file-short' % testigo, ''),
        ('tag', '--file="%s" fixture-file-long' % testigo, ''),
        ('commit', '--file="%s" --allow-empty' % testigo, 'fixture'),
    )
    for cmd,args,msg in casos:
        r=git(cmd,args,msg)
        mc.check(cmd+' '+args.split('=')[0]+': la puerta niega el lector',
                 mc.rechazado(r) and not mc.llego_a_git(r),r[:500])

finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('git lectores de ficheros')
