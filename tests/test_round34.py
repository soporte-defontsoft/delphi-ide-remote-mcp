# -*- coding: utf-8 -*-
"""E2E battery: la familia de TANDAS, ahora que tiene un solo motor.

Las dos tools de escritura compartian 132 y 140 lineas con un 78% identico.
Ese duplicado es lo que hizo que el bug de "occurrence" -resolver la ocurrencia
contra el fichero YA MUTADO, escribir en la linea equivocada y contestar OK-
tuviera que arreglarse dos veces... y dejara una TERCERA puerta abierta: las
anclas de BLOQUE, que pasaban por otra funcion.

Con Lsp.Patch.AplicaTanda las tres puertas son una. Esta bateria la vigila:

  B1  occurrence de BLOQUE dentro de una tanda cae en el bloque correcto
      aunque una entrada anterior haya movido las lineas
  B2  ...y en las dos tools, que es lo que el motor unico garantiza
  B3  un bloque que ANADE lineas desplaza las ocurrencias pendientes (antes
      la rama de bloque salia por Continue justo antes del arrastre, asi que
      no desplazaba nada)
  B4  la tanda devuelve ECO DE VERIFICACION: lo que hay en disco despues,
      no solo el ancla que pediste
  B5  todo-o-nada sigue intacto tras el refactor
  B6  una estructura que se abre en una entrada y se cierra en otra no avisa;
      si el fichero FINAL queda roto, la tanda avisa una vez
  B7  occurrence cuenta sin la sangria, igual en las dos tools (9-oct-2026:
      delphi_edit casaba "la linea TERMINA en el ancla" y escribia otra)
  B7b la guarda de sangria: un ancla que TRAE sangria y la linea que elige
      occurrence con otra -> negativa con las candidatas, en las dos tools
  B8  un ancla con MAS sangria que su linea unica casa (no hay eleccion)
  B9  un ancla que solo su sangria hacia unica se niega, suelta y en tanda
  B10 delphi_edit: el final de la linea cuenta, y la pista (EDIT-094) lo dice

Usage:  python tests/test_round34.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round34')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r34'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R34]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK)
cli.session('r34')
call = cli.call
CAT = mc.catalogo()


# Tres bloques IDENTICOS de dos lineas, separados. Una entrada previa mete
# lineas ANTES de todos ellos, para que las ocurrencias se muevan.
def semilla():
    return ('cabecera\n'
            'MARCA\n'
            'alfa\n'
            'beta\n'
            'medio uno\n'
            'alfa\n'
            'beta\n'
            'medio dos\n'
            'alfa\n'
            'beta\n'
            'final\n')


try:
    for tool, ext in (('delphi_textedit', '.md'), ('delphi_edit', '.pas')):
        # delphi_edit exige un fuente Delphi: se usa el mismo contenido pero
        # con extension .pas, que para anclas de bloque da igual.
        f = os.path.join(JAIL, 'tanda' + ext)
        open(f, 'w', newline='\n').write(semilla())
        # El caso que MUERDE no es mover lineas: es que una entrada anterior
        # cambie CUANTOS bloques casan. Al sustituir el primero quedan dos, y
        # quien recuenta sobre el fichero ya mutado no encuentra un tercero -
        # o peor, cae en otro. Resolviendo contra el ORIGINAL, el tercero
        # sigue siendo el tercero.
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': 'alfa\nbeta', 'new': 'PRIMERO-1\nPRIMERO-2',
             'occurrence': 1},
            {'old': 'alfa\nbeta', 'new': 'TERCERO-1\nTERCERO-2',
             'occurrence': 3},
        ])})
        lineas = [l for l in open(f).read().split('\n')]
        # el tercero es el que precede a 'final'
        try:
            i = lineas.index('final')
            acerto = lineas[i - 2] == 'TERCERO-1' and lineas[i - 1] == 'TERCERO-2'
        except ValueError:
            acerto = False
        check('B1/B2 %s: occurrence de BLOQUE cae en el 3o aunque una entrada '
              'anterior moviera las lineas' % tool, acerto,
              'quedo: %s | respuesta: %s' % (lineas, r[:160]))
        check('B3 %s: el 1o se sustituyo y el 2o (el del medio) sigue '
              'intacto' % tool,
              'PRIMERO-1' in lineas and lineas.count('alfa') == 1
              and lineas.count('beta') == 1,
              'quedo: %s' % lineas)
        check('B4 %s: la tanda devuelve ECO de lo que hay en disco, no solo '
              'el ancla' % tool,
              # linea y texto del disco, en LA forma de una cita (Lsp.Mascara.CitaDeLinea, 4-oct-2026)
              '->' in r and '3|PRIMERO-1' in r and '9|TERCERO-1' in r,
              r[:200])
        # el eco sale con UN separador de linea: mezclaba el CRLF de
        # AppendLine con el LF del mensaje que lo envuelve (26-sep-2026)
        check('B4b %s: el eco no mezcla CRLF con LF' % tool,
              '\r' not in r and r.count('\n') >= 3, repr(r[:120]))

    # ------------------------------------------------------------------ B5
    f = os.path.join(JAIL, 'atomico.md')
    open(f, 'w', newline='\n').write(semilla())
    antes = open(f, 'rb').read()
    r = call('delphi_textedit', {'path': f, 'edits': json.dumps([
        {'old': 'cabecera', 'new': 'CAMBIADA'},
        {'old': 'esta linea no existe en ninguna parte', 'new': 'x'},
    ])})
    check('B5 todo-o-nada: la tanda con una entrada mala se deshace entera',
          mc.es(r, 'SR_PATCH_EDITS_ROLLED_FMT'), r[:160])
    check('B5b ...y el fichero vuelve byte a byte',
          open(f, 'rb').read() == antes, 'el fichero cambio')

    # ------------------------------------------------------------------ B6
    # La ESTRUCTURA de una unidad se juzga sobre el fichero ENTERO al acabar
    # la tanda (2.5 de la 1.18.0): una entrada abre un (* y la siguiente lo
    # cierra; a mitad de tanda el end. quedaba DENTRO del comentario y la
    # auditoria de cada entrada avisaba de BROKEN STRUCTURE de un fichero que
    # acaba bien.
    def unidad():
        return ('unit UEstructura;\n\ninterface\n\nimplementation\n\n'
                'procedure Uno;\nbegin\nend;\n\nend.\n')
    f = os.path.join(JAIL, 'UEstructura.pas')
    open(f, 'w', newline='\r\n').write(unidad())
    r = call('delphi_edit', {'path': f, 'edits': json.dumps([
        {'old': 'procedure Uno;', 'new': '(* apartado un rato\nprocedure Uno;'},
        {'old': 'end;', 'new': 'end;\n*)'},
    ])})
    txt = open(f).read()
    check('B6 una tanda que abre un (* en una entrada y lo cierra en la siguiente: aplicada, '
          'sin aviso de BROKEN STRUCTURE',
          mc.abre(r, 'SN_PATCH_EDITS_OK_FMT') and '(* apartado' in txt and '*)' in txt and
          not mc.es(r, 'SN_EDIT_ESTRUCTURA_ROTA_END_FMT') and
          not mc.es(r, 'SN_EDIT_ESTRUCTURA_ROTA_ULTIMA'), r[:300])
    # ...y el aviso sigue saliendo cuando el fichero FINAL esta roto: el (*
    # se abre y nadie lo cierra
    open(f, 'w', newline='\r\n').write(unidad())
    r = call('delphi_edit', {'path': f, 'edits': json.dumps([
        {'old': 'procedure Uno;', 'new': '(* apartado un rato\nprocedure Uno;'},
        {'old': 'interface', 'new': 'interface\n// nada'},
    ])})
    check('B6b ...y si el fichero FINAL queda roto (el (* no se cierra), la tanda avisa UNA vez',
          mc.abre(r, 'SN_PATCH_EDITS_OK_FMT') and
          r.count('EDIT-085') == 1, r[:400])

    # B7 (medido el 9-oct-2026): anclas que solo difieren en la SANGRIA. La
    # descripcion promete que la sangria no cuenta; delphi_edit casaba "la
    # linea TERMINA en el ancla" (la sangria del ancla contaba como minima) y
    # la ocurrencia 2 del ancla de 4 espacios era la linea de 6: la tanda
    # escribio en silencio la linea equivocada. delphi_textedit acertaba.
    # Las dos tools, la misma tanda, el mismo resultado byte a byte.
    for tool, ext in (('delphi_textedit', '.md'), ('delphi_edit', '.pas')):
        f = os.path.join(JAIL, 'sangrias' + ext)
        open(f, 'wb').write(b'a\r\n  X := 1;\r\n    X := 1;\r\n      X := 1;\r\nb\r\n')
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '  X := 1;', 'new': '  X := 10;', 'occurrence': 1},
            {'old': '    X := 1;', 'new': '    X := 20;', 'occurrence': 2},
        ])})
        check('B7 %s: occurrence cuenta sin la sangria - la 2 es la segunda linea, no la tercera' % tool,
              open(f, 'rb').read() == b'a\r\n  X := 10;\r\n    X := 20;\r\n      X := 1;\r\nb\r\n',
              (r[:300], open(f, 'rb').read()))
        # B7b (David, 9-oct-2026): el mismo fallo girado. Un ancla de 6
        # espacios con occurrence 1: contando sin sangria es la linea de 2. No
        # se escribe en la "probable" (la de 6, que casa tal cual) ni en la
        # contada: negativa con las dos candidatas citadas, para contestar con
        # atline. Sin la guarda escribia la de 2 espacios contestando APPLIED
        ORIG7B = b'a\r\n  X := 1;\r\n    X := 1;\r\n      X := 1;\r\nb\r\n'
        open(f, 'wb').write(ORIG7B)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '      X := 1;', 'new': '      X := 30;', 'occurrence': 1}])})
        check('B7b %s: ancla con sangria y la linea de occurrence con otra: negativa (EDIT-121) con '
              'las dos candidatas (2 y 4), sin escribir nada' % tool,
              mc.es(r, 'SR_PATCH_OCCURRENCE_SANGRIA_FMT') and '2|  X := 1;' in r and
              '4|      X := 1;' in r and 'line 4 = occurrence 3' in r and open(f, 'rb').read() == ORIG7B,
              (r[:500], open(f, 'rb').read()))
        # B7c: el REINTENTO que aconseja la negativa (occurrence: 3), con una
        # entrada ANTERIOR en la tanda (David, 9-oct-2026). occurrence cuenta el
        # fichero de antes de la tanda y se arrastra: (i) si la anterior quita
        # una linea, (ii) o anade OTRA coincidencia encima, la 3 sigue siendo la
        # de 6 espacios y se escribe ESA; (iii) si la anterior quita la PROPIA
        # coincidencia, se niega y no se escribe nada
        RETRY = {'old': '      X := 1;', 'new': '      X := 30;', 'occurrence': 3}
        open(f, 'wb').write(ORIG7B)
        r = call(tool, {'path': f, 'edits': json.dumps([{'old': 'a', 'delete': True}, RETRY])})
        check('B7c %s (i): el reintento con occurrence 3 tras una entrada que quita una linea: la de 6 espacios' % tool,
              open(f, 'rb').read() == b'  X := 1;\r\n    X := 1;\r\n      X := 30;\r\nb\r\n', (r[:300], open(f, 'rb').read()))
        open(f, 'wb').write(ORIG7B)
        r = call(tool, {'path': f, 'edits': json.dumps([{'old': 'a', 'new': 'a\n        X := 1;'}, RETRY])})
        check('B7c %s (ii): ...tras una entrada que anade OTRA coincidencia encima: la misma de 6 espacios, no la nueva' % tool,
              open(f, 'rb').read() == b'a\r\n        X := 1;\r\n  X := 1;\r\n    X := 1;\r\n      X := 30;\r\nb\r\n',
              (r[:300], open(f, 'rb').read()))
        open(f, 'wb').write(ORIG7B)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '      X := 1;', 'new': '      Z := 1;', 'atline': 4}, RETRY])})
        check('B7c %s (iii): ...tras una entrada que quita la PROPIA coincidencia: negativa, el fichero intacto' % tool,
              mc.rechazado(r) and open(f, 'rb').read() == ORIG7B, (r[:300], open(f, 'rb').read()))
        # B7d: el atline de un BLOQUE en una tanda gana (se ignoraba, y con
        # occurrence el bloque se contaba sobre el fichero ya mutado: escribia
        # el PRIMER bloque contestando APPLIED; revisor propio, 9-oct-2026)
        ORIG7D = b'h\r\n    A;\r\n    B;\r\nm\r\n    A;\r\n    B;\r\nf\r\n'
        open(f, 'wb').write(ORIG7D)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '    A;\n    B;', 'new': '    A2;\n    B2;', 'occurrence': 1, 'atline': 5}])})
        check('B7d %s: un bloque con atline (y occurrence) en una tanda cae en SU linea, no en el primero' % tool,
              open(f, 'rb').read() == b'h\r\n    A;\r\n    B;\r\nm\r\n    A2;\r\n    B2;\r\nf\r\n', (r[:300], open(f, 'rb').read()))
        # B7e: la guarda en un BLOQUE (la sangria de su primera linea con texto);
        # y un bloque que EMPIEZA en una linea en blanco no salta por ella
        open(f, 'wb').write(b'h\r\n  A;\r\n  B;\r\nm\r\n      A;\r\n      B;\r\nf\r\n')
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '      A;\n      B;', 'new': '      A2;\n      B2;', 'occurrence': 1}])})
        check('B7e %s: la guarda en un bloque: la occurrence 1 lleva otra sangria -> EDIT-121, line 5 = occurrence 2' % tool,
              mc.es(r, 'SR_PATCH_OCCURRENCE_SANGRIA_FMT') and 'line 5 = occurrence 2' in r, r[:400])
        ORIG7E = b'\r\n  foo;\r\n  bar;\r\nx\r\n\r\n  foo;\r\n  bar;\r\n'
        open(f, 'wb').write(ORIG7E)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '    \n  foo;\n  bar;', 'new': '\n  foo2;\n  bar2;', 'occurrence': 2}])})
        check('B7e %s: ...un bloque que empieza en una linea en blanco mira la primera con texto: escribe' % tool,
              open(f, 'rb').read() == b'\r\n  foo;\r\n  bar;\r\nx\r\n\r\n  foo2;\r\n  bar2;\r\n', (r[:300], open(f, 'rb').read()))
        # B7f: occurrence con atline no la dispara (atline gana: es explicito)
        open(f, 'wb').write(ORIG7B)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '      X := 1;', 'new': '  X := 40;', 'occurrence': 1, 'atline': 2}])})
        check('B7f %s: occurrence con atline no dispara la guarda: escribe la linea de atline' % tool,
              open(f, 'rb').read() == b'a\r\n  X := 40;\r\n    X := 1;\r\n      X := 1;\r\nb\r\n', (r[:300], open(f, 'rb').read()))
        # B7g: el mensaje no miente - ninguna candidata, y mas de cinco
        open(f, 'wb').write(b'a\r\n  X := 1;\r\n  X := 1;\r\nb\r\n')
        r = call(tool, {'path': f, 'edits': json.dumps([{'old': '      X := 1;', 'new': 'x', 'occurrence': 1}])})
        check('B7g %s: sin ninguna candidata con esa sangria, lo dice (SF_PATCH_SANGRIA_NINGUNA)' % tool,
              mc.es(r, 'SR_PATCH_OCCURRENCE_SANGRIA_FMT') and CAT['SF_PATCH_SANGRIA_NINGUNA'].strip() in r, r[:400])
        open(f, 'wb').write(b'a\r\n  X := 1;\r\n' + b'      X := 1;\r\n' * 7 + b'b\r\n')
        r = call(tool, {'path': f, 'edits': json.dumps([{'old': '      X := 1;', 'new': 'x', 'occurrence': 1}])})
        check('B7g %s: con siete candidatas, cinco y "and 2 more"' % tool,
              'line 7 = occurrence 6' in r and 'line 8 = occurrence 7' not in r and
              'more: occurrence 7, 8' in r, r[:700])
        # B7i: un ancla de UNA linea que acaba en salto (tipica al copiar) la
        # tanda la trata como bloque; la guarda la mide normalizada y dice
        # EDIT-121, no la negativa de un bloque corto (revisor propio)
        open(f, 'wb').write(ORIG7B)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': '      X := 1;\n', 'new': '      X := 30;', 'occurrence': 1}])})
        check('B7i %s: ancla de una linea con salto final y occurrence: EDIT-121, sin escribir' % tool,
              mc.es(r, 'SR_PATCH_OCCURRENCE_SANGRIA_FMT') and open(f, 'rb').read() == ORIG7B, r[:400])
    # B7h: en delphi_textedit un blanco al FINAL casa (su regla recorta las dos
    # puntas): la candidata con la sangria y un espacio detras se nombra
    f = os.path.join(JAIL, 'sangrias.md')
    open(f, 'wb').write(b'a\r\n  X := 1;\r\n      X := 1; \r\n')
    r = call('delphi_textedit', {'path': f, 'edits': json.dumps([{'old': '      X := 1;', 'new': 'x', 'occurrence': 1}])})
    check('B7h delphi_textedit: la candidata con un blanco al final (que su motor casa) se nombra: line 3 = occurrence 2',
          mc.es(r, 'SR_PATCH_OCCURRENCE_SANGRIA_FMT') and 'line 3 = occurrence 2' in r, r[:400])

    # B8: un ancla con MAS sangria que su linea, que casa UNA vez: no hay nada
    # que elegir, casa (la sangria no cuenta) y new va con la suya
    f = os.path.join(JAIL, 'mas_sangria.pas')
    open(f, 'wb').write(b'a\r\n  Y := 1;\r\nb\r\n')
    r = call('delphi_edit', {'path': f, 'old': '      Y := 1;', 'new': '  Y := 2;'})
    check('B8 delphi_edit: un ancla con mas sangria que su linea unica casa y escribe',
          open(f, 'rb').read() == b'a\r\n  Y := 2;\r\nb\r\n', (r[:300], open(f, 'rb').read()))
    # B9: la red. Un ancla que solo su sangria hacia unica (la de un hijo en un
    # form, con la misma propiedad que el padre) ahora casa dos: se NIEGA con
    # sus lineas, suelta y en una tanda sin occurrence, sin tocar el fichero
    f = os.path.join(JAIL, 'red.dfm')
    ORIG9 = b"object F: TF\r\n  Caption = 'X'\r\n  object P: TP\r\n    Caption = 'X'\r\n  end\r\nend\r\n"
    open(f, 'wb').write(ORIG9)
    r = call('delphi_edit', {'path': f, 'old': "    Caption = 'X'", 'new': "    Caption = 'Y'"})
    r2 = call('delphi_edit', {'path': f, 'edits': json.dumps([
        {'old': "    Caption = 'X'", 'new': "    Caption = 'Y'"}])})
    check('B9 un ancla que solo su sangria hacia unica se niega (EDIT-077), suelta y en una tanda, sin tocar nada',
          mc.es(r, 'SR_EDIT_ANCLA_NO_UNICA_FMT') and mc.rechazado(r2) and open(f, 'rb').read() == ORIG9,
          (r[:200], r2[:200], open(f, 'rb').read()))
    # B10: la sangria fuera, el FINAL sigue contando (EDIT-062 de la novena
    # revision) - y la pista lo dice, ya no habla de "otra indentacion"
    f = os.path.join(JAIL, 'final.pas')
    open(f, 'wb').write(b'a\r\n  foo;  \r\nb\r\n')
    r = call('delphi_edit', {'path': f, 'old': '      foo;', 'new': 'bar;'})
    check('B10 delphi_edit: con la sangria fuera el final cuenta - negativa, y la pista habla del final (EDIT-094)',
          mc.rechazado(r) and mc.es(r, 'SN_ANCLA_BLANCOS_FMT') and
          open(f, 'rb').read() == b'a\r\n  foo;  \r\nb\r\n', r[:400])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round34')
