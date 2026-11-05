# -*- coding: utf-8 -*-
"""Quitar una carpeta VACIA aguanta a un lector de un instante (C30 de la 1.28).

LA politica de reintentos (Lsp.Guard.ConReintentos: 5, 32 y 33, cinco intentos de 100 ms) la tenian el
renombre y QuitaCarpetasCreadas; quitar una carpeta vacia estaba a pelo en seis sitios (el borrado de una
carpeta vacia de delphi_delete, la mezcla de un move, el borrador de arboles, la papelera que se vacia, la
carpeta que paclient deja en la de SDKs). Ahora es UNA (QuitaCarpetaConReintentos).

  Q1 delphi_delete de una carpeta vacia que otro proceso tiene abierta sin compartir el borrado y suelta
     a los 250 ms: se quita y lo dice (ROJA contra la 1.27.1: "no se deja quitar" y se queda)

Uso:  python tests/test_quita_carpeta_128.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys
import threading
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('quita_carpeta_128')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='quita-carpeta', t=120)
call = srv.call

K32 = ctypes.WinDLL('kernel32', use_last_error=True)
K32.CreateFileW.restype = wt.HANDLE
K32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p, wt.DWORD, wt.DWORD, wt.HANDLE]
K32.CloseHandle.argtypes = [wt.HANDLE]
GENERIC_READ, FILE_SHARE_READ, FILE_SHARE_WRITE = 0x80000000, 1, 2
OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS = 3, 0x02000000
INVALIDO = wt.HANDLE(-1).value

try:
    call('delphi_workspace', {})  # el servidor despierto: el borrado llega en milisegundos
    d = os.path.join(JAIL, 'Vacia')
    os.makedirs(d)
    # el lector de un instante: la carpeta abierta SIN compartir el borrado, soltada a los 250 ms
    h = K32.CreateFileW(d, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, None, OPEN_EXISTING,
                        FILE_FLAG_BACKUP_SEMANTICS, None)
    check('preparacion: la carpeta se abre sin compartir el borrado', h and h != INVALIDO, ctypes.get_last_error())
    suelta = threading.Timer(0.25, lambda: K32.CloseHandle(h))
    suelta.start()
    r = call('delphi_delete', {'path': d})
    suelta.join()
    check('Q1 delphi_delete de una carpeta vacia retenida un instante: se quita y lo dice',
          mc.es(r, 'SN_FILE_DELETE_EMPTY_OK_FMT') and not os.path.exists(d), r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('quitar una carpeta vacia aguanta a un lector de un instante 1.28 (C30)')
