"""Run every end-to-end battery against a CLEAN copy of the built server.

Why the copy matters: the server reads a settings.ini sitting next to its
executable, and a dev machine usually has one there (Roots, a Vault). Five
batteries assume a bare server - "no vault configured", "these are the roots I
gave you" - so running them against the build output in place made them fail
for reasons that had nothing to do with the code. Measured 2026-08-25: five
red batteries, zero real bugs. The exe is copied to a scratch folder, alone,
and every battery is pointed at that copy.

Usage:
    python tests/run_all.py [path-to-DelphiLspMcp.exe] [-k substring]
"""
import os, sys, glob, shutil, tempfile, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))

args = [a for a in sys.argv[1:]]
only = None
if '-k' in args:
    i = args.index('-k')
    only = args[i + 1]
    del args[i:i + 2]
SRC = args[0] if args else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
if not os.path.exists(SRC):
    sys.exit('no encuentro el exe: ' + SRC)

CLEAN = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', '_cleanexe')
shutil.rmtree(CLEAN, ignore_errors=True)
os.makedirs(CLEAN)
EXE = os.path.join(CLEAN, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
# The helper executables travel WITH the server (delphi_styles needs the
# text<->binary converter beside it); settings.ini deliberately does not.
for helper in ('DelphiStyleConvert.exe', 'DelphiLspMcpTray.exe'):
    _h = os.path.join(os.path.dirname(os.path.abspath(SRC)), helper)
    if os.path.exists(_h):
        shutil.copy(_h, os.path.join(CLEAN, helper))

batteries = sorted(glob.glob(os.path.join(HERE, 'test_*.py')))
if only:
    batteries = [b for b in batteries if only in os.path.basename(b)]

rows, total_ok, total_bad, failed = [], 0, 0, []
for b in batteries:
    name = os.path.basename(b)[:-3]
    t0 = time.time()
    r = subprocess.run([sys.executable, b, EXE], capture_output=True,
                       text=True, encoding='utf-8', errors='replace', cwd=REPO)
    out = (r.stdout or '') + (r.stderr or '')
    ok = sum(1 for line in out.splitlines() if line.startswith('PASS'))
    bad = sum(1 for line in out.splitlines() if line.startswith('FAIL'))
    # batteries print their own tally; trust rc for the verdict
    verdict = 'OK  ' if r.returncode == 0 else 'FALLA'
    if r.returncode != 0:
        failed.append((name, out))
    total_ok += ok
    total_bad += bad
    rows.append((verdict, name, ok, bad, time.time() - t0))
    print('%-6s %-26s %4d ok  %3d fail  %5.1fs' % (
        verdict, name, ok, bad, time.time() - t0))

print('\n== %d baterias | %d checks OK | %d fallos | %d baterias rojas ==' % (
    len(rows), total_ok, total_bad, len(failed)))
for name, out in failed:
    print('\n--- %s ---' % name)
    for line in out.splitlines():
        if line.startswith('FAIL') or 'Error' in line or 'Traceback' in line:
            print('   ', line[:220])
sys.exit(1 if failed else 0)
