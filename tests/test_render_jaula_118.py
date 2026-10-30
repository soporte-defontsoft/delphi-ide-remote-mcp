# -*- coding: utf-8 -*-
"""Puerta previa del renderizador: literal entero, relativo, lista, item y state.
Solo cobayas DUMMY. Claude ejecuta esta bateria; el mutante retira la llamada
a LiteralesDeRenderDenegados en CorreEnSuContenedor, recompila Win64 y debe
ponerla roja.

Desde V65 de la 1.24 el ayudante corre en un contenedor: lo de fuera de las raices
no lo alcanza (lo mide el AVI de fuera, que no abre), y la puerta solo mira lo que
el contenedor SI lee, las carpetas del sistema, y por el TEXTO: la misma respuesta
exista el fichero o no. Lo que dijera otra cosa seria un oraculo de existencia.
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
# lo que el contenedor si leeria, y uno que no existe en el mismo sitio
WINDIR=os.environ['WINDIR']
SIS=os.path.join(WINDIR,'win.ini')
SIS_NO=os.path.join(WINDIR,'no-existe-v65.ini')
mc.check('fixture win.ini existe y su gemelo no',os.path.isfile(SIS) and not os.path.exists(SIS_NO))
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
    mc.check(n+' no muestra valor',SIS not in mc.real(out) and 'win.ini' not in out,out[:400])
def sin_abrir(out):
    # lo intento y no llego: el contenedor no lo deja leer
    return mc.es(out,'SR_DESIGNER_RENDER_FALLO_FMT') and 'Cannot open AVI' in out
try:
    template=open(os.path.join(FIX,'DUMMY-path.dfm'),encoding='utf-8-sig').read()
    # el AVI RELATIVO junto al form: se le copia con el form, porque alli donde
    # esta el contenedor no lo alcanza (V65 de la 1.24)
    write(template)
    r=preview('relativo-propio')
    mc.check('control AVI relativo junto al form: se dibuja (viaja con el form)',ok(r),r[:400])
    # ...tambien en una subcarpeta; y uno que sube de la carpeta del form no viaja
    sub=os.path.join(JAIL,'res');os.makedirs(sub);shutil.copyfile(avi,os.path.join(sub,'DUMMY.avi'))
    write(template.replace('DUMMY.avi','res\\DUMMY.avi'))
    r=preview('relativo-sub')
    mc.check('control AVI en una subcarpeta del form: se dibuja, en su sitio',ok(r),r[:400])
    # por su ruta entera ni el propio: el contenedor no lee las raices, y un
    # componente que abre lo que le dicen no puede. Es el precio de V65
    write(template.replace('DUMMY.avi',inside))
    r=preview('inside')
    mc.check('un AVI por su ruta entera, aunque sea de la raiz: no lo abre, y lo dice',sin_abrir(r),r[:400])
    # LO QUE MIDE LA JAULA: el AVI de fuera no se abre, y se intento
    write(template.replace('DUMMY.avi',avi))
    r=preview('outside')
    mc.check('AVI exterior: el ayudante lo intenta y el contenedor no lo deja',sin_abrir(r),r[:400])
    mc.check('AVI exterior: la respuesta no nombra la carpeta de fuera',
             avi not in mc.real(r) and 'DUMMY-outside' not in r,r[:400])
    write(template.replace('DUMMY.avi',SIS))
    denied('un fichero del sistema',preview('sistema'),'FileName')
    # ...y el mismo form en BINARIO (1.5 de la lista de medidas, V51 de la
    # 1.23): la puerta lo lee por el lector existente (TStyleDoc, tambien el
    # binario) y lo niega igual; de control, el binario con el AVI propio
    for n,ruta,niega in (('binario de sistema',SIS,True),('binario propio','DUMMY.avi',False)):
        write(template.replace('DUMMY.avi',ruta))
        conv=srv.call('delphi_designer',dict(command='to-binary',path=f))
        # en disco va con la envoltura de recurso que escribe el IDE: TPF0 en la cabecera, no en el byte 0
        mc.check(n+' (fixture): el form paso a binario',b'TPF0' in open(f,'rb').read(64),conv[:300])
        out=preview(n.replace(' ','-'))
        if niega:
            denied(n,out,'FileName')
        else:
            mc.check('control '+n+': el binario con el AVI propio se dibuja',ok(out),out[:400])
    # EL ORACULO (V65): un Caption que nombra un fichero de fuera se dibuja exista
    # o no; uno del sistema se niega exista o no. La respuesta no dice si esta
    no_esta=os.path.join(OUT,'no-existe-v65.txt')
    write(form(' Caption = '+literal(avi)))
    a=preview('existe')
    write(form(' Caption = '+literal(no_esta)))
    b=preview('no-existe')
    mc.check('sin oraculo: un literal de fuera se dibuja exista o no',ok(a) and ok(b),(a[:300],b[:300]))
    write(form(' Caption = '+literal(SIS)))
    a=preview('sis-existe')
    write(form(' Caption = '+literal(SIS_NO)))
    b=preview('sis-no-existe')
    mc.check('sin oraculo: uno del sistema se niega exista o no, con el mismo texto',
             mc.es(a,'SR_DESIGNER_LITERAL_FUERA_FMT') and a==b,(a[:300],b[:300]))
    # el ayudante resuelve un relativo desde su carpeta, la de esta llamada en
    # nuestra casa: subiendo desde ahi llegaria a Windows
    casa_etapa=os.path.join(BASE,'srv',mc.TEMPORALES,'designer','x')
    for n,v in [('absoluto',literal(SIS)),
                ('escapes',''.join('#'+str(ord(c)) for c in SIS)),
                ('relativo',literal(os.path.relpath(SIS,casa_etapa))),
                ('trozos',literal(SIS[:len(SIS)//2])+' +\n   '+literal(SIS[len(SIS)//2:]))]:
        write(form(' Caption = '+v))
        denied(n,preview(n),'Caption')
    write(form(" object Memo1: TMemo\n Lines.Strings = (\n "+literal(SIS)+"\n )\n end"))
    denied('lista',preview('list'),'Lines.Strings')
    # V109 de la 1.23.1: la lista como la ESCRIBE EL IDE, con el ')' detras del
    # ultimo elemento. La de arriba lo pone en su propia linea y pasaba por la
    # forma de la fixture: el ultimo elemento (y el unico) no se juzgaba y el
    # form se dibujaba (medido en produccion con un TListBox)
    for n,cuerpo in (('lista del IDE, el unico',literal(SIS)+')'),
                     ('lista del IDE, el ultimo de dos',"'primero'\n "+literal(SIS)+')'),
                     ('lista del IDE, el ultimo en trozos',"'primero'\n "+literal(SIS[:len(SIS)//2])+' +\n   '+literal(SIS[len(SIS)//2:])+')')):
        write(form(" object Memo1: TMemo\n Lines.Strings = (\n "+cuerpo+"\n end"))
        denied(n,preview(n.replace(' ','-').replace(',','')),'Lines.Strings')
    write(form(" object Memo1: TMemo\n Lines.Strings = (\n 'uno'\n 'dos')\n end"))
    mc.check('control lista del IDE sin rutas: se dibuja',ok(preview('lista-normal')))
    write(form(" object Grid1: TGridPanel\n ColumnCollection = <\n item\n Value = 1.0\n DUMMY = "+literal(SIS)+"\n end>\n end"))
    denied('item',preview('item'),'DUMMY')
    write(form(''))
    denied('state',preview('state','Dummy.Caption='+SIS),'Dummy.Caption')
    write(form(" Caption = 'Texto ordinario'"))
    mc.check('control texto no ruta funciona',ok(preview('normal')))
    # un texto cualquiera no es una ruta, aunque lleve lo que una ruta no puede
    # llevar (TPath.GetExtension lanzaba con un |: DSGN-116, medido contra un form real)
    write(form(" Caption = 'a|b<c>:d?.txt'"))
    r=preview('raro')
    mc.check('control un texto con caracteres que una ruta no lleva se dibuja',ok(r),r[:300])
    # El mismo literal en un hermano inline, no solo en la form pedida.
    child=os.path.join(JAIL,'DUMMY-child.dfm')
    with open(child,'w',encoding='ascii') as file:
        file.write('object Child: TDummyChild\n Caption = '+literal(SIS)+'\nend\n')
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
    # una carpeta donde la sesion no puede escribir (una referencia, un
    # ReadOnlyPaths): el codigo de diseno de los paquetes escribe RELATIVO al cwd
    # (revisor del 2af, M3), y el cwd es siempre la carpeta de la llamada: el AVI
    # relativo se carga, y la carpeta queda como estaba
    RO=os.path.join(JAIL,'solo');os.makedirs(RO)
    shutil.copyfile(avi,os.path.join(RO,'DUMMY.avi'))
    fro=os.path.join(RO,'DUMMY.dfm')
    with open(fro,'w',encoding='ascii') as file:file.write(template)
    antes_ro=sorted(os.listdir(RO))
    srv2=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL,'DELPHI_MCP_READONLY_PATHS':RO}),nombre='render-jaula',t=110)
    try:
        r=srv2.call('delphi_designer',dict(command='preview',path=fro))
        mc.check('en una carpeta de solo lectura: el AVI relativo se dibuja, y nada cambia alli',
                 ok(r) and sorted(os.listdir(RO))==antes_ro,(r[:300],os.listdir(RO)))
    finally:
        srv2.cierra()
finally:
    srv.cierra();mc.borra(BASE)
mc.check('BASE borrada con el exe',not os.path.exists(BASE))
mc.fin('render jaula 118')
