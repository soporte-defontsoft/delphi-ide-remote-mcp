# -*- coding: utf-8 -*-
"""E2E battery for ReadOnlyPaths - carpetas de DENTRO de la jaula que se leen
pero no se escriben.

Nace de un caso real (20-sep-2026). Al estrechar la jaula de este repo al
propio repo, entraron con permiso de escritura dos clones de referencia que
viven dentro y tienen su PROPIO git (gdk-mcp, skybuck-mcp). Sacarlos fuera no
vale: lo relacionado con el proyecto vive en la carpeta del proyecto, que es
lo que encuentra quien lo clona. Y como son repos aparte, una escritura por
descuido ni siquiera sale en el "git status" del principal - puede pasar una
sesion entera sin que nadie se entere.

El servidor ya tenia esta semantica exacta para la zona de biblioteca del IDE
("reading tools may enter it; writing tools never can"), pero cableada. Esto
la abre al settings.ini.

  L1  leer dentro de un ReadOnlyPaths SI se puede (no es la jaula)
  L2  buscar dentro tambien
  L3  editar NO, y la negativa lo distingue de la jaula y nombra la clave
  L4  tras la negativa el fichero esta byte a byte como estaba
  L5  textedit, create y delete tampoco entran
  L6  fuera de esa carpeta se escribe igual que siempre (la regla no se
      desborda)
  L7  una entrada ABSOLUTA vale igual que una relativa

Usage:  python tests/test_round32.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round32')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
VENDOR = os.path.join(JAIL, 'vendor')       # relativa al root
AJENO = os.path.join(BASE, 'otro')          # absoluta, y FUERA del root
MIO = os.path.join(JAIL, 'mio')
for d in (EXEDIR, VENDOR, MIO, AJENO):
    os.makedirs(d)
EXE = mc.copia_exe(EXEDIR)

UNIT = ('unit Ajena;\n\ninterface\n\n'
        'procedure Saluda;\n\nimplementation\n\n'
        'procedure Saluda;\nbegin\nend;\n\nend.\n')
AJENA = os.path.join(VENDOR, 'Ajena.pas')
open(AJENA, 'w').write(UNIT)
open(os.path.join(VENDOR, 'LEEME.md'), 'w').write('# ajeno\n\nno tocar\n')
MIA = os.path.join(MIO, 'Mia.pas')
open(MIA, 'w').write(UNIT.replace('Ajena', 'Mia'))
# La carpeta absoluta esta FUERA del root a proposito: asi se comprueba que la
# jaula sigue mandando y que ReadOnlyPaths no es una puerta de entrada.
open(os.path.join(AJENO, 'Fuera.pas'), 'w').write(UNIT.replace('Ajena', 'Fuera'))

TOK = 'r32'
PORT = mc.puerto_libre()

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R32]',
    'Token=%s' % TOK,
    'Roots=%s' % JAIL,
    'ReadOnlyPaths=vendor;%s' % AJENO,
    '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en el detalle (como siempre en esta bateria)
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r32')
call = cli.call


ANTES = open(AJENA, 'rb').read()
try:
    # ----------------------------------------------------------------- L1/L2
    t = call('delphi_read', {'path': AJENA})
    check('L1 leer dentro de ReadOnlyPaths SI se puede (no es la jaula)',
          'procedure Saluda' in t, t[:200])
    t = call('delphi_search', {'root': JAIL, 'query': 'Saluda'})
    check('L2 buscar entra igual: aparece el fichero de vendor',
          'Ajena.pas' in t, t[:200])

    # -------------------------------------------------------------------- L3
    t = call('delphi_edit', {'path': AJENA, 'old': 'procedure Saluda;',
                             'new': 'procedure Saludado;', 'atline': 5})
    check('L3 editar dentro se RECHAZA', 'RECHAZADO' in t, t[:200])
    check('L3b la negativa nombra la clave que lo decide',
          'ReadOnlyPaths' in t, t[:250])
    check('L3c y lo distingue de la jaula: dice que leer SI puede',
          'SOLO LECTURA' in t.upper() and 'delphi_read' in t, t[:250])

    # -------------------------------------------------------------------- L4
    check('L4 tras la negativa el fichero sigue byte a byte igual',
          open(AJENA, 'rb').read() == ANTES, 'cambio en disco')

    # -------------------------------------------------------------------- L5
    t = call('delphi_textedit', {'path': os.path.join(VENDOR, 'LEEME.md'),
                                 'old': 'no tocar', 'new': 'tocado'})
    check('L5 textedit tampoco entra', 'RECHAZADO' in t, t[:200])
    t = call('delphi_textedit', {'path': os.path.join(VENDOR, 'Nuevo.md'),
                                 'create': True, 'content': 'x'})
    check('L5b crear dentro tampoco', 'RECHAZADO' in t, t[:200])
    check('L5c ...y de verdad no se ha creado',
          not os.path.exists(os.path.join(VENDOR, 'Nuevo.md')), 'existe')
    t = call('delphi_delete', {'path': AJENA})
    check('L5d borrar dentro tampoco', 'RECHAZADO' in t, t[:200])
    check('L5e ...y el fichero sigue ahi', os.path.exists(AJENA), 'no esta')

    # -------------------------------------------------------------------- L6
    t = call('delphi_edit', {'path': MIA, 'old': 'procedure Saluda;',
                             'new': 'procedure Saludado;', 'atline': 5})
    check('L6 fuera de esa carpeta se escribe igual que siempre: la regla no '
          'se desborda al resto de la jaula',
          'RECHAZADO' not in t and 'Saludado' in open(MIA).read(), t[:200])

    # -------------------------------------------------------------------- L7
    # La entrada ABSOLUTA esta fuera del root: manda la jaula, y la negativa
    # tiene que ser la de la jaula, no la de solo lectura. ReadOnlyPaths NO
    # es una puerta de entrada.
    # La negativa CONCRETA de la jaula (PathDenied), y ni una linea del
    # fichero: antes valia cualquier texto con "error" - un envoltorio
    # JSON-RPC de error, o un RECHAZADO por otro motivo, pasaban.
    t = call('delphi_read', {'path': os.path.join(AJENO, 'Fuera.pas')})
    check('L7 una ReadOnlyPaths absoluta FUERA del root no abre nada: '
          'sigue mandando la jaula',
          t.startswith('RECHAZADO') and 'FUERA de los workspaces permitidos' in t
          and 'ReadOnlyPaths' not in t and 'procedure Saluda' not in t,
          t[:250])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('test_round32')
