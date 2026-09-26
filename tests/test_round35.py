# -*- coding: utf-8 -*-
"""E2E battery: el RANGO (old + toline), el muro de los tres intentos.

Hasta la 1.0.5 no habia forma de quitar un tramo de lineas sin pegarlo entero
como ancla de bloque: para tirar un metodo de 40 lineas habia que mandar las
40. Con "toline" el ancla deja de ser UNA linea y pasa a ser la PRIMERA de un
tramo que acaba ahi, incluida.

Lo que vigila esta bateria:

  R1  borrado por rango en delphi_textedit
  R2  ...y en delphi_edit, que es el gemelo (mismo helper, RangoHasta)
  R3  rango + "new": el tramo se sustituye entero
  R4  rango al reves -> rechazo, y el fichero intacto
  R5  toline mas alla del final -> rechazo, y el fichero intacto
  R6  rango que se lleva el fichero ENTERO -> rechazo (es reescribirlo
      entero por la puerta de al lado, y eso ya estaba prohibido)
  R7  EN UNA TANDA el rango se ARRASTRA: si una entrada anterior anade
      lineas, toline se corrige solo. Sin esto se lleva por delante lineas
      que no eran, contestando OK.
  R8  ancla de BLOQUE + toline -> rechazo (dos formas de decir lo mismo)
  R9  toline en un modo que no va por lineas (create) -> rechazo, no se
      traga en silencio
  R10 los acentos DENTRO del tramo no disparan la alarma de "acentos fuera
      de cuadro" (el recuento mira lo que sale de verdad, no el ancla)
  R11 los apodos del parametro (to / endline) llegan a toline
  R12 la respuesta DICE cuantas lineas se han ido y desde donde
  R13 un campo que NO existe dentro de una entrada de "edits" se rechaza.
      Se leen a mano, uno a uno, asi que una errata no daba "Unknown
      parameter": se ignoraba, y la entrada acababa haciendo otra cosa y
      contestando OK. (Lo destapo esta misma bateria: contra el binario
      anterior "toline" entraba sin protestar.)

Usage:  python tests/test_round35.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round35')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r35'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R35]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

# espera a que ESCUCHE (antes un sleep fijo de 3 s)
proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r35')
call = cli.call


def lineas(path):
    return open(path, encoding='utf-8').read().replace('\r\n', '\n').split('\n')


SEIS = 'uno\ndos\ntres\ncuatro\ncinco\nseis\n'

# Un fuente Pascal de verdad: delphi_edit audita la estructura (un solo
# 'end.', y que sea la ultima linea), asi que el rango tiene que respetarla.
UNIT = ('unit Prueba;\n'
        '\n'
        'interface\n'
        '\n'
        'implementation\n'
        '\n'
        'procedure Sobra;\n'
        'begin\n'
        '  WriteLn(1);\n'
        '  WriteLn(2);\n'
        'end;\n'
        '\n'
        'procedure Queda;\n'
        'begin\n'
        '  WriteLn(3);\n'
        'end;\n'
        '\n'
        'end.\n')

try:
    # ------------------------------------------------------------------ R1
    f = os.path.join(JAIL, 'rango.md')
    open(f, 'w', newline='\n').write(SEIS)
    r = call('delphi_textedit',
             {'path': f, 'old': 'dos', 'toline': 4, 'delete': True})
    ls = [l for l in lineas(f) if l]
    check('R1 textedit: old+toline+delete quita el tramo entero',
          ls == ['uno', 'cinco', 'seis'], '%s | %s' % (ls, r[:140]))

    # ------------------------------------------------------------------ R12
    check('R12 la respuesta dice cuantas lineas y desde donde',
          'BORRADAS 3 lineas' in r and 'de la 2 a la 4' in r, r[:200])

    # ------------------------------------------------------------------ R2
    fp = os.path.join(JAIL, 'Prueba.pas')
    open(fp, 'w', newline='\n').write(UNIT)
    r = call('delphi_edit',
             {'path': fp, 'old': 'procedure Sobra;', 'toline': 11,
              'delete': True})
    txt = open(fp, encoding='utf-8').read()
    check('R2 edit: el gemelo Pascal borra el mismo rango',
          'procedure Sobra' not in txt and 'procedure Queda' in txt, r[:160])
    check('R2b ...y la estructura sigue sana (un solo end. al final)',
          txt.count('\nend.') == 1 and 'ESTRUCTURA ROTA' not in r,
          r[:200])

    # ------------------------------------------------------------------ R3
    f = os.path.join(JAIL, 'sust.md')
    open(f, 'w', newline='\n').write(SEIS)
    r = call('delphi_textedit',
             {'path': f, 'old': 'dos', 'toline': 5, 'new': 'EN SU LUGAR'})
    ls = [l for l in lineas(f) if l]
    check('R3 rango + new: el tramo entero se sustituye',
          ls == ['uno', 'EN SU LUGAR', 'seis'], '%s | %s' % (ls, r[:140]))
    check('R3b ...y lo dice como sustitucion, no como borrado',
          'SUSTITUIDAS 4 lineas' in r, r[:200])

    # ------------------------------------------------------------------ R4
    f = os.path.join(JAIL, 'reves.md')
    open(f, 'w', newline='\n').write(SEIS)
    antes = open(f, 'rb').read()
    r = call('delphi_textedit',
             {'path': f, 'old': 'cuatro', 'toline': 2, 'delete': True})
    check('R4 rango al reves: rechazado', 'toline=2' in r and 'ANTES' in r,
          r[:200])
    check('R4b ...y el fichero intacto', open(f, 'rb').read() == antes,
          'el fichero cambio')

    # ------------------------------------------------------------------ R5
    r = call('delphi_textedit',
             {'path': f, 'old': 'dos', 'toline': 99, 'delete': True})
    check('R5 toline mas alla del final: rechazado',
          'toline=99' in r and '6 lineas' in r, r[:200])
    check('R5b ...y el fichero intacto', open(f, 'rb').read() == antes,
          'el fichero cambio')

    # ------------------------------------------------------------------ R6
    r = call('delphi_textedit',
             {'path': f, 'old': 'uno', 'toline': 6, 'delete': True})
    check('R6 un rango que se lleva el fichero entero: rechazado',
          r.startswith('RECHAZADO') and 'ENTERO' in r, r[:200])
    check('R6b ...y el fichero intacto', open(f, 'rb').read() == antes,
          'el fichero cambio')

    # ------------------------------------------------------------------ R7
    # EL caso que muerde. La entrada 1 mete DOS lineas delante; la entrada 2
    # pide un rango cuyos numeros ya no valen. Si toline no se arrastra, o se
    # lleva lineas que no eran o el rango queda al reves y todo hace
    # ROLLBACK; en los dos casos, mal.
    for tool, ext in (('delphi_textedit', '.md'), ('delphi_edit', '.pas')):
        f = os.path.join(JAIL, 'tanda' + ext)
        open(f, 'w', newline='\n').write(SEIS)
        r = call(tool, {'path': f, 'edits': json.dumps([
            {'old': 'uno', 'new': 'uno\nEXTRA1\nEXTRA2'},
            {'old': 'tres', 'toline': 4, 'delete': True},
        ])})
        ls = [l for l in lineas(f) if l]
        check('R7 %s: el rango se arrastra tras una entrada que anade' % tool,
              ls == ['uno', 'EXTRA1', 'EXTRA2', 'dos', 'cinco', 'seis'],
              '%s | %s' % (ls, r[:160]))

    # ------------------------------------------------------------------ R8
    f = os.path.join(JAIL, 'bloque.md')
    open(f, 'w', newline='\n').write(SEIS)
    antes = open(f, 'rb').read()
    r = call('delphi_textedit', {'path': f, 'edits': json.dumps([
        {'old': 'dos\ntres', 'toline': 5, 'delete': True},
    ])})
    # el rechazo CONCRETO de la tanda (antes valia cualquier texto con
    # 'toline' y 'error': un envoltorio JSON-RPC, o un aplicado que lo nombrara)
    check('R8 ancla de bloque + toline: rechazado',
          r.startswith('ROLLBACK') and 'NADA se ha aplicado' in r and
          '"toline" no se combina con un ancla de VARIAS lineas' in r, r[:300])
    check('R8b ...y el fichero intacto', open(f, 'rb').read() == antes,
          'el fichero cambio')

    # ------------------------------------------------------------------ R9
    nuevo = os.path.join(JAIL, 'nacido.md')
    r = call('delphi_textedit',
             {'path': nuevo, 'create': True, 'content': 'hola\n',
              'toline': 3})
    check('R9 toline en un modo que no va por lineas: rechazado, no ignorado',
          'toline' in r and not os.path.exists(nuevo), r[:200])

    # ------------------------------------------------------------------ R10
    # El recuento de bytes altos de delphi_edit comparaba lo que entra con lo
    # que sale... y "lo que sale" era el ANCLA. Con un rango salen tambien las
    # lineas de debajo, asi que cualquier acento ahi dentro disparaba la
    # alarma que manda PARAR y restaurar.
    fa = os.path.join(JAIL, 'Acentos.pas')
    open(fa, 'w', newline='\n', encoding='utf-8').write(
        'unit Acentos;\n\ninterface\n\nimplementation\n\n'
        'procedure Fuera;\nbegin\n'
        "  WriteLn('camion');\n"
        "  WriteLn('accion numero dos');\n"
        'end;\n\nend.\n'.replace('camion', 'camión')
                        .replace('accion', 'acción'))
    r = call('delphi_edit',
             {'path': fa, 'old': 'procedure Fuera;', 'toline': 11,
              'delete': True})
    check('R10 los acentos del tramo no disparan la alarma de acentos',
          'ACENTOS FUERA DE CUADRO' not in r and 'procedure Fuera' not in
          open(fa, encoding='utf-8').read(), r[:240])

    # ------------------------------------------------------------------ R13
    f = os.path.join(JAIL, 'errata.md')
    open(f, 'w', newline='\n').write(SEIS)
    antes = open(f, 'rb').read()
    for malo, bueno in (('occurence', 'occurrence'), ('atlines', 'atline'),
                        ('Old', 'old')):
        r = call('delphi_textedit', {'path': f, 'edits': json.dumps([
            {'old': 'dos', 'new': 'DOS', malo: 1},
        ])})
        check('R13 el campo inventado "%s" se rechaza (no se ignora)' % malo,
              malo in r and bueno in r and r.startswith('RECHAZADO'), r[:200])
    check('R13b ...y el fichero intacto', open(f, 'rb').read() == antes,
          'el fichero cambio')

    # ------------------------------------------------------------------ R14
    # occurrence fuera de rango se IGNORABA: la resolucion devolvia 0, el
    # motor lo leia como "sin desempate" y la edicion caia en la PRIMERA
    # aparicion. El parametro que existe para no equivocarse de sitio te
    # llevaba al sitio equivocado, contestando OK.
    # El ancla es UNICA: sin ambiguedad que lo cace, pedir la ocurrencia 3 se
    # resolvia a 0, el motor lo leia como "sin desempate" y editaba la unica
    # que hay, contestando OK. Con un ancla repetida el viejo ya protestaba
    # -por ambigua, no por el occurrence-, asi que el agujero solo se ve aqui.
    f = os.path.join(JAIL, 'occ.md')
    open(f, 'w', newline='\n').write('a\nsolo\nb\nc\n')
    antes = open(f, 'rb').read()
    r = call('delphi_textedit', {'path': f, 'edits': json.dumps([
        {'old': 'solo', 'new': 'CAMBIADA', 'occurrence': 3},
    ])})
    check('R14 occurrence fuera de rango se rechaza, no se ignora',
          r.startswith('RECHAZADO') and 'occurrence 3' in r and
          'solo hay 1' in r, r[:220])
    check('R14b ...y no ha tocado la unica aparicion que hay',
          open(f, 'rb').read() == antes, open(f).read()[:80])
    # Y el caso repetido sigue protestando (por otra puerta, pero protesta)
    f2 = os.path.join(JAIL, 'occ2.md')
    open(f2, 'w', newline='\n').write('a\nrep\nb\nrep\nc\n')
    antes2 = open(f2, 'rb').read()
    r = call('delphi_textedit', {'path': f2, 'edits': json.dumps([
        {'old': 'rep', 'new': 'CAMBIADA', 'occurrence': 5},
    ])})
    check('R14c con el ancla repetida tampoco pasa de largo',
          'RECHAZADO' in r and open(f2, 'rb').read() == antes2, r[:220])
    # R16: un ancla VACIA con occurrence en una tanda tumbaba la tool con un
    # Access violation (el mensaje de rechazo hacia ''.Split()[0]; medido
    # 2026-09-26 contra produccion). Se rechaza como cualquier otra.
    r = call('delphi_textedit', {'path': f2, 'edits': json.dumps([
        {'old': '', 'new': 'CAMBIADA', 'occurrence': 5},
    ])})
    check('R16 ancla vacia + occurrence: se rechaza, sin Access violation',
          'RECHAZADO' in r and 'Access violation' not in r and
          open(f2, 'rb').read() == antes2, r[:220])

    # R17: el salto FINAL de new, una regla (LineasDeNew): uno es el fin de
    # linea, cada uno de mas una linea en blanco - de una linea o de bloque.
    # Habia tres reglas; con ancla de bloque se comia las lineas en blanco
    # del final y contestaba APLICADAS (medido 2026-09-26).
    for nombre, args, esperado in (
            ('linea, un salto', {'old': 'b', 'new': 'B\n'}, 'a\nB\nc\n'),
            ('linea, dos saltos', {'old': 'b', 'new': 'B\n\n'}, 'a\nB\n\nc\n'),
            ('bloque, un salto', {'edits': json.dumps([{'old': 'a\nb', 'new': 'a\nB\n'}])}, 'a\nB\nc\n'),
            ('bloque, dos saltos', {'edits': json.dumps([{'old': 'a\nb', 'new': 'a\nB\n\n'}])}, 'a\nB\n\nc\n')):
        f3 = os.path.join(JAIL, 'salto.md')
        open(f3, 'w', newline='\n').write('a\nb\nc\n')
        r = call('delphi_textedit', dict(args, path=f3))
        hay = open(f3, newline='').read()
        check('R17 salto final de new (%s)' % nombre, hay == esperado, '%r | %s' % (hay, r[:120]))

    # ------------------------------------------------------------------ R11
    for apodo in ('to', 'endline'):
        f = os.path.join(JAIL, 'apodo-%s.md' % apodo)
        open(f, 'w', newline='\n').write(SEIS)
        r = call('delphi_textedit',
                 {'path': f, 'old': 'dos', apodo: 4, 'delete': True})
        ls = [l for l in lineas(f) if l]
        check('R11 el apodo "%s" llega a toline' % apodo,
              ls == ['uno', 'cinco', 'seis'], '%s | %s' % (ls, r[:140]))
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round35')
