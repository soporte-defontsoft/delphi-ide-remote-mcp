# -*- coding: utf-8 -*-
"""MANUAL: RENDER_REACH_HELPER = copia VCL con URenderReachDummy y vigia interno apagado.
El producto no enlaza esa unidad. Mide el limite REAL exterior de 75 segundos.
Mutante: omitir AssignProcessToJobObject en la rama sin AppContainer de RunCore.
El arnes limpia solo sus PID verificados, tambien con el mutante.
"""
import atexit,ctypes,json,os,shutil,threading,time
import mcp_cliente as mc
HELPER=os.environ.get('RENDER_REACH_HELPER','')
if not HELPER:
    mc.fin('render hijos 118',sin_checks='manual: falta RENDER_REACH_HELPER DUMMY sin vigia interno')
BASE=mc.carpeta('render-hijos-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');os.makedirs(JAIL)
exe=mc.copia_exe(os.path.join(BASE,'srv'),con_render=True,con_conversor=True)
shutil.copyfile(HELPER,os.path.join(os.path.dirname(exe),'DelphiFormRenderVcl.exe'))
srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='render-hijos',t=110)
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32];k.OpenProcess.restype=ctypes.c_void_p
k.CloseHandle.argtypes=[ctypes.c_void_p]
k.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32)]
k.QueryFullProcessImageNameW.argtypes=[ctypes.c_void_p,ctypes.c_uint32,ctypes.c_wchar_p,ctypes.POINTER(ctypes.c_uint32)]
k.TerminateProcess.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
def alive(pid,cleanup=False):
    h=k.OpenProcess(0x1000|(1 if cleanup else 0),0,pid)
    if not h:
        err=ctypes.get_last_error()
        if err==87:return False
        raise ctypes.WinError(err)
    try:
        code=ctypes.c_uint32()
        if not k.GetExitCodeProcess(h,ctypes.byref(code)):raise ctypes.WinError(ctypes.get_last_error())
        if code.value!=259:return False
        if cleanup:
            buf=ctypes.create_unicode_buffer(32768);size=ctypes.c_uint32(len(buf))
            if not k.QueryFullProcessImageNameW(h,0,buf,ctypes.byref(size)):raise ctypes.WinError(ctypes.get_last_error())
            if os.path.commonpath([BASE,os.path.abspath(buf.value)]).lower()!=BASE.lower():
                raise RuntimeError('El PID ya no pertenece a la copia DUMMY')
            if not k.TerminateProcess(h,1):raise ctypes.WinError(ctypes.get_last_error())
        return True
    finally:k.CloseHandle(h)
def tick(path):
    for _ in range(20):
        try:
            text=mc.lee(path).strip()
            if text:return int(text)
        except OSError:pass
        time.sleep(.05)
    return None
pids=[];result={};counter=''
try:
    f=os.path.join(JAIL,'DUMMY-wait.dfm')
    with open(f,'w') as file:
        file.write("object Dummy: TDummy\n ClientWidth = 160\n ClientHeight = 100\n object Hold: TDummyReach\n Accion = 'espera'\n end\nend\n")
    def request():
        try:result['out']=srv.call('delphi_designer',dict(command='preview',path=f,out=os.path.join(JAIL,'DUMMY.png'),inline='false'))
        except Exception as e:result['out']=str(e)
    start=time.monotonic();worker=threading.Thread(target=request);worker.start()
    while worker.is_alive() and not counter and time.monotonic()-start<15:
        counter=next((os.path.join(d,'DUMMY-counter.txt') for d,_,ns in os.walk(BASE) if 'DUMMY-counter.txt' in ns),'')
        time.sleep(.1)
    mc.check('fixture hijo creado',bool(counter))
    first=tick(counter) if counter else None;time.sleep(.5);second=tick(counter) if counter else None
    mc.check('control hijo escribe durante la espera',first is not None and second is not None and second>first)
    if counter:
        for name in ['DUMMY-parent.pid','DUMMY-child.pid']:
            path=os.path.join(os.path.dirname(counter),name)
            if os.path.isfile(path):pids.append(int(mc.lee(path)))
    worker.join(100);elapsed=time.monotonic()-start
    mc.check('limite exterior real entre 74 y 90 segundos',not worker.is_alive() and 74<elapsed<90,str(elapsed))
    mc.check('rechazo etiquetado del vigia exterior','[DSGN-062 DENIED]' in result.get('out',''),result)
    last=tick(counter) if counter else None;time.sleep(.7);after=tick(counter) if counter else None
    mc.check('contador se detiene',last is not None and after==last,(last,after))
    mc.check('fixture identifica padre e hijo',len(pids)==2,pids)
    mc.check('ningun PID DUMMY sigue vivo',len(pids)==2 and not any(alive(p) for p in pids))
    mc.check('servidor sigue contestando',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
finally:
    srv.cierra()
    for pid in pids:
        if alive(pid):alive(pid,cleanup=True)
    mc.borra(BASE)
mc.check('BASE borrada con el exe',not os.path.exists(BASE))
mc.fin('render hijos 118')
