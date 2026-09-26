"""E2E battery for v0.74.0-beta - round 10 sweep (agent sweep10).

The data-loss trap sweep10 found: deleting a FOLDER whose content is locked (a
running .exe, a git process, the IDE) reported "A MEDIAS - the recoverable copy
IS made, the original could not be removed" - but the content had ALREADY been
moved into that copy and the original gutted, and every retry made another full
copy. A human reading "half done, retry" who purged those "leftover" copies
deleted real code.

Root cause: TDirectory.Move falls back to a recursive copy+delete of its own
accord when the atomic rename fails. The fix uses the raw Windows MoveFile,
which never copies: same-volume it renames atomically, and on a locked tree it
fails with everything untouched. Move or nothing.

  D1  a locked folder is NOT deleted and NOTHING is touched - no partial copy in
      the trash, the original intact, and a retry does not duplicate
  D2  the same folder, once unlocked, deletes cleanly

Usage:  python tests/test_round14.py [path-to-DelphiLspMcp.exe]
"""
import os, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round14')
EXE = mc.copia_exe(BASE)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='round14', t=30)
call = srv.call


def copies():
    return [c for c in glob.glob(os.path.join(BASE, '**', '__delphi-patch', '**', 'proj-*'),
                                 recursive=True) if not c.endswith('.by')]

sub = os.path.join(BASE, 'proj')
os.makedirs(sub)
open(os.path.join(sub, 'a.txt'), 'w').write('a' * 100)
lh = open(os.path.join(sub, 'locked.exe'), 'w')          # keep the handle open
lh.write('x' * 50)
lh.flush()

# D1 - locked folder: nothing touched, nothing copied, retry does not duplicate
r1 = call('delphi_delete', {'path': sub})
r2 = call('delphi_delete', {'path': sub})
intact = (os.path.exists(os.path.join(sub, 'a.txt')) and
          os.path.exists(os.path.join(sub, 'locked.exe')) and
          open(os.path.join(sub, 'a.txt')).read() == 'a' * 100)
check('D1 carpeta bloqueada: no la borra y NO toca nada',
      'NO he tocado NADA' in r1 and intact, r1)
check('D1 no deja copia a medias en la papelera (ni al reintentar)',
      len(copies()) == 0, copies())
check('D1 el reintento tampoco duplica ni gutea', 'NO he tocado NADA' in r2 and intact, r2)

# D2 - once unlocked, it deletes cleanly
lh.close()
r3 = call('delphi_delete', {'path': sub})
check('D2 sin lock, borra limpio', 'BORRADO' in r3 and not os.path.exists(sub), r3)
check('D2 y AHORA si hay una copia recuperable', len(copies()) == 1, copies())

srv.mata()
mc.fin('round-14 battery')
