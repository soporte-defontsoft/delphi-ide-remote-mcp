"""E2E battery: the startup purge reaches EVERY __delphi-temp under a write
root, nested ones included (2026-09-25: a nested one kept 90 captures, 66 MB,
through every restart of the day). And it touches nothing it must not: a
.git, a ReadOnlyPaths folder, a reference project (ReadOnlyRoots), whatever
sits behind a junction, a folder that is not called __delphi-temp.

Usage:  python tests/test_purga_temporales.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('purga-temporales')
# su propia copia, fuera de las raices: el compilado no se ejecuta en su sitio
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
ROOT = os.path.join(BASE, 'raiz')
REF = os.path.join(BASE, 'referencia')
FUERA = os.path.join(BASE, 'fuera')

def siembra(*partes):
    p = os.path.join(*partes)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w').write('x')
    return p


arriba = siembra(ROOT, '__delphi-temp', 'agente', 'desktop', 'cap.png')
anidada = siembra(ROOT, 'proy', 'sub', '__delphi-temp', 'viejo.png')
honda = siembra(ROOT, 'a', 'b', 'c', 'd', '__delphi-temp', 'log.txt')
git = siembra(ROOT, 'proy', '.git', '__delphi-temp', 'no-tocar.txt')
vendor = siembra(ROOT, 'vendor', '__delphi-temp', 'no-tocar.txt')
ref = siembra(REF, 'p', '__delphi-temp', 'no-tocar.txt')
fuera = siembra(FUERA, '__delphi-temp', 'no-tocar.txt')
normal = siembra(ROOT, 'proy', 'temp', 'fichero.txt')  # "temp" no es __delphi-temp
# the deletion guard (25-sep-2026): a SECOND root that lives inside the
# first root's temp folder must survive the purge of that temp folder,
# and a junction planted inside a temp folder is removed as a LINK - the
# folder it points to is never emptied.
RAIZ2 = os.path.join(ROOT, '__delphi-temp', 'otra-raiz')
raiz2 = siembra(RAIZ2, 'proyecto.pas')
VICTIMA = os.path.join(BASE, 'victima')
victima = siembra(VICTIMA, 'no-tocar.txt')
enlace_tmp = os.path.join(ROOT, 'proy', 'sub', '__delphi-temp', 'lnk')
subprocess.run(['cmd', '/c', 'mklink', '/J', enlace_tmp, VICTIMA], capture_output=True)
enlace = os.path.join(ROOT, 'enlace')
subprocess.run(['cmd', '/c', 'mklink', '/J', enlace, FUERA], capture_output=True)
check('fixture: junction creado dentro de la raiz apuntando fuera', os.path.isdir(enlace), enlace)

env = mc.entorno({'DELPHI_MCP_ROOTS': ROOT + ';' + RAIZ2,
                  'DELPHI_MCP_READONLY_PATHS': 'vendor',
                  'DELPHI_MCP_READONLY_ROOTS': REF})
srv = mc.Stdio(EXE, env, nombre='bateria-purga')  # respondio: el arranque (y su purga) ya paso
time.sleep(0.5)

check('purga: la temporal de la raiz se vacia', not os.path.exists(arriba), arriba)
check('purga: una ANIDADA se vacia', not os.path.exists(anidada), anidada)
check('purga: una anidada a cinco niveles se vacia', not os.path.exists(honda), honda)
check('purga: la carpeta __delphi-temp se conserva (se vacia, no se borra)',
      os.path.isdir(os.path.dirname(anidada)), os.path.dirname(anidada))
check('protegido: dentro de .git no se toca', os.path.exists(git), git)
check('protegido: ReadOnlyPaths (vendor) no se toca', os.path.exists(vendor), vendor)
check('protegido: un proyecto de referencia no se toca', os.path.exists(ref), ref)
check('protegido: lo que hay tras un junction no se toca', os.path.exists(fuera), fuera)
check('una carpeta "temp" cualquiera no se toca', os.path.exists(normal), normal)
check('guard: una RAIZ metida en una temporal sobrevive a la purga de esa temporal',
      os.path.exists(raiz2), raiz2)
check('guard: un junction dentro de una temporal cae como enlace',
      not os.path.exists(enlace_tmp), enlace_tmp)
check('guard: la carpeta a la que apuntaba el junction sigue intacta',
      os.path.exists(victima), victima)

# DUENO (26-sep-2026): la temporal de una raiz es del servidor que la
# reclamo, mientras viva. Un SEGUNDO servidor -otro exe, la misma raiz- no la
# vacia: hasta hoy una bateria sobre el repo vaciaba REPO\__delphi-temp con
# el servicio vivo y sus llamadas en vuelo (el cerrojo iba por la carpeta del
# exe, y cada bateria corre el suyo).
en_vuelo = siembra(ROOT, '__delphi-temp', 'agente', 'en-vuelo.txt')
srv2 = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'srv2')), env, nombre='bateria-purga-2')
time.sleep(0.5)
check('dueno: un SEGUNDO servidor con la misma raiz NO vacia la temporal de uno vivo',
      os.path.exists(en_vuelo), en_vuelo)
srv2.cierra()
srv.cierra()
# muerto el primero, lo que quedo no es de nadie: el siguiente arranque lo vacia
srv3 = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'srv3')), env, nombre='bateria-purga-3')
time.sleep(0.5)
check('dueno: muerto el primero, el siguiente arranque SI la vacia (ya es basura)',
      not os.path.exists(en_vuelo), en_vuelo)
srv3.cierra()
if os.path.isdir(enlace):
    os.rmdir(enlace)  # quita el junction, nunca lo que hay detras
mc.borra(BASE)
mc.fin('purga-temporales battery')
