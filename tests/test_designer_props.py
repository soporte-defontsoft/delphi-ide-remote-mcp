# -*- coding: utf-8 -*-
"""delphi_designer con VARIAS propiedades de una vez: props (3.10 de la 1.18.0;
replica de Hermes: copiar un form era un insert y un set por propiedad). Cada
una se juzga como set juzga una, todas en memoria y UNA escritura - todo o
nada -, y el resultado pasa por el parser del IDE (9.B).

  Q1  set props: dos propiedades de Button1 en una llamada, las dos escritas
  Q2  ...todo o nada: con una que no existe, ninguna (DSGN-129 nombra la entrada)
  Q3  un ';' dentro de un valor entre comillas no parte la entrada
  Q4  insert con props: el bloque nace con ellas (Text, Position.X como el IDE)
  Q5  ...todo o nada: con una mala no se escribe ni el form ni la unidad
  Q6  la sintaxis: Name va solo (DSGN-130), una propiedad dos veces (DSGN-131),
      props con prop/value (DSGN-132), una entrada sin '=' (DSGN-128)
  Q7  revisor 2 de la noche, M-A: una comilla que no EMPIEZA el valor es una
      letra (Don't save): no se traga la entrada de detras; uno que se abre y
      no se cierra, DSGN-134 y nada escrito
  Q8  B-3: solo nil sobre referencias que no estan no reescribe el form
      (DSGN-112, como set de una); insert con un nil lo dice en su entrada

Uso:  python tests/test_designer_props.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_props')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
FMX = os.path.join(JAIL, 'UProps.fmx')
PAS = os.path.join(JAIL, 'UProps.pas')
open(FMX, 'wb').write(b'object Form1: TForm1\r\n'
                      b'  Caption = \'Form1\'\r\n'
                      b'  ClientHeight = 200\r\n'
                      b'  ClientWidth = 300\r\n'
                      b'  object Button1: TButton\r\n'
                      b'    Position.X = 10.000000000000000000\r\n'
                      b'    Position.Y = 10.000000000000000000\r\n'
                      b'    TabOrder = 0\r\n'
                      b'    Text = \'Button1\'\r\n'
                      b'  end\r\n'
                      b'end\r\n')
open(PAS, 'wb').write(b'unit UProps;\r\n\r\ninterface\r\n\r\nuses\r\n'
                      b'  System.Classes, FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls;\r\n\r\n'
                      b'type\r\n  TForm1 = class(TForm)\r\n    Button1: TButton;\r\n  end;\r\n\r\n'
                      b'var\r\n  Form1: TForm1;\r\n\r\nimplementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n')


def bytes_de(p):
    return open(p, 'rb').read()


def J(r):
    try:
        return json.loads(r)
    except Exception:
        return {}


EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-props', t=300)
try:
    def dsg(args):
        return srv.call('delphi_designer', dict({'path': FMX}, **args), t=240)

    r = dsg({'command': 'set', 'component': 'Button1', 'props': 'Text=Uno;Opacity=0.5'})
    f = bytes_de(FMX)
    check('Q1 set props: dos propiedades en una llamada, las dos escritas',
          not mc.fallo(r) and b"Text = 'Uno'" in f and b'Opacity = 0.5' in f and '"props"' in r, r[:400])
    antes = bytes_de(FMX)
    r = dsg({'command': 'set', 'component': 'Button1', 'props': 'Text=Dos;Inventada=3'})
    check('Q2 ...todo o nada: con una propiedad que no existe no se escribe ninguna (DSGN-129, entrada 2)',
          mc.abre(r, 'SR_DESIGNER_PROPS_ENTRADA_FMT') and 'entry 2' in r and bytes_de(FMX) == antes, r[:400])
    r = dsg({'command': 'set', 'component': 'Button1', 'props': "Text='a;b';Opacity=0.7"})
    f = bytes_de(FMX)
    check("Q3 un ';' dentro de un valor entre comillas no parte la entrada",
          not mc.fallo(r) and b"Text = 'a;b'" in f and b'Opacity = 0.6999' in f, r[:400])  # un Single como el IDE

    pas_antes = bytes_de(PAS)
    r = dsg({'command': 'insert', 'classname': 'TLabel', 'component': 'Etiqueta1',
             'props': 'Text=Hola;Position.X=40'})
    f = bytes_de(FMX)
    check('Q4 insert con props: el bloque nace con ellas (Position.X con sus 18 decimales, como el IDE)',
          not mc.fallo(r) and b'object Etiqueta1: TLabel' in f and b"Text = 'Hola'" in f and
          b'Position.X = 40.000000000000000000' in f and b'Etiqueta1: TLabel;' in bytes_de(PAS), r[:500])
    antes, pas_antes = bytes_de(FMX), bytes_de(PAS)
    r = dsg({'command': 'insert', 'classname': 'TLabel', 'component': 'Etiqueta2',
             'props': 'Text=Mal;Inventada=1'})
    check('Q5 ...todo o nada: con una propiedad mala no se escribe ni el form ni la unidad',
          mc.abre(r, 'SR_DESIGNER_PROPS_ENTRADA_FMT') and bytes_de(FMX) == antes and bytes_de(PAS) == pas_antes,
          r[:400])

    antes = bytes_de(FMX)
    malos = [dsg({'command': 'set', 'component': 'Button1', 'props': 'Name=Otro'}),
             dsg({'command': 'set', 'component': 'Button1', 'props': 'Text=a;Text=b'}),
             dsg({'command': 'set', 'component': 'Button1', 'props': 'Text=a', 'prop': 'Opacity', 'value': '1'}),
             dsg({'command': 'set', 'component': 'Button1', 'props': 'Text'})]
    check('Q6 la sintaxis: Name solo (130), dos veces (131), con prop/value (132), sin = (128); nada escrito',
          mc.abre(malos[0], 'SR_DESIGNER_PROPS_NAME_FMT') and mc.abre(malos[1], 'SR_DESIGNER_PROPS_DOBLE_FMT') and
          mc.abre(malos[2], 'SR_DESIGNER_PROPS_SOLO') and mc.abre(malos[3], 'SR_DESIGNER_PROPS_PAR_FMT') and
          bytes_de(FMX) == antes, [m[:120] for m in malos])

    r = dsg({'command': 'set', 'component': 'Button1', 'props': "Text=Don't save;Opacity=0.25"})
    f = bytes_de(FMX)
    check("Q7 un apostrofo en un valor sin comillas (Don't save) es una letra: las dos entradas se escriben",
          not mc.fallo(r) and b"Text = 'Don'#39't save'" in f and b'Opacity = 0.25' in f, r[:400])  # el compositor: #39
    antes = bytes_de(FMX)
    r = dsg({'command': 'set', 'component': 'Button1', 'props': "Text='abierta;Opacity=0.5"})
    check('Q7 ...un literal que se abre y no se cierra: DSGN-134 y nada escrito',
          mc.abre(r, 'SR_DESIGNER_COMILLA_SIN_CERRAR_FMT') and bytes_de(FMX) == antes, r[:400])

    antes = bytes_de(FMX)
    r = dsg({'command': 'set', 'component': 'Button1', 'props': 'PopupMenu=nil'})
    # la respuesta ES la nota (abre con ella), no un set con la nota dentro: con
    # el bloque que no escribe quitado, el JSON tambien la llevaba y reescribir
    # daba los mismos bytes (revisor 3, B-1: el check era una guarda)
    check('Q8 solo nil sobre una referencia que no esta: DSGN-112 y el form NO se reescribe (B-3)',
          mc.abre(r, 'SN_DESIGNER_NADA_QUE_QUITAR_FMT') and not r.lstrip().startswith('{') and
          bytes_de(FMX) == antes, r[:400])
    r = dsg({'command': 'insert', 'classname': 'TLabel', 'component': 'Etiqueta3',
             'props': 'Text=Tres;PopupMenu=nil'})
    props = [p for p in (J(r).get('props') or []) if p.get('prop') == 'PopupMenu']
    check('Q8 ...insert con un nil que no hay que quitar: su entrada lo dice (DSGN-112), no value nil',
          not mc.fallo(r) and len(props) == 1 and 'value' not in props[0] and
          mc.es(props[0].get('note', ''), 'SN_DESIGNER_NADA_QUE_QUITAR_FMT'), r[:500])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('designer props')
