"""Controles en rutas: la regla se cumple con y sin jaula antes de Win32."""
import os
import mcp_cliente as mc
from mcp_cliente import check
BASE = mc.carpeta('ruta-controles')
MINE = os.path.join(BASE, 'mio')
VICTIM = os.path.join(BASE, 'victima')
os.makedirs(MINE)
os.makedirs(VICTIM)
open(os.path.join(MINE, 'local.txt'), 'w').write('local')
open(os.path.join(VICTIM, 'privado.txt'), 'w').write('intacto')
LINK = os.path.join(MINE, 'enlace')
check('fixture junction hacia victima fuera', mc.junction(LINK, VICTIM))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
try:
    for jailed in (True, False):
        srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE} if jailed else {}), nombre='ruta-controles')
        try:
            for n in range(32):
                bad = MINE + chr(n)
                out = srv.call('delphi_list', {'root': bad})
                check('control %d al final, jaula=%s' % (n, jailed),
                      mc.es(out, 'SR_GUARD_CONTROL_EN_RUTA_FMT') and mc.rechazado(out), out)
            out = srv.call('delphi_read', {'path': os.path.join(MINE, 'local.txt')})
            check('ruta normal sigue legible, jaula=%s' % jailed, 'local' in out and not mc.fallo(out), out)
            if jailed:
                out = srv.call('delphi_read', {'path': os.path.join(LINK, 'privado.txt')})
                check('junction no lee ni nombra a la victima', mc.rechazado(out) and 'intacto' not in out, out)
        finally:
            srv.cierra()
    check('victima intacta', os.listdir(VICTIM) == ['privado.txt'] and mc.lee(os.path.join(VICTIM, 'privado.txt')) == 'intacto')
finally:
    os.rmdir(LINK)
mc.borra(BASE)
check('BASE eliminada con su copia del exe', not os.path.exists(BASE), BASE)
mc.fin('ruta controles')
