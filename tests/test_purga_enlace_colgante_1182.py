# -*- coding: utf-8 -*-
"""2y de la 1.18.2 (medido en produccion el 11-oct): un enlace COLGANTE en la
papelera no se podia purgar. delphi_delete de un junction lo manda a la
papelera como enlace (bien); si despues desaparece la carpeta de detras,
delphi_delete purge=true del enlace contestaba SYS-012 "does not exist" (la
existencia se preguntaba SIGUIENDO el enlace) y el enlace se quedaba para
siempre. El juez es el atributo del propio nombre (EsEnlace).

  Y1 purgar el enlace colgante de la papelera: se va (ROJO en produccion: SYS-012)
  Y2 control: purgar un enlace VIVO de la papelera quita el enlace y NO toca lo
     de detras (el fichero del destino sigue)

Uso:  python tests/test_purga_enlace_colgante_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import shutil
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('purga_enlace_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
SKIP = None


def copia_de(r):
    m = re.search(r'copy: (\S+)', r)
    return mc.real(m.group(1)) if m else None


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='purga-enlace', t=120)
try:
    for nombre in ('d1', 'd2'):
        os.makedirs(os.path.join(JAIL, nombre))
        open(os.path.join(JAIL, nombre, 'x.txt'), 'w').write('x')
    if not (mc.junction(os.path.join(JAIL, 'J1'), os.path.join(JAIL, 'd1')) and
            mc.junction(os.path.join(JAIL, 'J2'), os.path.join(JAIL, 'd2'))):
        SKIP = 'no se pudo crear un junction'
    else:
        c1 = copia_de(srv.call('delphi_delete', {'path': os.path.join(JAIL, 'J1')}))
        c2 = copia_de(srv.call('delphi_delete', {'path': os.path.join(JAIL, 'J2')}))
        shutil.rmtree(os.path.join(JAIL, 'd1'))   # J1 queda colgante en la papelera
        r = srv.call('delphi_delete', {'path': c1, 'purge': True})
        check('Y1 purgar un enlace COLGANTE de la papelera: se va (no SYS-012)',
              not mc.rechazado(r) and c1 is not None and not os.path.lexists(c1), (r[:200], c1))
        r = srv.call('delphi_delete', {'path': c2, 'purge': True})
        check('Y2 control: purgar un enlace VIVO quita el enlace y NO toca lo de detras',
              not mc.rechazado(r) and c2 is not None and not os.path.lexists(c2) and
              os.path.exists(os.path.join(JAIL, 'd2', 'x.txt')), (r[:200], c2))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('purga de un enlace colgante 1182 (2y)', sin_checks=SKIP)
