"""E2E battery (V31 de la 1.23): el arranque NO toca ninguna __delphi-temp de una raiz.

Desde la 1.18.2 (2af) nada del servidor vive en las raices: las capturas, en su casa
(Lsp.Casa). La purga de las __delphi-temp de las raices solo se llevaba lo que dejaron las
versiones anteriores - un proceso interno del servidor borrando DENTRO del workspace, que no
es su casa (David, 11-oct-2026: lo interno vive en la suya) - y con una raiz compartida por
dos maquinas, lo que el servidor de la otra tuviera a medias (por eso llevaba un corte de una
hora en las de red). Su propio comentario decia "Retirarla en la 1.19": retirada en la 1.23.
Lo que quede en una raiz es del operador: oculto en los listados y negado para escribir.

  T1  una __delphi-temp en la raiz, una anidada y una a cinco niveles siguen enteras tras
      arrancar (ROJO contra r1222aw: las vaciaba)
  T2  ...y un junction dentro de una de ellas, y lo de detras, tambien
  T3  control: la purga del arranque SI corrio - la casa del servidor (la __delphi-temp junto
      a su exe) quedo vacia -, asi que T1 y T2 no pasan porque el arranque no haga nada

Lo que la purga de la casa no cruza enlaces lo mide test_round46 (J2); que solo purga la
primera instancia viva, test_purga_instancias y test_round46 (T7).

Usage:  python tests/test_purga_temporales.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('purga-temporales')
SRV = os.path.join(BASE, 'srv')
# su propia copia, fuera de las raices: el compilado no se ejecuta en su sitio
EXE = mc.copia_exe(SRV)
ROOT = os.path.join(BASE, 'raiz')
VICTIMA = os.path.join(BASE, 'victima')


def siembra(*partes):
    p = os.path.join(*partes)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w').write('x')
    return p


arriba = siembra(ROOT, mc.TEMPORALES, 'agente', 'desktop', 'cap.png')
anidada = siembra(ROOT, 'proy', 'sub', mc.TEMPORALES, 'viejo.png')
honda = siembra(ROOT, 'a', 'b', 'c', 'd', mc.TEMPORALES, 'log.txt')
victima = siembra(VICTIMA, 'no-tocar.txt')
enlace = os.path.join(ROOT, 'proy', 'sub', mc.TEMPORALES, 'lnk')
subprocess.run(['cmd', '/c', 'mklink', '/J', enlace, VICTIMA], capture_output=True)
# (revisor de baterias, 18-oct-2026) si el mklink no la creaba, "sigue el enlace"
# no mediria nada
check('fixture: junction dentro de una temporal de la raiz, hacia la victima', os.path.isjunction(enlace), enlace)
# la casa del servidor de esta bateria: la __delphi-temp junto a su exe (el control)
migaja = siembra(SRV, mc.TEMPORALES, 'de-la-vez-anterior.txt')

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': ROOT}), nombre='bateria-purga')  # respondio: el arranque ya paso
time.sleep(0.5)
try:
    check('T3 control: la purga del arranque corrio (la casa del servidor quedo vacia)',
          not os.path.exists(migaja), migaja)
    check('T1 la __delphi-temp de la raiz sigue entera', os.path.exists(arriba), arriba)
    check('T1 ...una anidada tambien', os.path.exists(anidada), anidada)
    check('T1 ...y una a cinco niveles', os.path.exists(honda), honda)
    check('T2 un junction dentro de una de ellas sigue, y lo de detras',
          os.path.isjunction(enlace) and os.path.exists(victima), enlace)
finally:
    srv.cierra()
    if os.path.isjunction(enlace):
        os.rmdir(enlace)  # quita el junction, nunca lo que hay detras
    mc.borra(BASE)
mc.fin('purga-temporales battery (V31)')
