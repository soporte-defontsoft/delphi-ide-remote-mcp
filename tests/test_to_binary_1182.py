# -*- coding: utf-8 -*-
"""delphi_designer to-binary lee el form como lo leen el IDE y dcc (1.18.2,
punto 4, M2). Tenia su camino propio: el texto ya decodificado, recodificado a
ANSI. Negaba (DSGN-045) un UTF-8 o UTF-16 con BOM que lint daba por limpio y
que dcc compila entero. Ahora le da los BYTES de disco al parser por el
alimentador de lint (DesignerAFlujo, tal cual) y el binario es el que compila dcc de
ese fichero. Rojo contra produccion (cfea828): B1, B4 y B6; B2, B3 y B5 ya
pasaban (el llamador decodificaba un form sin BOM en ANSI, como dcc): son
GUARDAS de que el camino nuevo no cambia lo que estaba bien.

Medido contra dcc el 13-oct (un exe compilado de estos mismos forms): con BOM,
'ok ✔ Ж' entra como vaUTF8String entero; sin BOM, 'Configuración' entra
con la ó partida en dos letras (C3 B3 leidos en la ANSI 1252).

  B1 UTF-8 con BOM con caracteres fuera de la ANSI: lint limpio Y to-binary
     convierte; el Caption del binario es el de dcc (vaUTF8String 'ok ✔ Ж')
  B2 UTF-8 SIN BOM con una o con tilde: el Caption es el de dcc (C3 83 C2 B3,
     solo en una maquina 1252)
  B3 ANSI con la o con tilde en crudo (F3): 'Configuración' entero
  B4 UTF-16 LE con BOM: desde A28 de la 1.23 el IDE no lo carga, y lint y
     to-binary lo niegan los dos (DSGN-122, el form intacto); convertia
  B5 un NOMBRE con letra fuera de ASCII en un form ANSI: el parser no lo lee y
     la negativa dice cual y en que linea (DSGN, el mensaje claro de antes)
  B6 la regla de M2 en todos: lint limpio <=> to-binary convierte

Y lo del revisor propio del punto 4 (13-oct):
  B7 UTF-32 LE / B8 UTF-32 BE: lo mismo que B4 (convertian, por UTF-16)
  B9 UTF-16 con medio caracter: DSGN-122 tambien y el form intacto (R7: salia
     U+FFFD sin decir nada; el suelto lo niega ahora to-text, DSGN-147, que es
     quien lo convierte: test_form_ancho_1230 T3)
  B10 UTF-8 con BOM, nombre no ASCII en la linea 2 y una cadena sin cerrar en
     la 3: el error del parser, no DSGN-120 (R2: con BOM el parser lee el nombre)
  B11 ANSI, cadena sin cerrar en la 2 y nombre no ASCII en la 4: el error del
     parser, no DSGN-120 (R2: el nombre no esta en la linea que nombra)

Uso:  python tests/test_to_binary_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('to_binary_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
ACP = ctypes.windll.kernel32.GetACP()

CABEZA = 'object FormA: TFormA\r\n  Left = 0\r\n  Top = 0\r\n'
PIE = '  ClientHeight = 100\r\n  ClientWidth = 200\r\nend\r\n'


def form(nombre, cuerpo_bytes):
    p = os.path.join(JAIL, nombre)
    open(p, 'wb').write(cuerpo_bytes)
    return p


def caption_del_binario(p):
    """(tipo, bytes) del Caption del primer objeto del .dfm binario."""
    b = open(p, 'rb').read()
    j = b.find(b'\x07Caption')
    if j < 0:
        return None, b''
    t = b[j + 8]
    if t == 6:  # vaString: un byte de largo
        n = b[j + 9]
        return t, b[j + 10:j + 10 + n]
    if t in (0x12, 0x14):  # vaWString / vaUTF8String: cuatro bytes de largo
        n = int.from_bytes(b[j + 9:j + 13], 'little')
        return t, b[j + 13:j + 13 + n * (2 if t == 0x12 else 1)]
    return t, b''


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='to-binary', t=120)
casos = []
try:
    def prueba(nombre, contenido):
        p = form(nombre, contenido)
        rl = srv.call('delphi_designer', {'path': p, 'command': 'lint'})
        rb = srv.call('delphi_designer', {'path': p, 'command': 'to-binary'})
        casos.append((nombre, not mc.rechazado(rl) and 'DSGN-020' in rl, not mc.rechazado(rb)))
        return p, rl, rb

    # B1 UTF-8 con BOM, fuera de la ANSI
    txt = CABEZA + "  Caption = 'ok ✔ Ж'\r\n" + PIE
    p, rl, rb = prueba('B1.dfm', b'\xef\xbb\xbf' + txt.encode('utf-8'))
    t, c = caption_del_binario(p)
    check('B1 UTF-8 con BOM fuera de la ANSI: lint limpio y to-binary convierte, Caption = el de dcc',
          'DSGN-020' in rl and not mc.rechazado(rb) and t == 0x14 and c == 'ok ✔ Ж'.encode('utf-8'),
          (rl[:120], rb[:200], t, c))

    # B2 UTF-8 SIN BOM: como dcc, en la ANSI de la maquina
    txt = CABEZA + "  Caption = 'Configuración'\r\n" + PIE
    p, rl, rb = prueba('B2.dfm', txt.encode('utf-8'))
    t, c = caption_del_binario(p)
    if ACP == 1252:
        check('B2 UTF-8 SIN BOM: el Caption es el de dcc (C3 B3 leidos en 1252: C3 83 C2 B3)',
              not mc.rechazado(rb) and c == 'ConfiguraciÃ³n'.encode('utf-8'), (rb[:200], t, c))
    else:
        print('NOTA B2: la ANSI de esta maquina es %d, no 1252: el Caption de dcc es otro y no se mide' % ACP)

    # B3 ANSI con la o con tilde en crudo
    txt = CABEZA + "  Caption = 'Configuración'\r\n" + PIE
    p, rl, rb = prueba('B3.dfm', txt.encode('cp1252') if ACP == 1252 else txt.replace('ó', "'#243'").encode('ascii'))
    t, c = caption_del_binario(p)
    check('B3 ANSI con la o con tilde: el Caption sale entero',
          not mc.rechazado(rb) and c == 'Configuración'.encode('utf-8'), (rb[:200], t, c))

    # B4 UTF-16 LE con BOM
    txt = CABEZA + "  Caption = 'ok ✔ Ж'\r\n" + PIE
    antes = b'\xff\xfe' + txt.encode('utf-16-le')
    p, rl, rb = prueba('B4.dfm', antes)
    check('B4 UTF-16 con BOM: lint y to-binary lo niegan (DSGN-122, el IDE no lo carga) y el form intacto',
          mc.abre(rl, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and mc.abre(rb, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and
          open(p, 'rb').read() == antes, (rl[:120], rb[:200]))

    # B5 un NOMBRE fuera de ASCII en un form ANSI: el mensaje claro
    if ACP == 1252:
        txt = 'object FormA: TFormA\r\n  object Botón1: TButton\r\n  end\r\nend\r\n'
        p, rl, rb = prueba('B5.dfm', txt.encode('cp1252'))
        check('B5 un nombre con letra fuera de ASCII en un form ANSI: negado diciendo cual y donde',
              mc.abre(rb, 'SR_DSGN_NOMBRE_NO_ASCII_BINARIO_FMT') and 'Botón1' in rb, rb[:300])
    else:
        print('NOTA B5: la ANSI de esta maquina es %d, no 1252: no se mide' % ACP)

    # B7 UTF-32 LE dentro de la ANSI
    txt = CABEZA + "  Caption = 'Configuración'\r\n" + PIE
    antes = b'\xff\xfe\x00\x00' + txt.encode('utf-32-le')
    p, rl, rb = prueba('B7.dfm', antes)
    check('B7 UTF-32 LE: lint y to-binary lo niegan (DSGN-122) y el form intacto',
          mc.abre(rl, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and mc.abre(rb, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and
          open(p, 'rb').read() == antes, (rl[:120], rb[:200]))

    # B8 UTF-32 BE fuera de la ANSI
    txt = CABEZA + "  Caption = 'ok ✔ Ж'\r\n" + PIE
    antes = b'\x00\x00\xfe\xff' + txt.encode('utf-32-be')
    p, rl, rb = prueba('B8.dfm', antes)
    check('B8 UTF-32 BE: lint y to-binary lo niegan (DSGN-122) y el form intacto',
          mc.abre(rl, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and mc.abre(rb, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and
          open(p, 'rb').read() == antes, (rl[:120], rb[:200]))

    # B9 UTF-16 con medio caracter: negado por ancho, el form intacto (fuera de B6)
    txt = CABEZA + "  Caption = 'a\ud800b'\r\n" + PIE
    antes = b'\xff\xfe' + txt.encode('utf-16-le', 'surrogatepass')
    p = form('B9.dfm', antes)
    rb = srv.call('delphi_designer', {'path': p, 'command': 'to-binary'})
    check('B9 UTF-16 con medio caracter: DSGN-122 (no U+FFFD callado) y el form intacto',
          mc.abre(rb, 'SR_DSGN_FORM_ANCHO_NO_CARGA_FMT') and open(p, 'rb').read() == antes, rb[:300])

    # B10 con BOM: el error de otra linea no lo tapa un nombre no ASCII
    txt = "object FormA: TFormA\r\n  object BotónÑ: TButton\r\n    Caption = 'abc\r\n  end\r\nend\r\n"
    p, rl, rb = prueba('B10.dfm', b'\xef\xbb\xbf' + txt.encode('utf-8'))
    check('B10 UTF-8 con BOM, cadena sin cerrar en la 3: el error del parser (DSGN-046, line 3), no DSGN-120',
          mc.abre(rb, 'SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT') and 'line 3' in rb, rb[:300])

    # B11 sin BOM: el nombre no esta en la linea que nombra el parser
    if ACP == 1252:
        txt = ("object FormA: TFormA\r\n  Caption = 'abc\r\n  Left = 0\r\n"
               "  object Botón1: TButton\r\n  end\r\nend\r\n")
        p, rl, rb = prueba('B11.dfm', txt.encode('cp1252'))
        check('B11 ANSI, cadena sin cerrar en la 2 y nombre no ASCII en la 4: DSGN-046 (line 2), no DSGN-120',
              mc.abre(rb, 'SR_DSGN_NO_PUDE_CONVERTIR_BINARIO_FMT') and 'line 2' in rb, rb[:300])
    else:
        print('NOTA B11: la ANSI de esta maquina es %d, no 1252: no se mide' % ACP)
finally:
    srv.cierra()

# B6 la regla de M2: lint limpio <=> to-binary convierte
desacuerdos = [(n, l, b) for (n, l, b) in casos if l != b]
check('B6 en todos los forms, lint limpio <=> to-binary convierte (la regla de M2)',
      not desacuerdos, desacuerdos)

mc.borra(BASE)
mc.fin('to-binary como dcc 1182')
