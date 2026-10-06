"""Medida de herencia: runner build/git y lanzador remoto Windows.
Solo inspecciona procesos de la fixture. Un evento propio heredable sirve
de testigo para McpRunJob; el vigia debe conservar el RC real del programa.
"""
import os, sys, time, json, uuid, shutil, threading, subprocess
import ctypes as C, ctypes.wintypes as W
import mcp_cliente as mc
from handles_windows import K, sockets, children, event_in

BASE=mc.carpeta('handles-lanzadores')
sd=os.path.join(BASE,'srv');exe=mc.copia_exe(sd);port=mc.puerto_libre()
with open(os.path.join(sd,'settings.ini'),'w') as f:
    f.write('[Server]\nBindIP=127.0.0.1\nPort=%d\n[Workspace.Probe]\nToken=fixture-handles\nRoots=%s\n'%(port,BASE))
p=None; job=None; direct=None; event=None; child_pid=None
def observes(cli, tool, args, process_name):
    result=[];measured=[]
    t=threading.Thread(target=lambda:result.append(cli.call(tool,args,600)),daemon=True)
    t.start()
    deadline=time.monotonic()+120
    seen=set()
    while t.is_alive() and time.monotonic()<deadline:
        for pid in children(p.pid,process_name):
            if pid in seen:continue
            try:
                measured.append(sockets(pid));seen.add(pid)
            except OSError:pass # el hijo pudo acabar entre ambas lecturas
        time.sleep(.002)
    t.join(600)
    return result[0] if result else 'sin respuesta',measured
try:
    p=mc.lanza_http(exe,port,mc.entorno(),creationflags=subprocess.CREATE_NO_WINDOW)
    cli=mc.Http(port,'fixture-handles',t=600);cli.session('handles-lanzadores')
    mc.check('R1 fixture: se ve SU listener heredable',any(x.get('socket_port')==port for x in sockets(p.pid)['inheritable']))
    project=os.path.join(BASE,'Probe')
    r=cli.call('delphi_create',{'kind':'project-console','name':'Probe','dir':project})
    assert mc.abre(r,'SK_CREATE_CREADO_PROYECTO_FMT'),r
    r,tables=observes(cli,'delphi_build',{'project':os.path.join(project,'Probe.dproj'),'platform':'Win64'},'MSBuild.exe')
    mc.check('R2 build positivo: compilacion correcta y proceso medido',mc.como_json(r).get('success') is True and bool(tables),r[:400])
    mc.check('R3 MSBuild no recibe sockets HTTP',bool(tables) and all(not any(x.get('socket_port')==port for x in t['inheritable']) for t in tables),json.dumps(tables))
    repo=os.path.join(BASE,'git');os.mkdir(repo)
    r=cli.call('delphi_git',{'repo':repo,'command':'init'})
    for i in range(12000):
        with open(os.path.join(repo,'fixture-%05d.txt'%i),'w') as f:f.write('fixture\n')
    tables=[]
    for attempt in range(3):
        r,tables=observes(cli,'delphi_git',{'repo':repo,'command':'status','args':'--untracked-files=all'},'git.exe')
        if tables:break
    mc.check('R4 git positivo: status correcto y proceso medido',not mc.rechazado(r) and 'fixture-' in r and bool(tables),r[:400])
    mc.check('R5 git no recibe sockets HTTP',bool(tables) and all(not any(x.get('socket_port')==port for x in t['inheritable']) for t in tables),json.dumps(tables))

    remote=os.path.join(BASE,'remote');os.mkdir(remote)
    app=os.path.join(remote,'Probe.exe');shutil.copy(sys.executable,app)
    script=os.path.join(remote,'fixture.py')
    with open(script,'w') as f:f.write('import time,sys\nprint("fixture viva",flush=True)\ntime.sleep(3)\nsys.exit(17)\n')
    # El mismo evento atraviesa SOLO el primer lanzamiento, autorizado por lista.
    class SA(C.Structure):
        _fields_=[('length',W.DWORD),('sd',C.c_void_p),('inherit',W.BOOL)]
    K.CreateEventW.argtypes=[C.POINTER(SA),W.BOOL,W.BOOL,W.LPCWSTR];K.CreateEventW.restype=W.HANDLE
    name='McpHandles'+uuid.uuid4().hex;sa=SA(C.sizeof(SA),None,True)
    event=K.CreateEventW(C.byref(sa),True,True,'Local\\'+name)
    if not event:raise C.WinError(C.get_last_error())
    startup=subprocess.STARTUPINFO();startup.lpAttributeList={'handle_list':[event]}
    direct=subprocess.Popen([app,script],startupinfo=startup,close_fds=True,creationflags=subprocess.CREATE_NO_WINDOW)
    mc.check('R6 control positivo: el evento propio llega cuando se pide',event_in(direct.pid,name))
    direct.wait(10)
    origin=os.environ.get('MCP_RUNJOB_EXE',os.path.join(mc.REPO,'src','RunJob','Win64','Release','McpRunJob.exe'))
    launcher=os.path.join(remote,'run-1234.exe');shutil.copy(origin,launcher)
    out=os.path.join(remote,'1234.out');pidfile=os.path.join(remote,'1234.pid')
    with open(os.path.join(remote,'run-1234.job'),'w',encoding='utf-8') as f:f.write('Probe.exe\n1234.out\n'+script+'\n')
    job=subprocess.Popen([launcher],startupinfo=startup,close_fds=True,creationflags=subprocess.CREATE_NO_WINDOW)
    deadline=time.monotonic()+10
    while not os.path.isfile(pidfile) and time.monotonic()<deadline:time.sleep(.01)
    if os.path.isfile(pidfile):
        with open(pidfile) as f:child_pid=int(f.read())
    mc.check('R7 fixture: McpRunJob arranca el programa nativo',child_pid is not None)
    if child_pid:
        mc.check('R8 programa remoto no recibe el evento ajeno',not event_in(child_pid,name))
    job.wait(10)
    deadline=time.monotonic()+15;text=''
    while time.monotonic()<deadline:
        if os.path.isfile(out):
            with open(out,encoding='utf-8-sig',errors='replace') as f:text=f.read()
        if '___RC=' in text:break
        time.sleep(.02)
    mc.check('R9 el vigia espera el programa y conserva su RC=17','___RC=17' in text,text)
finally:
    if direct is not None and direct.poll() is None:direct.kill();direct.wait(10)
    if job is not None and job.poll() is None:job.kill();job.wait(10)
    if child_pid:
        h=K.OpenProcess(1,False,child_pid)
        if h:K.TerminateProcess(h,1);K.CloseHandle(h)
    if event:K.CloseHandle(event)
    if p is not None and p.poll() is None:p.kill();p.wait(10)
    time.sleep(.2);mc.borra(BASE)
mc.fin('handles de los lanzadores')
