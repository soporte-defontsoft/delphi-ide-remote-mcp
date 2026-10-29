# -*- coding: utf-8 -*-
"""V164 (1.23.1): delphi_delete in a server temporary is judged by the REAL
path, not the text (the inverse of V112).

A delete under __delphi-temp is a PERMANENT delete (nothing is restored from a
temporary). EnTemporal used LongCanonical, which does not resolve junctions, so
a __delphi-temp that is a junction to <root>\\src (or a junction inside an old
__delphi-temp) made delphi_delete <root>\\__delphi-temp\\Main.pas wipe
src\\Main.pas for good, with no trash copy. Now the temp branch judges the real
path: if it is not really inside a temporary (a link to a live file), it is
refused (FILE-053) - the live file is deleted, recoverably, by its own path.

  T1 a junction __delphi-temp -> src, delete a file through it: refused
     FILE-053, src\\Main.pas STILL THERE (RED against 06f59ce: wiped, no copy)
  T2 (control) a real __delphi-temp file is still permanently deleted (FILE-012)

Usage:  python tests/test_delete_temp_enlace_v164.py [path-to-DelphiLspMcp.exe]
"""
import os, sys, _winapi
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('delete_temp_enlace_v164')
JAIL = os.path.join(BASE, 'jail')
SRC = os.path.join(JAIL, 'src')
os.makedirs(SRC)
open(os.path.join(SRC, 'Main.pas'), 'w', newline='\r\n').write(
    'unit Main;\r\ninterface\r\nimplementation\r\nend.\r\n')
LNK = os.path.join(JAIL, mc.TEMPORALES)
_winapi.CreateJunction(SRC, LNK)  # __delphi-temp -> src (una union a algo vivo)

S = mc.Stdio(mc.copia_exe(os.path.join(BASE, 's'), src=exe_src),
             mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='v164', t=300)
try:
    # T1: un fichero vivo a traves de una union __delphi-temp -> src
    r = S.call('delphi_delete', {'path': os.path.join(LNK, 'Main.pas')})
    sigue = os.path.isfile(os.path.join(SRC, 'Main.pas'))
    copias = mc.copias(JAIL, 'Main.pas', 'CAJON_BORRADOS', bajo=True)
    check('T1 borrar un fichero vivo por una union __delphi-temp se niega (FILE-053) y src\\Main.pas sigue; nada se pierde sin copia',
          mc.rechazado(r) and mc.es(r, 'SR_FILE_DELETE_TEMP_ENLACE_FMT') and sigue and not copias,
          (r[:160], 'sigue=%s' % sigue, copias))

    # T2 control: un temporal de VERDAD se borra para siempre (sin union)
    tmp = os.path.join(JAIL, 'proj', mc.TEMPORALES, 'cap')
    os.makedirs(tmp)
    open(os.path.join(tmp, 'x.png'), 'wb').write(b'\x89PNG\r\n\x1a\n' + b'0' * 32)
    r2 = S.call('delphi_delete', {'path': os.path.join(tmp, 'x.png')})
    check('T2 control: un fichero de un temporal REAL se borra de verdad (FILE-012), sin papelera',
          mc.abre(r2, 'SN_FILE_DELETE_TEMP_FMT') and not os.path.isfile(os.path.join(tmp, 'x.png')),
          r2[:160])
finally:
    S.cierra()
    if os.path.isdir(LNK):
        os.rmdir(LNK)  # quita el ENLACE, no src
    mc.borra(BASE)

mc.fin('V164 delete temp jail battery')
