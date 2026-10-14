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
  K4 control: con el enlace VIVO la proteccion ya valia (move negado)

Uso:  python tests/test_enlace_colgante_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('enlace_colgante_1182')
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(FUERA)
for b in ('B7', 'B9'):
    os.makedirs(os.path.join(JAIL, 'src', b))
    open(os.path.join(JAIL, 'src', b, 'U.dfm'), 'w').write('object F: TF\nend\n')
os.makedirs(os.path.join(JAIL, 'n9'))   # el destino del enlace VIVO
J7, N7 = os.path.join(JAIL, 'J7'), os.path.join(JAIL, 'n7')
J8, N8 = os.path.join(JAIL, 'J8'), os.path.join(JAIL, 'n8')
J9, N9 = os.path.join(JAIL, 'J9'), os.path.join(JAIL, 'n9')
JF, VICTIMA = os.path.join(JAIL, 'JF'), os.path.join(FUERA, 'nueva')
for j, d in ((J7, N7), (J8, N8), (J9, N9), (JF, VICTIMA)):
    mc.junction(j, d)
SKIP = None if all(os.path.lexists(j) for j in (J7, J8, J9, JF)) else 'no se pudieron crear los junctions'
TOKEN = 'colgante1182-0123456789abc'
PUERTO = mc.puerto_libre()
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n[Workspace.W]\nToken=%s\nRoots=%s\nReadOnlyPaths=%s;%s;%s\n'
            % (PUERTO, TOKEN, JAIL, os.path.join(J7, 'U.dfm'), J8, os.path.join(J9, 'U.dfm')))
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
        r = op.call('delphi_move', {'path': os.path.join(JAIL, 'src', 'B9'), 'dest': os.path.join(N9, 'B9')})
        check('K4 control: con el enlace vivo, lo protegido ya valia',
              not os.path.exists(os.path.join(N9, 'U.dfm')), r[:300])
    finally:
        try:
            proc.kill()
        except Exception:
            pass

mc.borra(BASE)
mc.fin('enlace colgante en la jaula 1182 (2w)', sin_checks=SKIP)
