# -*- coding: utf-8 -*-
"""Las teclas que el nodo de escritorio de Windows conoce (6-oct-2026).

delphi_desktop key en un target Windows manda la tecla por su NOMBRE y el
nodo la traduce (Mld.Win.TeclaPorNombre). Hasta hoy no conocia las letras:
Ctrl+S o Ctrl+A contestaban "Unknown key" (NODE-010), y la descripcion
llego a ofrecer Ctrl+K como ejemplo.

Se mide SIN PULSAR NADA en el escritorio de quien corre la bateria: el nodo
se lanza en un escritorio de Windows APARTE, que no es el de entrada, y alli
SendInput no entrega ni una tecla (medido: "accepted 0 of 2 inputs"). La
salida distingue lo que se mide:
  NODE-010  la tecla no tiene nombre en el nodo
  NODE-011  el nombre se resolvio y el envio quedo bloqueado
  NODE-044  la tecla SE ENVIO - si sale con la de control, el escritorio
            aparte no aisla y la bateria se para ANTES de mandar letras

  K1  control: shift sola en el escritorio aparte se bloquea (NODE-011)
  K2  ctrl k, ctrl s, ctrl a: las letras se resuelven (NODE-011, no 010)
  K3  f4 y alt+tab siguen como antes (NODE-011)
  K4  un nombre que no existe sigue diciendo NODE-010

Usage:  python tests/test_nodo_teclas.py [path-to-McpDesktopNode.exe]
"""
import ctypes, os, re, shutil, sys
import ctypes.wintypes as w
import mcp_cliente as mc
from mcp_cliente import check

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NODO_SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'node', 'McpDesktopNode.exe')
u32 = ctypes.WinDLL('user32', use_last_error=True)
k32 = ctypes.WinDLL('kernel32', use_last_error=True)


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [('cb', w.DWORD), ('lpReserved', w.LPWSTR), ('lpDesktop', w.LPWSTR),
                ('lpTitle', w.LPWSTR), ('dwX', w.DWORD), ('dwY', w.DWORD),
                ('dwXSize', w.DWORD), ('dwYSize', w.DWORD), ('dwXCountChars', w.DWORD),
                ('dwYCountChars', w.DWORD), ('dwFillAttribute', w.DWORD), ('dwFlags', w.DWORD),
                ('wShowWindow', w.WORD), ('cbReserved2', w.WORD), ('lpReserved2', ctypes.c_void_p),
                ('hStdInput', w.HANDLE), ('hStdOutput', w.HANDLE), ('hStdError', w.HANDLE)]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [('hProcess', w.HANDLE), ('hThread', w.HANDLE),
                ('dwProcessId', w.DWORD), ('dwThreadId', w.DWORD)]


u32.CreateDesktopW.restype = w.HANDLE
u32.CreateDesktopW.argtypes = [w.LPCWSTR, w.LPCWSTR, ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.c_void_p]
u32.CloseDesktop.argtypes = [w.HANDLE]
k32.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, w.BOOL,
                               w.DWORD, ctypes.c_void_p, w.LPCWSTR,
                               ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION)]
k32.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
k32.CloseHandle.argtypes = [w.HANDLE]
GENERIC_ALL = 0x10000000
CREATE_NO_WINDOW = 0x08000000


def clave_del_nodo():
    """La clave que el servidor le pasa al nodo (NodeKey.inc, la incluyen los
    dos proyectos). Se lee, nunca se imprime."""
    with open(os.path.join(REPO, 'src', 'DesktopNode', 'NodeKey.inc'), encoding='utf-8') as f:
        return re.search(r"NODE_KEY\s*=\s*'([^']+)'", f.read()).group(1)


def en_escritorio_aparte(nodo, args, base):
    """El nodo con 'args' en un escritorio de WinSta0 que nadie activa; su
    salida, por un fichero."""
    desk = 'mcp-bateria-teclas'
    hdesk = u32.CreateDesktopW(desk, None, None, 0, GENERIC_ALL, None)
    if not hdesk:
        raise OSError('CreateDesktop: %d' % ctypes.get_last_error())
    try:
        out = os.path.join(base, 'salida.txt')
        cmd = 'cmd.exe /c ""%s" %s > "%s" 2>&1"' % (nodo, ' '.join([clave_del_nodo()] + args), out)
        si = STARTUPINFOW()
        si.cb = ctypes.sizeof(si)
        si.lpDesktop = 'WinSta0\\' + desk
        pi = PROCESS_INFORMATION()
        if not k32.CreateProcessW(None, ctypes.create_unicode_buffer(cmd), None, None, False,
                                  CREATE_NO_WINDOW, None, base, ctypes.byref(si), ctypes.byref(pi)):
            raise OSError('CreateProcess: %d' % ctypes.get_last_error())
        k32.WaitForSingleObject(pi.hProcess, 30000)
        k32.CloseHandle(pi.hThread)
        k32.CloseHandle(pi.hProcess)
        with open(out, 'rb') as f:
            return f.read().decode('utf-8', 'replace')
    finally:
        u32.CloseDesktop(hdesk)


def codigo(salida):
    m = re.search(r'NODE-0(10|11|44)\b', salida)
    return 'NODE-0' + m.group(1) if m else ''


if not os.path.exists(NODO_SRC):
    print('NOTA: no hay node/McpDesktopNode.exe (BuildGroup lo deja ahi); no se mide.')
    mc.fin('teclas del nodo')
    sys.exit(0)

BASE = mc.carpeta('nodo_teclas')
try:
    NODO = os.path.join(BASE, 'McpDesktopNode.exe')
    shutil.copy(NODO_SRC, NODO)

    def tecla(*nombres):
        return en_escritorio_aparte(NODO, ['tecla'] + list(nombres), BASE)

    control = tecla('shift')
    check('K1 control: shift en el escritorio aparte se BLOQUEA (NODE-011)',
          codigo(control) == 'NODE-011', control[-300:])
    if codigo(control) == 'NODE-044':
        # el escritorio aparte no aisla: mandar letras tecleaba en el de verdad
        print('NOTA: el escritorio aparte dejo pasar la tecla; K2-K4 no se miden.')
    else:
        for combo in (('ctrl', 'k'), ('ctrl', 's'), ('ctrl', 'a')):
            s = tecla(*combo)
            check('K2 %s: la letra se resuelve (NODE-011, no "Unknown key")' % '+'.join(combo),
                  codigo(s) == 'NODE-011', s[-300:])
        for combo in (('f4',), ('alt', 'tab')):
            s = tecla(*combo)
            check('K3 %s: sigue resolviendose' % '+'.join(combo), codigo(s) == 'NODE-011', s[-300:])
        s = tecla('xx')
        check('K4 un nombre que no existe: NODE-010', codigo(s) == 'NODE-010', s[-300:])
finally:
    mc.borra(BASE)

mc.fin('teclas del nodo')
