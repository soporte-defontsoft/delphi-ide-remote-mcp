# -*- coding: utf-8 -*-
"""RenderTests, la bateria manual del renderizador (src/Render/README.md).

No es test_*: run_all no la lanza. Corre el exe ya compilado desde esta sesion,
sin cobayas y con las de DUMMY, las veces que se pida. El 1-nov-2026 salio un
rojo sin cobayas en una de muchas pasadas y no quedo cual, porque la salida se
tiraba: aqui la salida de una pasada roja se queda en release-out.

  python tests/rendertests_manual.py [vueltas]
"""
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR_EXE = os.path.join(RAIZ, 'src', 'Render', 'Pruebas', 'Win64', 'Debug')
EXE = os.path.join(DIR_EXE, 'RenderTests.exe')
DUMMY = os.path.join(RAIZ, 'src', 'Render', 'Pruebas', 'DUMMY')
SALIDA = os.path.join(RAIZ, 'release-out')


def pasada(nombre, vuelta, entorno):
    p = subprocess.run([EXE, '--exitbehavior:Continue'], cwd=DIR_EXE, env=entorno, stdin=subprocess.DEVNULL,
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    m = re.search(r'Tests Found\s*:\s*(\d+)', p.stdout)
    malos = re.findall(r'Tests (?:Failed|Errored)\s*:\s*(\d+)', p.stdout)
    roja = p.returncode != 0 or len(malos) != 2 or any(n != '0' for n in malos)
    if roja:
        os.makedirs(SALIDA, exist_ok=True)
        fichero = os.path.join(SALIDA, 'rendertests_rojo_%s_%d.txt' % (nombre, vuelta))
        with open(fichero, 'w', encoding='utf-8') as f:
            f.write(p.stdout + p.stderr)
        print('ROJA %s vuelta %d (rc=%d): %s' % (nombre, vuelta, p.returncode, fichero))
    return roja, m.group(1) if m else '?'


def main():
    vueltas = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    sin = {k: v for k, v in os.environ.items() if k != 'RENDER_COBAYAS'}
    con = dict(sin, RENDER_COBAYAS=DUMMY)
    rojas = 0
    for nombre, entorno in (('sin_cobayas', sin), ('dummy', con)):
        total = '?'
        rojas_aqui = 0
        for v in range(1, vueltas + 1):
            roja, total = pasada(nombre, v, entorno)
            rojas_aqui += roja
        print('== RenderTests %s: %s tests, %d vueltas, %d rojas ==' % (nombre, total, vueltas, rojas_aqui))
        rojas += rojas_aqui
    return 1 if rojas else 0


if __name__ == '__main__':
    sys.exit(main())
