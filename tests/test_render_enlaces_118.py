# -*- coding: utf-8 -*-
"""MANUAL: requiere dos enlaces DUMMY preparados por David.
RENDER_ENLACES_FIXTURE apunta al directorio que contiene jail y DUMMY-outside.
Mutante: retirar EsEnlace en AncestroDeClase e IndexaCarpeta del ayudante.
Los enlaces se conservan para repetir el mutante; la copia del exe se borra.
"""
import atexit,json,os,shutil
import mcp_cliente as mc
FIX=os.environ.get('RENDER_ENLACES_FIXTURE','')
if not FIX:
    mc.fin('render enlaces 118',sin_checks='manual: falta RENDER_ENLACES_FIXTURE y los dos symlinks DUMMY')
JAIL=os.path.join(FIX,'jail');OUT=os.path.join(FIX,'DUMMY-outside')
names=['DUMMY-root.pas','DUMMY-child.dfm']
if not all(os.path.islink(os.path.join(JAIL,n)) for n in names):
    raise RuntimeError('La fixture manual no tiene los dos enlaces DUMMY')
BASE=mc.carpeta('render-enlaces-118');atexit.register(mc.borra,BASE)
exe=mc.copia_exe(os.path.join(BASE,'srv'),con_render=True,con_conversor=True)
srv=mc.Stdio(exe,mc.entorno({'DELPHI_MCP_ROOTS':JAIL}),nombre='render-enlaces',t=110)
def preview(path,n,**kw):
    out=srv.call('delphi_designer',dict(command='preview',path=os.path.join(JAIL,path),
      out=os.path.join(JAIL,n+'.png'),inline='false',**kw))
    try:return json.loads(out)
    except:return {'error':out}
try:
    for mode in ['normal','link']:
        for n in names:
            link=os.path.join(JAIL,n);saved=link+'.saved'
            if mode=='normal':
                os.rename(link,saved);shutil.copyfile(os.path.join(OUT,n),link)
            else:
                os.remove(link);os.rename(saved,link)
        r=preview('DUMMY-root.dfm','root-'+mode)
        d=preview('DUMMY-inline.dfm','child-'+mode,component='F.DUMMYLabel')
        mc.check(mode+' PAS aporta frame solo sin enlace',
          r.get('root',{}).get('kind')==('frame' if mode=='normal' else 'form'),r)
        mc.check(mode+' DFM aporta componente solo sin enlace',
          bool(d.get('componentRect'))==(mode=='normal'),d)
    mc.check('servidor vivo',not mc.fallo(srv.call('delphi_list',{'root':JAIL})))
finally:
    srv.cierra()
    for n in names:
        link=os.path.join(JAIL,n);saved=link+'.saved'
        if os.path.lexists(saved):
            if os.path.lexists(link):os.remove(link)
            os.rename(saved,link)
    mc.borra(BASE)
mc.check('copia del exe borrada',not os.path.exists(BASE))
mc.fin('render enlaces 118')
