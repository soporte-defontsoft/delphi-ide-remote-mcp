# -*- coding: utf-8 -*-
"""Round 50: la estructura de carpetas de un proyecto la decide el programador.

Lo que enseno el sandbox el 2026-09-21, en diez minutos de usar las tools como
un agente cualquiera, y que ninguna de las 69 baterias veia:

  D  delphi_create ignoraba "dir" en silencio para todo lo que no fuese un
     proyecto: la unit caia junto al .dpr y la respuesta decia que bien.
  P  el buscador de proyectos de una unit solo subia UN nivel: una unit a tres
     carpetas de su .dpr no tenia proyecto.
  M  mover una CARPETA entera dejaba el .dpr/.dproj apuntando a donde ya no
     habia nada, con respuesta de exito.
  B  borrar una CARPETA entera, lo mismo: el proyecto dejaba de compilar.

"dir" es una subcarpeta RELATIVA al proyecto y pasa por la misma lista blanca
que set-output (ValidOutputFolder): ni absolutas, ni unidad, ni "..".

(La negativa de "out" de delphi_adb_linux - el "File name is empty" - solo se
puede medir con un nodo Linux vivo; se probo contra el Fedora y no tiene
bateria.)
"""
import os
import time
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round50')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
for d in (EXEDIR, JAIL, FUERA):
    os.makedirs(d)
EXE = mc.copia_exe(EXEDIR)

TOK = 'r50'
PORT = mc.puerto_libre()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R50]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '']))
proc = mc.lanza_http(EXE, PORT, mc.entorno())
# sin texto, el mensaje entero en el detalle (como siempre en esta bateria)
cli = mc.Http(PORT, TOK, respaldo_json=True)
cli.session('r50')
call = cli.call


PROY = os.path.join(JAIL, 'Tienda')
DPR = os.path.join(PROY, 'Tienda.dpr')
DPROJ = os.path.join(PROY, 'Tienda.dproj')
SEP = chr(92)


def proyecto():
    return (open(DPR, encoding='utf-8-sig', errors='replace').read(),
            open(DPROJ, encoding='utf-8-sig', errors='replace').read())


def rechazo_dir(r, malo=None):
    """La negativa CONCRETA de la lista blanca de "dir" (ValidOutputFolder),
    que repite la "dir" rechazada: tal cual si es relativa; con unidad, sale
    enmascarada y solo se mira que la nombre."""
    eco = '"dir"="%s"' % malo if malo and not os.path.isabs(malo) else '"dir"="'
    return (r.startswith('RECHAZADO') and eco in r
            and 'no vale para crear DENTRO de un proyecto' in r)


def rechazo_jaula(r):
    return r.startswith('RECHAZADO') and 'FUERA de los workspaces permitidos' in r


def compila():
    b = call('delphi_build', {'project': DPROJ})
    return '"success":true' in b.replace(' ', ''), b[:300]


