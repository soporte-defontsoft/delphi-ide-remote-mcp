# -*- coding: utf-8 -*-
"""El renderizador VCL con un componente DUMMY que lanza un hijo y espera (URenderReachDummy, de
src\\Render\\Pruebas: el producto no la enlaza) y su vigia interno apagado: la variante la hace y la compila el
propio servidor (mc.variante_del_renderizador; hasta la 1.29 era un exe a mano y la bateria salia sin checks,
I10). Mide el limite REAL exterior (RENDER_TIEMPO_MS, del fuente) y que el Job mata al hijo.
Mutante: omitir AssignProcessToJobObject en la rama sin AppContainer de RunCore.
El arnes limpia solo sus PID verificados, tambien con el mutante.
"""
import atexit,ctypes,json,os,shutil,threading,time
import mcp_cliente as mc
BASE=mc.carpeta('render-hijos-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');os.makedirs(JAIL)
exe=mc.copia_exe(os.path.join(BASE,'srv'),con_render=True,con_conversor=True)
srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='render-hijos',t=110)
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32];k.OpenProcess.restype=ctypes.c_void_p
k.CloseHandle.argtypes=[ctypes.c_void_p]
k.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32)]
k.QueryFullProcessImageNameW.argtypes=[ctypes.c_void_p,ctypes.c_uint32,ctypes.c_wchar_p,ctypes.POINTER(ctypes.c_uint32)]
k.TerminateProcess.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
def alive(pid,cleanup=False):
    # la pregunta sola es la de la casa (mc.pid_vivo); aqui solo lo de matar
    if not cleanup:return mc.pid_vivo(pid)
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
    HELPER=mc.variante_del_renderizador(srv.call,JAIL,'Vcl',
        cambios=[('FormRender.Comun.pas','  if AMs <= 0 then','  if True then // DUMMY: el vigia interno apagado')],
        unidades=['URenderReachDummy.pas'])
    shutil.copyfile(HELPER,os.path.join(os.path.dirname(exe),'DelphiFormRenderVcl.exe'))
    mc.check('la variante DUMMY la compila el servidor',os.path.isfile(HELPER))
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
    # el limite exterior, del fuente (eran 74 y 90 a mano): el plazo del servidor (RENDER_TIEMPO_MS; un
    # segundo menos, lo que pasa entre que la bateria pide y el servidor empieza a contar) y ese plazo
    # mas el margen de su vigia (MARGEN_DEL_VIGIA_MS), que sin el vigia interno ya no habla antes
    PLAZO=mc.entero_del_fuente('Server/Lsp.FormRender.pas','RENDER_TIEMPO_MS')/1000
    MARGEN=mc.entero_del_fuente('Server/Lsp.FormRender.pas','MARGEN_DEL_VIGIA_MS')/1000
    worker.join(PLAZO+MARGEN+10);elapsed=time.monotonic()-start
    mc.check('limite exterior real entre %g y %g segundos'%(PLAZO-1,PLAZO+MARGEN),
             not worker.is_alive() and PLAZO-1<elapsed<PLAZO+MARGEN,str(elapsed))
    mc.check('rechazo etiquetado del vigia exterior',mc.es(result.get('out',''),'SR_DESIGNER_RENDER_TIEMPO_FMT'),result)
    last=tick(counter) if counter else None;time.sleep(.7);after=tick(counter) if counter else None
    # (o ya no hay carpeta: el servidor borra la del render al acabar, y Windows no deja borrar el directorio
    # actual de un proceso vivo, el del hijo que escribia ahi)
    carpeta_viva=bool(counter) and os.path.isdir(os.path.dirname(counter))
    mc.check('contador se detiene (o su carpeta ya se borro)',
             bool(counter) and ((last is not None and after==last) or not carpeta_viva),(last,after,carpeta_viva))
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
