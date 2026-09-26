# -*- coding: utf-8 -*-
"""E2E battery for v0.90.0-beta - per-workspace configs.

Contrato v0.98 (decision David 19-sep-2026, rematando la del 11-sep): NADA
es global. Cada [Workspace.<name>] tiene EXACTAMENTE lo que declara: un
interruptor ausente esta APAGADO, una lista ausente esta VACIA. No existe
la seccion [Security] ni ninguna herencia.

  C1  delphi_run ya no existe (retirada 2026-09-23): tool desconocida para
      cualquier token; la unica via de ejecucion es remote-run
  C3  AllowTests=0 declarado: rechazado alli. Y quien no declara nada de
      tests tampoco los tiene (C3b); quien declara AllowTests=1 si (C3c)
  C4  AgentConfinement=1 solo en su workspace: su agente queda confinado a
      <root>\\<name>\\, y quien no lo declara campa libre

Usage:  python tests/test_round25.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round25')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Workspace]', 'Roots=%s' % JAIL, '',
    '[Workspace.Operador]',             # no declara capacidades: no las tiene
    'Token=op-25',
    'Roots=%s' % JAIL, '',
    '[Workspace.Runner]',               # may test, confined
    'Token=runner-25',
    'Roots=%s' % JAIL,
    'AllowTests=1',
    'AgentConfinement=1', '',
    '[Workspace.Notest]',               # only override: tests OFF here
    'Token=notest-25',
    'Roots=%s' % JAIL,
    'AllowTests=0', '',
]))

PORT = mc.puerto_libre()
# loopback: su settings.ini no declara [Server] BindIP
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))


def session(tok, name):
    return mc.Http(PORT, tok).session(name)


def call(tok, sid, tool, args):
    # el token y la sesion que se le pasan, solo para esta llamada
    return mc.Http(PORT, tok).call(tool, args, sid=sid)


try:
    s_run = session('runner-25', 'agente')
    s_op = session('op-25', 'operador')
    # inside the agent's own subfolder, so the workspace's confinement
    # (also under test in C4) never preempts the run/tests checks
    ghost = os.path.join(JAIL, 'agente', 'no-existe.exe')

    # C1: delphi_run ya no existe para NINGUN token (retirada 2026-09-23: la
    # unica via de ejecucion es remote-run): tool desconocida
    r = call('runner-25', s_run, 'delphi_run', {'path': ghost})
    check('C1 delphi_run retirada: tool desconocida para todo token',
          'Tool not found' in r, r[:200])


    # C3: declarar AllowTests=0 y no declararlo dan lo mismo (apagado), y
    # quien lo declara a 1 lo tiene, sin heredar nada de nadie
    s_nt = session('notest-25', 'probador')
    r = call('notest-25', s_nt, 'delphi_test',
             {'command': 'run', 'project': os.path.join(JAIL, 'X.dproj')})
    check('C3 AllowTests=0 declarado: tests rechazados',
          'AllowTests' in r or 'deshabilitad' in r, r[:200])
    r = call('op-25', s_op, 'delphi_test',
             {'command': 'run', 'project': os.path.join(JAIL, 'X.dproj')})
    check('C3b Operador no declara tests: rechazados tambien (nada se hereda)',
          'AllowTests' in r or 'deshabilitad' in r, r[:200])
    # El proyecto va en la carpeta DEL AGENTE: el Runner esta confinado (C4) y
    # con X.dproj en la raiz lo paraba el CONFINAMIENTO - el check pasaba
    # porque ese rechazo no nombra AllowTests, no porque el gate de tests
    # dejara pasar. Pasar el gate = llegar a mirar el proyecto (no existe).
    r = call('runner-25', s_run, 'delphi_test',
             {'command': 'run', 'project': os.path.join(JAIL, 'agente', 'X.dproj')})
    check('C3c Runner declara AllowTests=1: los tests pasan el gate',
          'AllowTests' not in r and 'deshabilitad' not in r and 'confinado' not in r
          and 'no existe' in r and 'X.dproj' in r, r[:200])

    # C4: confinement only inside the workspace
    r = call('runner-25', s_run, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'suelto.txt'), 'create': True, 'content': 'x'})
    check('C4 confinamiento del workspace: su agente NO escribe suelto en la raiz',
          'RECHAZADO' in r and 'confinado' in r and
          not os.path.exists(os.path.join(JAIL, 'suelto.txt')), r[:200])
    r = call('runner-25', s_run, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'agente', 'mio.txt'), 'create': True, 'content': 'x'})
    check('C4b ...pero si en SU subcarpeta',
          os.path.exists(os.path.join(JAIL, 'agente', 'mio.txt')), r[:200])
    r = call('op-25', s_op, 'delphi_textedit',
             {'path': os.path.join(JAIL, 'libre.txt'), 'create': True, 'content': 'x'})
    check('C4c Operador no declara confinamiento: campa libre',
          os.path.exists(os.path.join(JAIL, 'libre.txt')), r[:200])
finally:
    proc.kill()

mc.fin('round-25 battery')
