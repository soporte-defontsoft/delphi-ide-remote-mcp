# -*- coding: utf-8 -*-
"""EL PARSER DEL IDE juzga los forms y los estilos (8.10 y 9.B de la 1.18.0):
lint y los escritores de delphi_designer y delphi_styles preguntaban a una
gramatica propia y no al parser que carga el form (ObjectTextToBinary, el de
DesignerAFlujo). Medido el 8-oct: un // en un .fmx pasaba delphi_edit, lint
decia CLEAN y solo preview (el IDE) lo rechazaba: "Identifier expected on line
2". Ahora lo dice el parser, con su linea:

  P1  lint de un .fmx con un // : DSGN-123 con la linea 2 y su texto
  P2  preview del mismo: DSGN-126 ANTES de lanzar el renderizador
  P3  set sobre ese form YA roto: DSGN-125 (ya no se leia), y no escribe
  P4  delphi_styles set con un bloque {zz} (la gramatica propia lo da por
      bueno: "un bloque cerrado"): DSGN-124 y el .style no cambia
  P5  los controles: el form arreglado se lee (lint sin DSGN-123, preview sin
      DSGN-126) y un set de un valor bueno en el estilo se escribe
  P6  r5-L3: un set sobre un form de texto en UTF-16 lo escribe (en UTF-16,
      como estaba) y dice DSGN-121 - dcc no lo compila -, como ya lo decia lint
  P7  revisor 2 de la noche, M-B: delphi_edit que mete un // en un .fmx dice
      DSGN-123 (su lint no preguntaba al parser: la puerta del 8-oct)
  P8  B-8: la tanda (edits) lo lleva en su resumen, con lo que va debajo

Uso:  python tests/test_parser_form.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('parser_form')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
FMX = os.path.join(JAIL, 'UComent.fmx')
ROTO = (b'object Form1: TForm1\r\n'
        b'  // un comentario que el parser del IDE no lee\r\n'
        b'  Caption = \'Form1\'\r\n'
        b'  ClientHeight = 200\r\n'
        b'  ClientWidth = 300\r\n'
        b'  object Button1: TButton\r\n'
        b'    Position.X = 10.000000000000000000\r\n'
        b'    Position.Y = 10.000000000000000000\r\n'
        b'    Text = \'Button1\'\r\n'
        b'  end\r\n'
        b'end\r\n')
open(FMX, 'wb').write(ROTO)
STYLE = os.path.join(JAIL, 'Estilo.style')
ESTILO = (b'object TStyleContainer\r\n'
          b'  object TLayout\r\n'
          b'    StyleName = \'mibtn\'\r\n'
          b'    Align = Client\r\n'
          b'  end\r\n'
          b'end\r\n')
open(STYLE, 'wb').write(ESTILO)

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='parser-form', t=300)
try:
    r = srv.call('delphi_designer', {'command': 'lint', 'path': FMX}, t=200)
    check('P1 lint de un .fmx con un //: DSGN-123 con la linea 2 y su texto',
          mc.es(r, 'SN_DSGN_PARSER_FMT') and 'Line 2: // un comentario' in r, r[:500])
    r = srv.call('delphi_designer', {'command': 'preview', 'path': FMX}, t=200)
    check('P2 preview del mismo: DSGN-126 antes de lanzar el renderizador, con su linea',
          # '(line 2: <la cita>' es NUESTRO: el 'on line 2' lo trae ya el mensaje de la
          # RTL y no media la linea (revisor 2 de la noche, B-11)
          mc.abre(r, 'SR_DSGN_PREVIEW_PARSER_FMT') and '(line 2: // un comentario' in r, r[:400])
    r = srv.call('delphi_designer', {'command': 'set', 'path': FMX, 'component': 'Button1', 'prop': 'Text',
                                     'value': 'Otro'}, t=200)
    check('P3 set sobre un form YA roto: DSGN-125 y el form no cambia',
          mc.abre(r, 'SR_DSGN_PARSER_YA_ROTO_FMT') and open(FMX, 'rb').read() == ROTO, r[:400])
    r = srv.call('delphi_styles', {'command': 'set', 'path': STYLE, 'style': 'mibtn', 'prop': 'Opacity',
                                   'value': '{zz}'}, t=120)
    check('P4 delphi_styles set de un bloque {zz} que el parser no lee: DSGN-124 y el .style no cambia',
          mc.abre(r, 'SR_DSGN_PARSER_NO_ESCRIBE_FMT') and open(STYLE, 'rb').read() == ESTILO, r[:400])

    # P5: los controles
    open(FMX, 'wb').write(ROTO.replace(b'  // un comentario que el parser del IDE no lee\r\n', b''))
    r = srv.call('delphi_designer', {'command': 'lint', 'path': FMX}, t=200)
    check('P5 el form arreglado: lint sin DSGN-123', not mc.es(r, 'SN_DSGN_PARSER_FMT'), r[:300])
    r = srv.call('delphi_designer', {'command': 'preview', 'path': FMX}, t=200)
    check('P5 ...y preview sin DSGN-126', not mc.es(r, 'SR_DSGN_PREVIEW_PARSER_FMT'), r[:300])
    r = srv.call('delphi_styles', {'command': 'set', 'path': STYLE, 'style': 'mibtn', 'prop': 'Opacity',
                                   'value': '0.5'}, t=120)
    check('P5 ...y un set bueno en el estilo se escribe', not mc.fallo(r) and b'Opacity = 0.5' in open(STYLE, 'rb').read(),
          r[:300])

    # P6: un form de texto en UTF-16 (FF FE): set lo escribe y avisa como lint
    _f16 = os.path.join(JAIL, 'UAncho.fmx')
    open(_f16, 'wb').write(b'\xff\xfe' + ROTO.replace(b'  // un comentario que el parser del IDE no lee\r\n', b'')
                           .decode('ascii').encode('utf-16-le'))
    r = srv.call('delphi_designer', {'command': 'set', 'path': _f16, 'component': 'Button1', 'prop': 'Text',
                                     'value': 'Ancho'}, t=200)
    _b16 = open(_f16, 'rb').read()
    check('P6 set en un form UTF-16: se escribe en UTF-16 y avisa DSGN-121 (dcc no lo compila)',
          not mc.fallo(r) and mc.es(r, 'SN_DSGN_FORM_ANCHO_FMT') and _b16.startswith(b'\xff\xfe') and
          'Ancho' in _b16[2:].decode('utf-16-le'), r[:400])

    # P7: delphi_edit sobre el form arreglado de P5, metiendo un //
    r = srv.call('delphi_edit', {'path': FMX, 'old': 'object Form1: TForm1',
                                 'new': 'object Form1: TForm1\n  // otro comentario'}, t=200)
    check('P7 delphi_edit que mete un // en un .fmx: DSGN-123 en su respuesta (avisa, no niega)',
          not mc.fallo(r) and mc.es(r, 'SN_DSGN_PARSER_FMT') and b'// otro comentario' in open(FMX, 'rb').read(),
          r[-600:])
    # P8: lo mismo por la tanda, en otro form sano
    _tanda = os.path.join(JAIL, 'UTanda.fmx')
    open(_tanda, 'wb').write(ROTO.replace(b'  // un comentario que el parser del IDE no lee\r\n', b''))
    r = srv.call('delphi_edit', {'path': _tanda, 'edits': json.dumps([
        {'old': "Caption = 'Form1'", 'new': "Caption = 'Form1'\n  // de la tanda"}])}, t=200)
    check('P8 la tanda (edits) lleva el DSGN-123 en su resumen (B-8)',
          not mc.fallo(r) and mc.es(r, 'SN_DSGN_PARSER_FMT'), r[-600:])
    # ...y lo que va DEBAJO de un aviso *** (revisor 3, B-2: DSGN-123 ya llevaba
    # ***, y el filtro viejo de solo las lineas *** tambien lo pasaba): la lista
    # de EDIT-076, cuya linea no lleva marca
    _tanda2 = os.path.join(JAIL, 'UTanda2.fmx')
    open(_tanda2, 'wb').write(ROTO.replace(b'  // un comentario que el parser del IDE no lee\r\n', b''))
    r = srv.call('delphi_edit', {'path': _tanda2, 'edits': json.dumps([
        {'old': "    Text = 'Button1'", 'new': "    Text = 'Button1'\n    Inventada = 1"}])}, t=200)
    check('P8 ...y lo que va debajo de un aviso *** (la propiedad que nombra EDIT-076), no solo su cabecera',
          not mc.fallo(r) and mc.es(r, 'SN_EDIT_AVISO_DESIGNER_PROPIEDADES_FMT') and
          '"Inventada" does not exist' in r, r[-800:])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('parser del IDE')
