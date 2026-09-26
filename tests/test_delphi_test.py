"""E2E battery for v0.59.0-beta - delphi_test: the difference between "it
compiles" and "it works".

Two independent reviews (mine and an agent's, 2026-08-25) named the same gap
as the biggest one left: an agent could write code and never learn whether it
does the right thing. This battery builds a green suite and a red one and
checks the server tells them apart, with numbers.

Usage:  python tests/test_delphi_test.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('dtest')
EXE = mc.copia_exe(BASE)

def spawn(extra_env=None):
    # plazo de 600 s: compila y ejecuta suites
    return mc.Stdio(EXE, mc.entorno(dict({'DELPHI_MCP_ROOTS': BASE}, **(extra_env or {}))),
                    nombre='dt', t=600)
def J(t):
    try: return json.loads(t)
    except Exception: return {}

A = spawn()                                    # sin permiso de ejecutar
B = spawn({'DELPHI_MCP_ALLOW_TESTS': '1'})     # con el interruptor

# ---- fixtures: una suite verde y una roja, y un proyecto que NO es test ----
r = A.call('delphi_create', {'kind': 'project-console', 'name': 'VerdeTest', 'dir': os.path.join(BASE, 'VerdeTest')})
assert 'CREADO' in r, r
VERDE = os.path.join(BASE, 'VerdeTest', 'VerdeTest.dpr')
open(VERDE, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""program VerdeTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils;

procedure Comprobar(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName);
    ExitCode := 1;
  end;
end;

begin
  Comprobar('suma', 2 + 2 = 4);
  Comprobar('cadena', UpperCase('ab') = 'AB');
  Comprobar('resta', 5 - 3 = 2);
end.
""")
r = A.call('delphi_create', {'kind': 'project-console', 'name': 'RojoTest', 'dir': os.path.join(BASE, 'RojoTest')})
ROJO = os.path.join(BASE, 'RojoTest', 'RojoTest.dpr')
open(ROJO, 'w', encoding='utf-8-sig', newline='\r\n').write(
"""program RojoTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils;

procedure Comprobar(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName);
    ExitCode := 1;
  end;
end;

begin
  Comprobar('esta bien', True);
  Comprobar('esta MAL a proposito', 1 = 2);
end.
""")
A.call('delphi_create', {'kind': 'project-console', 'name': 'NormalApp', 'dir': os.path.join(BASE, 'NormalApp')})

# ---- discover ----
j = J(A.call('delphi_test', {'command': 'discover', 'path': BASE}))
names = [os.path.basename(p.get('dpr', '')) for p in j.get('projects', [])]
check('discover encuentra las dos suites', 'VerdeTest.dpr' in names and 'RojoTest.dpr' in names, str(j)[:300])
check('discover NO cuenta un proyecto normal', 'NormalApp.dpr' not in names, names)
check('discover dice el framework y el porque', all(p.get('framework') and p.get('why') for p in j.get('projects', [])), str(j)[:250])
j = J(A.call('delphi_test', {'command': 'discover', 'path': os.path.join(BASE, 'NormalApp')}))
check('carpeta sin tests: total 0 con explicacion', j.get('total') == 0 and 'test' in (j.get('note') or ''), str(j)[:250])

# ---- el interruptor ----
r = A.call('delphi_test', {'command': 'run', 'project': VERDE})
check('sin AllowTests: run RECHAZADO nombrando el interruptor', 'RECHAZADO' in r and 'AllowTests' in r, r[:250])
r = A.call('delphi_test', {'command': 'discover', 'path': BASE})
check('sin AllowTests: discover SI funciona', r.startswith('{'), r[:150])

# ---- run verde ----
j = J(B.call('delphi_test', {'command': 'run', 'project': VERDE}, t=900))
check('suite verde: result=pass', j.get('result') == 'pass', str(j)[:400])
check('suite verde: 3 de 3', j.get('total') == 3 and j.get('passed') == 3 and j.get('failed') == 0, str(j)[:300])
check('suite verde: veredicto por numeros', j.get('verdictFrom') == 'counts', str(j)[:200])
check('suite verde: dice el binario y la duracion', bool(j.get('binary')) and j.get('durationMs') is not None, str(j)[:250])
check('suite verde: corrio en sandbox', j.get('sandboxed') is True, str(j)[:200])

# ---- run rojo ----
j = J(B.call('delphi_test', {'command': 'run', 'project': ROJO}, t=900))
check('suite roja: result=fail', j.get('result') == 'fail', str(j)[:400])
check('suite roja: 1 de 2 y el fallo NOMBRADO', j.get('failed') == 1 and any('MAL' in f for f in j.get('failures', [])), str(j)[:350])
check('suite roja: exitCode distinto de 0', j.get('exitCode') not in (0, None), str(j)[:200])

# ---- contratos ----
r = B.call('delphi_test', {'command': 'run', 'project': os.path.join(BASE, 'NormalApp', 'NormalApp.dpr')})
check('un proyecto que no es test: rechazado y explicado', 'RECHAZADO' in r and 'DUnitX' in r, r[:300])
r = B.call('delphi_test', {'command': 'run'})
check('run sin project rechazado con pista', 'RECHAZADO' in r and 'discover' in r, r[:200])
r = B.call('delphi_test', {'command': 'volar', 'path': BASE})
check('comando invalido', 'discover' in r and 'run' in r, r[:150])
r = B.call('delphi_test', {'command': 'run', 'project': 'C:\\Windows\\x.dproj'})
check('fuera de la jaula rechazado', 'RECHAZADO' in r, r[:200])

# una suite que NO compila: se dice, no se ejecuta nada viejo
# ojo: Delphi IGNORA lo que va despues de "end." - hay que romperlo DENTRO
_txt = open(ROJO, encoding='utf-8-sig').read().replace(
    "Comprobar('esta bien', True);", "esto no compila ni de lejos;")
open(ROJO, 'w', encoding='utf-8-sig', newline='').write(_txt)
j = J(B.call('delphi_test', {'command': 'run', 'project': ROJO}, t=900))
check('suite que no compila: result=build-failed con los errores',
      j.get('result') == 'build-failed' and bool(j.get('build')), str(j)[:300])

A.mata(); B.mata()
mc.fin('delphi_test battery')
