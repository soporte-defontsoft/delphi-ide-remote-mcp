# -*- coding: utf-8 -*-
"""delphi_designer set before= / after= / index=: el ORDEN de un componente entre
sus hermanos (3.11 de la 1.18.0; replica de Hermes), SOLO donde el IDE lo guarda:
se le pregunta al juez (el renderizador carga la propuesta como el designer y
TWriter la escribe) - nada de listas propias de que va delante de que (norma 6;
revisor 4 de la noche, M5: la primera version imitaba al juez y se desviaba en
un TToolBar, en una form heredada con [n]...).

  O1  VCL before=: Button2 delante de Button1 (el IDE lo guarda)
  O2  VCL index= (entre TODOS los hermanos)
  O3  lo que el IDE no guardaria se niega con SU orden (DSGN-136): un TLabel tras
      un TButton, un TTimer delante, un TLabel tras el TTimer; nada escrito
  O4  no hermanos y la raiz (DSGN-137), index fuera e index=0 (DSGN-138), ya en su
      sitio (DSGN-141), si mismo (DSGN-139), dos a la vez o con prop (DSGN-135)
  O5  el resultado lo lee el parser del IDE y un bloque con hijos se mueve entero
  O6  TToolBar: un control delante de un boton SE guarda (M2 del revisor 4)
  O7  form heredada: un nuevo delante del que lleva [0] no se sostiene (M1)
  O8  un hermano de una clase que ningun paquete carga: DSGN-140
  F1  FMX: un TTimer tras un TButton se guarda
  F2  FMX index=
  F3  FMX: un TActionList (no TFmxObject) delante de un TButton se niega
  O9-O14  los arreglos del revisor 5: un hermano con acento (A1), un fichero que
      ya no estaba en el orden del IDE (M3), --folder trae el ancestro (M4), un
      ancestro en otra carpeta (A2, DSGN-143), un PADRE sin paquete (M2), un
      bloque con hijos (B4)
  O16 el form cambia mientras juzga el renderizador: DSGN-144 (A3)
  O17-O19 los arreglos del revisor 6: la referencia cuenta siempre y index es
      una posicion (A1); un ancestro sin leer niega aunque no falte nadie (A2)
  O20 el form se borra mientras juzga el renderizador: DSGN-144 (revisor 6, B2)
  O15 no queda ninguna carpeta __tmp- (B5)

Uso:  python tests/test_designer_orden.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_orden')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
DFM = os.path.join(JAIL, 'UOrden.dfm')
open(DFM, 'wb').write(b'object Form1: TForm1\r\n'
                      b'  Left = 0\r\n'
                      b'  Top = 0\r\n'
                      b"  Caption = 'Form1'\r\n"
                      b'  ClientHeight = 200\r\n'
                      b'  ClientWidth = 300\r\n'
                      b'  object Label1: TLabel\r\n'
                      b'    Left = 8\r\n'
                      b'    Top = 8\r\n'
                      b"    Caption = 'L'\r\n"
                      b'  end\r\n'
                      b'  object Button1: TButton\r\n'
                      b'    Left = 8\r\n'
                      b'    Top = 40\r\n'
                      b'    TabOrder = 0\r\n'
                      b'  end\r\n'
                      b'  object Panel1: TPanel\r\n'
                      b'    Left = 100\r\n'
                      b'    Top = 40\r\n'
                      b'    TabOrder = 1\r\n'
                      b'    object Button3: TButton\r\n'
                      b'      Left = 4\r\n'
                      b'      Top = 4\r\n'
                      b'      TabOrder = 0\r\n'
                      b'    end\r\n'
                      b'  end\r\n'
                      b'  object Button2: TButton\r\n'
                      b'    Left = 8\r\n'
                      b'    Top = 80\r\n'
                      b'    TabOrder = 2\r\n'
                      b'  end\r\n'
                      b'  object Timer1: TTimer\r\n'
                      b'    Left = 200\r\n'
                      b'    Top = 8\r\n'
                      b'  end\r\n'
                      b'end\r\n')
open(os.path.join(JAIL, 'UOrden.pas'), 'wb').write(
    b'unit UOrden;\r\n\r\ninterface\r\n\r\nuses\r\n'
    b'  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls;\r\n\r\n'
    b'type\r\n  TForm1 = class(TForm)\r\n    Label1: TLabel;\r\n    Button1: TButton;\r\n'
    b'    Panel1: TPanel;\r\n    Button3: TButton;\r\n    Button2: TButton;\r\n    Timer1: TTimer;\r\n  end;\r\n\r\n'
    b'var\r\n  Form1: TForm1;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
FMX = os.path.join(JAIL, 'UOrdenF.fmx')
open(FMX, 'wb').write(b'object Form1: TForm1\r\n'
                      b"  Caption = 'Form1'\r\n"
                      b'  ClientHeight = 200\r\n'
                      b'  ClientWidth = 300\r\n'
                      b'  object Rect1: TRectangle\r\n'
                      b'    Position.X = 10.000000000000000000\r\n'
                      b'    Position.Y = 10.000000000000000000\r\n'
                      b'  end\r\n'
                      b'  object Timer1: TTimer\r\n'
                      b'  end\r\n'
                      b'  object Button1: TButton\r\n'
                      b'    TabOrder = 0\r\n'
                      b'  end\r\n'
                      b'  object ActionList1: TActionList\r\n'
                      b'  end\r\n'
                      b'end\r\n')
open(os.path.join(JAIL, 'UOrdenF.pas'), 'wb').write(
    b'unit UOrdenF;\r\n\r\ninterface\r\n\r\nuses\r\n'
    b'  System.Classes, FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls, FMX.Objects, FMX.ActnList;\r\n\r\n'
    b'type\r\n  TForm1 = class(TForm)\r\n    Rect1: TRectangle;\r\n    Timer1: TTimer;\r\n'
    b'    Button1: TButton;\r\n    ActionList1: TActionList;\r\n  end;\r\n\r\n'
    b'var\r\n  Form1: TForm1;\r\n\r\nimplementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n')


BARRA = os.path.join(JAIL, 'UBarra.dfm')
open(BARRA, 'wb').write(b'object FormB: TFormB\r\n'
                        b'  Left = 0\r\n'
                        b'  Top = 0\r\n'
                        b"  Caption = 'B'\r\n"
                        b'  ClientHeight = 200\r\n'
                        b'  ClientWidth = 300\r\n'
                        b'  object ToolBar1: TToolBar\r\n'
                        b'    Left = 0\r\n'
                        b'    Top = 0\r\n'
                        b'    Width = 300\r\n'
                        b'    Height = 29\r\n'
                        b"    Caption = 'ToolBar1'\r\n"
                        b'    TabOrder = 0\r\n'
                        b'    object ToolButton1: TToolButton\r\n'
                        b'      Left = 0\r\n'
                        b'      Top = 0\r\n'
                        b"      Caption = 'ToolButton1'\r\n"
                        b'    end\r\n'
                        b'    object ComboBox1: TComboBox\r\n'
                        b'      Left = 23\r\n'
                        b'      Top = 0\r\n'
                        b'      Width = 145\r\n'
                        b'      Height = 23\r\n'
                        b'      TabOrder = 0\r\n'
                        b'    end\r\n'
                        b'    object ToolButton2: TToolButton\r\n'
                        b'      Left = 168\r\n'
                        b'      Top = 0\r\n'
                        b"      Caption = 'ToolButton2'\r\n"
                        b'    end\r\n'
                        b'  end\r\n'
                        b'end\r\n')
# la pareja heredada: el ancestro con Button1, la hija con un nuevo [0] y otro detras
open(os.path.join(JAIL, 'UBaseO.dfm'), 'wb').write(
    b'object FormBaseO: TFormBaseO\r\n  Left = 0\r\n  Top = 0\r\n  Caption = \'Base\'\r\n'
    b'  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    Caption = \'Button1\'\r\n'
    b'    TabOrder = 0\r\n  end\r\nend\r\n')
open(os.path.join(JAIL, 'UBaseO.pas'), 'wb').write(
    b'unit UBaseO;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls;\r\n\r\n'
    b'type\r\n  TFormBaseO = class(TForm)\r\n    Button1: TButton;\r\n  end;\r\n\r\n'
    b'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
HIJA = os.path.join(JAIL, 'UHijaO.dfm')
open(HIJA, 'wb').write(
    b'inherited FormHijaO: TFormHijaO\r\n  Caption = \'Hija\'\r\n'
    b'  object ButtonX: TButton [0]\r\n    Left = 8\r\n    Top = 40\r\n    Caption = \'ButtonX\'\r\n'
    b'    TabOrder = 1\r\n  end\r\n'
    b'  object ButtonY: TButton\r\n    Left = 8\r\n    Top = 80\r\n    Caption = \'ButtonY\'\r\n'
    b'    TabOrder = 2\r\n  end\r\nend\r\n')
open(os.path.join(JAIL, 'UHijaO.pas'), 'wb').write(
    b'unit UHijaO;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls, UBaseO;\r\n\r\n'
    b'type\r\n  TFormHijaO = class(TFormBaseO)\r\n    ButtonX: TButton;\r\n    ButtonY: TButton;\r\n  end;\r\n\r\n'
    b'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
RARO = os.path.join(JAIL, 'URaro.dfm')
open(RARO, 'wb').write(
    b'object FormR: TFormR\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Raro1: TClaseQueNoExisteEnNingunPaquete\r\n    Left = 8\r\n    Top = 8\r\n  end\r\n'
    b'  object Button1: TButton\r\n    Left = 8\r\n    Top = 40\r\n    TabOrder = 0\r\n  end\r\nend\r\n')
# revisor 5: A1 (un hermano con acento: el protocolo del ayudante en ANSI lo perdia), M3 (un
# fichero que ya no estaba en el orden del IDE), M4 (una heredada donde decide el ANCESTRO, que
# solo llega por --folder), A2 (el ancestro en OTRA carpeta: el juez juzgaria un form a medias),
# M2 (un padre de una clase que ningun paquete carga)
BOM = b'\xef\xbb\xbf'
ACENTO = os.path.join(JAIL, 'UAcentoO.dfm')
open(ACENTO, 'wb').write(BOM + 'object FormA: TFormA\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n'
                         '  ClientWidth = 300\r\n  object LblDirección: TLabel\r\n    Left = 8\r\n    Top = 8\r\n'
                         '  end\r\n  object Button1: TButton\r\n    Left = 8\r\n    Top = 40\r\n    TabOrder = 0\r\n'
                         '  end\r\nend\r\n'.encode('utf-8'))
DESORDEN = os.path.join(JAIL, 'UDesorden.dfm')
open(DESORDEN, 'wb').write(
    b'object FormD: TFormD\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    TabOrder = 0\r\n  end\r\n'
    b'  object Button2: TButton\r\n    Left = 8\r\n    Top = 40\r\n    TabOrder = 1\r\n  end\r\n'
    b'  object Label9: TLabel\r\n    Left = 8\r\n    Top = 80\r\n  end\r\nend\r\n')
# el que se borra mientras juzga el renderizador (O20)
BORRA = os.path.join(JAIL, 'UBorra.dfm')
open(BORRA, 'wb').write(
    b'object FormB: TFormB\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    TabOrder = 0\r\n  end\r\n'
    b'  object Button2: TButton\r\n    Left = 8\r\n    Top = 40\r\n    TabOrder = 1\r\n  end\r\nend\r\n')
HIJAP = os.path.join(JAIL, 'UHijaP.dfm')
open(HIJAP, 'wb').write(
    b'inherited FormHijaP: TFormHijaP\r\n  Caption = \'HijaP\'\r\n'
    b'  inherited Button1: TButton\r\n    Caption = \'X\'\r\n  end\r\n'
    b'  object ButtonN: TButton\r\n    Left = 8\r\n    Top = 80\r\n    TabOrder = 1\r\n  end\r\nend\r\n')
open(os.path.join(JAIL, 'UHijaP.pas'), 'wb').write(
    b'unit UHijaP;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls, UBaseO;\r\n\r\n'
    b'type\r\n  TFormHijaP = class(TFormBaseO)\r\n    ButtonN: TButton;\r\n  end;\r\n\r\n'
    b'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
COMUN = os.path.join(JAIL, 'comun')
APP = os.path.join(JAIL, 'app')
os.makedirs(COMUN)
os.makedirs(APP)
open(os.path.join(COMUN, 'UBaseQ.dfm'), 'wb').write(
    b'object FormBaseQ: TFormBaseQ\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    TabOrder = 0\r\n  end\r\nend\r\n')
open(os.path.join(COMUN, 'UBaseQ.pas'), 'wb').write(
    b'unit UBaseQ;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls;\r\n\r\n'
    b'type\r\n  TFormBaseQ = class(TForm)\r\n    Button1: TButton;\r\n  end;\r\n\r\n'
    b'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
HIJAQ = os.path.join(APP, 'UHijaQ.dfm')
open(HIJAQ, 'wb').write(
    b'inherited FormHijaQ: TFormHijaQ\r\n  Caption = \'HijaQ\'\r\n'
    b'  inherited Button1: TButton\r\n    Caption = \'X\'\r\n  end\r\n'
    b'  object ButtonN: TButton\r\n    Left = 8\r\n    Top = 80\r\n    TabOrder = 1\r\n  end\r\nend\r\n')
open(os.path.join(APP, 'UHijaQ.pas'), 'wb').write(
    b'unit UHijaQ;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls, UBaseQ;\r\n\r\n'
    b'type\r\n  TFormHijaQ = class(TFormBaseQ)\r\n    ButtonN: TButton;\r\n  end;\r\n\r\n'
    b'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
# el ancestro en OTRA carpeta y el delta SIN ningun inherited: solo PARTIAL= lo dice (revisor 6, A2)
HIJAR = os.path.join(APP, 'UHijaR.dfm')
open(HIJAR, 'wb').write(
    b'inherited FormHijaR: TFormHijaR\r\n  Caption = \'HijaR\'\r\n'
    b'  object ButtonA: TButton [1]\r\n    Left = 8\r\n    Top = 80\r\n    TabOrder = 1\r\n  end\r\n'
    b'  object ButtonB: TButton\r\n    Left = 8\r\n    Top = 120\r\n    TabOrder = 2\r\n  end\r\nend\r\n')
open(os.path.join(APP, 'UHijaR.pas'), 'wb').write(
    b'unit UHijaR;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.StdCtrls, UBaseQ;\r\n\r\n'
    b'type\r\n  TFormHijaR = class(TFormBaseQ)\r\n    ButtonA: TButton;\r\n    ButtonB: TButton;\r\n  end;\r\n\r\n'
    b'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n')
PADRERARO = os.path.join(JAIL, 'UPadreRaro.dfm')
open(PADRERARO, 'wb').write(
    b'object FormP: TFormP\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 200\r\n  ClientWidth = 300\r\n'
    b'  object Bar1: TBarraQueNoExisteEnNingunPaquete\r\n    Left = 0\r\n    Top = 0\r\n'
    b'    object Label1: TLabel\r\n      Left = 4\r\n      Top = 4\r\n    end\r\n'
    b'    object Edit1: TEdit\r\n      Left = 40\r\n      Top = 4\r\n      TabOrder = 0\r\n    end\r\n'
    b'  end\r\nend\r\n')


def bytes_de(p):
    return open(p, 'rb').read()


def hijos(p, padre):
    """Los nombres de los hijos DIRECTOS de padre, en el orden del fichero."""
    res, dentro, prof = [], False, 0
    for linea in bytes_de(p).decode('utf-8').splitlines():
        s = linea.strip()
        m = re.match(r'(object|inherited|inline) (\w+):', s)
        if not dentro:
            if m and m.group(2) == padre:
                dentro = True
            continue
        if m:
            prof += 1
            if prof == 1:
                res.append(m.group(2))
        elif s == 'end':
            if prof == 0:
                break
            prof -= 1
    return res


def orden(p):
    """Los nombres de los hijos DIRECTOS de la raiz, en el orden del fichero."""
    return re.findall(r'(?m)^  object (\w+):', bytes_de(p).decode('utf-8'))


def J(r):
    try:
        return json.loads(r)
    except Exception:
        return {}


EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)  # el juez es el renderizador
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-orden', t=300)
try:
    def dsg(path, args):
        return srv.call('delphi_designer', dict({'command': 'set', 'path': path}, **args), t=240)

    r = dsg(DFM, {'component': 'Button2', 'before': 'Button1'})
    j = J(r)
    check('O1 VCL before=: Button2 delante de Button1 - el IDE lo guarda ahi (el TLabel sigue el primero)',
          orden(DFM) == ['Label1', 'Button2', 'Button1', 'Panel1', 'Timer1'] and j.get('ordered') == 'Button2' and
          j.get('index') == 2 and j.get('of') == 5 and mc.es(j.get('note', ''), 'SN_DESIGNER_ORDEN_NOTA'),
          (orden(DFM), r[:300]))
    r = dsg(DFM, {'component': 'Button1', 'index': 4})
    check('O2 VCL index=4 (entre TODOS los hermanos): Button1 tras Panel1, delante del no visual',
          orden(DFM) == ['Label1', 'Button2', 'Panel1', 'Button1', 'Timer1'] and J(r).get('index') == 4,
          (orden(DFM), r[:300]))

    antes = bytes_de(DFM)
    r1 = dsg(DFM, {'component': 'Label1', 'after': 'Button1'})
    r2 = dsg(DFM, {'component': 'Timer1', 'before': 'Button2'})
    r3 = dsg(DFM, {'component': 'Label1', 'after': 'Timer1'})
    check('O3 lo que el IDE no guardaria se niega con SU orden (DSGN-136): un grafico tras una ventana, un no '
          'visual delante, un grafico tras el no visual; nada escrito',
          all(mc.abre(x, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') for x in (r1, r2, r3)) and
          'Label1, Button2, Panel1, Button1, Timer1' in r1 and bytes_de(DFM) == antes, (r1[:300], r2[:200], r3[:200]))

    malos = [dsg(DFM, {'component': 'Button3', 'before': 'Button1'}),
             dsg(DFM, {'component': 'Button2', 'index': 9}),
             dsg(DFM, {'component': 'Button2', 'index': 0}),
             dsg(DFM, {'component': 'Button2', 'index': 2}),
             dsg(DFM, {'component': 'Button2', 'before': 'Button2'}),
             dsg(DFM, {'component': 'Button2', 'before': 'Button1', 'after': 'Panel1'}),
             dsg(DFM, {'component': 'Button2', 'index': 2, 'prop': 'Caption', 'value': 'x'}),
             dsg(DFM, {'component': 'Button2', 'before': 'Form1'})]
    check('O4 no hermanos (137, tambien la raiz), index fuera y index=0 (138), ya en su sitio (141, sin '
          'escribir), si mismo (139), dos a la vez y con prop (135); nada escrito',
          mc.abre(malos[0], 'SR_DESIGNER_ORDEN_NO_HERMANO_FMT') and mc.abre(malos[1], 'SR_DESIGNER_ORDEN_INDICE_FMT') and
          mc.abre(malos[2], 'SR_DESIGNER_ORDEN_INDICE_FMT') and mc.abre(malos[3], 'SN_DESIGNER_ORDEN_YA_ESTA_FMT') and
          mc.abre(malos[4], 'SR_DESIGNER_ORDEN_SI_MISMO_FMT') and mc.abre(malos[5], 'SR_DESIGNER_ORDEN_SOLO') and
          mc.abre(malos[6], 'SR_DESIGNER_ORDEN_SOLO') and mc.abre(malos[7], 'SR_DESIGNER_ORDEN_NO_HERMANO_FMT') and
          'it is the form itself' in malos[7] and bytes_de(DFM) == antes, [m[:120] for m in malos])
    r = srv.call('delphi_designer', {'command': 'lint', 'path': DFM}, t=200)
    t = bytes_de(DFM).decode('utf-8')
    dentro = t.index('  object Panel1') < t.index('    object Button3') < t.index('  object Button1')
    check('O5 el form reordenado lo lee el parser del IDE (lint sin DSGN-123) y Button3 sigue dentro de Panel1',
          not mc.es(r, 'SN_DSGN_PARSER_FMT') and dentro, r[:300])

    # O6 revisor 4, M2: en un TToolBar el orden del fichero ES la posicion del boton y mezcla
    # botones y controles con ventana - una lista propia lo negaba; el juez lo deja
    r = dsg(BARRA, {'component': 'ComboBox1', 'before': 'ToolButton1'})
    check('O6 TToolBar: un TComboBox delante de un TToolButton se guarda (el IDE lo respeta)',
          not mc.fallo(r) and J(r).get('ordered') == 'ComboBox1' and
          hijos(BARRA, 'ToolBar1') == ['ComboBox1', 'ToolButton1', 'ToolButton2'], (hijos(BARRA, 'ToolBar1'), r[:400]))
    # O7 revisor 4, M1: en una form heredada un nuevo delante de los del ancestro lleva [n], y TReader
    # coloca por el [n], no por el texto: el juez lo ve (--folder: el ancestro y el .pas de verdad)
    antes = bytes_de(HIJA)
    r = dsg(HIJA, {'component': 'ButtonY', 'before': 'ButtonX'})
    check('O7 form heredada: ButtonY delante de ButtonX [0] no se sostiene (el IDE coloca por el [n]); nada escrito',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and bytes_de(HIJA) == antes, r[:400])
    # O8 una clase que ningun paquete tiene: donde la escribiria el IDE no se puede preguntar
    antes = bytes_de(RARO)
    r = dsg(RARO, {'component': 'Button1', 'before': 'Raro1'})
    check('O8 un hermano de una clase que ningun paquete carga: DSGN-140, nada escrito',
          mc.abre(r, 'SR_DESIGNER_ORDEN_SIN_CLASE_FMT') and 'TClaseQueNoExisteEnNingunPaquete' in r and
          bytes_de(RARO) == antes, r[:400])

    r = dsg(ACENTO, {'component': 'Button1', 'before': 'LblDirección'})
    check('O9 un hermano con acento (A1): el juez lo ve entero y niega poner el boton delante del TLabel',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and 'LblDirección, Button1' in r, r[:400])
    r = dsg(DESORDEN, {'component': 'Button2', 'before': 'Button1'})
    check('O10 un fichero que ya no estaba en el orden del IDE (un TLabel al final): Button2 delante de '
          'Button1 se guarda - solo cuenta el hermano que salta (M3)',
          not mc.fallo(r) and orden(DESORDEN) == ['Button2', 'Button1', 'Label9'], (orden(DESORDEN), r[:400]))
    antes = bytes_de(DESORDEN)
    r = dsg(DESORDEN, {'component': 'Label9', 'after': 'Button2'})
    check('O17 ...pero la REFERENCIA cuenta siempre: Label9 detras de Button2 el IDE lo guarda delante - '
          'DSGN-136, nada escrito (revisor 6, A1)',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and bytes_de(DESORDEN) == antes, r[:400])
    r = dsg(DESORDEN, {'component': 'Label9', 'index': 2})
    check('O18 ...e index es una POSICION: Label9 en la 2 el IDE lo deja en la 1 - DSGN-136 (revisor 6, A1)',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and bytes_de(DESORDEN) == antes, r[:400])
    antes = bytes_de(HIJAP)
    r = dsg(HIJAP, {'component': 'ButtonN', 'before': 'Button1'})
    check('O11 heredada: un nuevo delante de un heredado no se sostiene - lo dice el ANCESTRO, que llega '
          'por --folder (M4: sin el, el juez diria DSGN-143)',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and bytes_de(HIJAP) == antes, r[:400])
    antes = bytes_de(HIJAQ)
    r = dsg(HIJAQ, {'component': 'ButtonN', 'before': 'Button1'})
    # (desde el revisor 6 lo dice PARTIAL= y nombra el ANCESTRO; la regla de "un hermano escrito
    # que falta" queda detras como cinturon: sin un ancestro sin leer no hay forma de provocarla)
    check('O12 heredada con el ancestro en OTRA carpeta: el juez juzgaria un form a medias - DSGN-143 '
          'nombrando el ancestro, nada escrito (A2)', mc.abre(r, 'SR_DESIGNER_ORDEN_INCOMPLETO_FMT') and
          'TFormBaseQ' in r and bytes_de(HIJAQ) == antes, r[:400])
    antes = bytes_de(HIJAR)
    r = dsg(HIJAR, {'component': 'ButtonB', 'before': 'ButtonA'})
    check('O19 ...tambien si el delta no trae ningun heredado: el ayudante dice sin que ancestro leyo '
          '(PARTIAL=) - DSGN-143 nombrandolo, nada escrito (revisor 6, A2)',
          mc.abre(r, 'SR_DESIGNER_ORDEN_INCOMPLETO_FMT') and 'TFormBaseQ' in r and
          bytes_de(HIJAR) == antes, r[:400])
    antes = bytes_de(PADRERARO)
    r = dsg(PADRERARO, {'component': 'Label1', 'after': 'Edit1'})
    check('O13 el PADRE de una clase que ningun paquete carga: DSGN-140 nombrando al padre (M2)',
          mc.abre(r, 'SR_DESIGNER_ORDEN_SIN_CLASE_FMT') and 'TBarraQueNoExisteEnNingunPaquete' in r and
          bytes_de(PADRERARO) == antes, r[:400])
    r = dsg(DFM, {'component': 'Panel1', 'after': 'Button1'})
    t = bytes_de(DFM).decode('utf-8')
    check('O14 un bloque con hijos se mueve entero (Panel1 con Button3 dentro, tras Button1) (B4)',
          not mc.fallo(r) and orden(DFM) == ['Label1', 'Button2', 'Button1', 'Panel1', 'Timer1'] and
          t.index('  object Panel1') < t.index('    object Button3') < t.index('  object Timer1'),
          (orden(DFM), r[:300]))

    r = dsg(FMX, {'component': 'Timer1', 'after': 'Button1'})
    check('F1 FMX: un TTimer tras un TButton (los dos TFmxObject) se guarda; el TActionList sigue el ultimo',
          orden(FMX) == ['Rect1', 'Button1', 'Timer1', 'ActionList1'] and J(r).get('ordered') == 'Timer1',
          (orden(FMX), r[:300]))
    r = dsg(FMX, {'component': 'Rect1', 'index': 3})
    check('F2 FMX index=3: el rectangulo el tercero',
          orden(FMX) == ['Button1', 'Timer1', 'Rect1', 'ActionList1'], (orden(FMX), r[:300]))
    antes = bytes_de(FMX)
    r = dsg(FMX, {'component': 'ActionList1', 'before': 'Button1'})
    check('F3 FMX: un TActionList (no TFmxObject) delante de un TButton se niega con el orden del IDE',
          mc.abre(r, 'SR_DESIGNER_ORDEN_EL_IDE_FMT') and bytes_de(FMX) == antes, r[:300])
    # A3: el juez corre SIN el cerrojo; si el form cambia mientras juzga, no se
    # escribe encima (DSGN-144). La propuesta vive en una carpeta __tmp- del
    # temporal del servidor mientras corre el renderizador: al verla, se toca
    import glob
    import threading
    import time
    tmp = os.path.join(os.path.dirname(EXE), '__delphi-temp')

    def mientras_juzga(path, args, accion):
        """set con orden en un hilo; al aparecer la carpeta __tmp- del juez, accion().
        Devuelve (vista, respuesta): sin ver la carpeta, la accion no se hace."""
        res = {}
        hilo = threading.Thread(target=lambda: res.setdefault('r', dsg(path, args)))
        hilo.start()
        vista = False
        tope = time.time() + 120
        while hilo.is_alive() and time.time() < tope:
            if glob.glob(os.path.join(tmp, '**', '__tmp-*'), recursive=True):
                vista = True
                break
            time.sleep(0.005)
        if vista:
            accion()
        hilo.join(300)
        return vista, res.get('r', '')

    viejo = bytes_de(DFM)
    tocado = viejo.replace(b"Caption = 'L'\r\n", b"Caption = 'LZ'\r\n", 1)
    vista, r = mientras_juzga(DFM, {'component': 'Button1', 'before': 'Button2'},
                              lambda: open(DFM, 'wb').write(tocado))
    check('O16 el form cambia mientras juzga el renderizador: DSGN-144 y el cambio ajeno sigue ahi (A3)',
          vista and tocado != viejo and mc.abre(r, 'SR_DESIGNER_ORDEN_CAMBIO_FMT') and bytes_de(DFM) == tocado,
          (vista, r[:300]))
    vista, r = mientras_juzga(BORRA, {'component': 'Button2', 'before': 'Button1'},
                              lambda: os.remove(BORRA))
    check('O20 ...y si lo BORRAN mientras juzga, DSGN-144 y no una excepcion cruda (revisor 6, B2)',
          vista and mc.abre(r, 'SR_DESIGNER_ORDEN_CAMBIO_FMT') and not os.path.exists(BORRA),
          (vista, r[:300]))
    # B5: la carpeta de cada llamada del juez se borra siempre (en el temporal del SERVIDOR)
    quedan = glob.glob(os.path.join(os.path.dirname(EXE), '__delphi-temp', '**', '__tmp-*'), recursive=True)
    check('O15 no queda ninguna carpeta __tmp- del juez en el temporal del servidor (B5)', not quedan, quedan)
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('designer orden')
