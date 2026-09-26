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
              '->' in r and '3| PRIMERO-1' in r and '9| TERCERO-1' in r,  # linea y texto del disco
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
          'ROLLBACK' in r, r[:160])
    check('B5b ...y el fichero vuelve byte a byte',
          open(f, 'rb').read() == antes, 'el fichero cambio')
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round34')
