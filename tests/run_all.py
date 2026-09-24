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
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
if not os.path.exists(SRC):
    sys.exit('no encuentro el exe: ' + SRC)

RAIZ = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests')
CLEAN = os.path.join(RAIZ, '_cleanexe')
# Se barre la raiz ENTERA, no solo el exe: cada bateria limpia lo suyo cuando
# acaba bien, pero una que muere a medias deja su carpeta, y la siguiente
# pasada puede apoyarse en ella y salir verde por el motivo equivocado (paso
# dos veces en dos dias). Medido el 2026-09-21: 3,5 GB de restos de ~90
# baterias. Una suite completa empieza y acaba con la raiz vacia.
if not only:
    shutil.rmtree(RAIZ, ignore_errors=True)
shutil.rmtree(CLEAN, ignore_errors=True)
# Si la carpeta sigue ahi despues del rmtree es que OTRA regresion la tiene
# cogida (su exe esta en uso). Dos suites a la vez comparten la raiz temporal
# y se pisan, asi que se dice y se para - no se revienta con un traceback de
# makedirs (medido el 2026-09-20: lance dos sin darme cuenta y la segunda
# murio con FileExistsError en esta misma linea, sin explicar nada).
if os.path.isdir(CLEAN):
    sys.exit('Parece que hay OTRA regresion en marcha: no puedo limpiar\n  '
             + CLEAN + '\nporque su exe esta en uso. Dos suites a la vez '
             'comparten la carpeta temporal y se pisan.\nEspera a que termine '
             '(o matala) y vuelve a lanzar.')
os.makedirs(CLEAN)
EXE = os.path.join(CLEAN, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)
# The helper executables travel WITH the server (delphi_styles needs the
# text<->binary converter beside it); settings.ini deliberately does not.
for helper in ('DelphiStyleConvert.exe',):  # el Tray.exe era un fosil de agosto
    # el conversor tiene su propio proyecto y carpeta desde la reorganizacion del 24-sep
    _h = os.path.join(REPO, 'src', 'StyleConvert', 'Compiled', 'Win64', 'Release', helper)
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
    ok = sum(1 for line in out.splitlines() if line.lstrip().startswith('PASS'))  # misma regla que FAIL: test_styles indenta sus PASS y contaban 0
    # .lstrip(): test_messages indenta sus FAIL con dos espacios, asi que el
    # recolector no los veia: la bateria salia ROJA y sin una sola linea que
    # dijera por que (medido 2026-09-20, y es justo el pecado que este
    # release se dedica a arreglar en el servidor).
    bad = sum(1 for line in out.splitlines() if line.lstrip().startswith('FAIL'))
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
        if line.lstrip().startswith('FAIL') or 'Error' in line or 'Traceback' in line:
            print('   ', line[:220])
# ...y no se deja nada en el %TEMP% de la maquina. Con rojas se conserva: lo
# que dejo la bateria que fallo es la evidencia.
if not failed:
    shutil.rmtree(RAIZ if not only else CLEAN, ignore_errors=True)
sys.exit(1 if failed else 0)
