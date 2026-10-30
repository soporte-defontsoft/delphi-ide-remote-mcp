# -*- coding: utf-8 -*-
"""H2 de Hermes (1.18.2, punto 9): designer set sobre una propiedad que la
clase guarda POR CODIGO (DefineProperties: sin hoja de tipo en la tabla) la
escribia sin juzgar su valor, contestaba "ok" y dejaba un form que el cargador
del designer no leia. Medido en produccion el 14-oct: FontColor = -65536 en un
TEdit FMX -> ok; preview -> DSGN-061 EReadError "Error reading
Edit1.FontColor: Invalid property value". El juez es el cargador (norma 6):
set le pregunta (ComoLoEscribeElIde) cuando la tabla no juzgo el valor, y
niega (DSGN-149) si lo que no carga es ESA propiedad de ESE componente - lo
dicen las partes del error, que da el ayudante partido con el formato que lo
compuso: el lector habla el idioma de Windows (rtl370.de/.fr/.ja junto a
rtl370.bpl) y el servidor lo partia con el ingles; medido el 18-oct-2026, en
aleman no nombraba nada y el valor se escribia sin juzgar y sin decirlo.
Si falla otra cosa, se le pregunta por el form como estaba: si ese carga, lo
rompe el cambio (DSGN-158); si tampoco, o no se le pudo preguntar, el valor
se escribe sin juzgar y la respuesta lo dice (readerNote, DSGN-159).
DSGN-158 no se provoca aqui: con los componentes de serie, el error de una
propiedad guardada por codigo siempre es del lector y la nombra (haria falta
un componente que falle en su Loaded por ese valor).

  C1 set Edit1.FontColor = -65536: DSGN-149 y el form intacto (ROJO en
     produccion: ok y el form no carga)
  C2 set Edit1.HorzTextAlign = taRightJustify (el nombre VCL): DSGN-149
     (ROJO en produccion)
  C3 lo mismo por props (FontColor=-65536;TabOrder=1): DSGN-149, nada
     escrito (ROJO en produccion)
  C4 el control: FontColor = claRed se escribe y el form carga (preview)
  C5 un form que YA no cargaba por OTRO componente (Edit2 con el valor malo):
     set de Edit1.FontColor = claRed no se niega por eso (guarda)
  C6 ...y la respuesta dice que Edit1.FontColor no se juzgo (readerNote
     DSGN-159; ROJO en produccion: nada)
  C7 con el lector en ALEMAN, a mano (el idioma de un exe no se elige dentro del
     contenedor; el servidor lee sus partes en una unitaria): FontColor = -65536
     lo dice en aleman y partido, propiedad y motivo
  C8 el control en aleman: FontColor = claRed no dice nada
  C9 el lector no se pudo preguntar (un literal del form nombra un fichero del
     sistema, lo que el contenedor leeria): el valor se escribe y readerNote lo
     dice (ROJO en produccion: nada)

Uso:  python tests/test_designer_carga_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer_carga_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)

FMX = ("object FormC: TFormC\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'C'\r\n  ClientHeight = 480\r\n"
       "  ClientWidth = 640\r\n  FormFactor.Width = 320\r\n  FormFactor.Height = 480\r\n"
       "  FormFactor.Devices = [Desktop]\r\n  DesignerMasterStyle = 0\r\n{otro}"
       "  object Edit1: TEdit\r\n    Position.X = 10.000000000000000000\r\n"
       "    Position.Y = 10.000000000000000000\r\n    TabOrder = 0\r\n  end\r\nend\r\n")
EDIT2_MALO = ("  object Edit2: TEdit\r\n    FontColor = -65536\r\n    Position.X = 10.000000000000000000\r\n"
              "    Position.Y = 40.000000000000000000\r\n    TabOrder = 1\r\n  end\r\n")
# un Text que nombra un fichero del sistema, lo que el contenedor leeria: el
# servidor no le da el form al lector (LiteralesDeRenderDenegados)
EDIT2_LITERAL = ("  object Edit2: TEdit\r\n    Text = '{ruta}'\r\n    Position.X = 10.000000000000000000\r\n"
                 "    Position.Y = 40.000000000000000000\r\n    TabOrder = 1\r\n  end\r\n")
PAS = ("unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Types, System.UITypes, "
       "System.Classes, System.Variants,\r\n  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, "
       "FMX.Edit;\r\n\r\ntype\r\n  TFormC = class(TForm)\r\n{campos}  end;\r\n\r\nvar\r\n  FormC: TFormC;\r\n\r\n"
       "implementation\r\n\r\n{$R *.fmx}\r\n\r\nend.\r\n")


def form(nombre, con_edit2=False, edit2=''):
    edit2 = EDIT2_MALO if con_edit2 else edit2
    texto = FMX.replace('{otro}', edit2)
    campos = '    Edit2: TEdit;\r\n    Edit1: TEdit;\r\n' if edit2 else '    Edit1: TEdit;\r\n'
    p = os.path.join(JAIL, nombre + '.fmx')
    open(p, 'wb').write(b'\xef\xbb\xbf' + texto.encode('utf-8'))
    open(os.path.join(JAIL, nombre + '.pas'), 'wb').write(
        PAS.replace('{u}', nombre).replace('{campos}', campos).encode('utf-8'))
    return p


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='designer-carga', t=240)
try:
    p = form('UC1')
    antes = open(p, 'rb').read()
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Edit1', 'prop': 'FontColor',
                                     'value': '-65536'}, t=240)
    check('C1 set FontColor=-65536 (por codigo): DSGN-149 con lo que dijo el lector, y el form intacto',
          mc.abre(r, 'SR_DESIGNER_SET_NO_CARGA_FMT') and 'Invalid property value' in r and open(p, 'rb').read() == antes,
          r[:300])

    p = form('UC2')
    antes = open(p, 'rb').read()
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Edit1', 'prop': 'HorzTextAlign',
                                     'value': 'taRightJustify'}, t=240)
    check('C2 set HorzTextAlign=taRightJustify (el nombre VCL): DSGN-149 y el form intacto',
          mc.abre(r, 'SR_DESIGNER_SET_NO_CARGA_FMT') and open(p, 'rb').read() == antes, r[:300])

    p = form('UC3')
    antes = open(p, 'rb').read()
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Edit1',
                                     'props': 'FontColor=-65536;TabOrder=1'}, t=240)
    check('C3 lo mismo por props: DSGN-149 y nada escrito (todo o nada)',
          mc.es(r, 'SR_DESIGNER_SET_NO_CARGA_FMT') and mc.rechazado(r) and open(p, 'rb').read() == antes, r[:300])

    p = form('UC4')
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Edit1', 'prop': 'FontColor',
                                     'value': 'claRed'}, t=240)
    pv = srv.call('delphi_designer', {'path': p, 'command': 'preview', 'maxwidth': 200}, t=240)
    check('C4 el control: FontColor=claRed se escribe y el form carga (preview sin DSGN-061)',
          # not fallo: DSGN-061 es INTERNAL y "not rechazado" lo dejaba pasar
          # (revisor de baterias, 18-oct-2026)
          not mc.fallo(r) and b'FontColor = claRed' in open(p, 'rb').read() and not mc.fallo(pv),
          (r[:200], pv[:200]))

    p = form('UC5', con_edit2=True)
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Edit1', 'prop': 'FontColor',
                                     'value': 'claRed'}, t=240)
    check('C5 un form que ya no cargaba por OTRO componente (Edit2): el set de Edit1 no se niega por eso',
          not mc.rechazado(r) and b'FontColor = claRed' in open(p, 'rb').read(), r[:300])
    nota = mc.como_json(r).get('readerNote') or ''
    check('C6 ...y la respuesta dice que Edit1.FontColor = claRed se escribio sin juzgar, por Edit2 (readerNote)',
          mc.abre(nota, 'SN_DESIGNER_SET_SIN_JUZGAR_FMT') and 'Edit1.FontColor = claRed' in nota and
          'Edit2.FontColor' in nota, r[:400])

    # el lector en aleman, a mano: el ayudante que lanza ESTE servidor (copia_exe
    # lo puso a su lado)
    RENDER = os.path.join(os.path.dirname(EXE), 'DelphiFormRenderFmx.exe')
    p = form('UC7')
    t = open(p, 'rb').read().replace(b'    Position.X', b'    FontColor = -65536\r\n    Position.X', 1)
    open(p, 'wb').write(t)
    d = mc.juez_en_idioma(RENDER, p, 'DE')
    check('C7 con el lector en aleman: FontColor=-65536 lo dice en aleman y partido, propiedad y motivo',
          '|Edit1|FontColor|Ungültiger Eigenschaftswert|' in d, d[:600])
    p = form('UC8')
    t = open(p, 'rb').read().replace(b'    Position.X', b'    FontColor = claRed\r\n    Position.X', 1)
    open(p, 'wb').write(t)
    d = mc.juez_en_idioma(RENDER, p, 'DE')
    check('C8 el control en aleman: FontColor=claRed no dice nada', 'FontColor|' not in d and 'WRITTEN=' in d, d[:600])

    p = form('UC9', edit2=EDIT2_LITERAL.replace('{ruta}', os.path.join(os.environ['WINDIR'], 'win.ini')))
    r = srv.call('delphi_designer', {'path': p, 'command': 'set', 'component': 'Edit1', 'prop': 'FontColor',
                                     'value': 'claRed'}, t=240)
    nota = mc.como_json(r).get('readerNote') or ''
    check('C9 el lector no se pudo preguntar (un literal fuera de la jaula): se escribe y readerNote lo dice',
          not mc.rechazado(r) and b'FontColor = claRed' in open(p, 'rb').read() and
          mc.abre(nota, 'SN_DESIGNER_SET_SIN_JUZGAR_FMT'), r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('designer set: el cargador juzga lo que la tabla no 1182 (H2)')
