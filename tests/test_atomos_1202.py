# -*- coding: utf-8 -*-
"""Lo que matamos, lo limpiamos (1.20.2, 18-oct-2026): un proceso VCL/FMX
muerto sin finalizar deja sus atomos globales (Vcl.Controls, Vcl.Dialogs,
FMX.Platform.Win) en la tabla de la sesion, 16384 para todos los procesos;
llena, Windows no arranca ningun proceso mas (0xC0000142). Esa noche cayeron
195 baterias y la maquina entera: 3.894 servidores de bateria matados con
proc.kill() y ~1.000 renderizadores muertos por plazo. Aqui se mide que ya no
dejan nada:

  A. el renderizador que se mata a si mismo por su plazo (--timeout 1) limpia
     antes lo suyo (BorraAtomosPropios, Lsp.AtomosRtl). El CONTROL: el mismo
     renderizador matado desde fuera a medio cargar SI deja atomos (asi se sabe
     que la medida ve una fuga), y la bateria los recoge: son basura suya.
  B. un servidor HTTP de bateria se PARA con proc.kill() (mc.ServidorHttp:
     CTRL_BREAK, salida limpia con codigo 0) sin dejar atomos; por stdio,
     cierra() y mata() tampoco (mata() mataba a pelo: 3 atomos por servidor
     en 62 sitios de tests/, medido el 19-oct-2026). Lo que el arnes mata de
     verdad, lo recoge (mc.atomos_rtl_recoge: A4 lo usa con el control).
  C. con la CPU llena (la pone la bateria), un servidor recien arrancado se
     para sin colgarse y casi siempre en menos de 4 s: su generador de tablas, a prioridad baja, no la
     retiene (Lsp.DesignerMetaGen le sube la prioridad al cerrar), y una
     conexion que se cruza con la parada tampoco: la del HTTP tiene un plazo
     de 3 s (V58 de la 1.23; Indy la esperaba sin limite).

(El plazo del servidor sobre un renderizador colgado - 75 s - no se provoca
aqui: lo cubren la prueba DUnitX de Lsp.AtomosRtl y la regla de test_paisaje
"lo que matamos, lo limpiamos".)

Uso:  python tests/test_atomos_1202.py [exe]
"""
import ctypes, os, subprocess, sys, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('atomos_1202')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
# sin paquetes del IDE: el exe solo ya registra los suyos al arrancar
FMX = os.path.join(JAIL, 'Uno.fmx')
open(FMX, 'w', encoding='utf-8', newline='\r\n').write(
    "object FormUno: TForm\n  ClientHeight = 100\n  ClientWidth = 200\n  object Label1: TLabel\n    Text = 'x'\n  end\nend\n")
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
RENDER = os.path.join(os.path.dirname(EXE), 'DelphiFormRenderFmx.exe')
k32 = ctypes.WinDLL('kernel32', use_last_error=True)


def atomos_de(pid, tid):
    """los atomos del RTL que llevan ESE pid o ESE hilo, vivan o no"""
    return [n for n, _v in mc.atomos_rtl() if n.endswith('%08X' % tid) or ('%08X' % pid) in n]


# ---- A. el vigia del renderizador limpia lo suyo antes de matarse
# (lo que deja cada paso se mide por NOMBRES nuevos de procesos muertos, no por
# la cuenta: un atomo viejo de la tabla cambia de 'vivo' a 'muerto' cuando acaba
# el hilo ajeno que reutilizaba su id, y un pid reutilizado casaba con uno viejo)
antes = mc.atomos_rtl_nombres()
r = subprocess.run([RENDER, '--path', FMX, '--out', os.path.join(JAIL, 'a.png'), '--timeout', '1'],
                   capture_output=True, text=True, errors='replace', timeout=120)
check('A1 renderizador con --timeout 1: lo mata su vigia (rc 3) y lo dice',
      r.returncode == 3 and 'ERROR=' in r.stdout, 'rc=%s %s' % (r.returncode, (r.stdout + r.stderr)[-200:]))
check('A2 ...y no deja ni un atomo del RTL de proceso muerto', not mc.atomos_rtl_dejados(antes),
      mc.atomos_rtl_dejados(antes))

