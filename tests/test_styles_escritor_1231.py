# -*- coding: utf-8 -*-
r"""delphi_styles set pregunta al escritor de FMX, como designer set (V141 de la 1.23.1).

set escribia el valor que le daban, tal cual, y una propiedad nueva justo detras de StyleName.
Un color de 6 cifras (xF7DFC6) salia CHANGED y FMX lo carga x00F7DFC6: alfa 00, invisible;
designer set del mismo valor decia storedAs (medido el 28-oct, report de fable-opencode). El juez:
el escritor de FMX tal como lo usa el IDE, el conversor de 32 bits (totext): el de 64 escribe los
flotantes con 17 decimales y el IDE con 18 (medido con los .style de los Samples).

  S1 Fill.Color = xF7DFC6: se escribe x00F7DFC6 y lo dice STYLE-058 (ROJA contra b28336a: tal cual)
  S2 una propiedad NUEVA (Opacity) va donde la pone el escritor: detras de HitTest, no detras de
     StyleName (ROJA)
  S3 el valor que ya da la clase (Opacity = 1) en un objeto que tenia 0.5: la linea se quita y lo
     dice STYLE-059 (ROJA: escribia Opacity = 1)
  S4 un flotante con sus 18 decimales: sin STYLE-058 (el escritor de 32 bits lo escribe igual; con
     el de 64 saldria 0.25000000000000000)
  S5 (control) un color de 8 cifras: sin STYLE-058
  S6 0.4 en una propiedad Single (Opacity): el escritor guarda 0.400000005960464500, el valor que
     FMX carga, y STYLE-058 lo dice (medido: el IDE escribe igual un Single)

Uso:  python tests/test_styles_escritor_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('styles-escritor')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
ST = os.path.join(BASE, 'Styles')
os.makedirs(ST)
STYLE = os.path.join(ST, 'Uno.style')
ORIGINAL = ("object TStyleContainer\r\n"
            "  object TRectangle\r\n"
            "    StyleName = 'cardstyle'\r\n"
            "    Align = Client\r\n"
            "    Fill.Color = xFFFFFFFF\r\n"
            "    HitTest = False\r\n"
            "    Size.Width = 50.000000000000000000\r\n"
            "    Size.Height = 50.000000000000000000\r\n"
            "    Size.PlatformDefault = False\r\n"
            "  end\r\n"
            "end\r\n")


def escribe(texto=ORIGINAL):
    with open(STYLE, 'w', newline='') as f:
        f.write(texto)


def lee():
    with open(STYLE, newline='') as f:
        return f.read()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='styles-escritor', t=120)


def pon(prop, valor):
    return srv.call('delphi_styles', {'command': 'set', 'path': STYLE, 'style': 'cardstyle',
                                      'prop': prop, 'value': valor})


try:
    escribe()
    r = pon('Fill.Color', 'xF7DFC6')
    check('S1 un color de 6 cifras se escribe como FMX lo guarda (x00F7DFC6) y STYLE-058 lo dice',
          'Fill.Color = x00F7DFC6' in lee() and mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT'), (r[:400], lee()))

    escribe()
    r = pon('Opacity', '0.500000000000000000')
    lineas = [x.strip() for x in lee().split('\r\n')]
    check('S2 una propiedad nueva va donde la pone el escritor: detras de HitTest',
          'Opacity = 0.500000000000000000' in lineas and
          lineas.index('Opacity = 0.500000000000000000') == lineas.index('HitTest = False') + 1, (r[:300], lineas))

    escribe(ORIGINAL.replace("    HitTest = False\r\n", "    HitTest = False\r\n    Opacity = 0.500000000000000000\r\n"))
    r = pon('Opacity', '1')
    check('S3 el valor que ya da la clase: la linea se quita y STYLE-059 lo dice',
          'Opacity' not in lee() and mc.es(r, 'SN_STYLES_NO_GUARDADA_FMT'), (r[:400], lee()))

    escribe()
    r = pon('Opacity', '0.250000000000000000')
    check('S4 un flotante con sus 18 decimales: sin STYLE-058 (el escritor de 32 bits, el del IDE)',
          'Opacity = 0.250000000000000000' in lee() and not mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT'),
          (r[:400], lee()))

    escribe()
    r = pon('Opacity', '0.400000000000000000')
    check('S6 0.4 en un Single: se guarda 0.400000005960464500, como el IDE, y STYLE-058 lo dice',
          'Opacity = 0.400000005960464500' in lee() and mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT'),
          (r[:400], lee()))

    escribe()
    r = pon('Fill.Color', 'xFF102030')
    check('S5 (control) un color de 8 cifras: sin STYLE-058',
          'Fill.Color = xFF102030' in lee() and not mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT'), (r[:400], lee()))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('styles set y el escritor de FMX 1.23.1 (V141)')
