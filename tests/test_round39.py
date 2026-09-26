# -*- coding: utf-8 -*-
"""E2E battery: tres respuestas que no se podian leer.

Ninguna de las tres rompia nada. Las tres hacian perder una llamada, que es
como se gasta el contexto de un agente sin que nadie lo apunte.

  D1  el "path" de las tools de POSICION ya no dice que acepta una carpeta.
      Venia heredado de una clase base compartida con delphi_symbols -la
      unica que SI acepta carpeta-, asi que SEIS tools anunciaban algo que no
      hacen. Compartir la clase base hizo compartir una descripcion que solo
      era verdad en una de ellas.
  D2  ...y delphi_symbols sigue diciendo que SI la acepta
  D3  git diff sobre un arbol limpio dice "sin diferencias" en vez de
      contestar "exit=0" y nada, que es indistinguible de una respuesta rota
      (y lo primero que se hace con una respuesta rota es repetirla)
  D4  ...y las demas ordenes mudas dicen que su silencio ES el exito
  D5  la severidad de delphi_diagnostics documenta los CUATRO valores de la
      escala LSP: llegaba un 4 sin que nada dijera que significa
  D6  delphi_definition sobre algo que no se resuelve ya no contesta "null"
      a secas: cuatro caracteres correctos e ilegibles, que no distinguen
      entre apuntar mal, faltar la configuracion del proyecto y no haber
      nada que resolver - y las tres se arreglan de forma distinta

Usage:  python tests/test_round39.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check


# git deja sus objetos en SOLO LECTURA: mc.carpeta los quita tambien (antes
# lo hacia aqui un borra() propio con chmod)
BASE = mc.carpeta('round39')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR, exist_ok=True)
os.makedirs(JAIL, exist_ok=True)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r39'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R39]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
cli = mc.Http(PORT, TOK, t=180, respaldo_json=True)  # el plazo de esta bateria
cli.session('r39')
call = cli.call


def esquema(tool):
    return json.loads(call('delphi_help', {'command': 'tool', 'name': tool}))


try:
    # ------------------------------------------------------------------ D1
    posicion = ['delphi_definition', 'delphi_hover', 'delphi_completion',
                'delphi_signature', 'delphi_references', 'delphi_rename_symbol']
    mienten = []
    for t in posicion:
        try:
            d = esquema(t)['parameters']['properties']['path']['description']
        except Exception as ex:
            mienten.append('%s (%s)' % (t, ex))
            continue
        # Se afirma el CONTRATO, no la letra: lo que mentia era prometer el
        # digest de una carpeta. Buscar la palabra "carpeta" a secas daria
        # falso positivo con el texto nuevo, que la usa para NEGARLO.
        if 'OFRECE cada unit' in d:
            mienten.append(t)
    check('D1 ninguna tool de posicion promete el digest de una carpeta',
          not mienten, 'lo siguen prometiendo: %s' % mienten)
    dicen = [t for t in posicion
             if 'no una carpeta' in
             esquema(t)['parameters']['properties']['path']['description']]
    check('D1b ...y las de esta unit lo dicen explicitamente',
          len(dicen) >= 4, 'solo lo dicen: %s' % dicen)

    # ------------------------------------------------------------------ D2
    ds = esquema('delphi_symbols')['parameters']['properties']['path']['description']
    check('D2 ...y delphi_symbols sigue diciendo que SI la acepta',
          'CARPETA' in ds.upper(), ds[:200])

    # ------------------------------------------------------------------ D3
    repo = os.path.join(JAIL, 'r')
    os.makedirs(repo)
    call('delphi_git', {'repo': repo, 'command': 'init'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.email', 'message': 'r39@test'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.name', 'message': 'R39'})
    open(os.path.join(repo, 'a.txt'), 'w').write('uno\n')
    call('delphi_git', {'repo': repo, 'command': 'add', 'args': '-A'})
    call('delphi_git', {'repo': repo, 'command': 'commit', 'message': 'uno'})
    d = call('delphi_git', {'repo': repo, 'command': 'diff'})
    check('D3 git diff en arbol limpio dice que no hay diferencias',
          'sin diferencias' in d and len(d.strip()) > len('exit=0') + 5, d[:200])

    # ------------------------------------------------------------------ D4
    a = call('delphi_git', {'repo': repo, 'command': 'add', 'args': '-A'})
    check('D4 una orden muda dice que su silencio ES el exito',
          'exit=0' in a and 'terminado bien' in a, a[:200])

    # ------------------------------------------------------------------ D5
    desc = esquema('delphi_diagnostics')['description']
    check('D5 la severidad documenta los CUATRO valores de la escala LSP',
          '4=hint' in desc and '3=information' in desc, desc[:260])

    # ------------------------------------------------------------------ D6
    pas = os.path.join(JAIL, 'N.pas')
    open(pas, 'w', newline='\r\n').write(
        'unit N;\n\ninterface\n\nimplementation\n\nend.\n')
    # la linea 4 (0-based) es "implementation": una palabra reservada, ahi no
    # hay simbolo que resolver
    n = call('delphi_definition', {'path': pas, 'line': 4, 'character': 2})
    check('D6 un null viene explicado, no a secas',
          n.startswith('null') and len(n) > 200 and '0-BASED' in n, n[:220])
    check('D6b ...y dice las tres causas, que se arreglan distinto',
          ('delphi_read' in n) and ('delphi_symbols' in n), n[:260])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round39')
