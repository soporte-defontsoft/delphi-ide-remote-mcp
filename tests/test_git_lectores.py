"""Contrato de git: la llamada no puede pedir lectores de ficheros externos.
Desde la 1.19.0 delphi_git no tiene args: la forma vieja (--pathspec-from-file,
-O, -F, --file en args) contesta GIT-068 sin llegar a git, y en los campos
tipados la opcion ni se puede escribir (un nombre con '-' delante: GIT-071;
una ref que es una opcion: GIT-070).
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
def git(command,args=None,message='',**campos):
    # 1.19.0: args solo viaja cuando se pasa (para ver que se rechaza)
    llamada=dict({'repo':REPO,'command':command,'message':message},**campos)
    if args is not None:
        llamada['args']=args
    return srv.call('delphi_git',llamada)
try:
    mc.check('fixture: init', 'exit=0' in git('init'))
    git('config',name='user.name',message='Fixture')
    git('config',name='user.email',message='fixture@example.com')
    with open(os.path.join(REPO,'a.txt'),'w') as f:f.write('fixture')
    git('add',paths=['.'])
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
    # 1.19.0: sin args; la forma vieja se rechaza entera (GIT-068) y no llega a git
    for cmd,args,msg in casos:
        r=git(cmd,args,msg)
        mc.check(cmd+' '+args.split('=')[0]+': args GIT-068, la puerta niega el lector',
                 'GIT-068' in r and mc.rechazado(r) and not mc.llego_a_git(r),r[:500])
    # 1.19.0: en los campos tipados la opcion ni se puede escribir
    r=git('tag',name='-F'+testigo)
    mc.check('tag name=-F<fichero>: GIT-071, no es un nombre',
             'GIT-071' in r and not mc.llego_a_git(r),r[:500])
    r=git('diff',ref='-O'+testigo)
    mc.check('diff ref=-O<fichero>: GIT-070, no es una revision',
             'GIT-070' in r and not mc.llego_a_git(r),r[:500])

finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('git lectores de ficheros')
