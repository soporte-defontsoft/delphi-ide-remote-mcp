# -*- coding: utf-8 -*-
"""V99 de la 1.23.1: el recorte de lo que ve el agente no es del proceso interno.

V80 (1.23.1) puso UNA cola de salida (400 lineas, 64K) a lo que remote-run
devuelve al agente, y la puso DENTRO de Lsp.RemoteRun.RemoteRun. Pero
delphi_desktop llama a ese mismo RemoteRun para correr el nodo y lee de su
salida el PROTOCOLO (CAPTURE=, la lista de ventanas, WINERR=): con un escritorio
de muchas ventanas la linea CAPTURE= - que va DELANTE de la lista - se caia de
la cola, y status decia reachable=false con la captura hecha. Hallado por la
pasada del paisaje del diff (27-oct). Ahora el nodo recibe su salida entera y
la cola es solo de lo que se le da al agente.

Sin PAServer: el paclient falso de test_remoterun (tests/paclient_stub.py) corre
el lanzador real sobre un "nodo" de mentira: un programa de consola que esta
bateria compila y que imprime el protocolo del nodo - CAPTURE= y 450 ventanas -
diga lo que diga su linea de ordenes (el nodo de verdad recibe su clave delante).

  D1 status con CAPTURE= y 450 ventanas detras: reachable=true (ROJO contra
     el build con la cola dentro de RemoteRun: la captura se caia)
  C1 control: remote-run del MISMO programa al agente sigue recortado
     (outputTruncated, la cola de V80)

Uso:  python tests/test_desktop_salida_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import json, os, shutil
import mcp_cliente as mc
from mcp_cliente import check

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('desktop_salida_1231')
SERVERDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SERVERDIR, 'node'))
EXE = mc.copia_exe(SERVERDIR)
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SERVERDIR, 'node', f))
RUNJOB_EXE = os.path.join(SERVERDIR, 'node', 'McpRunJob.exe')
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
PROFILE = 'perfil'
NOMBRE = 'Ventanas'
PRJDIR = os.path.join(BASE, 'proj')
DPROJ = os.path.join(PRJDIR, NOMBRE + '.dproj')
VENTANAS = 450

STUB = os.path.join(BASE, 'paclient.cmd')
open(STUB, 'w').write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))
env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['MCP_STUB_RUNJOB_EXE'] = RUNJOB_EXE
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = DPROJ
_ad, _host = mc.appdata_perfil(BASE, PROFILE, '127.0.0.1')
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host
srv = mc.Stdio(EXE, env, nombre='desktop-salida', t=300)
call = srv.call

try:
    # el "nodo": imprime el protocolo y sale, sin mirar sus argumentos
    r = call('delphi_create', {'kind': 'project-console', 'name': NOMBRE, 'dir': PRJDIR}, t=120)
    check('preparacion: el proyecto del nodo de mentira', not mc.fallo(r), r[:200])
    dpr = os.path.join(PRJDIR, NOMBRE + '.dpr')
    open(dpr, 'w', encoding='utf-8', newline='\r\n').write(
        'program %s;\n\n{$APPTYPE CONSOLE}\n\nvar\n  I: Integer;\nbegin\n'
        "  Writeln('CAPTURE=/tmp/captura.png');\n"
        "  Writeln('  %d visible windows:');\n"
        '  for I := 1 to %d do\n'
        "    Writeln('  WINDOW 0 0 10 10 Ventana ', I);\n"
        'end.\n' % (NOMBRE, VENTANAS, VENTANAS))
    b = mc.como_json(call('delphi_build', {'project': DPROJ, 'platform': 'Win64'}, t=600)) or {}
    salida = b.get('output', '')
    check('preparacion: el nodo de mentira compila', b.get('success') is True and os.path.isfile(mc.real(salida)),
          (b.get('success'), salida, b.get('errors')))
    DEPLOY = os.path.join(SCRATCH, NOMBRE)
    os.makedirs(DEPLOY)
    shutil.copy(mc.real(salida), os.path.join(DEPLOY, NOMBRE + '.exe'))

    r = call('delphi_desktop', {'command': 'status', 'profile': PROFILE, 'project': DPROJ}, t=180)
    j = mc.como_json(r) or {}
    check('D1 status con CAPTURE= y %d ventanas detras: reachable=true (ROJO contra la cola dentro de RemoteRun)'
          % VENTANAS, j.get('reachable') is True, r[:400])

    r = call('delphi_paserver', {'command': 'remote-run', 'name': PROFILE, 'project': DPROJ,
                                 'timeoutms': 30000}, t=180)
    j = mc.como_json(r) or {}
    check('C1 control: remote-run del mismo programa al agente sigue recortado (outputTruncated, V80)',
          j.get('outputTruncated') is True and 'CAPTURE=' not in (j.get('output') or ''), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('desktop: el nodo lee su salida entera 1.23.1 (V99)')
