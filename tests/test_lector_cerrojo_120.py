# -*- coding: utf-8 -*-
"""El juicio del LECTOR del IDE tras escribir un form (DSGN-061 de la 1.20) va
FUERA del cerrojo de escritura del servidor (EnterFileEdit, uno por proceso).

El lector es un proceso que carga el form como el designer: un form real con
paquetes de diseno tarda de 1 a 5 segundos (medido el 16-oct-2026 con una
Sample de RAD Studio: 112 de 153 paquetes). La primera version lo pedia desde
DesignerLint, que corre DENTRO del cerrojo de delphi_edit: una escritura de
OTRO agente, en otro fichero, esperaba a que acabara. Es lo que ya paso con el
juez del orden del disenador (revisor 5 de la noche, A3). Ahora lo piden las
tools al volver (Lsp.Patch.AvisosDelLector).

  K1 A edita el form pesado (y su lector tarda); B, medio segundo despues,
     escribe un .txt en la misma jaula: B acaba ANTES que A (con el lector
     dentro del cerrojo, B esperaba a A)
  K2 y A trae el juicio del lector igual (lo pidio, fuera): el form carga, sin
     EDIT-127

Si la maquina no da la secuencia (sin la Sample, o el lector demasiado rapido
para separar las dos cosas) la bateria sale SIN_CHECKS, no en falso verde.

Uso:  python tests/test_lector_cerrojo_120.py [ruta-al-exe]
"""
import atexit
import os
import shutil
import threading
import time
import mcp_cliente as mc
from mcp_cliente import check

TOKEN = 'lector-cerrojo-token'
B_DELAY = 0.5      # B entra cuando A ya escribio y su lector esta cargando
MIN_A = 1.0        # A tiene que durar al menos esto para separar "espera" de "no espera"

# la Sample de RAD Studio de 2,5 MB con paquetes de diseno (LiveBindings, DB)
SAMPLE = os.path.join(os.environ.get('PUBLIC', r'C:\Users\Public'), 'Documents', 'Embarcadero', 'Studio',
                      '37.0', 'Samples', 'Object Pascal', 'LiveBindings', 'bindgridlink', 'vcl')

WORK = mc.carpeta('lector-cerrojo-120')
atexit.register(mc.borra, WORK)
JAIL = os.path.join(WORK, 'jaula')
os.makedirs(JAIL)
SKIP = None
if not os.path.isfile(os.path.join(SAMPLE, 'GridLinkFormUnit1.dfm')):
    SKIP = 'no esta la Sample de RAD Studio 37.0 (bindgridlink\\vcl): no hay form pesado que medir'
else:
    for ext in ('.pas', '.dfm'):
        shutil.copy(os.path.join(SAMPLE, 'GridLinkFormUnit1' + ext), JAIL)
    open(os.path.join(JAIL, 'notas.txt'), 'wb').write(b'uno\r\ndos\r\n')

if SKIP:
    mc.fin('el lector fuera del cerrojo 120', sin_checks=SKIP)
    raise SystemExit(0)

EXE = mc.copia_exe(WORK, con_render=True)
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
cli = mc.Http(PORT, TOKEN, t=300)   # seguro entre hilos
try:
    cli.session('lector-cerrojo')
    for fw, r in mc.espera_tablas(cli.call):
        check('K0 la tabla %s esta lista' % fw, not mc.tiene(r, 'DSGN-051') and not mc.fallo(r), r[:200])
    dfm = os.path.join(JAIL, 'GridLinkFormUnit1.dfm')
    txt = os.path.join(JAIL, 'notas.txt')
    # el lector en caliente (la primera carga de los paquetes, fria, no cuenta)
    cli.call('delphi_designer', {'path': dfm, 'command': 'lint'}, t=300)

    res = {}

    def a():
        t0 = time.time()
        res['a'] = cli.call('delphi_edit', {'path': dfm, 'old': '    Left = 152', 'new': '    Left = 153'}, t=300)
        res['a_fin'] = time.time() - t0

    def b():
        time.sleep(B_DELAY)
        t0 = time.time()
        res['b'] = cli.call('delphi_textedit', {'path': txt, 'old': 'dos', 'new': 'tres'}, t=300)
        res['b_fin'] = B_DELAY + time.time() - t0

    ha, hb = threading.Thread(target=a), threading.Thread(target=b)
    ha.start()
    hb.start()
    ha.join(320)
    hb.join(320)
    a_fin, b_fin = res.get('a_fin', 0), res.get('b_fin', 0)
    print('  (A tardo %.2f s; B acabo a los %.2f s)' % (a_fin, b_fin))
    if a_fin < MIN_A:
        SKIP = 'A tardo %.2f s: el lector es demasiado rapido aqui para separar espera de no espera' % a_fin
    else:
        # lo que tarda B frente a lo que A pasa con su lector: con el lector
        # DENTRO del cerrojo B espera casi todo (mutante del 16-oct: 43,5 s de
        # 45,3); fuera, nada (0,04 s de 3,3). "Acaba antes que A" pasaba en
        # los dos: era una guarda que no media
        b_dur = b_fin - B_DELAY
        check('K1 B (otro fichero) no espera al lector de A: tarda menos de la mitad de lo que A pasa con el',
              not mc.rechazado(res.get('b', '')) and b_dur < (a_fin - B_DELAY) / 2,
              (a_fin, b_fin, res.get('b', '')[:200]))
        check('K2 A escribio y trae el juicio del lector (el form carga: sin EDIT-127)',
              not mc.rechazado(res.get('a', '')) and not mc.tiene(res.get('a', ''), 'EDIT-127')
              and b'Left = 153' in open(dfm, 'rb').read(), res.get('a', '')[-400:])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('el lector fuera del cerrojo 120', sin_checks=SKIP)
