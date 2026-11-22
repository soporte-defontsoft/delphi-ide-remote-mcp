# -*- coding: utf-8 -*-
"""D7 de la 1.29.3 (un agente, 16-nov): delphi_designer preview component=X de un form FMX recortaba la caja de X
aunque X no se dibujase, y no decia nada. El panel tenia Visible = False (lo abre un boton) y una rejilla con
Align=Client que va DESPUES se pintaba en su sitio: el agente dio por buena "su card dorada", que era la rejilla. La
preview es fiel (el IDE tampoco dibuja un oculto: TControl.ShowInDesigner); lo que faltaba era DECIRLO. Ahora las
cajas del MISMO render (el ayudante da cajas e imagen juntas desde el protocolo 16) y los jueces de layout (OcultoEn,
PuedeSolaparse, LoPisa) dan componentNote.

  T1 component=pnlOculto (Visible = False): componentNote DSGN-200 lo dice y da el state= que lo pinta, y el recorte
     sale igual (ROJO: sin nota)
  T2 component=pnlTapado, con recTapa DESPUES encima: componentNote DSGN-201 nombra recTapa con su linea (ROJO)
  T3 control: component=pnlLibre: ni nota ni nada nuevo
  T4 control: state=pnlOculto.Visible=True component=pnlOculto: se pinta, sin nota
  T5 layout igual que antes (OcultoEn, PuedeSolaparse y LoPisa salieron de JuzgaCajas): pnlOculto visible false en
     boxes, y pnlTapado y recTapa en overlapping
  T6 un nieto de un oculto (lblDentro dentro de pnlOculto): la nota nombra al PADRE oculto

Uso:  python tests/test_preview_componente_1293.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('preview_componente_1293')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

FMX = ("object FormP: TFormP\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'P'\r\n  ClientHeight = 200\r\n"
       "  ClientWidth = 400\r\n  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n"
       "  FormFactor.Devices = [Desktop]\r\n  DesignerMasterStyle = 0\r\n"
       "  object pnlOculto: TPanel\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    Size.Width = 100.000000000000000000\r\n"
       "    Size.Height = 60.000000000000000000\r\n    Size.PlatformDefault = False\r\n    Visible = False\r\n"
       "    TabOrder = 0\r\n    object lblDentro: TLabel\r\n      Position.X = 5.000000000000000000\r\n"
       "      Position.Y = 5.000000000000000000\r\n      Text = 'dentro'\r\n      TabOrder = 0\r\n    end\r\n  end\r\n"
       "  object pnlTapado: TPanel\r\n    Position.X = 130.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    Size.Width = 100.000000000000000000\r\n"
       "    Size.Height = 60.000000000000000000\r\n    Size.PlatformDefault = False\r\n    TabOrder = 1\r\n  end\r\n"
       "  object pnlLibre: TPanel\r\n    Position.X = 260.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    Size.Width = 100.000000000000000000\r\n"
       "    Size.Height = 60.000000000000000000\r\n    Size.PlatformDefault = False\r\n    TabOrder = 2\r\n  end\r\n"
       "  object recTapa: TRectangle\r\n    Fill.Color = xFFE04040\r\n    Position.X = 120.000000000000000000\r\n"
       "    Position.Y = 0.000000000000000000\r\n    Size.Width = 130.000000000000000000\r\n"
       "    Size.Height = 90.000000000000000000\r\n    Size.PlatformDefault = False\r\n  end\r\nend\r\n")
PAS = ("unit UPrev;\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Types, System.UITypes, System.Classes,\r\n"
       "  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.StdCtrls, FMX.Objects, FMX.Controls.Presentation;\r\n"
       "\r\ntype\r\n  TFormP = class(TForm)\r\n    pnlOculto: TPanel;\r\n    lblDentro: TLabel;\r\n    pnlTapado: TPanel;\r\n"
       "    pnlLibre: TPanel;\r\n    recTapa: TRectangle;\r\n  end;\r\n\r\nvar\r\n  FormP: TFormP;\r\n\r\nimplementation\r\n"
       "\r\n{$R *.fmx}\r\n\r\nend.\r\n")
FORM = os.path.join(JAIL, 'UPrev.fmx')
open(FORM, 'wb').write(b'\xef\xbb\xbf' + FMX.encode('utf-8'))
open(os.path.join(JAIL, 'UPrev.pas'), 'wb').write(PAS.encode('utf-8'))
LINEA_RECTAPA = FMX.split('\r\n').index('  object recTapa: TRectangle') + 1
LINEA_OCULTO = FMX.split('\r\n').index('  object pnlOculto: TPanel') + 1


def preview(comp, estado=None, n=[0]):
    n[0] += 1
    args = {'command': 'preview', 'path': FORM, 'component': comp, 'inline': 'false',
            'out': os.path.join(JAIL, 'p%d.png' % n[0])}
    if estado:
        args['state'] = estado
    r = srv.call('delphi_designer', args, t=300)
    return r, (mc.como_json(r) or {}), args['out']


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='preview-componente', t=300)
try:
    r, j, png = preview('pnlOculto')
    nota = j.get('componentNote', '')
    check('T1 component=pnlOculto (Visible = False): componentNote DSGN-200 con su linea y el state= que lo pinta,'
          ' y el recorte sale (ROJO: sin nota)',
          mc.abre(nota, 'SN_DSGN_PREVIEW_OCULTO_FMT') and 'state=pnlOculto.Visible=True' in nota
          and ('line %d' % LINEA_OCULTO) in nota and os.path.isfile(png), (nota, r[:400]))
    r, j, png = preview('pnlTapado')
    nota = j.get('componentNote', '')
    check('T2 component=pnlTapado, recTapa despues y encima: DSGN-201 nombra recTapa con su linea (ROJO)',
          mc.abre(nota, 'SN_DSGN_PREVIEW_TAPADO_FMT') and ('recTapa (line %d)' % LINEA_RECTAPA) in nota
          and 'state=recTapa.Visible=False' in nota and os.path.isfile(png), (nota, r[:400]))
    r, j, png = preview('pnlLibre')
    check('T3 control: component=pnlLibre, ni nota y el recorte sale', 'componentNote' not in j and os.path.isfile(png),
          r[:400])
    r, j, png = preview('pnlOculto', 'pnlOculto.Visible=True')
    check('T4 control: state=pnlOculto.Visible=True lo pinta: sin nota', 'componentNote' not in j and os.path.isfile(png),
          r[:400])
    r, j, png = preview('lblDentro')
    nota = j.get('componentNote', '')
    check('T6 un nieto de un oculto: la nota nombra al PADRE oculto, pnlOculto',
          mc.abre(nota, 'SN_DSGN_PREVIEW_OCULTO_FMT') and 'state=pnlOculto.Visible=True' in nota, (nota, r[:400]))
    rl = srv.call('delphi_designer', {'command': 'layout', 'path': FORM}, t=300)
    jl = mc.como_json(rl) or {}
    cajas = {b.get('name'): b for b in (jl.get('boxes') or [])}
    solapes = ' '.join(jl.get('overlapping') or [])
    check('T5 layout igual que antes: pnlOculto visible false, y pnlTapado y recTapa en overlapping',
          cajas.get('pnlOculto', {}).get('visible') is False and 'pnlTapado' in solapes and 'recTapa' in solapes,
          rl[:900])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('preview component= que no es lo que se ve 1.29.3 (D7)')
