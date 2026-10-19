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
     cierra() tampoco.

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
# son basura de esta bateria: se recogen por su nombre exacto (de un proceso que ya no existe)
for n in dejados:
    a = k32.GlobalFindAtomW(n)
    while a:
        k32.GlobalDeleteAtom(a)
        a = k32.GlobalFindAtomW(n)
check('A4 ...y la bateria recoge lo que dejo su control', not mc.atomos_rtl_dejados(antes),
      mc.atomos_rtl_dejados(antes))

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

mc.borra(BASE)
mc.fin('atomos battery')
