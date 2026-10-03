"""E2E battery: the startup purge empties the temporaries (the server's house,
the temp folder of every root, and the delphi_test containers of the house)
only when this is the ONLY live instance of the exe.

Pending point 2 of 1.11.0: the purge ran in the FIRST instance (a mutex keyed
by the exe's folder). A stdio instance started while the service ran was not
first, so it did not purge - right. But when the SERVICE restarted, its new
process took the free mutex, became "first" and emptied __delphi-temp, the
temp folder of every root and the containers of the house: also what the
stdio instance had in flight (a test's copy, a commit's message file).

This battery reproduces it with a copy of the exe: instance A (the service)
and instance B (stdio, same exe); something "in flight" of B is planted in
the house and in a root's temp; A is killed and restarted with B alive. What
B had must survive. The control: with B gone, a lone start DOES purge - so the
first two checks cannot pass because the purge simply does nothing.

Usage:  python tests/test_purga_instancias.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

TOKEN = 'purga-token-123'
PORT = mc.puerto_libre()
BASE = mc.carpeta('purga_inst')
SRV = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(SRV)
with open(os.path.join(SRV, 'settings.ini'), 'w') as f:
    f.write('[Server]\nPort=%d\nBindIP=127.0.0.1\n\n' % PORT +
            '[Workspace.Purga]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
CASA = os.path.join(SRV, '__delphi-temp')
RAIZ_TMP = os.path.join(JAIL, '__delphi-temp')
VIVO_CASA = os.path.join(CASA, 'vivo-de-la-stdio.txt')
VIVO_RAIZ = os.path.join(RAIZ_TMP, 'vivo-de-la-stdio.txt')
env = mc.entorno()


def planta():
    for d, f in ((CASA, VIVO_CASA), (RAIZ_TMP, VIVO_RAIZ)):
        os.makedirs(d, exist_ok=True)
        with open(f, 'w') as h:
            h.write('en vuelo')


def para(p):
    try:
        p.kill()
        p.wait(10)
    except Exception:
        pass


A = B = A2 = A3 = None
try:
    A = mc.lanza_http(EXE, PORT, env=env)            # el servicio
    B = mc.Stdio(EXE, env, nombre='stdio-misma-casa')  # otra instancia del MISMO exe
    check('fixture: la instancia stdio del mismo exe contesta', B.init is not None, str(B.init)[:200])
    planta()
    # el servicio se reinicia con la stdio viva
    para(A)
    A2 = mc.lanza_http(EXE, PORT, env=env)
    check('P1 el servicio que rearranca con otra instancia VIVA del mismo exe no vacia la casa',
          os.path.exists(VIVO_CASA), VIVO_CASA)
    check('P2 ...ni la temporal de una raiz (lo que la viva tenia en vuelo sigue)',
          os.path.exists(VIVO_RAIZ), VIVO_RAIZ)
    # control: sin la stdio, un arranque a solas SI purga
    B.mata()
    B = None
    para(A2)
    A2 = None
    A3 = mc.lanza_http(EXE, PORT, env=env)
    check('P3 control: a solas, el arranque SI vacia la casa (P1 no pasa porque la purga no haga nada)',
          not os.path.exists(VIVO_CASA), VIVO_CASA)
    check('P4 control: a solas, el arranque SI vacia la temporal de la raiz',
          not os.path.exists(VIVO_RAIZ), VIVO_RAIZ)
finally:
    if B is not None:
        B.mata()
    for p in (A, A2, A3):
        if p is not None:
            para(p)
    mc.borra(BASE)
mc.fin('startup purge vs a live instance battery')
