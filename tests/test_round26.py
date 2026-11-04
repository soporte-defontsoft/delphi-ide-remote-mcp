# -*- coding: utf-8 -*-
"""Round 26 - get-sdk distro-aware (openclaw's Fedora 44 bug, v0.92).

Field report 20260911-224935: `delphi_paserver get-sdk` aborted the whole
pull on Fedora because /usr/lib/gcc/x86_64-linux-gnu (the DEBIAN triplet)
was marked required per-entry. The fix replaces per-entry requiredness with
GROUP semantics: every variant is tried, and the pull succeeds iff at least
one 'gcc' tree AND one 'libc' dir actually landed.

Static gate - no server executable needed. It reads the REAL LINUX64_PULLS
table out of src/Mcp.Tools.PAServer.pas: losing a distro variant (or going
back to per-entry Optional flags) fails here. The group rule itself is
measured live by test_get_sdk_1230 (NOGROUP). Since 1.27 the checks on the
shape of the code, the Python simulation of the rule (it could not fail: it
imitated the rule) and the version floor are gone (revisor de baterias).

Usage:  python tests/test_round26.py
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO


pas = open(os.path.join(REPO, 'src', 'Server', 'Mcp.Tools.PAServer.pas'),
           encoding='utf-8').read()

# ---- the table itself: each distro variant in its GROUP ----
# (4-nov-2026: fuera las dos comprobaciones de la FORMA del codigo -sin campo Optional, con campo
# Group- y la de "parseada", que la cabecera ya daba por retiradas: una fila sin su Group no se lee
# y su variante sale roja abajo; la regla de grupos la mide test_get_sdk_1230 en vivo)
rows = re.findall(
    r"\(RemoteBase:\s*'([^']+)';\s*Recursive:\s*(True|False);\s*"
    r"Group:\s*'([^']*)'\)", pas)
table = {base: grp for base, _rec, grp in rows}
check('tripleta Debian/Ubuntu en grupo gcc',
      table.get('/usr/lib/gcc/x86_64-linux-gnu') == 'gcc', table)
check('tripleta Fedora/RHEL en grupo gcc',
      table.get('/usr/lib/gcc/x86_64-redhat-linux') == 'gcc', table)
check('libc Debian/Ubuntu en grupo libc',
      table.get('/usr/lib/x86_64-linux-gnu') == 'libc', table)
check('libc Fedora/RHEL (/usr/lib64) en grupo libc',
      table.get('/usr/lib64') == 'libc', table)

mc.fin('round26 (get-sdk distro-aware)')
