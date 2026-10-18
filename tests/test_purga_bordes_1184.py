# -*- coding: utf-8 -*-
"""2g de la 1.18.x (1.18.4): los bordes de la purga que no tenian bateria
(revisor propio del punto 2 de la 1.18.1; 4.8 los evaluo el 13-oct: no son un
escape). GUARDAS: verdes ya en la 1.18.3; vigilan que siga asi.

  G1 un repo cuyo .git es un FICHERO (gitdir: hacia FUERA de las raices), a
     la papelera y purgado: se va entero, y lo de detras del gitdir sale
     intacto (un fichero .git se borra como fichero; no se sigue)
  G2 un repo dentro de una __delphi-temp: delphi_delete lo borra DE VERDAD
     (de una temporal no se restaura nada), sin restos
  G3 ...pero con un enlace en su .git hacia fuera de las raices, se niega
     (el juicio de los enlaces de los metadatos se queda al borrar, David
     11-oct) y la victima sale intacta

Uso:  python tests/test_purga_bordes_1184.py [ruta-a-DelphiLspMcp.exe]
"""
import os, subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('purga_bordes_1184')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
os.makedirs(FUERA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def foto(d):
    return sorted((os.path.relpath(os.path.join(r, f), d), open(os.path.join(r, f), 'rb').read())
                  for r, _, fs in os.walk(d) for f in fs)


# lo de detras del gitdir, FUERA de las raices
GITDIR = os.path.join(FUERA, 'realgit')
os.makedirs(GITDIR)
open(os.path.join(GITDIR, 'HEAD'), 'w').write('ref: refs/heads/main\n')
VICTIMA = os.path.join(FUERA, 'victima')
os.makedirs(VICTIMA)
open(os.path.join(VICTIMA, 'secreto.txt'), 'w').write('no se toca')
ANTES = foto(FUERA)

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='purga-bordes', t=120)
try:
    R = os.path.join(JAIL, 'R')
    os.makedirs(R)
    open(os.path.join(R, '.git'), 'w').write('gitdir: %s\n' % GITDIR)
    open(os.path.join(R, 'a.txt'), 'w').write('a')
    r = s.call('delphi_delete', {'path': R})
    copia = [ln.split('copy:', 1)[1].strip() for ln in r.splitlines() if 'copy:' in ln]
    ok = False
    if copia:
        r2 = s.call('delphi_delete', {'path': copia[0], 'purge': True})
        ok = not os.path.exists(mc.real(copia[0]))
        r = r + ' || ' + r2
    check('G1 un .git FICHERO con gitdir: hacia fuera: el repo se purga entero y lo de fuera sale intacto',
          ok and foto(FUERA) == ANTES, r[:500])

    T = os.path.join(JAIL, mc.TEMPORALES, 'agente', 'repo')
    os.makedirs(os.path.dirname(T))
    subprocess.run(['git', 'init', '-q', T], check=True, capture_output=True)
    open(os.path.join(T, 'b.txt'), 'w').write('b')
    r = s.call('delphi_delete', {'path': T})
    check('G2 un repo dentro de una __delphi-temp se borra de verdad, sin restos',
          not os.path.exists(T) and mc.PAPELERA not in r, r[:300])

    T3 = os.path.join(JAIL, mc.TEMPORALES, 'agente', 'repo3')
    subprocess.run(['git', 'init', '-q', T3], check=True, capture_output=True)
    subprocess.run(['cmd', '/c', 'mklink', '/J', os.path.join(T3, '.git', 'enlace'), VICTIMA],
                   check=True, capture_output=True)
    r = s.call('delphi_delete', {'path': T3})
    check('G3 ...con un enlace en su .git hacia fuera: negado (GUARD-033) y la victima intacta',
          'GUARD-033' in r and os.path.isdir(T3) and foto(FUERA) == ANTES, (r[:300], foto(FUERA) == ANTES))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('bordes de la purga 1184')
