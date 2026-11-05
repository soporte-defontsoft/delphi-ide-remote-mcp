# -*- coding: utf-8 -*-
"""Un enlace de FICHERO entre los hermanos de un form no lo lee el ayudante (EsEnlace en AncestroDeClase e
IndexaCarpeta del renderizador): lo de detras no es de la jaula. Era MANUAL - dos symlinks DUMMY que preparaba
David, porque esta cuenta no podia crear enlaces -; con Developer Mode os.symlink los crea (medido el 5-nov-2026)
y la bateria fabrica su fixture (C21 del cierre de la 1.28). Sin permiso para crear un symlink, NOTA.
  normal: DUMMY-root.pas (un TFrame) y DUMMY_child.dfm son ficheros: la raiz es un frame y F.DUMMYLabel esta
  link:   los dos son enlaces a DUMMY-outside, fuera de las raices: la raiz sale form y F.DUMMYLabel no
          (DSGN-066: no hay ese componente dibujado; el frame sale sustituido)
El frame en linea se encuentra por su UNIDAD: el fichero se llama como ella (DUMMY_child), o sale
sustituido aun sin enlace (medido al fabricar la fixture).
Mutante: retirar EsEnlace en AncestroDeClase e IndexaCarpeta del ayudante.
"""
import atexit,json,os,shutil
import mcp_cliente as mc
BASE=mc.carpeta('render-enlaces-118');atexit.register(mc.borra,BASE)
JAIL=os.path.join(BASE,'jail');OUT=os.path.join(BASE,'DUMMY-outside')
os.makedirs(JAIL);os.makedirs(OUT)
def escribe(ruta,texto):
    with open(ruta,'w',encoding='utf-8',newline='\r\n') as f:f.write(texto)
# lo de FUERA de las raices: el .pas del frame raiz y el .dfm del frame en linea
escribe(os.path.join(OUT,'DUMMY-root.pas'),
  'unit DUMMY_root;\ninterface\nuses Vcl.Forms;\ntype\n  TDUMMYRoot = class(TFrame)\n  end;\n'
  'implementation\n{$R *.dfm}\nend.\n')
escribe(os.path.join(OUT,'DUMMY_child.dfm'),
  'object DUMMYChild: TDUMMYChild\n  Left = 0\n  Top = 0\n  Width = 200\n  Height = 100\n  TabOrder = 0\n'
  '  object DUMMYLabel: TLabel\n    Left = 8\n    Top = 8\n    Width = 60\n    Height = 15\n'
  "    Caption = 'DUMMY'\n  end\nend\n")
# lo de DENTRO: la raiz, el form con el frame en linea y la unidad del frame
escribe(os.path.join(JAIL,'DUMMY-root.dfm'),
  'object DUMMYRoot: TDUMMYRoot\n  Left = 0\n  Top = 0\n  Width = 320\n  Height = 240\n  TabOrder = 0\nend\n')
escribe(os.path.join(JAIL,'DUMMY_child.pas'),
  'unit DUMMY_child;\ninterface\nuses Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;\ntype\n'
  '  TDUMMYChild = class(TFrame)\n    DUMMYLabel: TLabel;\n  end;\nimplementation\n{$R *.dfm}\nend.\n')
escribe(os.path.join(JAIL,'DUMMY_inline.dfm'),
  "object DUMMYInline: TDUMMYInline\n  Left = 0\n  Top = 0\n  Caption = 'Inline'\n  ClientHeight = 200\n"
  '  ClientWidth = 300\n  inline F: TDUMMYChild\n    Left = 10\n    Top = 10\n    Width = 200\n'
  '    Height = 100\n    TabOrder = 0\n  end\nend\n')
escribe(os.path.join(JAIL,'DUMMY_inline.pas'),
  'unit DUMMY_inline;\ninterface\nuses Vcl.Forms, DUMMY_child;\ntype\n  TDUMMYInline = class(TForm)\n'
  '    F: TDUMMYChild;\n  end;\nimplementation\n{$R *.dfm}\nend.\n')
names=['DUMMY-root.pas','DUMMY_child.dfm']
try:
    for n in names:
        os.symlink(os.path.join(OUT,n),os.path.join(JAIL,n))
except OSError as e:
    mc.fin('render enlaces 118',sin_checks='esta cuenta no puede crear un symlink de fichero (%s)' % e)
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
        d=preview('DUMMY_inline.dfm','child-'+mode,component='F.DUMMYLabel')
        mc.check(mode+' PAS aporta frame solo sin enlace',
          r.get('root',{}).get('kind')==('frame' if mode=='normal' else 'form'),r)
        # (revisor de baterias, 18-oct-2026) un preview que FALLA tampoco trae
        # componentRect: en modo link pasaba con cualquier error
        if mode=='normal':
            mc.check('normal DFM aporta componente sin enlace (el preview sale con su rectangulo)',
              'error' not in d and bool(d.get('componentRect')),d)
        else:
            mc.check('link DFM con enlace no aporta el componente: DSGN-066, sin rectangulo',
              mc.es(str(d.get('error','')),'SR_DESIGNER_PREVIEW_SIN_COMPONENTE_FMT') and not d.get('componentRect'),d)
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
