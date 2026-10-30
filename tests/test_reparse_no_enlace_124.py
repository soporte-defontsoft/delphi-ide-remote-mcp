# -*- coding: utf-8 -*-
"""V126 de la 1.24: "es un enlace" era CUALQUIER punto de reparse. Un marcador de
OneDrive o de dedup no apunta a otro nombre: es el contenido del propio fichero, y
un proyecto en un Documentos de OneDrive era todo enlaces (no se listaba, no se
recorria, no se purgaba). Aqui no hay OneDrive; el mismo caso, sin escribir nada,
son los alias de WindowsApps (etiqueta 8000001B, atributo 00000420):

  R1 control: la maquina tiene un alias y es un punto de reparse sin el bit de enlace
  R2 delphi_list lo enumera (ROJO en la 1.23.1: se saltaba como enlace)
  R3 una union de verdad sigue sin recorrerse: lo que hay detras no se lista

Solo lee: la raiz de R2 es de la maquina y no se escribe en ella.

Uso:  python tests/test_reparse_no_enlace_124.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes
import glob
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

FILE_ATTRIBUTE_REPARSE_POINT = 0x400
ALIAS = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Microsoft', 'WindowsApps')
ctypes.windll.kernel32.GetFileAttributesW.argtypes = [ctypes.c_wchar_p]
ctypes.windll.kernel32.GetFileAttributesW.restype = ctypes.c_uint32


def es_reparse(ruta):
    return bool(ctypes.windll.kernel32.GetFileAttributesW(ruta) & FILE_ATTRIBUTE_REPARSE_POINT)


alias = [f for f in glob.glob(os.path.join(ALIAS, '*.exe')) if es_reparse(f)]
if not alias:
    mc.fin('un punto de reparse no es un enlace (V126)', sin_checks='esta maquina no tiene alias en WindowsApps')

BASE = mc.carpeta('reparse_no_enlace_124')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
os.makedirs(FUERA)
open(os.path.join(JAIL, 'Normal.pas'), 'wb').write(b'unit Normal;\r\ninterface\r\nimplementation\r\nend.\r\n')
open(os.path.join(FUERA, 'Oculto.pas'), 'wb').write(b'unit Oculto;\r\ninterface\r\nimplementation\r\nend.\r\n')
UNION = mc.junction(os.path.join(JAIL, 'union'), FUERA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL + ';' + ALIAS}), nombre='reparse-no-enlace', t=120)
try:
    check('R1 control: la maquina tiene un alias y es un punto de reparse', es_reparse(alias[0]), alias[0])
    r = srv.call('delphi_list', {'root': ALIAS, 'pattern': '*.exe'})
    try:
        nombres = [f['name'] for d in json.loads(r).get('folders', []) for f in d.get('files', [])]
    except ValueError:
        nombres = []
    check('R2 delphi_list enumera el alias: no es un enlace',
          os.path.basename(alias[0]) in nombres, (os.path.basename(alias[0]), r[:300]))
    r = srv.call('delphi_list', {'root': JAIL, 'pattern': '*.pas'})
    check('R3 una union sigue sin recorrerse: Normal.pas si, lo de detras no',
          UNION and 'Normal.pas' in r and 'Oculto.pas' not in r, r[:300])
finally:
    srv.cierra()
    os.rmdir(os.path.join(JAIL, 'union'))  # quita la union, nunca lo que hay detras

mc.borra(BASE)
mc.fin('un punto de reparse no es un enlace (V126)')