try:
    r = call('delphi_create', {'kind': 'project-console', 'name': 'Tienda',
                               'dir': PROY})
    check('D0 proyecto creado', r.startswith('CREADO'), r[:160])

    # ------------------------------------------------------------------- D
    r = call('delphi_create', {'kind': 'unit', 'name': 'UCliente',
                               'project': DPR,
                               'dir': SEP.join(['Nucleo', 'Modelos', 'Dto']),
                               'content': 'unit UCliente;\r\n\r\ninterface\r\n\r\n'
                               'type\r\n  TCliente = class\r\n  end;\r\n\r\n'
                               'implementation\r\n\r\nend.\r\n'})
    donde = os.path.join(PROY, 'Nucleo', 'Modelos', 'Dto', 'UCliente.pas')
    rel = SEP.join(['Nucleo', 'Modelos', 'Dto', 'UCliente.pas'])
    dpr, dproj = proyecto()
    check('D1 "dir" crea la unit en la subcarpeta, tan honda como se pida',
          os.path.exists(donde) and
          not os.path.exists(os.path.join(PROY, 'UCliente.pas')), r[:200])
    check('D2 ...y la registra con su ruta RELATIVA en el .dpr y en el .dproj',
          rel in dpr and ('Include="%s"' % rel) in dproj, dpr[:300])
    malas = ((SEP.join(['C:', 'Windows', 'Temp']), 'absoluta'),
             (SEP.join(['..', 'fuera']), 'con ..'),
             (SEP.join(['Nucleo', '..', '..', 'x']), 'con .. en medio'),
             ('a"b', 'con comillas (inyeccion en el .dproj)'),
             (FUERA, 'absoluta fuera de la jaula'))
    for malo, nombre in malas:
        r = call('delphi_create', {'kind': 'unit', 'name': 'UMala',
                                   'project': DPR, 'dir': malo})
        # la lista blanca; una absoluta de FUERA la para antes la jaula. Antes
        # valia "RECHAZAD" o un "error" en los 30 primeros caracteres: una
        # negativa por otro motivo, o un error del protocolo, pasaban.
        check('D3 una "dir" %s se rechaza' % nombre,
              rechazo_dir(r, malo) or (os.path.isabs(malo) and rechazo_jaula(r)),
              r[:160])
    hay = [os.path.join(d, f) for d, _, fs in os.walk(BASE) for f in fs
           if f.lower() == 'umala.pas']
    check('D4 ...y ninguna de las cinco ha dejado un UMala.pas en ningun sitio',
          not hay and 'UMala' not in proyecto()[0], hay)
    # Las dos absolutas de D3 estan FUERA de la jaula, asi que las para la
    # jaula y no la regla "sin ruta absoluta" de la lista blanca. Esta la mide
    # a ELLA: absoluta, pero DENTRO del proyecto.
    r = call('delphi_create', {'kind': 'unit', 'name': 'UAbsDentro',
                               'project': DPR, 'dir': os.path.join(PROY, 'Abs')})
    check('D3b una "dir" absoluta DENTRO de la jaula tambien se rechaza (la lista '
          'blanca, no la jaula)',
          rechazo_dir(r) and not os.path.exists(os.path.join(PROY, 'Abs')), r[:160])
    r = call('delphi_create', {'kind': 'unit', 'name': 'UProducto',
                               'project': DPR, 'dir': 'Nucleo/Modelos',
                               'content': 'unit UProducto;\r\n\r\ninterface\r\n\r\n'
                               'uses\r\n  UCliente;\r\n\r\ntype\r\n'
                               '  TProducto = class\r\n'
                               '    Comprador: TCliente;\r\n  end;\r\n\r\n'
                               'implementation\r\n\r\nend.\r\n'})
    check('D5 la barra normal tambien vale como separador',
          os.path.exists(os.path.join(PROY, 'Nucleo', 'Modelos',
                                      'UProducto.pas')), r[:200])
    ok, det = compila()
    check('D6 y el proyecto COMPILA con las units repartidas en carpetas',
          ok, det)

    # ------------------------------------------------------------------- P
    dto = os.path.join(PROY, 'Nucleo', 'Modelos', 'Dto')
    r = call('delphi_move', {'path': os.path.join(dto, 'UCliente.pas'),
                             'dest': os.path.join(dto, 'UClienteDto.pas')})
    dpr, dproj = proyecto()
    check('P1 renombrar una unit a TRES carpetas del .dpr encuentra su proyecto',
          'UClienteDto.pas' in dpr and 'UClienteDto.pas' in dproj and
          rel not in dpr, r[:240])
    call('delphi_move', {'path': os.path.join(dto, 'UClienteDto.pas'),
                         'dest': os.path.join(dto, 'UCliente.pas')})
    ok, det = compila()
    check('P2 ...y de vuelta a su nombre, compila', ok, det)

    # ------------------------------------------------------------------- M
    r = call('delphi_move', {'path': os.path.join(PROY, 'Nucleo'),
                             'dest': os.path.join(PROY, 'Dominio')})
    dpr, dproj = proyecto()
    check('M1 mover una CARPETA re-apunta las units de dentro (.dpr y .dproj)',
          SEP.join(['Dominio', 'Modelos', 'Dto', 'UCliente.pas']) in dpr and
          ('Include="%s"' % SEP.join(['Dominio', 'Modelos', 'UProducto.pas']))
          in dproj and
          ('Nucleo' + SEP) not in dpr and ('Nucleo' + SEP) not in dproj,
          r[:300])
    ok, det = compila()
    check('M2 ...y el proyecto sigue compilando', ok, det)

    # ------------------------------------------------------------------- B
    r = call('delphi_delete', {'path': os.path.join(PROY, 'Dominio')})
    dpr, dproj = proyecto()
    check('B1 borrar una CARPETA saca del proyecto las units de dentro',
          'UCliente' not in dpr and 'UProducto' not in dpr and
          'UCliente' not in dproj and 'UProducto' not in dproj, r[:300])
    ok, det = compila()
    check('B2 ...y el proyecto sigue compilando', ok, det)
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    mc.borra(BASE)

mc.fin('test_round50')
