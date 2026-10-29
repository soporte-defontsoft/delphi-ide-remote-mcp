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

V152: delphi_styles lint no veia un color de menos de 8 cifras. xFF7DFC6 por xFFF7DFC6 en un tema
real (el editrostyle de un proyecto): FMX lo carga x0FF7DFC6, alfa 0F, casi transparente, y solo la
vista previa lo enseno (informe de fable-opencode, 28-oct). Cuantas cifras: gramatica propia; como lo
carga FMX: su escritor. Medido antes: en tres temas reales el escritor reescribe ~190 propiedades por
fichero (defectos, colores con nombre, TabOrder, orden de un set), todo benigno: no se dice todo lo
que reescribe, solo esto. Rojas contra 42f24cd:
  S7 lint de un .style con xFF7DFC6 y x000000: colorsWithoutAlpha los dice con su linea y como los
     carga FMX (x0FF7DFC6), STYLE-061, y clean es false
  S8 (control) el mismo fichero con 8 cifras y un color con nombre: sin colorsWithoutAlpha
  S9 (control de V141) set de xFF7DFC6: se escribe x0FF7DFC6 y STYLE-058 lo dice

V173h y V173i (29-oct, revisor del disenador #8 y #9), rojas contra 6334404:
  S10 (V173h) lint de un .style con Fill.Color = $F7DFC6 (6 cifras con $, como lo escribe Pascal):
      colorsWithoutAlpha lo dice; la gramatica solo veia x
  S11 (V173i) set de xfff7dfc5 (8 cifras, minusculas): el escritor lo guarda xFFF7DFC5 y STYLE-058
      lo dice SIN la pista de "menos de 8 cifras" (se miraba si lo guardado empezaba por x)
  S12 (control) set de xF7DFC6: STYLE-058 CON la pista
  S13 (V173g) lint de un degradado con un item Color = xFF5FBF5: colorsWithoutAlpha lo dice, con
      la clave de su item (Fill.Gradient.Points[0].Color) y como lo carga FMX (x0FF5FBF5); los
      candidatos eran solo las propiedades del nivel propio, fuera de las colecciones
  S14 (control) el otro item, con sus 8 cifras (xFFFFFFFF): no sale
  S15 (V173d) set child=Fondo (un objeto con NOMBRE, sin StyleName) de xF7DFC6: se escribe
      x00F7DFC6 y lo dice STYLE-058. El juicio buscaba el objeto por su nombre en lo que
      devuelve el escritor, que quita los nombres: STYLE-060 "sin escritor" y xF7DFC6 tal cual

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

    # V152: el lint y los colores de menos de 8 cifras
    def lint():
        r = srv.call('delphi_styles', {'command': 'lint', 'path': ST}, 180)
        return r, mc.como_json(r)

    SIN_ALFA = ORIGINAL.replace("    Fill.Color = xFFFFFFFF\r\n",
                                "    Fill.Color = xFF7DFC6\r\n    Stroke.Color = x000000\r\n")
    escribe(SIN_ALFA)
    r, j = lint()
    colores = j.get('colorsWithoutAlpha') or []
    linea7 = SIN_ALFA.split('\r\n').index('    Fill.Color = xFF7DFC6') + 1
    c7 = [c for c in colores if c.get('value') == 'xFF7DFC6']
    c6 = [c for c in colores if c.get('value') == 'x000000']
    check('S7 lint: el color de 7 cifras sale, con su linea, su estilo y como lo carga FMX (x0FF7DFC6)',
          len(c7) == 1 and c7[0].get('line') == linea7 and c7[0].get('prop') == 'Fill.Color' and
          c7[0].get('style') == 'cardstyle' and c7[0].get('loadedAs') == 'x0FF7DFC6', r[:900])
    check('S7 ...y el de 6 cifras, con lo que guarda el escritor (no x000000)',
          len(c6) == 1 and c6[0].get('loadedAs') not in ('x000000', None), r[:900])
    check('S7 ...con su nota STYLE-061, y clean es false',
          mc.es(r, 'SN_STYLES_COLORES_SIN_ALFA_FMT') and j.get('clean') is False, r[:900])
    escribe(ORIGINAL.replace("    Fill.Color = xFFFFFFFF\r\n",
                             "    Fill.Color = xFFF7DFC6\r\n    Stroke.Color = claBlack\r\n"))
    r, j = lint()
    check('S8 (control) 8 cifras y un color con nombre: sin colorsWithoutAlpha',
          'colorsWithoutAlpha' not in j and not mc.es(r, 'SN_STYLES_COLORES_SIN_ALFA_FMT'), r[:600])
    escribe()
    r = pon('Fill.Color', 'xFF7DFC6')
    check('S9 (V141) set de un color de 7 cifras: se escribe x0FF7DFC6 y STYLE-058 lo dice',
          'Fill.Color = x0FF7DFC6' in lee() and mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT'), (r[:400], lee()))

    # V173h: un color sin alfa escrito con $
    escribe(ORIGINAL.replace("    Fill.Color = xFFFFFFFF\r\n", "    Fill.Color = $F7DFC6\r\n"))
    r, j = lint()
    c10 = [c for c in (j.get('colorsWithoutAlpha') or []) if c.get('value') == '$F7DFC6']
    check('S10 (V173h) lint: $F7DFC6 (6 cifras con $) sale en colorsWithoutAlpha, con como lo carga FMX',
          len(c10) == 1 and c10[0].get('loadedAs') not in ('$F7DFC6', None) and
          mc.es(r, 'SN_STYLES_COLORES_SIN_ALFA_FMT'), r[:900])

    # V173i: la pista de las 8 cifras, solo si el valor dado tiene menos (un fragmento sin
    # etiqueta: se busca por su texto del catalogo)
    PISTA = mc.catalogo()['SF_STYLES_COLOR_8_CIFRAS'].strip()
    escribe()
    r = pon('Fill.Color', 'xfff7dfc5')
    check('S11 (V173i) set de xfff7dfc5 (8 cifras): STYLE-058 sin la pista de menos de 8 cifras',
          'Fill.Color = xFFF7DFC5' in lee() and mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT') and
          PISTA not in r, (r[:500], lee()))
    escribe()
    r = pon('Fill.Color', 'xF7DFC6')
    check('S12 (control) set de xF7DFC6 (6 cifras): STYLE-058 con la pista',
          mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT') and PISTA in r, r[:500])

    # V173g: los colores de los items de una coleccion (los puntos de un degradado)
    DEGRADADO = ("object TStyleContainer\r\n"
                 "  object TRectangle\r\n"
                 "    StyleName = 'gradstyle'\r\n"
                 "    Fill.Kind = Gradient\r\n"
                 "    Fill.Gradient.Points = <\r\n"
                 "      item\r\n"
                 "        Color = xFF5FBF5\r\n"
                 "      end\r\n"
                 "      item\r\n"
                 "        Color = xFFFFFFFF\r\n"
                 "        Offset = 1.000000000000000000\r\n"
                 "      end>\r\n"
                 "  end\r\n"
                 "end\r\n")
    escribe(DEGRADADO)
    r, j = lint()
    colores = j.get('colorsWithoutAlpha') or []
    c13 = [c for c in colores if c.get('value') == 'xFF5FBF5']
    check('S13 (V173g) lint: el Color de un item del degradado sale, con la clave de su item y como lo carga FMX',
          len(c13) == 1 and c13[0].get('prop') == 'Fill.Gradient.Points[0].Color' and
          c13[0].get('line') == DEGRADADO.split('\r\n').index('        Color = xFF5FBF5') + 1 and
          c13[0].get('loadedAs') == 'x0FF5FBF5' and c13[0].get('style') == 'gradstyle', r[:900])
    check('S14 (control) el item con sus 8 cifras no sale',
          not [c for c in colores if c.get('value') == 'xFFFFFFFF'], r[:900])

    # V173d: el objeto del escritor, por su posicion (el escritor quita los nombres)
    escribe(ORIGINAL.replace("    Size.PlatformDefault = False\r\n",
                             "    Size.PlatformDefault = False\r\n    object Fondo: TRectangle\r\n"
                             "      Fill.Color = xFFFFFFFF\r\n    end\r\n"))
    r = srv.call('delphi_styles', {'command': 'set', 'path': STYLE, 'style': 'cardstyle', 'child': 'Fondo',
                                   'prop': 'Fill.Color', 'value': 'xF7DFC6'})
    check('S15 (V173d) set de un hijo con nombre y sin StyleName: x00F7DFC6 y STYLE-058, no STYLE-060',
          'Fill.Color = x00F7DFC6' in lee() and mc.es(r, 'SN_STYLES_GUARDADA_COMO_FMT') and
          not mc.es(r, 'SN_STYLES_SIN_ESCRITOR'), (r[:500], lee()))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('styles set, lint y el escritor de FMX 1.23.1 (V141, V152)')
