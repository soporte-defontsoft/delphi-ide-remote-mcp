# -*- coding: utf-8 -*-
"""Literales UNC/dispositivo: decidir por texto antes de cualquier E/S.
Mutante: retirar RutaSinTocarElDisco de Comprueba -> latencia o rechazo rojo.
La reserva TEST-NET sobrevive a run_all: Windows recuerda hosts fallidos.
"""
import atexit,json,os,tempfile,time
import mcp_cliente as mc

def host_nuevo():
    carpeta=os.path.join(tempfile.gettempdir(),'delphi-mcp-testnet-reservado')
    os.makedirs(carpeta,exist_ok=True)
    for red in ('198.51.100.','203.0.113.','192.0.2.'):
        for n in range(1,255):
            ip=red+str(n)
            if ip in ('198.51.100.7','203.0.113.211'):continue
            try:
                fd=os.open(os.path.join(carpeta,ip),os.O_CREAT|os.O_EXCL|os.O_WRONLY)
            except FileExistsError:continue
            os.close(fd)
            return ip
    raise RuntimeError('TEST-NET agotado: no se reutiliza un host cacheado')

def main():
    base=mc.carpeta('render-unc-118');atexit.register(mc.borra,base)
    jail=os.path.join(base,'jail');os.makedirs(jail)
    exe=mc.copia_exe(os.path.join(base,'srv'),con_render=True,con_conversor=True)
    srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':jail}),nombre='render-unc',t=90)
    form=os.path.join(jail,'DUMMY.dfm');child=os.path.join(jail,'DUMMY-child.dfm')
    def escribe(path,caption):
        open(path,'w',encoding='ascii').write("object Dummy: TDummy\n ClientWidth = 160\n ClientHeight = 100\n Caption = '"+caption+"'\nend\n")
    def preview(state=''):
        return srv.call('delphi_designer',dict(command='preview',path=form,inline='false',
            out=os.path.join(jail,'DUMMY.png'),state=state))
    def control():
        escribe(form,'DUMMY control')
        out=preview()
        mc.check('control positivo renderiza',mc.como_json(out).get('framework')=='vcl',out[:250])
    try:
        control()
        for caso in ('form','hermano','state','dispositivo-largo','dispositivo-win32'):
            ip=host_nuevo();value='\\\\'+ip+'\\share\\DUMMY.txt'
            if caso=='dispositivo-largo':value='\\\\?\\UNC\\'+ip+'\\share\\DUMMY.txt'
            if caso=='dispositivo-win32':value='\\\\.\\UNC\\'+ip+'\\share\\DUMMY.txt'
            escribe(form,value if caso not in ('hermano','state') else 'DUMMY control')
            if caso=='hermano':escribe(child,value)
            before=time.monotonic()
            out=preview('Dummy.Caption='+value if caso=='state' else '')
            elapsed=time.monotonic()-before
            mc.check(caso+' niega por propiedad','[DSGN-115 DENIED]' in out and 'Caption' in out,out[:250])
            mc.check(caso+' responde antes de 2 s',elapsed<2,elapsed)
            mc.check(caso+' no revela valor',ip not in out and 'share' not in out,out[:250])
            if caso=='hermano':os.remove(child)
        control()
        mc.check('servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':jail})))
    finally:
        srv.cierra();mc.borra(base)
    mc.check('BASE borrada con exe',not os.path.exists(base))
    mc.fin('render UNC 118')

if __name__=='__main__':main()
