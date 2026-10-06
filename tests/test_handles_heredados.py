"""Contrato E2E: el motor no recibe los sockets HTTP del servidor.
La copia publicada 1.11.2 hereda el listener y una conexion aceptada.
La bateria inspecciona una fixture propia mientras esta viva; despues la
cierra. La liberacion final del puerto es una guarda de limpieza.
"""
import sys, os, subprocess, json, time
import mcp_cliente as mc
from handles_windows import K, sockets, bind_result
base=mc.carpeta('handles-heredados'); sd=os.path.join(base,'srv'); exe=mc.copia_exe(sd); port=mc.puerto_libre()
with open(os.path.join(sd,'settings.ini'),'w') as f:
    f.write('[Server]\nBindIP=127.0.0.1\nPort=%d\n[Workspace.Probe]\nToken=probe-handles-local\nRoots=%s\n'%(port,base))
p=None; engines=[];
try:
    print('PORT_BEFORE',port,bind_result(port),flush=True)
    p=mc.lanza_http(exe,port,mc.entorno(),creationflags=subprocess.CREATE_NO_WINDOW)
    c=mc.Http(port,'probe-handles-local');c.session('codex-handles-probe'); assert c.init
    d=os.path.join(base,'Probe')
    print('CREATE',c.call('delphi_create',{'kind':'project-vcl','name':'Probe','dir':d})[:350],flush=True)
    print('SYMBOLS',c.call('delphi_symbols',{'path':os.path.join(d,'UMain.pas')})[:400],flush=True)
    engines=mc.hijos_lsp(p.pid); print('ENGINES',engines,flush=True); assert engines
    server_table=sockets(p.pid)
    mc.check('H1 fixture: la tabla identifica el listener heredable del servidor', any(x.get('socket_port')==port for x in server_table['inheritable']), json.dumps(server_table))
    for pid in engines:
        table=sockets(pid)
        mc.check('H2 motor %d: no recibe el listener ni las conexiones HTTP'%pid, not any(x.get('socket_port')==port for x in table['inheritable']), json.dumps(table))
    p.terminate();p.wait(10)
    for i in range(30):
        state=bind_result(port)
        if state=='FREE':break
        time.sleep(.1)
    mc.check('H3 guarda: tras cerrar la fixture el puerto queda libre',state=='FREE',state)
finally:
    if p is not None and p.poll() is None:p.kill();p.wait(10)
    for pid in engines:
        h=K.OpenProcess(1,False,pid)
        if h:K.TerminateProcess(h,1);K.CloseHandle(h)
    print('FINAL_PORT',bind_result(port),flush=True)
mc.fin('herencia de handles LSP')
