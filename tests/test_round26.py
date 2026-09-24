# -*- coding: utf-8 -*-
"""Round 26 - get-sdk distro-aware (openclaw's Fedora 44 bug, v0.92).

Field report 20260911-224935: `delphi_paserver get-sdk` aborted the whole
pull on Fedora because /usr/lib/gcc/x86_64-linux-gnu (the DEBIAN triplet)
was marked required per-entry. The fix replaces per-entry requiredness with
GROUP semantics: every variant is tried, and the pull succeeds iff at least
one 'gcc' tree AND one 'libc' dir actually landed.

Static gate - no server executable needed. It parses the REAL LINUX64_PULLS
table out of src/Mcp.Tools.PAServer.pas and simulates three targets against
the group rule, so a regression to per-entry Optional flags (or losing a
distro variant) fails here before it fails in the field.

Usage:  python tests/test_round26.py
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:300])


pas = open(os.path.join(REPO, 'src', 'Server', 'Mcp.Tools.PAServer.pas'),
           encoding='utf-8').read()
texts = open(os.path.join(REPO, 'src', 'Server', 'Lsp.Texts.pas'),
             encoding='utf-8').read()

# ---- 1. the table itself: group semantics, no per-entry requiredness ----
check('TSdkPull ya no tiene campo Optional (per-entry requiredness fuera)',
      'Optional: Boolean' not in pas)
check('TSdkPull declara Group', 'Group: string' in pas)

rows = re.findall(
    r"\(RemoteBase:\s*'([^']+)';\s*Recursive:\s*(True|False);\s*"
    r"Group:\s*'([^']*)'\)", pas)
check('LINUX64_PULLS parseada (6 entradas)', len(rows) == 6, rows)

table = {base: grp for base, _rec, grp in rows}
check('tripleta Debian/Ubuntu en grupo gcc',
      table.get('/usr/lib/gcc/x86_64-linux-gnu') == 'gcc', table)
check('tripleta Fedora/RHEL en grupo gcc',
      table.get('/usr/lib/gcc/x86_64-redhat-linux') == 'gcc', table)
check('libc Debian/Ubuntu en grupo libc',
      table.get('/usr/lib/x86_64-linux-gnu') == 'libc', table)
check('libc Fedora/RHEL (/usr/lib64) en grupo libc',
      table.get('/usr/lib64') == 'libc', table)

# ---- 2. the loop: no hard abort per entry; group check after the loop ----
check('el abort por entrada ha desaparecido del .pas',
      'SR_PASERVER_SDK_PULL_FMT' not in pas)
check('exit 0 con 0 ficheros cuenta como skipped, no como ok',
      re.search(r'\(ExitCode = 0\) and \(NFiles > 0\)', pas))
check('comprobacion de grupos tras el bucle',
      re.search(r'if not \(GotGcc and GotLibc\)', pas))
check('el rechazo de grupos usa SR_PASERVER_SDK_NOGROUP_FMT',
      'SR_PASERVER_SDK_NOGROUP_FMT' in pas)
check('SR_PASERVER_SDK_NOGROUP_FMT definido en Lsp.Texts',
      'SR_PASERVER_SDK_NOGROUP_FMT' in texts)

# ---- 3. simulate the rule over the REAL table for three targets ---------
def pull_outcome(present):
    """Which groups land when only `present` dirs exist on the target."""
    got = set()
    for base, _rec, grp in rows:
        if base in present and grp:
            got.add(grp)
    return got


UBUNTU = {'/usr/lib/gcc/x86_64-linux-gnu', '/usr/lib/x86_64-linux-gnu',
          '/lib/x86_64-linux-gnu'}
FEDORA44 = {'/usr/lib/gcc/x86_64-redhat-linux', '/usr/lib64', '/lib64'}
ALIEN = {'/usr/lib/musl'}   # nothing we know: must be refused, not half-built

check('target Ubuntu: gcc+libc aterrizan',
      pull_outcome(UBUNTU) == {'gcc', 'libc'}, pull_outcome(UBUNTU))
check('target Fedora 44 (bug de openclaw): gcc+libc aterrizan',
      pull_outcome(FEDORA44) == {'gcc', 'libc'}, pull_outcome(FEDORA44))
check('target desconocido: grupos incompletos -> rechazo del bucle',
      pull_outcome(ALIEN) != {'gcc', 'libc'}, pull_outcome(ALIEN))

# ---- 4. version floor ---------------------------------------------------
m = re.search(r"SERVER_VERSION = '(\d+)\.(\d+)", texts)
check('SERVER_VERSION >= 0.92',
      m and (int(m.group(1)), int(m.group(2))) >= (0, 92),
      m.group(0) if m else 'sin SERVER_VERSION')

print('\n== round26 (get-sdk distro-aware): %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
