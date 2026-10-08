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
    mc.check(n+' se niega antes del ayudante','[DSGN-115 DENIED]' in out and prop in out,out[:400])
    mc.check(n+' no muestra valor',avi not in mc.real(out) and 'DUMMY-outside' not in out,out[:400])
try:
    template=open(os.path.join(FIX,'DUMMY-path.dfm'),encoding='utf-8-sig').read()
    write(template.replace('DUMMY.avi',inside))
    mc.check('control AVI propio funciona',ok(preview('inside')))
    write(template.replace('DUMMY.avi',avi))
    denied('AVI exterior',preview('outside'),'FileName')
    for n,v in [('absoluto',literal(avi)),
                ('escapes',''.join('#'+str(ord(c)) for c in avi)),
                ('relativo',literal(os.path.relpath(avi,JAIL))),
                ('trozos',literal(avi[:len(avi)//2])+' +\n   '+literal(avi[len(avi)//2:]))]:
        write(form(' Caption = '+v))
        denied(n,preview(n),'Caption')
    write(form(" object Memo1: TMemo\n Lines.Strings = (\n "+literal(avi)+"\n )\n end"))
    denied('lista',preview('list'),'Lines.Strings')
    write(form(" object Grid1: TGridPanel\n ColumnCollection = <\n item\n Value = 1.0\n DUMMY = "+literal(avi)+"\n end>\n end"))
    denied('item',preview('item'),'DUMMY')
    write(form(''))
    denied('state',preview('state','Dummy.Caption='+avi),'Dummy.Caption')
    write(form(" Caption = 'Texto ordinario'"))
    mc.check('control texto no ruta funciona',ok(preview('normal')))
    cwd=os.path.join(JAIL,'__delphi-temp','render-jaula','designer')
    mc.check('fixture cwd del ayudante existe',os.path.isdir(cwd))
    write(form(' Caption = '+literal(os.path.relpath(avi,cwd))))
    denied('relativo desde cwd',preview('cwd'),'Caption')
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
    mc.check('presupuesto previo del hermano','[DSGN-117 DENIED]' in out,out[:350])
    os.remove(child)
    other=os.path.join(JAIL,'DUMMY-other.dfm')
    for sibling in (child,other):
        with open(sibling,'w',encoding='ascii') as file:
            file.write('object Child: TDummyChild\n Caption = '+literal('X'*(9*1024*1024))+'\nend\n')
    out=preview('budget-total')
    mc.check('presupuesto suma hermanos individualmente menores','[DSGN-117 DENIED]' in out,out[:350])
    os.remove(child);os.remove(other)
    write(form(' object Image1: TImage\n Picture.Data = {\n'+('00'*64+'\n')*131072+'}\n end'))
    out=preview('budget-blob')
    mc.check('presupuesto previo de la form','[DSGN-117 DENIED]' in out,out[:350])
    write(form(" Caption = 'DUMMY control'"))
    mc.check('control pequeno despues de rechazos',ok(preview('budget-after')))
    mc.check('servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
finally:
    srv.cierra();mc.borra(BASE)
mc.check('BASE borrada con el exe',not os.path.exists(BASE))
mc.fin('render jaula 118')