# el CONTROL: matado desde fuera, sin pasar por su vigia, SI deja atomos
antes = mc.atomos_rtl_nombres()
p = subprocess.Popen([RENDER, '--path', FMX, '--out', os.path.join(JAIL, 'b.png'), '--timeout', '60000'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
tid = 0
fin = time.time() + 10
while time.time() < fin and not tid:
    tid = mc.hilo_principal(p.pid)
    # hasta que haya registrado los suyos (FIREMONKEY<pid>_<tid>, al arrancar FMX)
    if tid and not any(n.startswith('FIREMONKEY') for n in atomos_de(p.pid, tid)):
        tid = 0
        time.sleep(0.02)
p.kill()
p.wait(10)
# ...y a que muera su hilo principal: el proceso se senala antes de que el hilo
# deje de contestar STILL_ACTIVE, y el contador lo tomaria por vivo (medido:
# el control salia sin fuga una pasada de tres)
h = k32.OpenThread(0x00100000, False, tid)  # SYNCHRONIZE
if h:
    k32.WaitForSingleObject(h, 5000)
    k32.CloseHandle(h)
dejados = atomos_de(p.pid, tid)
nuevos = mc.atomos_rtl_dejados(antes)
check('A3 control: el mismo renderizador matado desde fuera deja sus atomos (la medida ve una fuga)',
      bool(tid) and nuevos and any(n.startswith('FIREMONKEY') for n in dejados), (dejados, nuevos))
# son basura de esta bateria: se recogen por su pid y su hilo (el mismo recogedor
# que usa el arnes tras un kill de verdad)
recogidos = mc.atomos_rtl_recoge(p.pid, tid)
check('A4 ...y la bateria recoge lo que dejo su control (mc.atomos_rtl_recoge)',
      recogidos > 0 and not mc.atomos_rtl_dejados(antes),
      (recogidos, dejados, mc.atomos_rtl_dejados(antes)))

# ---- B. un servidor de bateria se PARA, no se mata
antes = mc.atomos_rtl_nombres()
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}))
pid = proc.pid
t0 = time.time()
proc.kill()
check('B1 proc.kill() de un servidor HTTP de bateria lo PARA: sale limpio (codigo 0), antes del plazo',
      proc.returncode == 0 and time.time() - t0 < mc.ServidorHttp.PLAZO_PARADA,
      'rc=%s %.1f s' % (proc.returncode, time.time() - t0))


def suyos(pid, antes):
    """los atomos NUEVOS que llevan ESE pid por su nombre exacto (Delphi<pid>,
    FIREMONKEY<pid>_...): el pid como subcadena cazaba el tid de un muerto viejo,
    y un pid reutilizado casaba con un atomo viejo que ya estaba antes"""
    return [n for n, _v in mc.atomos_rtl()
            if (n == 'Delphi%08X' % pid or n.startswith('FIREMONKEY%08X_' % pid)) and n not in antes]


check('B2 ...sin dejar sus atomos (Delphi<pid> incluido)',
      not mc.atomos_rtl_dejados(antes) and not suyos(pid, antes), (mc.atomos_rtl_dejados(antes), suyos(pid, antes)))
antes = mc.atomos_rtl_nombres()
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='atomos', t=60)
pid = srv.p.pid
srv.cierra()
check('B3 cierra() de un servidor stdio: salida limpia (codigo 0) y sin atomos',
      srv.p.returncode == 0 and not mc.atomos_rtl_dejados(antes) and not suyos(pid, antes),
      'rc=%s %s %s' % (srv.p.returncode, mc.atomos_rtl_dejados(antes), suyos(pid, antes)))

antes = mc.atomos_rtl_nombres()
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='atomos', t=60)
pid = srv.p.pid
t0 = time.time()
srv.mata()
check('B4 mata() de un servidor stdio tambien lo PARA (62 sitios en tests/): codigo 0, antes del plazo y sin atomos',
      srv.p.returncode == 0 and time.time() - t0 < 15 and not mc.atomos_rtl_dejados(antes) and not suyos(pid, antes),
      'rc=%s %.1f s %s %s' % (srv.p.returncode, time.time() - t0, mc.atomos_rtl_dejados(antes), suyos(pid, antes)))

