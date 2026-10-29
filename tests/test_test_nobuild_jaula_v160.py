# -*- coding: utf-8 -*-
"""V160b (1.23.1): delphi_test nobuild=true judges the binary by the jail.

With a build, SalidaDenegada gates the output folder (a build only writes
inside the roots). With nobuild=true the binary comes from ResolveBuildOutput,
which takes any DCC_ExeOutput and resolves it to any folder, with no gate: a
DCC_ExeOutput pointing OUTSIDE the roots made delphi_test name the binary, date
it, COPY its folder into the server's house (the container runs on a copy) and
run it - reading outside the jail, the thing the jail exists to stop. Measured
2026-10-29 against 06f59ce: binary = <outside>\\TP2.exe, sandboxed true.

Now the binary's folder is judged by the jail's read gate (LugarDeLecturaDenegado
[ltJaula]), the same judge the <Import> scan uses: outside -> TEST-036, before
anything is named, copied or run.

  A1  nobuild=true with a DCC_ExeOutput that points OUTSIDE the roots, and a
      binary of the project's name there: refused TEST-036, nothing named/run.
  A2  (control) nobuild=true on a binary INSIDE the roots still runs: the fix
      does not break legitimate nobuild.

The unit root (X:\\) is OUTSIDE the jail (X:\\proj) and INSIDE the battery
folder: a subst unit over a temp folder, like test_raiz_unidad, so nothing is
written outside the battery's own folder.

Usage:  python tests/test_test_nobuild_jaula_v160.py [path-to-DelphiLspMcp.exe]
"""
import atexit, os, shutil, subprocess, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('test_nobuild_jaula_v160')
UNI = os.path.join(BASE, 'unidad')
os.makedirs(UNI)
L = mc.letras_libres(1)[0]
_r = subprocess.run(['subst', L + ':', UNI], capture_output=True, text=True)
assert _r.returncode == 0 and os.path.isdir(L + ':\\'), _r.stdout + _r.stderr
atexit.register(lambda: subprocess.run(['subst', L + ':', '/d'], capture_output=True))
X = L + ':\\'
J = os.path.join(X, 'proj')          # la jaula; X:\ (la raiz de la unidad) queda FUERA
FUERA = os.path.join(X, 'fuera')     # FUERA de la jaula, dentro de la bateria
os.makedirs(J)
os.makedirs(FUERA)

EXE = mc.copia_exe(os.path.join(BASE, 's'), src=exe_src)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': J, 'DELPHI_MCP_ALLOW_TESTS': '1'}),
             nombre='v160b', t=600)


def lee(p):
    return open(p, 'rb').read().decode('utf-8-sig')


def escribe(p, t):
    open(p, 'wb').write(b'\xef\xbb\xbf' + t.encode('utf-8'))


try:
    # --- A2 control: un proyecto de test construido normal, nobuild dentro de la jaula ---
    d2 = os.path.join(J, 'ok')
    assert mc.abre(S.call('delphi_create', {'kind': 'project-test', 'name': 'TPok', 'dir': d2}),
                   'SK_CREATE_CREADO_PROYECTO_FMT')
    pok = os.path.join(d2, 'TPok.dproj')
    rb = S.call('delphi_build', {'project': pok, 'platform': 'Win32', 'config': 'Debug'}, 300)
    assert mc.como_json(rb).get('success'), rb[:300]
    r2 = S.call('delphi_test', {'project': pok, 'platform': 'Win32', 'config': 'Debug', 'nobuild': True}, 300)
    j2 = mc.como_json(r2)
    check('A2 control: nobuild de un binario DENTRO de las raices se corre (no lo frena el juez)',
          not mc.rechazado(r2) and bool(j2.get('binary')) and j2.get('sandboxed') is True
          and mc.real(j2.get('binary', '')).lower().startswith((J + os.sep).lower()),
          r2[:300])

    # --- A1: nobuild con DCC_ExeOutput FUERA de las raices y un binario alli ---
    d1 = os.path.join(J, 'malo')
    assert mc.abre(S.call('delphi_create', {'kind': 'project-test', 'name': 'TP2', 'dir': d1}),
                   'SK_CREATE_CREADO_PROYECTO_FMT')
    p1 = os.path.join(d1, 'TP2.dproj')
    # un binario inerte FUERA con el nombre del proyecto (un PE real: el exe copiado)
    shutil.copy(EXE, os.path.join(FUERA, 'TP2.exe'))
    # DCC_ExeOutput = la carpeta de FUERA (absoluta); el proyecto NO se construye
    t = lee(p1)
    i = t.index('<PropertyGroup')
    t = t[:i] + ('<PropertyGroup><DCC_ExeOutput>%s</DCC_ExeOutput></PropertyGroup>\r\n    '
                 % FUERA.rstrip('\\')) + t[i:]
    escribe(p1, t)
    r1 = S.call('delphi_test', {'project': p1, 'platform': 'Win32', 'nobuild': True}, 300)
    j1 = mc.como_json(r1)
    check('A1 nobuild con DCC_ExeOutput fuera de las raices: TEST-036, sin nombrar ni correr el binario de fuera',
          mc.rechazado(r1) and mc.es(r1, 'SR_TEST_BINARY_FUERA_FMT')
          and j1.get('binary') is None and j1.get('sandboxed') is None,
          r1[:300])
finally:
    S.cierra()
    subprocess.run(['subst', L + ':', '/d'], capture_output=True)
    mc.borra(BASE)

mc.fin('V160b nobuild jail battery')
