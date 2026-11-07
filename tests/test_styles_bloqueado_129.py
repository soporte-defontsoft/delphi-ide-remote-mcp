# -*- coding: utf-8 -*-
"""1.29 (I14-b de la depuracion de la 1.23): delphi_styles build armaba su respuesta y solo al final le daba a
Ret la lista de convertidos (Arr) y cada entrada (E): si leer, escribir o colocar un estilo lanzaba antes, esa
parte se perdia. Ahora cada pieza tiene su propietario desde que nace. La fuga no se ve desde fuera; lo que se
mide aqui es el CAMINO de la excepcion, que no recorria ninguna bateria: un .style que otro proceso tiene abierto
en exclusiva.

  S1 build con un .style bloqueado en exclusiva: contesta un error (no se cuelga ni cae)
  S2 ...y el servidor sigue contestando
  S3 control: liberado, el mismo build convierte

Uso:  python tests/test_styles_bloqueado_129.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('styles_bloqueado_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src, con_conversor=True)
JAIL = os.path.join(BASE, 'jail')
STY = os.path.join(JAIL, 'Estilos')
os.makedirs(STY)
open(os.path.join(STY, 'Uno.style'), 'w', encoding='utf-8', newline='\n').write(
    "object TStyleContainer\n  object TLayout\n    StyleName = 'uno'\n    Visible = False\n  end\nend\n")
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='styles-bloq', t=180)
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.CreateFileW.restype = ctypes.c_void_p
k32.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32,
                            ctypes.c_uint32, ctypes.c_void_p]
k32.CloseHandle.argtypes = [ctypes.c_void_p]
try:
    # GENERIC_READ, sin compartir nada (share 0), OPEN_EXISTING
    h = k32.CreateFileW(os.path.join(STY, 'Uno.style'), 0x80000000, 0, None, 3, 0x80, None)
    check('preparacion: el .style queda abierto en exclusiva', h not in (None, ctypes.c_void_p(-1).value),
          ctypes.get_last_error())
    try:
        r = srv.call('delphi_styles', {'path': STY, 'command': 'build'}, 120)
        check('S1 build con el .style bloqueado: un error, no un cuelgue', mc.fallo(r) or '"ok":false' in r, r[:300])
        check('S2 ...y el servidor sigue contestando', not mc.fallo(srv.call('delphi_list', {'root': JAIL})))
    finally:
        k32.CloseHandle(h)
    r = srv.call('delphi_styles', {'path': STY, 'command': 'build'}, 120)
    check('S3 control: liberado, el mismo build convierte', '"ok":true' in r.replace(' ', '')
          and os.path.isfile(os.path.join(STY, 'Uno.bin.style')), r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('styles build con un estilo bloqueado (1.29)')