# un servidor lanzado SIN consola (CREATE_NO_WINDOW, como las baterias de handles):
# el CTRL_BREAK no le llega; kill() lo mata y recoge sin esperar. Con el kill suave
# llamandose a si mismo (560c99b) colgaba 15 s por vuelta: el release_check se quedo
# 52 minutos en test_handles_heredados (19-oct-2026). Con plazo: rojo, no colgado
import threading
antes = mc.atomos_rtl_nombres()
proc = mc.lanza_http(EXE, mc.puerto_libre(), mc.entorno({'DELPHI_MCP_ROOTS': JAIL}),
                     creationflags=subprocess.CREATE_NO_WINDOW)
pid = proc.pid
t0 = time.time()
h = threading.Thread(target=proc.kill, daemon=True)
h.start()
h.join(30)
dt = time.time() - t0
colgado = h.is_alive()
if proc.poll() is None:
    subprocess.Popen.kill(proc)
    proc.wait(10)
    mc.atomos_rtl_recoge(pid, 0)
check('B5 kill() de un servidor sin consola: muere enseguida, sin esperar el CTRL_BREAK que no le llega',
      not colgado and dt < mc.ServidorHttp.PLAZO_PARADA and proc.poll() is not None,
      'colgado=%s %.1f s rc=%s' % (colgado, dt, proc.poll()))
check('B6 ...y lo que deja matado, el arnes lo recoge (sin atomos)',
      not mc.atomos_rtl_dejados(antes) and not suyos(pid, antes), (mc.atomos_rtl_dejados(antes), suyos(pid, antes)))

# ---- C. la parada no espera a un hilo hambriento: el generador de tablas va a
# tpLower y, con la CPU llena, no le llegaba tiempo ni para ver que se cerraba;
# la finalizacion de Lsp.DesignerMetaGen lo esperaba sus 5 s enteros (B1 rojo
# dos veces en run_all, 24 y 25-oct-2026; medido: 5,3 s con la CPU llena, 13
# de 13). Ahora le sube la prioridad al cerrar. La carga la pone la bateria,
# dos procesos por nucleo, y se quitan por su propio handle
QUEMADORES = [subprocess.Popen([sys.executable, '-c', 'while True: pass'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
              for _ in range(2 * (os.cpu_count() or 2))]
tiempos = []
try:
    for _ in range(3):
        proc = mc.lanza_http(EXE, mc.puerto_libre(), mc.entorno({'DELPHI_MCP_ROOTS': JAIL}))
        t0 = time.time()
        proc.kill()
        tiempos.append((round(time.time() - t0, 1), proc.returncode))
finally:
    for q in QUEMADORES:
        q.kill()
        q.wait(10)
# (V58 de la 1.23) el umbral era 2 s, y 1 de cada ~15 paradas lo pasaba: la
# conexion con que espera_puerto comprueba el puerto se cruza con la parada y el
# TerminateAllYarns de Indy esperaba SIN limite a una yarn sin hilo (medido con
# cdb: 23,9 s y la mataba el arnes). La parada del HTTP tiene ahora un plazo de
# 3 s (TMCPIdHTTPServer.Stop). Y con la CPU llena aun hay paradas de 6 a 10 s, 6
# de 120 (V59, sin medir su causa: dos veces fueron 3-4 s dentro de
# TMcpHost.Destroy): ninguna se cuelga (menos de 12 s, el arnes espera 15) y la
# MEDIANA sigue cazando el hilo de las tablas, que retenia CADA parada (13 de 13)
check('C1 con la CPU llena, proc.kill() de un servidor recien arrancado sale limpio: ninguna se cuelga '
      '(menos de 12 s) y la mediana, menos de 4 s (antes 5,3 cada una)',
      len(tiempos) == 3 and all(rc == 0 and dt < 12 for dt, rc in tiempos)
      and sorted(dt for dt, _ in tiempos)[1] < 4, tiempos)

mc.borra(BASE)
mc.fin('atomos battery')
