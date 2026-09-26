# -*- coding: utf-8 -*-
"""E2E battery: la papelera recuperable, que no se podia ni encontrar ni
restaurar del todo.

TRES sintomas apuntados como bugs conocidos por separado, UNA causa: al
aparcar un fichero, delphi_delete le pone el sello de hora DETRAS de la
extension -"UFicha.pas-215825250"-, y nadie sabia quitarselo.

  T1  delphi_list includetrash=true encuentra lo BORRADO
      (ensenaba las copias de seguridad, que conservan su nombre, y escondia
      justo lo borrado, que es lo unico que ese flag promete)
  T2  ...sin ensenar los marcadores .by, que no son ficheros del usuario
  T3  restaurar una unit de formulario se lleva su .dfm
      (el camino de "esto es una unit" miraba la extension, leia
      ".pas-215825250" y no entraba: quedaba una unit sin designer, que el
      IDE ya no abre)
  T4  ...y lo dice en la respuesta
  T5  restaurar NO deja una papelera dentro de la papelera
      (hacia copia de la copia, con el sello doblado, y cada restauracion
      anadia otra capa)
  T6  restaurar barre el marcador .by de los dos ficheros
  T7  sin includetrash la papelera sigue escondida (no se ha abierto de par
      en par por el camino)
  T8  EL NOMBRADOR: la copia previa a un restore -que se componia a mano, con
      OTRA forma de sello (".pas.antes-restaurar-221530")- tambien se
      encuentra y tambien se restaura. Tres sitios componian rutas dentro de
      __delphi-patch con tres convenciones y el lector solo entendia una:
      arreglado el borde, el punto seguia abierto. Ahora el sello lo pone UN
      nombrador y lo que distingue una copia de otra es su CAJON.

Usage:  python tests/test_round37.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round37')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r37'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R37]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)  # el plazo de esta bateria
cli.session('r37')
call = cli.call


PROY = os.path.join(JAIL, 'p')

try:
    call('delphi_create', {'kind': 'project-vcl', 'name': 'Pap', 'dir': PROY})
    dpr = os.path.join(PROY, 'Pap.dpr')
    call('delphi_create', {'kind': 'form-vcl', 'name': 'UFicha',
                           'project': dpr})
    pas = os.path.join(PROY, 'UFicha.pas')
    dfm = os.path.join(PROY, 'UFicha.dfm')
    check('setup: el form y su designer existen',
          os.path.exists(pas) and os.path.exists(dfm))

    borrado = call('delphi_delete', {'path': pas})
    check('setup: borrado a la papelera', 'papelera' in borrado.lower() and
          not os.path.exists(pas) and not os.path.exists(dfm), borrado[:200])

    # ------------------------------------------------------------------ T1
    lst = json.loads(call('delphi_list', {'root': PROY, 'includetrash': True}))
    rutas = [f['path'] for f in lst['files']]
    enpap = [p for p in rutas if 'deleted' in p.replace('/', '\\')]
    check('T1 includetrash encuentra la unit BORRADA',
          any('UFicha.pas-' in p for p in enpap), str(rutas)[:300])
    check('T1b ...y tambien su designer borrado',
          any('UFicha.dfm-' in p for p in enpap), str(rutas)[:300])

    # ------------------------------------------------------------------ T2
    # sobre un listado que SI trae la papelera: vacio tambien "no tenia .by"
    check('T2 no se cuelan los marcadores .by',
          bool(enpap) and not any(p.lower().endswith('.by') for p in rutas), str(rutas)[:300])

    # ------------------------------------------------------------------ T7
    sin = json.loads(call('delphi_list', {'root': PROY}))
    # escondida = el listado la CUENTA como oculta (hiddenTrash), no solo que
    # no aparezca: un listado vacio tampoco la ensenaba
    check('T7 sin includetrash la papelera sigue escondida',
          sin.get('hiddenTrash', 0) >= 1 and
          not any('deleted' in f['path'].replace('/', '\\')
                  for f in sin['files']), str(sin)[:260])

    # ------------------------------------------------------------------ T3
    # La copia se localiza EN DISCO y no en la respuesta de T1, a proposito:
    # asi T3-T6 miden la restauracion aunque el listado no sepa encontrarla,
    # que es justo lo que pasa contra un build anterior. Una bateria que se
    # cae en el primer fallo deja de medir los demas.
    copia = ''
    for r_, d_, f_ in os.walk(PROY):
        for x in f_:
            if x.startswith('UFicha.pas-') and not x.endswith('.by'):
                copia = os.path.join(r_, x)
    check('setup: la copia de la unit esta en la papelera', bool(copia), PROY)
    rest = call('delphi_move', {'path': copia, 'dest': pas}) if copia else \
        '(no se encontro la copia)'
    check('T3 la unit vuelve', os.path.exists(pas), rest[:200])
    check('T3b y su .dfm vuelve CON ella', os.path.exists(dfm), rest[:260])
    check('T4 ...y la respuesta lo dice',
          'dfm' in rest.lower(), rest[:260])

    # ------------------------------------------------------------------ T5
    anidada = []
    for r_, d_, f_ in os.walk(os.path.join(PROY, '__delphi-patch')):
        if r_.replace('/', '\\').count('__delphi-patch') > 1:
            anidada.append(r_)
    # T5/T5b miran la papelera DESPUES de una restauracion que ocurrio (la
    # unit volvio): sin restaurar, tampoco habia nada anidado ni doblado
    restaurada = os.path.exists(pas)
    check('T5 restaurar no crea una papelera dentro de la papelera',
          restaurada and not anidada, str(anidada)[:240])
    dobles = []
    for r_, d_, f_ in os.walk(os.path.join(PROY, '__delphi-patch')):
        for x in f_:
            if x.count('-') >= 2 and x.split('-')[-1].isdigit() and \
               x.split('-')[-2].isdigit():
                dobles.append(x)
    check('T5b ...ni sellos de hora encadenados', restaurada and not dobles,
          str(dobles)[:240])

    # ------------------------------------------------------------------ T6
    quedan = []
    for r_, d_, f_ in os.walk(os.path.join(PROY, '__delphi-patch')):
        quedan += [x for x in f_ if x.lower().endswith('.by')]
    check('T6 los marcadores .by de lo restaurado se barren',
          not any('UFicha' in x for x in quedan), str(quedan)[:240])

    # ------------------------------------------------------------------ T8
    # Se edita UMain.pas y se restaura: eso deja una copia "previa al
    # restore" que ANTES se llamaba UMain.pas.antes-restaurar-221530 y que
    # ningun lector de la papelera reconocia.
    umain = os.path.join(PROY, 'UMain.pas')
    orig = open(umain, 'rb').read()
    call('delphi_edit', {'path': umain, 'old': 'implementation',
                         'new': 'implementation' + chr(10) + chr(10) +
                                '// linea que se perdera al restaurar'})
    r = call('delphi_edit', {'path': umain, 'restore': True, 'confirm': True})
    check('T8 setup: restaurado', 'RESTAURADO' in r, r[:200])
    previas = []
    for r_, d_, f_ in os.walk(os.path.join(PROY, '__delphi-patch')):
        for x in f_:
            if x.startswith('UMain.pas') and x != 'UMain.pas':
                previas.append(os.path.join(r_, x))
    check('T8b la copia previa al restore lleva el sello del NOMBRADOR',
          previas and all(p.split('-')[-1].isdigit() and
                          len(p.split('-')[-1]) == 9 for p in previas),
          str([os.path.basename(p) for p in previas])[:240])
    lst2 = json.loads(call('delphi_list', {'root': PROY,
                                           'includetrash': True}))
    check('T8c ...y includetrash la encuentra, como a las de borrado',
          any('UMain.pas-' in f['path'] for f in lst2['files']),
          str([f['path'] for f in lst2['files']])[:300])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round37')
