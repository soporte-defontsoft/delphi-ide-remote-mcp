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
assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r
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
r = A.call('delphi_create', {'kind': 'project-console', 'name': 'NormalApp', 'dir': os.path.join(BASE, 'NormalApp')})
check('NormalApp creado (sin el, "no cuenta un proyecto normal" no mide nada)',
      os.path.isfile(os.path.join(BASE, 'NormalApp', 'NormalApp.dpr')), r[:200])
# ...y con DUnitX nombrado en un COMENTARIO: no lo hace una suite (1.10.0, el
# lexico de la casa; se buscaba 'DUnitX.' en el texto entero)
_n = os.path.join(BASE, 'NormalApp', 'NormalApp.dpr')
_b = open(_n, 'rb').read()
open(_n, 'wb').write(_b.replace(b'{$APPTYPE CONSOLE}',
                                b'{$APPTYPE CONSOLE}\r\n// la version de antes usaba DUnitX.TestFramework', 1))
check('NormalApp lleva DUnitX en un comentario', b'usaba DUnitX.TestFramework' in open(_n, 'rb').read(), '')

# una suite DUnitX con un test que LANZA (1.10.0): para DUnitX un error no es
# un fallo ('Tests Errored', bloque 'Tests With Errors'), y delphi_test solo
# leia 'Tests Failed': la suite salia 'pass' con el ejecutable acabando en 1
# (medido en la mutacion de la 1.10.0: 'pass 16/17' sin fallos)
r = A.call('delphi_create', {'kind': 'project-test', 'name': 'LanzaTest', 'dir': os.path.join(BASE, 'LanzaTest')})
check('LanzaTest creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
LANZA = os.path.join(BASE, 'LanzaTest', 'LanzaTest.dproj')
open(os.path.join(BASE, 'LanzaTest', 'ULanzaTest.pas'), 'w', encoding='utf-8-sig', newline='\r\n').write(
"""unit ULanzaTest;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLanzaTest = class
  public
    [Test]
    procedure Bien;
    [Test]
    procedure Lanza;
  end;

implementation

uses
  System.SysUtils;

procedure TLanzaTest.Bien;
begin
  Assert.AreEqual(4, 2 + 2);
end;

procedure TLanzaTest.Lanza;
begin
  raise Exception.Create('lanza a proposito');
end;

initialization
  TDUnitX.RegisterTestFixture(TLanzaTest);

end.
""")

# ---- discover ----
j = J(A.call('delphi_test', {'command': 'discover', 'path': BASE}))
names = [p.get('name', '') for p in mc.ficheros(j, 'projects')]
check('discover encuentra las dos suites', 'VerdeTest.dpr' in names and 'RojoTest.dpr' in names, str(j)[:300])
check('discover NO cuenta un proyecto normal', 'NormalApp.dpr' not in names, names)
check('discover dice el framework y el porque', mc.ficheros(j, 'projects') and all(p.get('framework') and p.get('why') for p in mc.ficheros(j, 'projects')), str(j)[:250])
j = J(A.call('delphi_test', {'command': 'discover', 'path': os.path.join(BASE, 'NormalApp')}))
check('carpeta sin tests: total 0 con explicacion', j.get('total') == 0 and mc.es(j.get('note') or '', 'SN_TEST_NONE'), str(j)[:250])

# ---- el interruptor ----
r = A.call('delphi_test', {'command': 'run', 'project': VERDE})
check('sin AllowTests: run RECHAZADO nombrando el interruptor', mc.rechazado(r) and mc.es(r, 'SR_TEST_DISABLED'), r[:250])
r = A.call('delphi_test', {'command': 'discover', 'path': BASE})
check('sin AllowTests: discover SI funciona', r.startswith('{'), r[:150])

# ---- run verde ----
j = J(B.call('delphi_test', {'command': 'run', 'project': VERDE}, t=900))
check('suite verde: result=pass', j.get('result') == 'pass', str(j)[:400])
check('suite verde: 3 de 3', j.get('total') == 3 and j.get('passed') == 3 and j.get('failed') == 0, str(j)[:300])
check('suite verde: veredicto por numeros', j.get('verdictFrom') == 'counts', str(j)[:200])
check('suite verde: dice el binario y la duracion', bool(j.get('binary')) and j.get('durationMs') is not None, str(j)[:250])
# el campo del contrato, que desde la 1.11.0 es siempre true (sin contenedor no
# corre); lo que la jaula HACE lo mide test_delphi_test_contenedor
check('suite verde: la respuesta declara sandboxed=true', j.get('sandboxed') is True, str(j)[:200])
# 1.13.0 (revisor de tokens): ni la nota fija TEST-024 en cada ejecucion (la
# suite verde es un runner de consola; el recuadro de DUnitX lo mira
# test_delphi_test_contenedor, que corre uno)
check('suite verde: sin la nota fija TEST-024', 'note' not in j, str(j)[:500])

# ---- run rojo ----
j = J(B.call('delphi_test', {'command': 'run', 'project': ROJO}, t=900))
check('suite roja: result=fail', j.get('result') == 'fail', str(j)[:400])
check('suite roja: 1 de 2 y el fallo NOMBRADO', j.get('failed') == 1 and any('MAL' in f for f in j.get('failures', [])), str(j)[:350])
check('suite roja: exitCode distinto de 0', j.get('exitCode') not in (0, None), str(j)[:200])

# ---- run con un test que lanza ----
j = J(B.call('delphi_test', {'command': 'run', 'project': LANZA}, t=900))
check('suite con un test que lanza: result=fail', j.get('result') == 'fail', str(j)[:400])
check('...con el error contado y NOMBRADO', j.get('errored') == 1 and j.get('failed') == 0
      and any('Lanza' in f and 'a proposito' in f for f in j.get('failures', [])), str(j)[:400])

# un test NUEVO metido con delphi_edit INSERT metodo, con su atributo delante y
# una directiva detras (1.11.2): se rechazaba con EDIT-070. Que DUnitX lo
# CORRA es la prueba de que el [Test] cayo en la declaracion (medido: en la
# implementacion compila y la RTTI no lo ve) y de que 'virtual' no fue a la
# implementacion (alli es E2070 y la suite no compila)
r = A.call('delphi_edit', {'path': os.path.join(BASE, 'LanzaTest', 'ULanzaTest.pas'), 'insert': 'metodo',
                           'inclass': 'TLanzaTest', 'visibility': 'public',
                           'code': "[Test]\nprocedure Insertado; virtual;\nbegin\n  Assert.AreEqual(9, 3 * 3);\nend;"})
check('INSERT metodo con [Test] y virtual en la suite DUnitX: las dos mitades',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT'), r[:300])
j = J(B.call('delphi_test', {'command': 'run', 'project': LANZA}, t=900))
check('...y DUnitX lo CORRE: 3 tests, 2 pasan (Bien e Insertado) y 1 lanza',
      j.get('total') == 3 and j.get('passed') == 2 and j.get('errored') == 1, str(j)[:400])

# ---- contratos ----
r = B.call('delphi_test', {'command': 'run', 'project': os.path.join(BASE, 'NormalApp', 'NormalApp.dpr')})
check('un proyecto que no es test: rechazado y explicado', mc.es(r, 'SR_TEST_NOTATEST_FMT'), r[:300])
r = B.call('delphi_test', {'command': 'run'})
check('run sin project rechazado con pista', mc.rechazado(r) and mc.es(r, 'SR_TEST_NEED_PROJECT'), r[:200])
r = B.call('delphi_test', {'command': 'volar', 'path': BASE})
check('comando invalido', mc.es(r, 'SR_TEST_CMD'), r[:150])
r = B.call('delphi_test', {'command': 'run', 'project': 'C:\\Windows\\x.dproj'})
check('fuera de la jaula rechazado', mc.rechazado(r) and mc.es(r, 'SR_JAIL_FMT'), r[:200])

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
