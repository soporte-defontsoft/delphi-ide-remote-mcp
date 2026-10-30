# -*- coding: utf-8 -*-
"""Un hijo de RunCore que acaba POR SU CUENTA sin finalizar (1.21.2). Hasta la
1.21.1 el servidor limpiaba los atomos del RTL solo de lo que mataba el (su
plazo); un renderizador que moria solo - su Job lo mata por una excepcion sin
tratar (DIE_ON_UNHANDLED_EXCEPTION), un paquete de diseno que revienta - dejaba
sus atomos y nadie los veia: 6 renderizadores VCL en la puerta de la 1.21.1
(20-oct-2026), 2 en la pasada instrumentada, intermitentes. Y el juez del orden
de un set lo tolera (orderNote), asi que la bateria salia verde.

  H1 el renderizador VCL muere desde fuera a media vida (matado por esta
     bateria: para RunCore es lo mismo que un reventon): la respuesta lo dice,
     el servidor limpia lo que dejo (0 atomos nuevos de proceso muerto) y lo
     apunta en su log con el codigo
  H2 control: el mismo preview intacto: imagen, 0 atomos y nada en el log
  H3 la ventana de aplicacion de FMX (TFMAppClass, la trae fmx<nnn>.bpl con los
     paquetes) no se ve en la barra ni un instante: el gancho CBT cambiaba el
     CREATESTRUCT, que Windows ignora (medido con una sonda), y nacia con
     WS_EX_APPWINDOW hasta que EscondeVentanaDeApp la escondia (3 muestras de
     4.043 en el corpus de la 1.21.1). Ahora el gancho cambia el estilo de la
     VENTANA al nacer. Se mira cada ~0,5 ms durante cinco renders con paquetes.

H1 es ROJA contra 1.21.1 (5 atomos quedan, nada en el log). H3 solo A VECES:
el parpadeo dura menos de un milisegundo y el muestreo lo pilla o no (contra
1.21.1: 1 de 3 renders una pasada, '00040000' = WS_EX_APPWINDOW; 0 de 5 otra);
con el arreglo no puede darse, y por eso aqui es 0 siempre.

Uso:  python tests/test_hijo_sin_finalizar_1212.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, os, threading, time
from ctypes import wintypes as w
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('hijo_sin_finalizar_1212')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
# una form con una clase de un PAQUETE del IDE (FireDAC): el renderizador con
# --packages auto carga los paquetes, vive ~1 s y lleva sus atomos todo ese tiempo
open(os.path.join(JAIL, 'UFd.pas'), 'wb').write(
    b'unit UFd;\r\n\r\ninterface\r\n\r\nuses\r\n  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,\r\n'
    b'  FireDAC.Comp.Client;\r\n\r\ntype\r\n  TForm1 = class(TForm)\r\n    Button1: TButton;\r\n'
    b'    FDConnection1: TFDConnection;\r\n  end;\r\n\r\nvar\r\n  Form1: TForm1;\r\n\r\nimplementation\r\n\r\n'
    b'{$R *.dfm}\r\n\r\nend.\r\n')
DFM = os.path.join(JAIL, 'UFd.dfm')
open(DFM, 'wb').write(
    b"object Form1: TForm1\r\n  Left = 0\r\n  Top = 0\r\n  Caption = 'Form1'\r\n  ClientHeight = 200\r\n"
    b"  ClientWidth = 300\r\n  object Button1: TButton\r\n    Left = 8\r\n    Top = 8\r\n    TabOrder = 0\r\n  end\r\n"
    b"  object FDConnection1: TFDConnection\r\n    Left = 120\r\n    Top = 40\r\n  end\r\nend\r\n")

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
u32 = ctypes.WinDLL('user32', use_last_error=True)
TH32CS_SNAPPROCESS = 0x2


class PE32(ctypes.Structure):
    _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('th32ProcessID', w.DWORD),
                ('th32DefaultHeapID', ctypes.c_size_t), ('th32ModuleID', w.DWORD), ('cntThreads', w.DWORD),
                ('th32ParentProcessID', w.DWORD), ('pcPriClassBase', ctypes.c_long), ('dwFlags', w.DWORD),
                ('szExeFile', ctypes.c_wchar * 260)]


k32.CreateToolhelp32Snapshot.restype = w.HANDLE
k32.Process32FirstW.argtypes = k32.Process32NextW.argtypes = [w.HANDLE, ctypes.POINTER(PE32)]
k32.OpenProcess.restype = w.HANDLE
k32.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k32.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
k32.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
k32.CloseHandle.argtypes = [w.HANDLE]


def renderizador_hijo_de(pid_padre, nombre='delphiformrendervcl.exe'):
    """el pid del renderizador que lanzo ese servidor (0 si aun no hay)"""
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    pe = PE32()
    pe.dwSize = ctypes.sizeof(PE32)
    hallado = 0
    ok = k32.Process32FirstW(snap, ctypes.byref(pe))
    while ok and not hallado:
        if pe.th32ParentProcessID == pid_padre and pe.szExeFile.lower() == nombre:
            hallado = pe.th32ProcessID
        ok = k32.Process32NextW(snap, ctypes.byref(pe))
    k32.CloseHandle(snap)
    return hallado


def atomos_de(pid, tid):
    return [n for n, _v in mc.atomos_rtl() if n == 'Delphi%08X' % pid or n.endswith('%08X' % tid)]


def espera_log(srv, aguja, t=3):
    fin = time.time() + t
    while time.time() < fin:
        if any(aguja in l for l in srv.errores):
            return True
        time.sleep(0.05)
    return False


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='hijo-sin-finalizar', t=180, lee_stderr=True)
try:
    # la caja de paquetes hecha: al hacerla, el servidor corre ayudantes de vida corta que
    # H1 tomaria por el renderizador (V65 de la 1.24)
    r = srv.call('delphi_designer', {'command': 'preview', 'path': DFM}, t=120)
    check('H1 preparacion: la caja de paquetes hecha, el primer preview dibuja', not mc.rechazado(r), r[:300])
    # ---- H1: el renderizador muere a media vida, desde fuera
    antes = mc.atomos_rtl_nombres()
    resp = []
    hilo = threading.Thread(target=lambda: resp.append(srv.call('delphi_designer', {'command': 'preview', 'path': DFM}, t=120)))
    hilo.start()
    rpid = tid = 0
    fin = time.time() + 20
    while time.time() < fin and not tid:
        rpid = rpid or renderizador_hijo_de(srv.p.pid)
        if rpid:
            tid = mc.hilo_principal(rpid)
            # hasta que lleve los suyos (los del exe y los de los paquetes: 4 o mas)
            if tid and len(atomos_de(rpid, tid)) < 4:
                tid = 0
        time.sleep(0.005)
    suyos = atomos_de(rpid, tid) if tid else []
    h = k32.OpenProcess(0x0001 | 0x00100000, False, rpid) if rpid else None  # TERMINATE | SYNCHRONIZE
    matado = bool(h) and bool(k32.TerminateProcess(h, 7))
    if h:
        k32.WaitForSingleObject(h, 5000)
        k32.CloseHandle(h)
    check('H1 preparacion: el renderizador VCL vive con sus atomos y se mata desde fuera a media vida',
          bool(tid) and len(suyos) >= 4 and matado, (rpid, tid, suyos, matado))
    hilo.join(120)
    r = resp[0] if resp else ''
    check('H1 la respuesta dice que el renderizador acabo mal (codigo 7, DSGN-061)',
          'DSGN-061' in r and 'exit code 7' in r, r[:300])
    dej = mc.atomos_rtl_dejados(antes)
    check('H1 el servidor limpia lo que dejo: ningun atomo nuevo de proceso muerto', not dej, (dej, suyos))
    check('H1 ...y lo apunta en su log con el codigo (SL_HIJO_SIN_FINALIZAR)',
          espera_log(srv, 'without finalizing') and any('0x00000007' in l for l in srv.errores),
          [l for l in srv.errores if 'finaliz' in l][:3])
    # lo que la bateria dejara si el arreglo falta, no es de nadie mas: se recoge
    if dej and tid:
        mc.atomos_rtl_recoge(rpid, tid)

    # ---- H2: control, el mismo preview intacto
    n_log = len(srv.errores)
    antes = mc.atomos_rtl_nombres()
    r = srv.call('delphi_designer', {'command': 'preview', 'path': DFM}, t=120)
    check('H2 control: el mismo preview intacto da imagen y no deja atomos',
          not mc.rechazado(r) and not mc.atomos_rtl_dejados(antes), (r[:200], mc.atomos_rtl_dejados(antes)))
    time.sleep(0.5)
    check('H2 ...y nada nuevo en el log de hijos sin finalizar',
          not any('without finalizing' in l for l in srv.errores[n_log:]), srv.errores[n_log:][:3])

    # ---- H3: la TFMAppClass no se ve en la barra ni un instante
    PROC = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
    u32.EnumWindows.argtypes = [PROC, ctypes.c_void_p]
    u32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    u32.IsWindowVisible.argtypes = [ctypes.c_void_p]
    u32.GetClassNameW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_int]
    u32.GetWindowLongW.argtypes = [ctypes.c_void_p, ctypes.c_int]
    vistas = []
    parar = [False]
    pids = set()

    def vigila():
        def cb(hwnd, _lp):
            pid = ctypes.c_uint32()
            u32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            if pid.value in pids and u32.IsWindowVisible(hwnd):
                ex = u32.GetWindowLongW(hwnd, -20) & 0xFFFFFFFF
                if ex & 0x40000:
                    cls = ctypes.create_unicode_buffer(64)
                    u32.GetClassNameW(hwnd, cls, 64)
                    vistas.append((pid.value, cls.value, '%08X' % ex))
            return 1
        f = PROC(cb)
        while not parar[0]:
            rp = renderizador_hijo_de(srv.p.pid)
            if rp:
                pids.add(rp)
            u32.EnumWindows(f, None)
            time.sleep(0.0005)

    v = threading.Thread(target=vigila, daemon=True)
    v.start()
    for i in range(5):
        srv.call('delphi_designer', {'command': 'preview', 'path': DFM, 'state': 'Button1.Left=%d' % (20 + i)}, t=120)
    parar[0] = True
    v.join(5)
    check('H3 ninguna ventana de aplicacion visible (WS_EX_APPWINDOW) del renderizador en cinco renders con paquetes',
          not vistas, (len(vistas), vistas[:4], sorted(pids)))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('hijo sin finalizar 1.21.2')
