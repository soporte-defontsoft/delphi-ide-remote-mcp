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
import mcp_cliente as mc  # borra(): el barrido que puede con lo de solo lectura

# La consola es cp1252, y el error de una bateria puede traer un mensaje de
# Windows en castellano leido con errors='replace' (U+FFFD dentro). Al
# imprimirlo se caia ESTE script, justo cuando explicaba por que una
# bateria salio roja: medido 2026-09-26, test_round20 roja "sin una linea"
# y run_all muerto con UnicodeEncodeError. Lo que no quepa sale como '?'.
sys.stdout.reconfigure(errors='replace')

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

RAIZ = mc.RAIZ
CLEAN = os.path.join(RAIZ, '_cleanexe')
# El adb que arranquen las baterias se para al final, una vez: dentro de la
# suite ninguna lo para por su cuenta (mc.fin mira esta variable).
os.environ[mc.SUITE] = '1'
# Se barre la raiz ENTERA, no solo el exe: cada bateria limpia lo suyo cuando
# acaba bien, pero una que muere a medias deja su carpeta, y la siguiente
# pasada puede apoyarse en ella y salir verde por el motivo equivocado (paso
# dos veces en dos dias). Medido el 2026-09-21: 3,5 GB de restos de ~90
# baterias. Una suite completa empieza y acaba con la raiz vacia.
if not only:
    mc.borra(RAIZ)
mc.borra(CLEAN)
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
# lo que una bateria dice que NO midio (NOTA/SKIP): una verde con su nucleo
# saltado no se distinguia de una verde de verdad (revision 27-sep-2026)
notas = []
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
    notas += ['%s: %s' % (name, line.strip()[:200]) for line in out.splitlines()
              if line.lstrip().startswith(('NOTA', 'SKIP'))]
    # batteries print their own tally; trust rc for the verdict...
    verdict = 'OK  ' if r.returncode == 0 else 'FALLA'
    # ...salvo con 0 checks y sin decir por que: una que no mide nada no
    # sale verde, pase por mc.fin o se le olvide (la marca la pone mc.fin)
    if r.returncode == 0 and ok == 0 and bad == 0 and not mc.sin_checks_de(out):
        verdict = 'FALLA'
        bad = 1
        out += '\nFAIL 0 checks: la bateria no midio nada y no dijo por que'
    if verdict == 'FALLA':
        failed.append((name, out, r.returncode))
    total_ok += ok
    total_bad += bad
    rows.append((verdict, name, ok, bad, time.time() - t0))
    print('%-6s %-26s %4d ok  %3d fail  %5.1fs' % (
        verdict, name, ok, bad, time.time() - t0))

print('\n== %d baterias | %d checks OK | %d fallos | %d baterias rojas | %d notas ==' % (
    len(rows), total_ok, total_bad, len(failed), len(notas)))
if notas:
    print('\n--- lo que las baterias dicen que NO midieron (NOTA/SKIP) ---')
    for n in notas:
        print('   ', n)
for name, out, rc in failed:
    print('\n--- %s (rc=%d) ---' % (name, rc))
    motivo = [line for line in out.splitlines()
              if line.lstrip().startswith('FAIL') or 'Error' in line or 'Traceback' in line]
    for line in motivo:
        print('   ', line[:220])
    # Roja sin decir por que: se ensena el final. El 26-sep-2026
    # test_readonly_roots salio roja con 57 PASS y 0 FAIL y aqui no quedo
    # ni una linea: una bateria roja tiene que decir por que.
    if not motivo:
        print('    (sin FAIL ni Traceback; sus ultimas lineas:)')
        for line in out.splitlines()[-8:]:
            print('   ', line[:220])
# ...ni un adb vivo que no estuviera antes de empezar (mc.ADB_ANTES)...
if not mc.ADB_ANTES and mc.adb_vivo():
    print('NOTA: adb arrancado por las baterias: %s' % (
        'parado' if mc.adb_para() else 'NO se ha podido parar'))
# ...y no se deja nada en el %TEMP% de la maquina. Con rojas se conserva: lo
# que dejo la bateria que fallo es la evidencia.
if not failed:
    mc.borra(RAIZ if not only else CLEAN)
    # ...ni las caches del LSP de los proyectos de las baterias en %LOCALAPPDATA%
    # (con una roja se conservan: para un fallo de symbols/definition son la evidencia)
    n_caches = mc.limpia_caches_lsp()
    if n_caches:
        print('NOTA: %d caches .delphilsp.json de proyectos de baterias quitadas de %%LOCALAPPDATA%%' % n_caches)
sys.exit(1 if failed else 0)
