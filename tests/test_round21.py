"""E2E battery for v0.84.0-beta - hermes' P2.9: startup/repeat work.

Two internal costs removed, with the ONE risk each removal introduces pinned
by a check:

  - The low-integrity labeling of a run's workdir used to re-walk and relabel
    the whole tree on EVERY run (delphi_run then, delphi_test until 1.10).
    Since 1.11.0 there is no labeling of the agent's folder at all: the test
    runs in a container of its own on a COPY of it (Lsp.Sandbox). What this
    battery measured stays measured: a MEDIUM file created BETWEEN runs by
    the server/agent travels with the copy and run #2 overwrites it there.
  - The designer fact tables (~14k facts, 14 dictionaries) used to be built
    in initialization even when no designer tool was ever called. Now lazy on
    the first designer call. The risk: the first call after startup breaking.
    Covered by calling designer FIRST thing on a fresh server.

  Z1  fresh server: the FIRST call is delphi_designer -> lazy tables work
  Z2  run #1: sandboxed, writes its own folder (its copy)
  Z3  a NEW medium-integrity file created BETWEEN runs is still writable by
      run #2 (it travels with the copy, which is the container's)

Usage:  python tests/test_round21.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('round21')
EXE = mc.copia_exe(BASE)

# a text .dfm for the lazy-designer check
open(os.path.join(BASE, 'Main.dfm'), 'w').write(
    "object Form1: TForm1\r\n  Left = 0\r\n  Top = 0\r\n"
    "  Caption = 'Hola'\r\n  ClientHeight = 300\r\n  ClientWidth = 400\r\n"
    "  object Boton1: TButton\r\n    Left = 10\r\n    Top = 10\r\n"
    "    Width = 75\r\n    Height = 25\r\n    Caption = 'Pulsa'\r\n  end\r\nend\r\n")

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_ALLOW_TESTS': '1'}),
               nombre='round21', t=600)
call = srv.call

# Z1: the VERY FIRST tool call is a designer one - lazy tables must build now
r = call('delphi_designer', {'command': 'tree', 'path': os.path.join(BASE, 'Main.dfm')})
check('Z1 primera llamada del proceso = designer: tablas lazy funcionan',
      'TButton' in r and 'Boton1' in r, r[:200])
# El veredicto CONCRETO del lint: un form correcto sale LIMPIO, y solo sale
# limpio si las tablas reconocen TForm1/TButton y sus propiedades. Antes se
# miraba que no empezara por 'ERR': un RECHAZADO o un "error: ..." pasaban.
r = call('delphi_designer', {'command': 'lint', 'path': os.path.join(BASE, 'Main.dfm')})
check('Z1b lint del designer tambien (segunda entrada a las tablas)',
      mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT') and 'Main.dfm' in r, r[:160])

# Z2/Z3: the label cache vs a medium file created BETWEEN runs
_q = chr(39)
call('delphi_create', {"kind": "project-console", "dir": os.path.join(BASE, 'SbxTest'), "name": "SbxTest"})
_body = ['program SbxTest;', '{$APPTYPE CONSOLE}', 'uses System.SysUtils, System.IOUtils;', 'begin',
         '  try TFile.WriteAllText(' + _q + 'entre.txt' + _q + ', ' + _q + 'y' + _q + '); Writeln('
         + _q + 'LOCAL-OK' + _q + '); except Writeln(' + _q + 'local-blocked' + _q + '); end;', 'end.']
open(os.path.join(BASE, 'SbxTest', 'SbxTest.dpr'), 'w', encoding='utf-8-sig', newline='').write('\r\n'.join(_body) + '\r\n')
out = call('delphi_build', {"project": os.path.join(BASE, 'SbxTest', 'SbxTest.dproj'),
                            "platform": "Win64", "config": "Debug", "target": "Build"})
try:
    sbok = json.loads(out)['success']
except Exception:
    sbok = False
check('Z2 proyecto de prueba compila', sbok, out[:150])
if sbok:
    rundir = os.path.join(BASE, 'SbxTest', 'Win64', 'Debug')
    # delphi_run was retired on 2026-09-23: the same sandbox is measured
    # through delphi_test, the one thing that still executes here.
    def _run():
        r = call('delphi_test', {"command": "run", "project": os.path.join(BASE, 'SbxTest', 'SbxTest.dproj'),
                                 "platform": "Win64", "nobuild": True, "timeoutms": 10000}, 60)
        try:
            j = json.loads(r)
        except Exception:
            j = {}
        return j.get('outputTail', ''), j.get('sandboxed') is True, r
    tail, sbx, raw = _run()
    check('Z2 run #1 sandboxed escribe en su carpeta', 'LOCAL-OK' in tail and sbx, raw[:200])
    # BETWEEN runs: this test process (MEDIUM integrity) creates the file the
    # program will overwrite. It travels with the copy into the container's
    # folder, where it is the container's. Measure it.
    open(os.path.join(rundir, 'entre.txt'), 'w').write('medium-file-created-between-runs')
    tail, sbx, raw = _run()
    check('Z3 fichero MEDIUM creado ENTRE runs: run #2 lo sobrescribe en su copia, '
          'y el original del agente queda como estaba',
          'LOCAL-OK' in tail and sbx and
          open(os.path.join(rundir, 'entre.txt')).read() == 'medium-file-created-between-runs', raw[:220])

srv.mata()
mc.fin('round-21 battery')
