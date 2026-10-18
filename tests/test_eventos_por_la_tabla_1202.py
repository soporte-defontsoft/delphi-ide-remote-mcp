# -*- coding: utf-8 -*-
"""Que una linea de un form es un EVENTO lo decidia el nombre: 'On' delante
(Lsp.DesignerBinding, EVENT_LINE_RE). Los eventos de un TDataSet (AfterOpen,
BeforePost...) y los de un TWebModule (BeforeDispatch) no empiezan por On, y
el juez estaba en casa: la tabla del marco sabe que propiedad es un metodo
(Kind 'm'; info los lista aparte). Medido el 18-oct-2026 en produccion, con un
TFDMemTable y AfterOpen = FDMemTable1AfterOpen: check-binding daba clean sin
el manejador y con el manejador en public (el form no carga: el streaming solo
resuelve published), e insert=metodo lo dejaba en public. Ahora lo dice la
tabla por la clase del objeto (la raiz, por la que la juzga); el nombre solo
donde la tabla no sabe (un item de una coleccion, una clase que no tiene).

  E1 check-binding sin manejadores: avisa AfterOpen (ROJO en produccion) y el
     control OnTimer; DataSet = FDMemTable1 (una referencia) no es un evento
  E2 el manejador de AfterOpen en public: eventsWithMethodNotPublished (ROJO)
  E3 insert=metodo de ese manejador sin visibility: va a published y lo dice
     (ROJO: a public)
  E4 delete del FDMemTable1 con su manejador vacio (AlAbrir: un nombre que
     no lleva el del componente, que el analizador ya cuenta por el nombre):
     se lo lleva (ROJO: se quedaba huerfano)
  E5 la raiz es un TWebModule: BeforeDispatch sin manejador se avisa (ROJO)

Uso:  python tests/test_eventos_por_la_tabla_1202.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('eventos_tabla_1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

DFM = ("object FormE: TFormE\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'E'\r\n  ClientHeight = 200\r\n"
       "  ClientWidth = 300\r\n  TextHeight = 15\r\n"
       "  object FDMemTable1: TFDMemTable\r\n    AfterOpen = FDMemTable1AfterOpen\r\n    Left = 40\r\n"
       "    Top = 40\r\n  end\r\n"
       "  object DataSource1: TDataSource\r\n    DataSet = FDMemTable1\r\n    Left = 80\r\n    Top = 40\r\n  end\r\n"
       "  object Timer1: TTimer\r\n    OnTimer = Timer1Timer\r\n    Left = 120\r\n    Top = 40\r\n  end\r\nend\r\n")
PAS = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, "
       "Vcl.ExtCtrls, Data.DB,\r\n  FireDAC.Comp.Client;\r\n\r\ntype\r\n  TFormE = class(TForm)\r\n"
       "    FDMemTable1: TFDMemTable;\r\n    DataSource1: TDataSource;\r\n    Timer1: TTimer;\r\n{publicados}"
       "  private\r\n  public\r\n{publicos}  end;\r\n\r\nvar\r\n  FormE: TFormE;\r\n\r\nimplementation\r\n\r\n"
       "{$R *.dfm}\r\n\r\n{cuerpos}end.\r\n")
WEB_DFM = ("object WebModule1: TWebModule1\r\n  OldCreateOrder = False\r\n"
           "  BeforeDispatch = WebModule1BeforeDispatch\r\n  Actions = <>\r\n  Height = 230\r\n  Width = 415\r\nend\r\n")
WEB_PAS = ("unit UWeb;\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Classes, Web.HTTPApp;\r\n\r\n"
           "type\r\n  TWebModule1 = class(TWebModule)\r\n  private\r\n  public\r\n  end;\r\n\r\nvar\r\n"
           "  WebModule1: TComponentClass = TWebModule1;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n")
CUERPO = 'procedure TFormE.{m}({a});\r\nbegin\r\nend;\r\n\r\n'


def form(nombre, publicados='', publicos='', cuerpos='', abre='FDMemTable1AfterOpen'):
    p = os.path.join(JAIL, nombre + '.dfm')
    open(p, 'wb').write(DFM.replace('AfterOpen = FDMemTable1AfterOpen', 'AfterOpen = ' + abre).encode('utf-8'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(
        PAS.replace('{u}', nombre).replace('{publicados}', publicados).replace('{publicos}', publicos)
        .replace('{cuerpos}', cuerpos).encode('utf-8'))
    return p


def lista(d, clave):
    return ' | '.join(d.get(clave) or [])


DECL_ABRE = '    procedure FDMemTable1AfterOpen(DataSet: TDataSet);\r\n'
DECL_TIMER = '    procedure Timer1Timer(Sender: TObject);\r\n'
CUERPOS = (CUERPO.replace('{m}', 'FDMemTable1AfterOpen').replace('{a}', 'DataSet: TDataSet') +
           CUERPO.replace('{m}', 'Timer1Timer').replace('{a}', 'Sender: TObject'))

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='eventos-tabla', t=240)
try:
    # el juez es la tabla: tiene que estar
    for fw, r in mc.espera_tablas(srv.call):
        check('E0 la tabla %s esta lista' % fw, not mc.tiene(r, 'DSGN-051') and not mc.fallo(r), r[:200])

    p = form('UE1')
    d = mc.como_json(srv.call('delphi_designer', {'command': 'check-binding', 'path': p}))
    sin = lista(d, 'eventsWithoutMethod')
    check('E1 check-binding sin manejadores: AfterOpen se avisa, y OnTimer (el control); DataSet no es un evento',
          d.get('clean') is False and 'FDMemTable1AfterOpen' in sin and 'Timer1Timer' in sin and
          'DataSet' not in sin, d)

    p = form('UE2', publicados=DECL_TIMER, publicos=DECL_ABRE, cuerpos=CUERPOS)
    d = mc.como_json(srv.call('delphi_designer', {'command': 'check-binding', 'path': p}))
    check('E2 el manejador de AfterOpen en public: eventsWithMethodNotPublished',
          d.get('clean') is False and 'FDMemTable1AfterOpen' in lista(d, 'eventsWithMethodNotPublished'), d)

    p = form('UE3', publicados=DECL_TIMER,
             cuerpos=CUERPO.replace('{m}', 'Timer1Timer').replace('{a}', 'Sender: TObject'))
    pas = p[:-4] + '.pas'
    r = srv.call('delphi_edit', {'path': pas, 'insert': 'metodo', 'inclass': 'TFormE',
                                 'code': 'procedure FDMemTable1AfterOpen(DataSet: TDataSet);\r\nbegin\r\nend;'})
    src = open(pas, 'rb').read().decode('utf-8')
    check('E3 insert=metodo del manejador de AfterOpen sin visibility: a published, y lo dice',
          mc.es(r, 'SN_PATCH_INSERT_PUBLISHED_BY_EVENT_FMT') and
          0 <= src.find('procedure FDMemTable1AfterOpen') < src.find('  private'), r[:500])

    # el manejador NO lleva el nombre del componente: el analizador ya cuenta
    # como suyos los que lo llevan, y el check pasaba en produccion por eso
    p = form('UE4', abre='AlAbrir', publicados=DECL_ABRE.replace('FDMemTable1AfterOpen', 'AlAbrir') + DECL_TIMER,
             cuerpos=CUERPOS.replace('FDMemTable1AfterOpen', 'AlAbrir'))
    pas = p[:-4] + '.pas'
    r = srv.call('delphi_designer', {'command': 'delete', 'path': p, 'component': 'FDMemTable1'}, t=240)
    src = open(pas, 'rb').read().decode('utf-8')
    check('E4 delete del FDMemTable1: se lleva su manejador vacio de AfterOpen, AlAbrir (y deja el del Timer1)',
          not mc.fallo(r) and 'AlAbrir' in lista(mc.como_json(r), 'handlersRemoved') and
          'AlAbrir' not in src and 'Timer1Timer' in src, r[:600])

    pw = os.path.join(JAIL, 'UWeb.dfm')
    open(pw, 'wb').write(WEB_DFM.encode('utf-8'))
    open(os.path.join(JAIL, 'UWeb.pas'), 'wb').write(WEB_PAS.encode('utf-8'))
    d = mc.como_json(srv.call('delphi_designer', {'command': 'check-binding', 'path': pw}))
    check('E5 la raiz es un TWebModule: BeforeDispatch sin manejador se avisa',
          d.get('clean') is False and 'WebModule1BeforeDispatch' in lista(d, 'eventsWithoutMethod'), d)
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('un evento por la tabla, no por el nombre 1202')
