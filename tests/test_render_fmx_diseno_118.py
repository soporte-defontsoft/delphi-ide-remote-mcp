# -*- coding: utf-8 -*-
"""El renderizador FMX carga los componentes del form del agente EN DISENO (PonEnDiseno), y la variante de control
(SetDesigning(False)) en ejecucion: lo mide su estado (csDesigning de un TMediaPlayer), que la unidad DUMMY anota al
cargar. Las dos variantes (con URenderFmxReachDummy, de src\\Render\\Pruebas, que el producto no enlaza) las hace y
compila el propio servidor (mc.variante_del_renderizador; hasta la 1.29 eran exes a mano y la bateria salia sin
checks, I10).

Por su EFECTO ya no se mide (7-nov-2026): el fichero que nombre el form, o lo niega la puerta del servidor por su
texto (DSGN-115: bajo Windows o Program Files, que el contenedor si lee) o el contenedor del renderizador no lo
lee (las raices, desde la 1.24); y la red tampoco la tiene ese contenedor (K8 de test_delphi_test_contenedor, el
mismo Lsp.Sandbox): un TWebBrowser no navegaba ni en ejecucion. El modo diseno es la tercera barrera. El marcador
se lee MIENTRAS dibuja: el servidor borra la carpeta del render al acabar.
"""
import atexit,json,os,shutil,threading,time
import mcp_cliente as mc
BASE=mc.carpeta('render-fmx-diseno-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');os.makedirs(JAIL)
form=os.path.join(JAIL,'DUMMY-media.fmx')
with open(form,'w',encoding='ascii') as file:
    file.write("object Dummy: TDummy\n ClientWidth = 160\n ClientHeight = 100\n"+
      " object Player1: TMediaPlayer\n end\n"+
      " object Measure: TDummyFmxMeasure\n end\nend\n")


def marcador():
    return [mc.lee(os.path.join(d,'DUMMY-media.txt')) for d,_,ns in os.walk(BASE) if 'DUMMY-media.txt' in ns]


try:
    hacedor=mc.Stdio(mc.copia_exe(os.path.join(BASE,'hacedor')),mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),
                     nombre='fmx-variantes',t=110)
    try:
        HELPERS=[('design',mc.variante_del_renderizador(hacedor.call,JAIL,'Fmx',
                     unidades=['URenderFmxReachDummy.pas'],etiqueta='Diseno')),
                 ('runtime',mc.variante_del_renderizador(hacedor.call,JAIL,'Fmx',
                     cambios=[('FormRender.Comun.pas','  TComponentCrack(AComp).SetDesigning(True);',
                               '  TComponentCrack(AComp).SetDesigning(False); // DUMMY: el control, en ejecucion')],
                     unidades=['URenderFmxReachDummy.pas'],etiqueta='Ejecucion'))]
    finally:
        hacedor.cierra()
    mc.check('las dos variantes las compila el servidor',all(os.path.isfile(h) for _,h in HELPERS))
    for mode,helper in HELPERS:
        for d,_,ns in os.walk(BASE):
            if 'DUMMY-media.txt' in ns:os.remove(os.path.join(d,'DUMMY-media.txt'))
        exe=mc.copia_exe(os.path.join(BASE,mode),con_render=True,con_conversor=True)
        shutil.copyfile(helper,os.path.join(os.path.dirname(exe),'DelphiFormRenderFmx.exe'))
        srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='fmx-'+mode,t=110)
        try:
            res={}
            def pide():
                res['out']=srv.call('delphi_designer',dict(command='preview',path=form,out=os.path.join(JAIL,mode+'.png'),
                                                            inline='false'))
            hilo=threading.Thread(target=pide);hilo.start()
            marker=[]
            while hilo.is_alive():
                marker=marker or [x for x in marcador() if x]
                time.sleep(.1)
            hilo.join()
            out=res.get('out','')
            try:r=json.loads(out)
            except:r={}
            mc.check(mode+' dibuja FMX sin ignorar propiedades',r.get('framework')=='fmx' and not r.get('ignored'),out[:900])
            mc.check(mode+' el componente del agente se carga '+('en diseno' if mode=='design' else 'en ejecucion'),
                     marker==['diseno=%s'%(mode=='design')],marker)
            mc.check(mode+' servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
        finally:srv.cierra()
finally:
    mc.borra(BASE)
mc.check('BASE borrada con los exes',not os.path.exists(BASE))
mc.fin('render FMX diseno 118')
