# -*- coding: utf-8 -*-
"""2w de la 1.18.2 (medido por el revisor del 2r y otra vez en produccion el
14-oct): un enlace COLGANTE - un junction cuyo destino no existe todavia -
dejaba a RealPath con su TEXTO, porque para pedirle a Windows el nombre final
hay que abrirlo y un colgante no se abre. Con ReadOnlyPaths=jail\\J7\\U.dfm y
J7 -> jail\\n7 (sin crear), delphi_move src\\B7 -> jail\\n7 creaba el destino y
U.dfm aparecia DENTRO de lo declarado de solo lectura. Ahora RealPath lee lo
que guarda el propio enlace (FSCTL_GET_REPARSE_POINT: el juez es Windows).

  K1 el move que crearia el destino de un colgante protegido: negado, y
     J7\\U.dfm no aparece (ROJO en produccion)
  K2 ReadOnlyPaths = la carpeta J8 (colgante a n8): crear n8\\V.txt negado
     (ROJO en produccion)
  K3 control: un colgante que apunta FUERA de las raices: crear a traves de
     el se niega y fuera no aparece nada
  K4 control: con el enlace VIVO la proteccion ya valia: mover un fichero
     encima de n9\\U.dfm (= J9\\U.dfm) se niega (movia a n9\\B9 y no media nada:
     J6 del revisor de cierre)

Y lo del revisor de cierre de la 1.18.2:
  K5 una CADENA de 9 colgantes C1 -> ... -> C9 -> n10 y ReadOnlyPaths
     C1\\U.dfm: el move a n10 se niega (J1, ROJO en produccion: el tope era 8 y
     Windows sigue 63, medido)
  K6 una junction a un UNC (\\\\192.0.2.1, que Windows ni sigue): crear a traves
     de ella se niega SIN ir a la red, en menos de 5 s (J2, ROJO en produccion:
     21 s). (J3, un symlink relativo, pide un privilegio que esta cuenta no
     tiene: sin bateria, declarado.)

Uso:  python tests/test_enlace_colgante_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('enlace_colgante_1182')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(FUERA)
for b in ('B7', 'B9', 'B10'):
    os.makedirs(os.path.join(JAIL, 'src', b))
    open(os.path.join(JAIL, 'src', b, 'U.dfm'), 'w').write('object F: TF\nend\n')
os.makedirs(os.path.join(JAIL, 'n9'))   # el destino del enlace VIVO
J7, N7 = os.path.join(JAIL, 'J7'), os.path.join(JAIL, 'n7')
J8, N8 = os.path.join(JAIL, 'J8'), os.path.join(JAIL, 'n8')
J9, N9 = os.path.join(JAIL, 'J9'), os.path.join(JAIL, 'n9')
JF, VICTIMA = os.path.join(JAIL, 'JF'), os.path.join(FUERA, 'nueva')
for j, d in ((J7, N7), (J8, N8), (J9, N9), (JF, VICTIMA)):
    mc.junction(j, d)
N10 = os.path.join(JAIL, 'n10')
CADENA = [os.path.join(JAIL, 'C%d' % i) for i in range(1, 10)]
for i in range(len(CADENA) - 1, -1, -1):  # C9 -> n10, C8 -> C9, ..., C1 -> C2: todos colgantes
    mc.junction(CADENA[i], CADENA[i + 1] if i + 1 < len(CADENA) else N10)
JU = os.path.join(JAIL, 'JU')
mc.junction_nt(JU, r'\??\UNC\192.0.2.1\s\x')
SKIP = None if all(os.path.lexists(j) for j in [J7, J8, J9, JF, JU] + CADENA) else 'no se pudieron crear los junctions'
TOKEN = 'colgante1182-0123456789abc'
PUERTO = mc.puerto_libre()
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace.W]\nToken=%s\nRoots=%s\nReadOnlyPaths=%s;%s;%s\n'
            % (PUERTO, TOKEN, JAIL, os.path.join(J7, 'U.dfm'), J8,
               os.path.join(J9, 'U.dfm') + ';' + os.path.join(CADENA[0], 'U.dfm')))
if SKIP is None:
    proc = mc.lanza_http(EXE, None, mc.entorno(), espera_en=PUERTO)
    try:
        op = mc.Http(PUERTO, TOKEN, t=120)
        op.session('ana')
        r = op.call('delphi_move', {'path': os.path.join(JAIL, 'src', 'B7'), 'dest': N7})
        check('K1 move al destino de un colgante protegido: negado y J7\\U.dfm no aparece',
              mc.rechazado(r) and not os.path.exists(os.path.join(J7, 'U.dfm')), r[:300])
        r = op.call('delphi_textedit', {'path': os.path.join(N8, 'V.txt'), 'create': True, 'content': 'x'})
        check('K2 crear dentro del destino de una carpeta protegida por un colgante: negado',
              mc.rechazado(r) and not os.path.exists(os.path.join(N8, 'V.txt')), r[:300])
        r = op.call('delphi_textedit', {'path': os.path.join(JF, 'x.txt'), 'create': True, 'content': 'x'})
        check('K3 control: a traves de un colgante que sale de las raices no se escribe ni se crea nada fuera',
              mc.rechazado(r) and not os.path.exists(VICTIMA) and os.listdir(FUERA) == [], (r[:300], os.listdir(FUERA)))
        r = op.call('delphi_move', {'path': os.path.join(JAIL, 'src', 'B9', 'U.dfm'), 'dest': os.path.join(N9, 'U.dfm')})
        check('K4 control: con el enlace vivo, mover un fichero encima de lo protegido (n9\\U.dfm = J9\\U.dfm) se niega',
              mc.rechazado(r) and not os.path.exists(os.path.join(N9, 'U.dfm')), r[:300])
        r = op.call('delphi_move', {'path': os.path.join(JAIL, 'src', 'B10'), 'dest': N10})
        check('K5 una cadena de 9 colgantes hasta n10, protegido C1\\U.dfm: el move a n10 se niega',
              mc.rechazado(r) and not os.path.exists(os.path.join(CADENA[0], 'U.dfm')), r[:300])
        t0 = time.time()
        r = op.call('delphi_textedit', {'path': os.path.join(JU, 'q.txt'), 'create': True, 'content': 'q'})
        dt = time.time() - t0
        check('K6 una junction a un UNC: crear a traves de ella se niega sin ir a la red (< 5 s)',
              mc.rechazado(r) and dt < 5, ('%.1f s' % dt, r[:300]))
    finally:
        try:
            proc.kill()
        except Exception:
            pass

mc.borra(BASE)
mc.fin('enlace colgante en la jaula 1182 (2w)', sin_checks=SKIP)
