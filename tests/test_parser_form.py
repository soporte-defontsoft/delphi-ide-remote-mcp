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
  P6  un set sobre un form de texto en UTF-16: DSGN-122 y no escribe - el IDE
      no lo carga (A28 de la 1.23; lo escribia y decia que el IDE lo abria) -
  P7  (B3 de la 1.28) delphi_edit que mete un // en un .fmx que se leia NO lo
      escribe: DSGN-124, como el disenador. Desde la M-B del revisor 2 de la
      noche lo escribia y avisaba DSGN-123 despues (roja contra 578ccf2)
  P7b ...sobre un form YA roto se escribe y se avisa (DSGN-123): quien lo
      arregla a mano escribe pasos que aun no se leen; P7c el paso que lo
      arregla se escribe sin aviso
  P8  la tanda (edits) que deja un // en un form sano vuelve entera: DSGN-124
      y el form byte a byte; P8b juzgada por lo que QUEDA: un paso intermedio
      ilegible que el siguiente quita se escribe. Y lo que va debajo de un
      aviso *** (B-8) sigue en su resumen

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
    # (revisor de baterias, 18-oct-2026) ausencias sobre respuestas que podian
    # ser error: el lint CONTESTA (limpio), y el preview pasa la puerta del
    # parser y llega a la del renderizador - que este servidor no lleva: DSGN-060
    check('P5 el form arreglado: lint limpio, sin DSGN-123',
          mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and not mc.es(r, 'SN_DSGN_PARSER_FMT'), r[:300])
    r = srv.call('delphi_designer', {'command': 'preview', 'path': FMX}, t=200)
    check('P5 ...y preview pasa el parser (sin DSGN-126) hasta el renderizador, que aqui no esta (DSGN-060)',
          not mc.es(r, 'SR_DSGN_PREVIEW_PARSER_FMT') and mc.abre(r, 'SR_DESIGNER_SIN_RENDER_FMT'), r[:300])
    r = srv.call('delphi_styles', {'command': 'set', 'path': STYLE, 'style': 'mibtn', 'prop': 'Opacity',
                                   'value': '0.5'}, t=120)
    check('P5 ...y un set bueno en el estilo se escribe', not mc.fallo(r) and b'Opacity = 0.5' in open(STYLE, 'rb').read(),
          r[:300])

    # P6: un form de texto en UTF-16 (FF FE): set lo niega, como lint (A28 de la 1.23)
    _f16 = os.path.join(JAIL, 'UAncho.fmx')
    open(_f16, 'wb').write(b'\xff\xfe' + ROTO.replace(b'  // un comentario que el parser del IDE no lee\r\n', b'')
                           .decode('ascii').encode('utf-16-le'))
    r = srv.call('delphi_designer', {'command': 'set', 'path': _f16, 'component': 'Button1', 'prop': 'Text',
                                     'value': 'Ancho'}, t=200)
    _b16 = open(_f16, 'rb').read()
    check('P6 set en un form UTF-16: DSGN-122 (el IDE no lo carga) y el form intacto',
          mc.abre(r, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and _b16.startswith(b'\xff\xfe') and
          'Ancho' not in _b16[2:].decode('utf-16-le'), r[:400])

    # P7: delphi_edit sobre el form arreglado de P5, metiendo un //: no se escribe
    _antes7 = open(FMX, 'rb').read()
    r = srv.call('delphi_edit', {'path': FMX, 'old': 'object Form1: TForm1',
                                 'new': 'object Form1: TForm1\n  // otro comentario'}, t=200)
    check('P7 delphi_edit que mete un // en un .fmx sano: DSGN-124 y el form intacto (niega, como el disenador)',
          mc.abre(r, 'SR_DSGN_PARSER_NO_ESCRIBE_FMT') and open(FMX, 'rb').read() == _antes7, r[:500])
    # P7b/P7c: un form YA roto se sigue arreglando a mano, paso a paso
    _roto7 = os.path.join(JAIL, 'URoto7.fmx')
    open(_roto7, 'wb').write(ROTO)
    r = srv.call('delphi_edit', {'path': _roto7, 'old': "    Text = 'Button1'", 'new': "    Text = 'Boton'"}, t=200)
    check('P7b delphi_edit en un form YA roto: se escribe y avisa DSGN-123 (el arreglo a mano sigue abierto)',
          not mc.fallo(r) and mc.es(r, 'SN_DSGN_PARSER_FMT') and b"Text = 'Boton'" in open(_roto7, 'rb').read(),
          r[-600:])
    r = srv.call('delphi_edit', {'path': _roto7, 'old': '  // un comentario que el parser del IDE no lee',
                                 'delete': True}, t=200)
    check('P7c ...y el paso que lo arregla se escribe, ya sin DSGN-123',
          not mc.fallo(r) and not mc.es(r, 'SN_DSGN_PARSER_FMT') and b'//' not in open(_roto7, 'rb').read(),
          r[-600:])
    # P8: lo mismo por la tanda, en otro form sano: vuelve entera
    _tanda = os.path.join(JAIL, 'UTanda.fmx')
    open(_tanda, 'wb').write(ROTO.replace(b'  // un comentario que el parser del IDE no lee\r\n', b''))
    _antes8 = open(_tanda, 'rb').read()
    r = srv.call('delphi_edit', {'path': _tanda, 'edits': json.dumps([
        {'old': "Caption = 'Form1'", 'new': "Caption = 'Form1'\n  // de la tanda"}])}, t=200)
    check('P8 la tanda que deja un // en un form sano: DSGN-124 y el form intacto, byte a byte',
          mc.abre(r, 'SR_DSGN_PARSER_NO_ESCRIBE_FMT') and open(_tanda, 'rb').read() == _antes8, r[:500])
    # (en su propio form: con el de P8, un P8 rojo le dejaba su // y P8b fallaba por el)
    _tanda3 = os.path.join(JAIL, 'UTanda3.fmx')
    open(_tanda3, 'wb').write(_antes8)
    r = srv.call('delphi_edit', {'path': _tanda3, 'edits': json.dumps([
        {'old': "Caption = 'Form1'", 'new': "Caption = 'Form1'\n  // de paso"},
        {'old': '  // de paso', 'delete': True},
        {'old': "    Text = 'Button1'", 'new': "    Text = 'Tanda'"}])}, t=200)
    check('P8b ...juzgada sobre lo que QUEDA: un paso intermedio ilegible que el siguiente quita, se escribe',
          not mc.fallo(r) and b"Text = 'Tanda'" in open(_tanda3, 'rb').read() and b'//' not in open(_tanda3, 'rb').read(),
          r[-600:])
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
