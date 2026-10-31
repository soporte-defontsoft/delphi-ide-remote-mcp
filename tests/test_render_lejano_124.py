# -*- coding: utf-8 -*-
"""V120b de la 1.24: un ancestro o un frame en OTRA carpeta del proyecto salia a medias
(RENDER-010 y DSGN-143 en el juez, sustituido el frame): el ayudante solo ve los forms de
la carpeta del suyo. Ahora, si dice que le falto una clase y el proyecto la tiene, el
servidor le lleva ese form, juzgado como un hermano.

  L1 un form heredado de un ancestro de otra carpeta se dibuja entero
  L2 un frame inline de otra carpeta tambien
  L3 el juez del orden lo juzga y escribe (era DSGN-143)
  L4 el literal de un ancestro lejano se juzga como el de un hermano
  L5 lo que el form trae de otra carpeta no se escribe nunca en ella
  L6 ...con READ= en la ruta real: si volviera con la de la carpeta del form, el set de L3
     no encontraria lo leido y se negaria (CambioEnLoLeido)
  L7 sin proyecto que lo liste, sigue a medias y lo dice
  L8 con otro proyecto al lado, solo manda el que lista la unidad: su copia de otro no se trae
  L9 un ancestro fuera de lo que la sesion lee no entra

ROJO contra un build sin el arreglo: L1, L2, L3 y L4.

Uso:  python tests/test_render_lejano_124.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

SIN_ANCESTRO = 'SN_RENDER_ANCESTRO_SIN_FICHERO_FMT'
BASE = mc.carpeta('render_lejano_124')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
os.makedirs(FUERA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)


def escribe(raiz, rel, texto):
    ruta = os.path.join(raiz, rel)
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'wb').write(texto.replace('\n', '\r\n').encode('ascii'))
    return ruta


def unidad(nombre, clase, padre, usos, campos=''):
    return ('unit %s;\n\ninterface\n\nuses\n  %s;\n\ntype\n  %s = class(%s)\n%s  end;\n\n'
            'implementation\n\n{$R *.dfm}\n\nend.\n' % (nombre, usos, clase, padre, campos))


def dpr(nombre, entradas):
    usos = ',\n  '.join(entradas)
    return 'program %s;\n\nuses\n  Vcl.Forms,\n  %s;\n\nbegin\nend.\n' % (nombre, usos)


USOS = 'System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls'
BOTON = "  object %s: TButton\n    Left = %d\n    Top = 8\n    Width = 75\n    Height = 25\n    Caption = '%s'\n    TabOrder = %d\n  end\n"

# ---- el proyecto: forms\ hereda de base\ y lleva un frame de frames\
APP = os.path.join(JAIL, 'app')
escribe(APP, 'App.dpr', dpr('App', ["UHija in 'forms\\UHija.pas' {FormHija}", "UBase in 'base\\UBase.pas' {FormBase}",
                                    "UFr in 'frames\\UFr.pas' {Frame1: TFrame}", "UMalo in 'base\\UMalo.pas' {FormMalo}",
                                    "UHijaMala in 'forms\\UHijaMala.pas' {FormHijaMala}"]))
escribe(APP, 'base\\UBase.pas', unidad('UBase', 'TFormBase', 'TForm', USOS, '    ButtonBase: TButton;\n'))
escribe(APP, 'base\\UBase.dfm', "object FormBase: TFormBase\n  Left = 0\n  Top = 0\n  Caption = 'Base'\n  ClientHeight = 200\n  ClientWidth = 400\n"
        + BOTON % ('ButtonBase', 8, 'Base', 0) + 'end\n')
escribe(APP, 'frames\\UFr.pas', unidad('UFr', 'TFrame1', 'TFrame', USOS, '    LabelF: TLabel;\n'))
escribe(APP, 'frames\\UFr.dfm', "object Frame1: TFrame1\n  Left = 0\n  Top = 0\n  Width = 200\n  Height = 60\n"
        "  object LabelF: TLabel\n    Left = 8\n    Top = 8\n    Width = 50\n    Height = 15\n    Caption = 'Marco'\n  end\nend\n")
escribe(APP, 'forms\\UHija.pas', unidad('UHija', 'TFormHija', 'TFormBase', USOS + ', UBase, UFr',
                                        '    ButtonA: TButton;\n    ButtonB: TButton;\n    Frame11: TFrame1;\n'))
HIJA = escribe(APP, 'forms\\UHija.dfm', "inherited FormHija: TFormHija\n  Caption = 'Hija'\n"
               + BOTON % ('ButtonA', 90, 'A', 1) + BOTON % ('ButtonB', 170, 'B', 2)
               + "  inline Frame11: TFrame1\n    Left = 8\n    Top = 60\n    TabOrder = 3\n  end\nend\n")
# un ancestro lejano con un literal bajo Windows, y su hija
SIS = os.path.join(os.environ['WINDIR'], 'win.ini')
escribe(APP, 'base\\UMalo.pas', unidad('UMalo', 'TFormMalo', 'TForm', USOS))
escribe(APP, 'base\\UMalo.dfm', "object FormMalo: TFormMalo\n  Left = 0\n  Top = 0\n  Caption = '%s'\n  ClientHeight = 200\n  ClientWidth = 400\nend\n" % SIS)
escribe(APP, 'forms\\UHijaMala.pas', unidad('UHijaMala', 'TFormHijaMala', 'TFormMalo', USOS + ', UMalo'))
HIJAMALA = escribe(APP, 'forms\\UHijaMala.dfm', "inherited FormHijaMala: TFormHijaMala\n  Caption = 'HM'\nend\n")

# ---- sin proyecto
SOLA = os.path.join(JAIL, 'sola')
escribe(SOLA, 'base\\UBaseS.pas', unidad('UBaseS', 'TFormBaseS', 'TForm', USOS, '    ButtonBase: TButton;\n'))
escribe(SOLA, 'base\\UBaseS.dfm', "object FormBaseS: TFormBaseS\n  Left = 0\n  Top = 0\n  Caption = 'B'\n  ClientHeight = 200\n  ClientWidth = 400\n"
        + BOTON % ('ButtonBase', 8, 'Base', 0) + 'end\n')
escribe(SOLA, 'forms\\UHijaS.pas', unidad('UHijaS', 'TFormHijaS', 'TFormBaseS', USOS + ', UBaseS'))
HIJAS = escribe(SOLA, 'forms\\UHijaS.dfm', "inherited FormHijaS: TFormHijaS\n  Caption = 'HS'\nend\n")

# ---- el ancestro de un proyecto vive fuera de las raices
PF = os.path.join(JAIL, 'pfuera')
escribe(FUERA, 'UBaseF.pas', unidad('UBaseF', 'TFormBaseF', 'TForm', USOS, '    ButtonBase: TButton;\n'))
escribe(FUERA, 'UBaseF.dfm', "object FormBaseF: TFormBaseF\n  Left = 0\n  Top = 0\n  Caption = 'B'\n  ClientHeight = 200\n  ClientWidth = 400\n"
        + BOTON % ('ButtonBase', 8, 'Base', 0) + 'end\n')
escribe(PF, 'Pf.dpr', dpr('Pf', ["UHijaF in 'forms\\UHijaF.pas' {FormHijaF}", "UBaseF in '%s' {FormBaseF}" % os.path.join(FUERA, 'UBaseF.pas')]))
escribe(PF, 'forms\\UHijaF.pas', unidad('UHijaF', 'TFormHijaF', 'TFormBaseF', USOS + ', UBaseF'))
HIJAF = escribe(PF, 'forms\\UHijaF.dfm', "inherited FormHijaF: TFormHijaF\n  Caption = 'HF'\nend\n")

# ---- otro proyecto al lado, con SU TFormBase: no lista UHija y no decide
OTRO = os.path.join(JAIL, 'otro')
escribe(OTRO, 'Otro.dpr', dpr('Otro', ["UBase in 'base\\UBase.pas' {FormBase}"]))
escribe(OTRO, 'base\\UBase.pas', unidad('UBase', 'TFormBase', 'TForm', USOS, '    ButtonBase: TButton;\n'))
escribe(OTRO, 'base\\UBase.dfm', "object FormBase: TFormBase\n  Left = 0\n  Top = 0\n  Caption = 'Otro'\n  ClientHeight = 200\n  ClientWidth = 400\n"
        + BOTON % ('ButtonBase', 300, 'Otro', 0) + 'end\n')

BASE_BYTES = open(os.path.join(APP, 'base', 'UBase.dfm'), 'rb').read()
FR_BYTES = open(os.path.join(APP, 'frames', 'UFr.dfm'), 'rb').read()


def J(r):
    try:
        return json.loads(r)
    except ValueError:
        return {}


def orden(ruta):
    return [l.split()[1].rstrip(':') for l in open(ruta, encoding='ascii') if l.startswith('  object ') or l.startswith('  inline ')]


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='render-lejano', t=300)
try:
    def preview(path, nombre):
        return srv.call('delphi_designer', {'command': 'preview', 'path': path, 'out': os.path.join(JAIL, nombre)}, t=240)

    r = preview(HIJA, 'h.png')
    j = J(r)
    # ButtonBase (del ancestro), ButtonA, ButtonB y Frame11
    check('L1 heredado de otra carpeta: el form entero, sin sustituidos ni a medias',
          j.get('components') == 4 and not j.get('substituted') and not mc.es(r, SIN_ANCESTRO), r[:700])
    r = srv.call('delphi_designer', {'command': 'preview', 'path': HIJA, 'component': 'Frame11.LabelF',
                                     'out': os.path.join(JAIL, 'fr.png')}, t=240)
    check('L2 el frame de otra carpeta se lee: su LabelF tiene sitio en el form',
          len(J(r).get('componentRect', '').split(',')) == 4 and not J(r).get('substituted'), r[:900])
    r = srv.call('delphi_designer', {'command': 'preview', 'path': HIJA, 'component': 'ButtonBase',
                                     'out': os.path.join(JAIL, 'bb.png')}, t=240)
    check('L8 con otro proyecto al lado y su TFormBase, manda el que lista la unidad',
          J(r).get('componentRect', '').split(',')[:1] == ['8'], r[:500])

    r = srv.call('delphi_designer', {'command': 'set', 'path': HIJA, 'component': 'ButtonB', 'before': 'ButtonA'}, t=240)
    check('L3 el juez del orden lo juzga y escribe (era DSGN-143); lo leido vuelve con su ruta real',
          not mc.rechazado(r) and orden(HIJA) == ['ButtonB', 'ButtonA', 'Frame11'], (orden(HIJA), r[:500]))
    check('L5 nada se escribe en la carpeta del ancestro ni en la del frame',
          open(os.path.join(APP, 'base', 'UBase.dfm'), 'rb').read() == BASE_BYTES and
          open(os.path.join(APP, 'frames', 'UFr.dfm'), 'rb').read() == FR_BYTES and
          sorted(os.listdir(os.path.join(APP, 'frames'))) == ['UFr.dfm', 'UFr.pas'], os.listdir(os.path.join(APP, 'frames')))

    r = preview(HIJAMALA, 'm.png')
    check('L4 el literal de un ancestro lejano se juzga como el de un hermano (DSGN-115)', mc.abre(r, 'SR_DESIGNER_LITERAL_FUERA_FMT'), r[:400])

    r = preview(HIJAS, 's.png')
    check('L7 sin proyecto que lo liste, a medias y lo dice (RENDER-010)', mc.es(r, SIN_ANCESTRO) and J(r).get('components') == 0, r[:500])

    r = preview(HIJAF, 'f.png')
    check('L9 un ancestro fuera de lo que la sesion lee no entra: a medias (RENDER-010), sin nombrar su boton',
          mc.es(r, SIN_ANCESTRO) and J(r).get('components') == 0, r[:500])

    # ---- V77: insert de un frame del proyecto
    UN_FORM = os.path.join(APP, 'forms', 'UOtra.dfm')
    escribe(APP, 'forms\\UOtra.pas', unidad('UOtra', 'TFormOtra', 'TForm', USOS))
    escribe(APP, 'forms\\UOtra.dfm', "object FormOtra: TFormOtra\n  Left = 0\n  Top = 0\n  Caption = 'Otra'\n  ClientHeight = 200\n  ClientWidth = 400\nend\n")
    P_APP = os.path.join(APP, 'App.dpr')
    t = open(P_APP, encoding='ascii', newline='').read().replace("{FormHijaMala};", "{FormHijaMala},\r\n  UOtra in 'forms\\UOtra.pas' {FormOtra};")
    open(P_APP, 'w', encoding='ascii', newline='').write(t)
    r = srv.call('delphi_designer', {'command': 'insert', 'path': UN_FORM, 'classname': 'TFrame1'}, t=240)
    dfm = open(UN_FORM, encoding='ascii').read()
    pas = open(os.path.join(APP, 'forms', 'UOtra.pas'), encoding='ascii').read()
    check('I1 V77 insert de un frame del proyecto: inline con el nombre del IDE, su campo y su unidad en el uses',
          'inline Frame11: TFrame1' in dfm and 'Frame11: TFrame1;' in pas and 'UFr' in pas.split('type')[0], (r[:500], dfm))
    r = srv.call('delphi_designer', {'command': 'preview', 'path': UN_FORM, 'component': 'Frame11.LabelF', 'out': os.path.join(JAIL, 'i.png')}, t=240)
    check('I2 ...y carga: su LabelF tiene sitio, nada sustituido', len(J(r).get('componentRect', '').split(',')) == 4 and not J(r).get('substituted'), r[:500])
    antes = open(UN_FORM, 'rb').read()
    r = srv.call('delphi_designer', {'command': 'insert', 'path': UN_FORM, 'classname': 'TFormBase'}, t=240)
    check('I3 una clase del proyecto que no es un frame no entra (DSGN-015), nada escrito',
          mc.abre(r, 'SR_DESIGNER_CLASS_FMT') and open(UN_FORM, 'rb').read() == antes, r[:300])
    r = srv.call('delphi_designer', {'command': 'insert', 'path': os.path.join(APP, 'frames', 'UFr.dfm'), 'classname': 'TFrame1'}, t=240)
    check('I4 un frame no se mete en si mismo', mc.abre(r, 'SR_DESIGNER_CLASS_FMT'), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('ancestros y frames en otra carpeta (V120b)')
