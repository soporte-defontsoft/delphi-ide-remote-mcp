# -*- coding: utf-8 -*-
"""1.29 (EH3 del revisor del paisaje): references y rename saltaban, por su NOMBRE, las carpetas que se llaman
como un artefacto (win32, win64, debug, release, dcu) tambien cuando tenian una unidad que el proyecto lista en
su .dpr: el uso de alli no salia (medido el 7-nov-2026: 2 ficheros escaneados) y un rename lo dejaba con el
nombre viejo. Lo que el proyecto lista es suyo, este donde este.

  A1 references desde la declaracion: el uso en debug\\UEnDebug.pas (unidad del .dpr) sale confirmado
  A2 control: una unidad en debug\\ que el proyecto NO lista sigue sin escanearse (la lista de artefactos vale)

Uso:  python tests/test_references_artefacto_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('references_artefacto_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
P = os.path.join(BASE, 'jail', 'MideEH3')
os.makedirs(os.path.join(P, 'debug'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': os.path.join(BASE, 'jail')}), nombre='eh3', t=180)
try:
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'MideEH3', 'dir': P})
    DPROJ = os.path.join(P, 'MideEH3.dproj')
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UFuente', 'project': DPROJ})
    srv.call('delphi_create', {'kind': 'unit', 'name': 'UEnDebug', 'dir': 'debug', 'project': DPROJ})
    FUENTE = os.path.join(P, 'UFuente.pas')
    EN_DEBUG = os.path.join(P, 'debug', 'UEnDebug.pas')
    srv.call('delphi_edit', {'path': FUENTE, 'old': 'interface', 'new': 'interface\r\n\r\nfunction MideSimbolo: Integer;'})
    srv.call('delphi_edit', {'path': FUENTE, 'old': 'implementation',
                             'new': 'implementation\r\n\r\nfunction MideSimbolo: Integer;\r\nbegin\r\n  Result := 1;\r\nend;'})
    srv.call('delphi_edit', {'path': EN_DEBUG, 'old': 'implementation',
                             'new': 'implementation\r\n\r\nuses\r\n  UFuente;\r\n\r\nfunction UsaElSimbolo: Integer;\r\n'
                                    'begin\r\n  Result := MideSimbolo + 1;\r\nend;'})
    # una unidad en debug\ que el proyecto NO lista: la lista de artefactos sigue valiendo para ella
    open(os.path.join(P, 'debug', 'Suelta.pas'), 'w', encoding='utf-8').write(
        'unit Suelta;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nuses UFuente;\r\n\r\n'
        'procedure X;\r\nbegin\r\n  MideSimbolo;\r\nend;\r\n\r\nend.\r\n')
    r = srv.call('delphi_references', {'path': FUENTE, 'line': 4, 'character': 10}, t=150)
    j = mc.como_json(r)
    ficheros = [fi.get('name') for d in j.get('confirmed', []) + j.get('unverified', []) for fi in d.get('files', [])]
    check('A1 el uso en debug\\UEnDebug.pas (unidad del .dpr) sale. ROJO contra 958be0fe: no se escaneaba',
          'UEnDebug.pas' in ficheros, (ficheros, r[:300]))
    check('A2 control: debug\\Suelta.pas, que el proyecto no lista, sigue fuera', 'Suelta.pas' not in ficheros, ficheros)
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('references en una carpeta con nombre de artefacto (1.29)')
