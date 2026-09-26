# -*- coding: utf-8 -*-
"""E2E battery: la jaula NO sigue junctions ni symlinks fuera del root.

EL ESCAPE (encontrado el 20-sep-2026 por un agente auditor, confirmado y
detenido ahi mismo). El control de frontera validaba la ruta TEXTUAL - que
cae dentro del root - pero el sistema de ficheros desreferencia el reparse
point a su destino real. Un junction plantado dentro del root apuntando a
C:\\Windows\\System32\\drivers\\etc hizo que delphi_list listara ese directorio
y que delphi_read devolviera el hosts de la maquina.

Y no hacia falta una consola en el servidor para plantarlo: un
"delphi_git clone" con core.symlinks=true mete el enlace sin salir del MCP,
o sea que el escape era alcanzable por el propio agente. Con el servidor
corriendo como servicio con la cuenta del operador, el alcance era todo lo
que esa cuenta alcanza.

La causa cabe en una linea: TPath.GetFullPath normaliza el TEXTO y no sigue
reparse points. La jaula hay que medirla contra la ruta REAL
(GetFinalPathNameByHandle), y los roots tambien, o se resuelve un solo lado
de la comparacion.

  E1  control: sin enlaces, dentro se lee y fuera se rechaza
  E2  un junction DENTRO del root apuntando FUERA no se puede listar
  E3  ...ni leer a traves de el
  E4  ...ni escribir a traves de el
  E5  ...ni crear un fichero nuevo a traves de el (la ruta aun no existe:
      se resuelve el antecesor)
  E6  un junction que apunta DENTRO del root sigue funcionando: el arreglo
      cierra el escape sin romper el caso legitimo

Necesita poder crear junctions (mklink /J NO pide administrador). Si no se
puede, la bateria lo DICE y no finge que paso.

Usage:  python tests/test_round33.py [path-to-DelphiLspMcp.exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round33')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')        # el botin, fuera de la jaula
DENTRO = os.path.join(JAIL, 'dentro')      # destino legitimo, dentro
for d in (EXEDIR, JAIL, FUERA, DENTRO):
    os.makedirs(d)
EXE = mc.copia_exe(EXEDIR)

SECRETO = 'unit Secreto;\n\ninterface\n\nimplementation\n\nend.\n'
open(os.path.join(FUERA, 'Secreto.pas'), 'w').write(SECRETO)
open(os.path.join(DENTRO, 'Legitima.pas'), 'w').write(
    SECRETO.replace('Secreto', 'Legitima'))


def junction(enlace, destino):
    """mklink /J no necesita administrador. True si quedo hecho."""
    r = subprocess.run(['cmd', '/c', 'mklink', '/J', enlace, destino],
                       capture_output=True, text=True)
    return r.returncode == 0 and os.path.isdir(enlace)


SALIDA = os.path.join(JAIL, 'salida')      # enlace -> FUERA  (el escape)
INTERNO = os.path.join(JAIL, 'interno')    # enlace -> DENTRO (legitimo)
HAY_SALIDA = junction(SALIDA, FUERA)
HAY_INTERNO = junction(INTERNO, DENTRO)

TOK = 'r33'
PORT = mc.puerto_libre()

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R33]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en JSON: es lo que ensena el detalle de un FAIL
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r33')
call = cli.call


# La negativa CONCRETA de la jaula, no "cualquier RECHAZADO o error": un
# "error: no existe" o un ancla que no casa tambien pasaban por negativa.
def fuera(t):
    """rechazado por estar FUERA de las raices (la ruta textual ya sale)."""
    return t.startswith('RECHAZADO') and 'FUERA de los workspaces permitidos' in t


def por_enlace(t):
    """rechazado porque un tramo del camino es un ENLACE que sale de la jaula."""
    return t.startswith('RECHAZADO') and 'ENLACE (junction o symlink)' in t


try:
    # -------------------------------------------------------------------- E1
    t = call('delphi_read', {'path': os.path.join(DENTRO, 'Legitima.pas')})
    check('E1 control: dentro del root se lee', 'unit Legitima' in t, t[:160])
    t = call('delphi_read', {'path': os.path.join(FUERA, 'Secreto.pas')})
    check('E1b control: la misma ruta por fuera del root se rechaza',
          fuera(t) and 'unit Secreto' not in t, t[:160])

    if not HAY_SALIDA:
        check('E2..E5 NO SE HAN PODIDO PROBAR: mklink /J no pudo crear el '
              'junction en este equipo', False, 'sin junction no hay medida')
    else:
        # ---------------------------------------------------------------- E2
        t = call('delphi_list', {'root': SALIDA})
        check('E2 listar a traves de un junction que sale del root: RECHAZADO',
              por_enlace(t) and 'Secreto.pas' not in t, t[:200])
        # ---------------------------------------------------------------- E3
        t = call('delphi_read', {'path': os.path.join(SALIDA, 'Secreto.pas')})
        check('E3 leer a traves de el: RECHAZADO (y NO llega el contenido)',
              por_enlace(t) and 'unit Secreto' not in t, t[:200])
        # ---------------------------------------------------------------- E4
        t = call('delphi_edit', {'path': os.path.join(SALIDA, 'Secreto.pas'),
                                 'old': 'interface', 'new': 'interface // x'})
        check('E4 escribir a traves de el: RECHAZADO', por_enlace(t), t[:200])
        check('E4b ...y el fichero de fuera sigue intacto',
              open(os.path.join(FUERA, 'Secreto.pas')).read() == SECRETO,
              'lo ha tocado')
        # ---------------------------------------------------------------- E5
        # La ruta NO existe aun: lo que hay que resolver es el ANTECESOR.
        nuevo = os.path.join(SALIDA, 'Plantado.md')
        t = call('delphi_textedit', {'path': nuevo, 'create': True,
                                     'content': 'plantado'})
        check('E5 crear algo nuevo a traves de el: RECHAZADO', por_enlace(t),
              t[:200])
        check('E5b ...y de verdad no ha aparecido nada fuera',
              not os.path.exists(os.path.join(FUERA, 'Plantado.md')),
              'se ha plantado fuera de la jaula')

    # -------------------------------------------------------------------- E6
    if not HAY_INTERNO:
        check('E6 NO SE HA PODIDO PROBAR: sin junction interno', False, '')
    else:
        t = call('delphi_read', {'path': os.path.join(INTERNO,
                                                      'Legitima.pas')})
        check('E6 un junction que apunta DENTRO del root sigue funcionando: '
              'el arreglo cierra el escape sin romper el caso legitimo',
              'unit Legitima' in t, t[:200])
finally:
    try:
        proc.kill()
    except Exception:
        pass
    # Los junctions se quitan con rmdir, que NO toca el destino.
    for enlace in (SALIDA, INTERNO):
        try:
            if os.path.isdir(enlace):
                os.rmdir(enlace)
        except Exception:
            pass

mc.fin('test_round33')
