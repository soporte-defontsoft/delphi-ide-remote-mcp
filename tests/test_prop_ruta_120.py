# -*- coding: utf-8 -*-
"""delphi_designer prop con una ruta con punto, y el enlace a la clase (1.20).

Medido en las rondas del 27B de Hermes (16-oct, encargo dirigido de la 1.20,
lo de Hermes aparte): tras DSGN-087 por Alignment en un TLabel FMX, el modelo
adivino bien TextSettings.HorzAlign y, ANTES de escribirlo, lo pregunto con
prop -> "TextSettings.HorzAlign is not a published property of TLabel", que
set escribe sin rechistar. prop buscaba la propiedad solo en el primer nivel
de la clase, y no con EL juez de set (JuzgaPropiedad), que baja por la
propiedad objeto y por la descendiente que guarda la instancia
(TLabelTextSettings). Lo mismo en VCL con Font.Size. El agente que preguntaba
antes de escribir salia peor parado que el que no (Flash: 1 llamada; el 27B:
7 y una pausa de su puente).

Y lo que pidio David, como el enlace de la ayuda de Delphi: una propiedad que
es un objeto dice que su clase se pregunta con info, y la lista cortada de
"it publishes: ..." enlaza con la entera. Sin equivalencias entre marcos.

  P1  prop TLabel fmx TextSettings.HorzAlign: TTextAlign con sus valores
      (ROJO en produccion: DSGN-016)
  P2  prop TLabel vcl Font.Size: la hoja, no DSGN-016
  P3  prop TLabel fmx TextSettings: un objeto, DSGN-155 con el enlace a info
      de TTextSettings y "set writes them dotted"
  P4  prop TLabel fmx Alignment: DSGN-016 con las palabras del juez, la pista
      del TLabel de la VCL y el enlace a la lista entera
  P5  prop TLabel fmx TextSettings.Foo120: lo que no publica nadie de la familia
  P6  control: prop TButton vcl Caption sigue igual (una hoja de primer nivel)
  P7  control: prop TLabel fmx FontColor (guardado por codigo, el juez calla):
      el DSGN-016 de antes
  P8  set Alignment en un form FMX: el enlace a la lista entera tambien ahi
  P9  el enlace lleva a algo: info TLabel fmx trae TextSettings kind=class, y
      su nota explica el enlace
  P10 lo que prop dice que existe, set lo escribe: TextSettings.HorzAlign
  P11 prop TButton vcl PopupMenu: una REFERENCIA a un componente, sin DSGN-155
      (0c0dfcd le decia "set writes them dotted": EsObjetoPropio, la regla de set)
  P12 info TLabel fmx filter=Horz: TextSettings.HorzAlign un nivel por dentro
      (decia "no such member": en el 27B acabo en HorzTextAlign, la vieja)
  P13 info TButton vcl filter=AutoPopup: una referencia no se abre (DSGN-048)
  P14 info TLabel vcl filter=Size: Font.Size, tambien en VCL
  P15 control: info TLabel fmx sin filtro, solo el primer nivel
  P16 info TTextSettings fmx filter=color: la clase no publica nada y su familia
      si, y el filtro lo encuentra (decia "no such member" junto a un
      descendantsPublish con FontColor; DSGN-155 manda ahi: Flash, 16-oct)

Uso:  python tests/test_prop_ruta_120.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('prop_ruta_120')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

FMX = ("object FormF: TFormF\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'F'\r\n  ClientHeight = 480\r\n"
       "  ClientWidth = 640\r\n  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n"
       "  FormFactor.Devices = [Desktop]\r\n  DesignerMasterStyle = 0\r\n"
       "  object Label1: TLabel\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    Text = 'Label1'\r\n  end\r\nend\r\n")
PAS_FMX = ("unit UF;\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Types, System.UITypes, "
           "System.Classes, System.Variants,\r\n  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, "
           "FMX.StdCtrls, FMX.Controls.Presentation;\r\n\r\ntype\r\n"
           "  TFormF = class(TForm)\r\n    Label1: TLabel;\r\n"
           "  end;\r\n\r\nvar\r\n  FormF: TFormF;\r\n\r\nimplementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n")


def plano(r):
    """La respuesta con las comillas como las escribe el servidor (en una
    respuesta JSON van escapadas)."""
    return (r or '').replace('\\"', '"')


def prop(clase, fw, p):
    return plano(srv.call('delphi_designer', {'command': 'prop', 'classname': clase, 'framework': fw, 'prop': p}))


ENLACE_TLABEL_FMX = ' - all, with their types: info classname=TLabel framework=fmx'

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='prop-ruta', t=240)
try:
    # la pista pregunta a la tabla del OTRO marco sin esperar: tienen que estar
    for fw, r in mc.espera_tablas(srv.call):
        check('P0 la tabla %s esta lista' % fw, mc.tabla_lista(r), r[:200])

    pf = os.path.join(JAIL, 'UF.fmx')
    open(pf, 'wb').write(b'\xef\xbb\xbf' + FMX.encode('utf-8'))
    open(os.path.join(JAIL, 'UF.pas'), 'wb').write(PAS_FMX.encode('utf-8'))

    r = prop('TLabel', 'fmx', 'TextSettings.HorzAlign')
    check('P1 prop TLabel fmx TextSettings.HorzAlign: TTextAlign con Trailing',
          not mc.fallo(r) and '"type":"TTextAlign"' in r and 'Trailing' in r
          and '"property":"TextSettings.HorzAlign"' in r, r[:500])

    r = prop('TLabel', 'vcl', 'Font.Size')
    check('P2 prop TLabel vcl Font.Size: la hoja, no DSGN-016',
          not mc.fallo(r) and not mc.es(r, 'SR_DESIGNER_PROP_FMT') and '"property":"Font.Size"' in r, r[:500])

    r = prop('TLabel', 'fmx', 'TextSettings')
    check('P3 prop TLabel fmx TextSettings: un objeto, con el enlace a info de su clase',
          not mc.fallo(r) and '"kind":"class"' in r and mc.tiene(r, 'DSGN-155')
          and 'command=info classname=TTextSettings framework=fmx' in r
          and '(TextSettings.<property>)' in r, r[:600])

    r = prop('TLabel', 'fmx', 'Alignment')
    check('P4 prop TLabel fmx Alignment: el juez, la pista de la VCL y el enlace a la lista entera',
          mc.tiene(r, 'DSGN-016')
          and 'Alignment is not a published property of TLabel: "Alignment" does not exist in TLabel' in r
          and '"Alignment" is what the VCL TLabel publishes' in r and ENLACE_TLABEL_FMX in r, r[:900])

    r = prop('TLabel', 'fmx', 'TextSettings.Foo120')
    check('P5 prop TLabel fmx TextSettings.Foo120: no lo publica nadie de la familia',
          mc.tiene(r, 'DSGN-016') and 'nor in any class that descends from it' in r, r[:700])

    r = prop('TButton', 'vcl', 'Caption')
    check('P6 control: prop TButton vcl Caption, una hoja de primer nivel, igual que antes',
          not mc.fallo(r) and '"property":"Caption"' in r and '"type":"TCaption"' in r, r[:500])

    r = prop('TLabel', 'fmx', 'FontColor')
    check('P7 control: FontColor del TLabel FMX (guardado por codigo): el DSGN-016 de antes',
          mc.tiene(r, 'DSGN-016') and 'FontColor is not a published property of TLabel' in r, r[:500])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Label1',
                                           'prop': 'Alignment', 'value': 'taRightJustify'}))
    check('P8 set Alignment en un form FMX: el enlace a la lista entera tambien en set',
          mc.tiene(r, 'DSGN-087') and ENLACE_TLABEL_FMX in r, r[:900])

    r = plano(srv.call('delphi_designer', {'command': 'info', 'classname': 'TLabel', 'framework': 'fmx'}))
    check('P9 el enlace lleva a algo: info TLabel fmx trae TextSettings como clase, y la nota lo explica',
          '{"name":"TextSettings","kind":"class","type":"TTextSettings"}' in r
          and 'A property of kind class whose type is not a component is an object' in r, r[-700:])

    r = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Label1',
                                           'prop': 'TextSettings.HorzAlign', 'value': 'Trailing'}))
    check('P10 lo que prop dice que existe, set lo escribe',
          not mc.fallo(r) and 'TextSettings.HorzAlign = Trailing' in open(pf, 'rb').read().decode('utf-8-sig'),
          r[:500])

    r = prop('TButton', 'vcl', 'PopupMenu')
    check('P11 prop TButton vcl PopupMenu: una referencia, sin el enlace de los objetos (DSGN-155)',
          not mc.fallo(r) and '"kind":"class"' in r and not mc.es(r, 'SN_DESIGNER_PROP_CLASE_FMT') and 'dotted' not in r,
          r[:500])

    def info(clase, fw, filtro=None):
        a = {'command': 'info', 'classname': clase, 'framework': fw}
        if filtro:
            a['filter'] = filtro
        return plano(srv.call('delphi_designer', a))

    r = info('TLabel', 'fmx', 'Horz')
    check('P12 info TLabel fmx filter=Horz: TextSettings.HorzAlign por dentro, sin DSGN-048',
          '{"name":"TextSettings.HorzAlign","kind":"enum","type":"TTextAlign"}' in r
          and not mc.es(r, 'SN_DESIGNER_INFO_FILTRO_VACIO_FMT'), r[:700])

    r = info('TButton', 'vcl', 'AutoPopup')
    check('P13 info TButton vcl filter=AutoPopup: PopupMenu es una referencia y no se abre',
          'PopupMenu.AutoPopup' not in r and mc.tiene(r, 'DSGN-048'), r[:700])

    r = info('TLabel', 'vcl', 'Size')
    check('P14 info TLabel vcl filter=Size: Font.Size, tambien en VCL',
          '"name":"Font.Size"' in r, r[:700])

    r = info('TLabel', 'fmx')
    check('P15 control: info sin filtro, solo el primer nivel (nada con punto)',
          '"name":"TextSettings"' in r and '"name":"TextSettings.' not in r, r[:300])

    r = info('TTextSettings', 'fmx', 'color')
    check('P16 info TTextSettings fmx filter=color: FontColor de su familia, sin DSGN-048',
          '"name":"FontColor"' in r and not mc.es(r, 'SN_DESIGNER_INFO_FILTRO_VACIO_FMT') and 'descendantsPublish' in r, r[:700])

    # 1.20.1: prop de un entero con constantes dice lo que toma, con EL texto
    # que da set al negar (LoQueToma). Decia solo el tipo y Flash tuvo que
    # provocar DSGN-093 para saber cla*/cl*/xNN
    r = r17 = prop('TLabel', 'fmx', 'TextSettings.FontColor')
    check('P17 prop TLabel fmx TextSettings.FontColor (TAlphaColor): takes con sus nombres y la forma x+hexadecimal',
          not mc.fallo(r) and '"takes":' in r and 'claAliceblue' in r and 'xFF00FF00' in r, r[:900])
    r = prop('TLabel', 'vcl', 'Font.Color')
    check('P18 prop TLabel vcl Font.Color (TColor): takes con sus constantes con nombre',
          not mc.fallo(r) and '"takes":' in r and 'named constants' in r, r[:900])
    t = plano(srv.call('delphi_designer', {'path': pf, 'command': 'set', 'component': 'Label1',
                                           'prop': 'TextSettings.FontColor', 'value': 'Rojo'}))
    toma = mc.como_json(r17).get('takes', '')
    check('P19 ...y es EL mismo texto que da set al negar un valor (Rojo en el TAlphaColor de un form FMX)',
          mc.tiene(t, 'DSGN-093') and toma != '' and toma in t, (toma[:200], t[:600]))
    r = prop('TLabel', 'fmx', 'TextSettings.HorzAlign')
    # contesta, y es el enumerado (sin takes); "no lleva takes" sobre un error
    # pasaba (revisor de baterias, 18-oct-2026)
    check('P20 control: un enumerado no lleva takes (sus members ya lo dicen)',
          not mc.fallo(r) and 'TTextAlign' in r and '"takes"' not in r, r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('prop con una ruta con punto, el enlace a la clase y el filtro por dentro 120 (DSGN-016, DSGN-155, DSGN-048)')
