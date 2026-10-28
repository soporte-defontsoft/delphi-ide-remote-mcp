# -*- coding: utf-8 -*-
r"""Una lista del operador se lee con UN lector (V128 de la 1.23.1).

Las listas del settings.ini y del entorno se troceaban de cinco formas: GitRemotes y RemoteHosts
por coma y punto y coma, recortadas al usarlas; AdbAllowedDevices y RemoteRunProjects solo por
punto y coma; SharedFolders y el Only= de [Tools] por las dos, SIN recortar. "a, b" dejaba la
entrada " b", que no casaba nunca: lo que el operador declaro se negaba, en silencio. Ahora
Lsp.Settings.EntradasDeLista (la coma solo en las listas de NOMBRES: una ruta puede llevarla).

  O1 DELPHI_MCP_TOOLS_ONLY=delphi_read, delphi_list: se anuncian las dos (ROJA contra 281f9ba: solo
     delphi_read)
  O2 [Tools] Only= del settings.ini, igual (ROJA)
  O3 DELPHI_MCP_ADB_DEVICES=192.0.2.1, 192.0.2.2: el segundo no es ADB-005 (ROJA); uno que no
     esta, si (control: la lista sigue cerrada)
  O4 AdbAllowedDevices= de un [Workspace.*], por HTTP con su token: igual (ROJA)

Las direcciones son de TEST-NET (192.0.2.x): no hay nada detras.

Uso:  python tests/test_listas_operador_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('listas-operador')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
TOKEN = 'bateria-listas-operador'
LISTA = '192.0.2.1, 192.0.2.2'


def stdio(n, entorno, ini=''):
    d = os.path.join(BASE, 's%d' % n)
    exe = mc.copia_exe(d)
    if ini:
        with open(os.path.join(d, 'settings.ini'), 'w') as f:
            f.write(ini)
    return mc.Stdio(exe, mc.entorno(dict({'DELPHI_MCP_ROOTS': JAIL}, **entorno)), nombre='listas-operador')


def anunciadas(srv):
    m = srv.request('tools/list', {}, 30)
    return {t['name'] for t in ((m or {}).get('result') or {}).get('tools', [])}


def adb_negado(call, device):
    return mc.es(call('delphi_adb', {'command': 'devices', 'device': device}), 'SR_ADB_ALLOWLIST_FMT')


srv = stdio(1, {'DELPHI_MCP_TOOLS_ONLY': 'delphi_read, delphi_list'})
try:
    n = anunciadas(srv)
finally:
    srv.cierra()
check('O1 DELPHI_MCP_TOOLS_ONLY con coma y blanco: se anuncian las dos',
      {'delphi_read', 'delphi_list'} <= n and 'delphi_edit' not in n, sorted(n))

srv = stdio(2, {}, '[Tools]\nOnly=delphi_read, delphi_list\n')
try:
    n = anunciadas(srv)
finally:
    srv.cierra()
check('O2 [Tools] Only= del settings.ini con coma y blanco: se anuncian las dos',
      {'delphi_read', 'delphi_list'} <= n and 'delphi_edit' not in n, sorted(n))

srv = stdio(3, {'DELPHI_MCP_ADB_DEVICES': LISTA})
try:
    check('O3 DELPHI_MCP_ADB_DEVICES con coma y blanco: el segundo esta en la lista',
          not adb_negado(srv.call, '192.0.2.2'))
    check('O3 ...y uno que no esta sigue negado (ADB-005)', adb_negado(srv.call, '192.0.2.3'))
finally:
    srv.cierra()

d = os.path.join(BASE, 'h4')
exe = mc.copia_exe(d)
with open(os.path.join(d, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\nAdbAllowedDevices=%s\n' % (TOKEN, JAIL, LISTA))
puerto = mc.puerto_libre()
proc = mc.lanza_http(exe, puerto, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
try:
    c = mc.Http(puerto, TOKEN)
    c.session('listas-operador')
    check('O4 AdbAllowedDevices= de un workspace con coma y blanco: el segundo esta en la lista',
          not adb_negado(c.call, '192.0.2.2'))
    check('O4 ...y uno que no esta sigue negado (ADB-005)', adb_negado(c.call, '192.0.2.3'))
finally:
    proc.kill()
mc.borra(BASE)
mc.fin('listas del operador 1.23.1 (V128)')
