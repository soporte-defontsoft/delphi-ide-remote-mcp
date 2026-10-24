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
import mcp_cliente as mc
from mcp_cliente import check

TOKEN = 'lector-cerrojo-token'
B_DELAY = 0.5      # B entra cuando A ya escribio y su lector esta cargando
MIN_A = 1.0        # A tiene que durar al menos esto para separar "espera" de "no espera"

WORK = mc.carpeta('lector-cerrojo-120')
atexit.register(mc.borra, WORK)
JAIL = os.path.join(WORK, 'jaula')
os.makedirs(JAIL)
EXE = mc.copia_exe(WORK, con_render=True)
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
cli = mc.Http(PORT, TOKEN, t=300)   # seguro entre hilos
try:
    cli.session('lector-cerrojo')
    # la Sample de RAD Studio de 2,5 MB con paquetes de diseno (LiveBindings, DB), donde la deja
    # el IDE: su BDSCOMMONDIR (r5-L4: se componia a mano, con la 37.0 escrita)
    SAMPLE = os.path.join(mc.variable_de_rsvars(cli.call, 'BDSCOMMONDIR'), 'Samples', 'Object Pascal',
                          'LiveBindings', 'bindgridlink', 'vcl')
except Exception:
    proc.kill()
    raise
SKIP = None
if not os.path.isfile(os.path.join(SAMPLE, 'GridLinkFormUnit1.dfm')):
    proc.kill()
    mc.fin('el lector fuera del cerrojo 120',
           sin_checks='no esta la Sample de RAD Studio (bindgridlink\\vcl): no hay form pesado que medir')
for ext in ('.pas', '.dfm'):
    shutil.copy(os.path.join(SAMPLE, 'GridLinkFormUnit1' + ext), JAIL)
open(os.path.join(JAIL, 'notas.txt'), 'wb').write(b'uno\r\ndos\r\n')
try:
    for fw, r in mc.espera_tablas(cli.call):
        check('K0 la tabla %s esta lista' % fw, mc.tabla_lista(r), r[:200])
    dfm = os.path.join(JAIL, 'GridLinkFormUnit1.dfm')
    txt = os.path.join(JAIL, 'notas.txt')
    # el lector en caliente (la primera carga de los paquetes, fria, no cuenta)
    cli.call('delphi_designer', {'path': dfm, 'command': 'lint'}, t=300)

    (ra, a_fin), (rb, b_dur), _ = mc.a_la_vez(
        cli.call, ('delphi_edit', {'path': dfm, 'old': '    Left = 152', 'new': '    Left = 153'}, 300),
        ('delphi_textedit', {'path': txt, 'old': 'dos', 'new': 'tres'}, 300), B_DELAY)
    res = {'a': ra, 'b': rb}
    b_fin = B_DELAY + b_dur
    print('  (A tardo %.2f s; B acabo a los %.2f s)' % (a_fin, b_fin))
    # (revisor de baterias, 18-oct-2026) antes de decidir que no se puede
    # medir: A y B contestaron y escribieron. Un edit que fallaba deprisa (un
    # ancla cambiada, un hilo colgado: a_fin 0) daba SKIP, y tras los dos K0
    # la bateria salia verde sin decirlo
    check('K1 preparacion: A contesto y escribio (Left = 153), y B tambien (tres)',
          not mc.fallo(res.get('a', '')) and b'Left = 153' in open(dfm, 'rb').read()
          and not mc.fallo(res.get('b', '')) and b'tres' in open(txt, 'rb').read(),
          (res.get('a', '')[:200], res.get('b', '')[:200]))
    if a_fin < MIN_A:
        SKIP = 'A tardo %.2f s: el lector es demasiado rapido aqui para separar espera de no espera' % a_fin
        # con los K0 ya contados fin(sin_checks=) no lo diria: lo dice la NOTA
        print('NOTA: K1 y K2 no se miden: %s' % SKIP)
    else:
        # lo que tarda B frente a lo que A pasa con su lector: con el lector
        # DENTRO del cerrojo B espera casi todo (mutante del 16-oct: 43,5 s de
        # 45,3); fuera, nada (0,04 s de 3,3). "Acaba antes que A" pasaba en
        # los dos: era una guarda que no media
        check('K1 B (otro fichero) no espera al lector de A: tarda menos de la mitad de lo que A pasa con el',
              not mc.fallo(res.get('b', '')) and b_dur < (a_fin - B_DELAY) / 2,
              (a_fin, b_fin, res.get('b', '')[:200]))
        check('K2 A escribio y trae el juicio del lector (el form carga: sin EDIT-127)',
              not mc.fallo(res.get('a', '')) and not mc.es(res.get('a', ''), 'SN_EDIT_AVISO_LECTOR_FMT')
              and b'Left = 153' in open(dfm, 'rb').read(), res.get('a', '')[-400:])
finally:
    try:
        proc.kill()
    except Exception:
        pass

mc.fin('el lector fuera del cerrojo 120', sin_checks=SKIP)
