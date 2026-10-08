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
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round34')
