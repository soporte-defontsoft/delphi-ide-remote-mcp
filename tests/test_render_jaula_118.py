# -*- coding: utf-8 -*-
"""Puerta previa del renderizador: literal entero, relativo, lista, item y state.
Solo cobayas DUMMY. Claude ejecuta esta bateria; el mutante retira la llamada
a LiteralesDeRenderDenegados en CorreRender, recompila Win64 y debe ponerla roja.
"""
import atexit, json, os, shutil
import mcp_cliente as mc
BASE=mc.carpeta('render-jaula-118')
atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');OUT=os.path.join(BASE,'DUMMY-outside')
os.makedirs(JAIL);os.makedirs(OUT)
FIX=os.path.join(mc.REPO,'src','Render','Pruebas','DUMMY')
avi=os.path.join(OUT,'DUMMY.avi')
shutil.copyfile(os.path.join(FIX,'DUMMY.avi'),avi)
inside=os.path.join(JAIL,'DUMMY.avi');shutil.copyfile(avi,inside)
exe=mc.copia_exe(os.path.join(BASE,'srv'),con_render=True,con_conversor=True)
srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='render-jaula',t=110)
f=os.path.join(JAIL,'DUMMY.dfm')
def write(s):
    with open(f,'w',encoding='ascii') as file:file.write(s)
def form(s):
    return 'object Dummy: TDummy\n ClientWidth = 160\n ClientHeight = 100\n'+s+'\nend\n'
def literal(s):return "'"+s.replace("'","''")+"'"
def preview(n,state=''):
    return srv.call('delphi_designer',dict(command='preview',path=f,
        out=os.path.join(JAIL,n+'.png'),inline='false',state=state))
def ok(out):
    try:return json.loads(out).get('framework') in ('vcl','fmx')
    except:return False
def denied(n,out,prop):
    mc.check(n+' se niega antes del ayudante',mc.es(out,'SR_DESIGNER_LITERAL_FUERA_FMT') and prop in out,out[:400])
    mc.check(n+' no muestra valor',avi not in mc.real(out) and 'DUMMY-outside' not in out,out[:400])
