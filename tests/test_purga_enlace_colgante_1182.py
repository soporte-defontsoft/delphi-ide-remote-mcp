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
  Y3 borrar un enlace colgante que NO esta en la papelera: va a ella como
     enlace (SYS-012 "does not exist" y se quedaba: H10 de la revision del
     paisaje de Fable, 26-oct-2026, ROJO contra r1222ch)
  Y4 ...y moverlo: se renombra el enlace (FILE-024, ROJO contra r1222ch)

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
              # PURGADO de verdad: not rechazado aceptaba INTERNAL y NO_ANSWER
              # (revisor de baterias, 18-oct-2026)
              mc.abre(r, 'SN_FILE_PURGED_FMT') and c1 is not None and not os.path.lexists(c1), (r[:200], c1))
        r = srv.call('delphi_delete', {'path': c2, 'purge': True})
        check('Y2 control: purgar un enlace VIVO quita el enlace y NO toca lo de detras',
              mc.abre(r, 'SN_FILE_PURGED_FMT') and c2 is not None and not os.path.lexists(c2) and
              os.path.exists(os.path.join(JAIL, 'd2', 'x.txt')), (r[:200], c2))
        # Y3/Y4: colgantes VIVOS (fuera de la papelera), su destino ya borrado
        for n in ('J3', 'J4'):
            os.makedirs(os.path.join(JAIL, 'd' + n))
            mc.junction(os.path.join(JAIL, n), os.path.join(JAIL, 'd' + n))
            os.rmdir(os.path.join(JAIL, 'd' + n))
        r = srv.call('delphi_delete', {'path': os.path.join(JAIL, 'J3')})
        c3 = copia_de(r)
        check('Y3 borrar un enlace COLGANTE vivo: a la papelera como enlace (no SYS-012)',
              mc.abre(r, 'SK_FILE_BORRADO_PAPELERA_FMT') and not os.path.lexists(os.path.join(JAIL, 'J3')) and
              c3 is not None and os.path.lexists(c3) and not os.path.exists(c3), (r[:200], c3))
        r = srv.call('delphi_move', {'path': os.path.join(JAIL, 'J4'), 'dest': os.path.join(JAIL, 'J4b')})
        check('Y4 ...y moverlo: se renombra el enlace (no FILE-024)',
              mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and not os.path.lexists(os.path.join(JAIL, 'J4')) and
              os.path.lexists(os.path.join(JAIL, 'J4b')) and not os.path.exists(os.path.join(JAIL, 'dJ4')),
              r[:200])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('purga de un enlace colgante 1182 (2y)', sin_checks=SKIP)
