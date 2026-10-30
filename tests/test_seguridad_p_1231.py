# -*- coding: utf-8 -*-
"""Revisor del paisaje del 29-oct, seguridad (V193, V194, V195 de la 1.23.1), medido con sondas.

  P1 alice borra la carpeta X (una marca .by para la carpeta entera); bob purga X-<sello>\\U.pas, de DENTRO
     de la copia de alice: negado y U.pas sigue (V193; ROJA contra b6c7ff9: FILE-014 PURGED y la copia de
     alice desaparecia)
  P2 bob purga la carpeta X-<sello> entera: negado (V193)
  P3 alice mueve M.txt: la copia previa de delphi_move en la papelera lleva SU marca, y bob no la purga
     (V194; ROJA: sin marca, bob la purgaba)
  P4 control: alice SI purga lo suyo de dentro de su copia
  P5 una CLAVE repetida (ReadOnlyPaths dos veces) bajo "[Workspace. W]", con un espacio tras el punto: el
     workspace queda CERRADO como con "[Workspace.W]" (V195; ROJA: ABIERTO, la segunda ReadOnlyPaths sin
     efecto, y se creaba en la carpeta protegida)

Uso:  python tests/test_seguridad_p_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('seguridad_p_1231')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV, src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(os.path.join(JAIL, 'X'))
open(os.path.join(JAIL, 'X', 'U.pas'), 'w').write('unit U;\ninterface\nimplementation\nend.\n')
open(os.path.join(JAIL, 'X', 'V.pas'), 'w').write('unit V;\ninterface\nimplementation\nend.\n')
open(os.path.join(JAIL, 'M.txt'), 'w').write('m')
PUERTO = mc.puerto_libre()
TOKEN = 'seguridad-p-1231-0123456789'
open(os.path.join(SRV, 'settings.ini'), 'w').write('[Workspace.S]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
proc = mc.lanza_http(EXE, PUERTO, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
try:
    cli = mc.Http(PUERTO, TOKEN)
    alice = cli.session('alice')
    bob = cli.session('bob')
    assert alice and bob and alice != bob
    cli.call('delphi_delete', {'path': os.path.join(JAIL, 'X')}, sid=alice)
    cx = mc.copias(JAIL, 'X', 'CAJON_BORRADOS')
    dentro = os.path.join(cx[0], 'U.pas') if cx else ''
    r = cli.call('delphi_delete', {'path': dentro, 'purge': True}, sid=bob)
    check('P1 bob purga U.pas de DENTRO de la copia de alice: negado y sigue',
          mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_NOT_YOURS_FMT') and 'alice' in r and os.path.exists(dentro),
          r[:200])
    r = cli.call('delphi_delete', {'path': cx[0] if cx else '', 'purge': True}, sid=bob)
    check('P2 bob purga la copia entera de alice: negado y sigue',
          mc.rechazado(r) and 'alice' in r and bool(cx) and os.path.exists(cx[0]), r[:200])
    cli.call('delphi_move', {'path': os.path.join(JAIL, 'M.txt'), 'dest': os.path.join(JAIL, 'N.txt')}, sid=alice)
    cm = mc.copias(JAIL, 'M.txt', 'CAJON_BORRADOS')
    marca = bool(cm) and os.path.exists(mc.marca_dueno(cm[0])) and \
        open(mc.marca_dueno(cm[0]), encoding='utf-8-sig').read().strip().endswith('alice')
    r = cli.call('delphi_delete', {'path': cm[0] if cm else '', 'purge': True}, sid=bob)
    check('P3 la copia previa de un move lleva la marca de alice y bob no la purga',
          marca and mc.rechazado(r) and bool(cm) and os.path.exists(cm[0]), (marca, r[:200]))
    otro = os.path.join(cx[0], 'V.pas') if cx else ''
    r = cli.call('delphi_delete', {'path': otro, 'purge': True}, sid=alice)
    check('P4 control: alice purga lo suyo de dentro de su copia', not os.path.exists(otro), r[:200])
finally:
    proc.kill()

# P5: el ini con una clave repetida bajo "[Workspace. W]"
SRV2 = os.path.join(BASE, 'srv2')
EXE2 = mc.copia_exe(SRV2, src=exe_src)
RO = os.path.join(JAIL, 'ro')
os.makedirs(RO)
PUERTO2 = mc.puerto_libre()
open(os.path.join(SRV2, 'settings.ini'), 'w').write(
    '[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace. W]\nToken=%s\nRoots=%s\nReadOnlyPaths=%s\nReadOnlyPaths=%s\n'
    % (PUERTO2, TOKEN, JAIL, os.path.join(JAIL, 'otra'), RO))
proc = mc.lanza_http(EXE2, None, mc.entorno(), espera_en=PUERTO2)
try:
    cli = mc.Http(PUERTO2, TOKEN, t=60)
    cli.session('p5')
    r = str(cli.call('delphi_textedit', {'path': os.path.join(RO, 'x.txt'), 'create': True, 'content': 'x'}))
    check('P5 clave repetida bajo "[Workspace. W]": el workspace se CIERRA (SYS-034) y nada se crea',
          mc.es(r, 'SR_SYS_WORKSPACE_CERRADO_FMT') and not os.path.exists(os.path.join(RO, 'x.txt')), r[:200])
finally:
    proc.kill()

mc.borra(BASE)
mc.fin('seguridad del revisor del paisaje 1231 (V193, V194, V195)')