try:
    template=open(os.path.join(FIX,'DUMMY-path.dfm'),encoding='utf-8-sig').read()
    write(template.replace('DUMMY.avi',inside))
    mc.check('control AVI propio funciona',ok(preview('inside')))
    # el AVI RELATIVO junto al form: solo se carga si el cwd del ayudante es la
    # carpeta del form (2af de la 1.18.2: era la del png, en nuestra casa)
    write(template)
    r=preview('relativo-propio')
    mc.check('control AVI relativo junto al form: se dibuja (el cwd del ayudante es la carpeta del form)',ok(r),r[:400])
    write(template.replace('DUMMY.avi',avi))
    denied('AVI exterior',preview('outside'),'FileName')
    # ...y el mismo form en BINARIO (1.5 de la lista de medidas, V51 de la
    # 1.23): la puerta lo lee por el lector existente (TStyleDoc, tambien el
    # binario) y lo niega igual; de control, el binario con el AVI propio
    for n,ruta,niega in (('binario exterior',avi,True),('binario propio',inside,False)):
        write(template.replace('DUMMY.avi',ruta))
        conv=srv.call('delphi_designer',dict(command='to-binary',path=f))
        # en disco va con la envoltura de recurso que escribe el IDE: TPF0 en la cabecera, no en el byte 0
        mc.check(n+' (fixture): el form paso a binario',b'TPF0' in open(f,'rb').read(64),conv[:300])
        out=preview(n.replace(' ','-'))
        if niega:
            denied(n,out,'FileName')
        else:
            mc.check('control '+n+': el binario con el AVI propio se dibuja',ok(out),out[:400])
    for n,v in [('absoluto',literal(avi)),
                ('escapes',''.join('#'+str(ord(c)) for c in avi)),
                ('relativo',literal(os.path.relpath(avi,JAIL))),
                ('trozos',literal(avi[:len(avi)//2])+' +\n   '+literal(avi[len(avi)//2:]))]:
        write(form(' Caption = '+v))
        denied(n,preview(n),'Caption')
    write(form(" object Memo1: TMemo\n Lines.Strings = (\n "+literal(avi)+"\n )\n end"))
    denied('lista',preview('list'),'Lines.Strings')
    # V109 de la 1.23.1: la lista como la ESCRIBE EL IDE, con el ')' detras del
    # ultimo elemento. La de arriba lo pone en su propia linea y pasaba por la
    # forma de la fixture: el ultimo elemento (y el unico) no se juzgaba y el
    # form se dibujaba (medido en produccion con un TListBox)
    for n,cuerpo in (('lista del IDE, el unico',literal(avi)+')'),
                     ('lista del IDE, el ultimo de dos',"'primero'\n "+literal(avi)+')'),
                     ('lista del IDE, el ultimo en trozos',"'primero'\n "+literal(avi[:len(avi)//2])+' +\n   '+literal(avi[len(avi)//2:])+')')):
        write(form(" object Memo1: TMemo\n Lines.Strings = (\n "+cuerpo+"\n end"))
        denied(n,preview(n.replace(' ','-').replace(',','')),'Lines.Strings')
    write(form(" object Memo1: TMemo\n Lines.Strings = (\n 'uno'\n 'dos')\n end"))
    mc.check('control lista del IDE sin rutas: se dibuja',ok(preview('lista-normal')))
    write(form(" object Grid1: TGridPanel\n ColumnCollection = <\n item\n Value = 1.0\n DUMMY = "+literal(avi)+"\n end>\n end"))
    denied('item',preview('item'),'DUMMY')
    write(form(''))
    denied('state',preview('state','Dummy.Caption='+avi),'Dummy.Caption')
    write(form(" Caption = 'Texto ordinario'"))
    mc.check('control texto no ruta funciona',ok(preview('normal')))
    # el cwd del ayudante es la carpeta del form que carga, la del agente (2af
    # de la 1.18.2: era la del png, que vive en NUESTRA casa de capturas)
    cwd=os.path.dirname(f)
    write(form(' Caption = '+literal(os.path.relpath(avi,cwd))))
    denied('relativo desde cwd',preview('cwd'),'Caption')
    # ...y la carpeta del png (nuestra casa) se sigue mirando como base: una
    # base de mas no abre nada
    casa=os.path.join(mc.casa_de_capturas(os.path.join(BASE,'srv'),'render-jaula',''),'designer')
    mc.check('fixture la carpeta del png (nuestra casa) existe',os.path.isdir(casa))
    write(form(' Caption = '+literal(os.path.relpath(avi,casa))))
    denied('relativo desde la carpeta del png',preview('casa'),'Caption')
    # El mismo literal en un hermano inline, no solo en la form pedida.
    child=os.path.join(JAIL,'DUMMY-child.dfm')
    with open(child,'w',encoding='ascii') as file:
        file.write('object Child: TDummyChild\n Caption = '+literal(avi)+'\nend\n')
    write(form(' inline F: TDummyChild\n end'))
    denied('hermano',preview('sibling'),'Caption')
    os.remove(child)
    # El presupuesto se cuenta antes de cargar y suma los hermanos.
    write(form(" Caption = 'DUMMY control'"))
    with open(child,'w',encoding='ascii') as file:
        file.write('object Child: TDummyChild\n Caption = '+literal('X'*(16*1024*1024))+'\nend\n')
    out=preview('budget-sibling')
    mc.check('presupuesto previo del hermano',mc.es(out,'SR_DESIGNER_LITERAL_TOPE_FMT'),out[:350])
    os.remove(child)
    other=os.path.join(JAIL,'DUMMY-other.dfm')
    for sibling in (child,other):
        with open(sibling,'w',encoding='ascii') as file:
            file.write('object Child: TDummyChild\n Caption = '+literal('X'*(9*1024*1024))+'\nend\n')
    out=preview('budget-total')
    mc.check('presupuesto suma hermanos individualmente menores',mc.es(out,'SR_DESIGNER_LITERAL_TOPE_FMT'),out[:350])
    os.remove(child);os.remove(other)
    write(form(' object Image1: TImage\n Picture.Data = {\n'+('00'*64+'\n')*131072+'}\n end'))
    out=preview('budget-blob')
    mc.check('presupuesto previo de la form',mc.es(out,'SR_DESIGNER_LITERAL_TOPE_FMT'),out[:350])
    write(form(" Caption = 'DUMMY control'"))
    mc.check('control pequeno despues de rechazos',ok(preview('budget-after')))
    mc.check('servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
    # ...pero NO en una carpeta donde la sesion no puede escribir (una
    # referencia, un ReadOnlyPaths): el codigo de diseno de los paquetes
    # escribe RELATIVO al cwd (revisor del 2af, M3). Medido con el mismo AVI
    # relativo: alli no se carga (el ayudante corre en una carpeta nuestra), y
    # la carpeta queda como estaba
    RO=os.path.join(JAIL,'solo');os.makedirs(RO)
    shutil.copyfile(avi,os.path.join(RO,'DUMMY.avi'))
    fro=os.path.join(RO,'DUMMY.dfm')
    with open(fro,'w',encoding='ascii') as file:file.write(template)
    antes_ro=sorted(os.listdir(RO))
    srv2=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL,'DELPHI_MCP_READONLY_PATHS':RO}),nombre='render-jaula',t=110)
    try:
        r=srv2.call('delphi_designer',dict(command='preview',path=fro))
        mc.check('en una carpeta de solo lectura el ayudante no corre alli: el AVI relativo de alli no se carga, y nada cambia',
                 'Cannot open AVI' in r and sorted(os.listdir(RO))==antes_ro,(r[:300],os.listdir(RO)))
    finally:
        srv2.cierra()
finally:
    srv.cierra();mc.borra(BASE)
mc.check('BASE borrada con el exe',not os.path.exists(BASE))
mc.fin('render jaula 118')
