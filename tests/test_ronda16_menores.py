"""E2E battery for v1.13.0 - the minors of review round 16 that were left
"untouched" since 1.7.x, each measured before the fix (4-oct-2026):

  R1  a .delphilsp.json next to a project that is not a JSON object (an
      array, a "settings" that is text, a number) answered SYS-006 INTERNAL
      "Invalid class typecast" in EVERY tool of the engine: now it names no
      project and the server fabricates its own (Lsp.Client.ObjetoJson, the
      one reader of a JSON that must be an object)
  R2  delphi_references opened each candidate with AcquireFor, which looks
      for the CANDIDATE's engine: a unit shared by two projects started the
      engine of the other one (the first .dproj naming it) just to warm it,
      and the question went to the usual engine anyway - two engines where
      one was needed. Now the candidate is opened in the engine that is asked
      (TLspSession.AbreEn)
  R3  the settings cache decided by a .dproj, with no IDE settings file at
      the time, stayed valid while the .dproj did not change: a
      <project>.delphilsp.json the IDE writes later was never taken. Now the
      entry stops being valid when it appears
  R4  delphi_definition kind=declaration chained to the target file with
      AcquireFor too - the twin of R2: a declaration in a shared unit
      started another engine and overwrote the settings of the answer
      with the other one's (an LSP-021 note that was false). Now it asks
      the same engine (review of 1.13.0)

Measured and NOT reproduced, so no code change: the "two millisecond windows"
of a transient FILE-036 (0 of 15 hover-then-delete, 0 of 12 with three
threads hovering on the folder being deleted, 2379 hovers). The git minors
of that round belong to the git jail.

Usage:  python tests/test_ronda16_menores.py [path-to-DelphiLspMcp.exe]
"""
import glob, os, shutil, subprocess, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('ronda16_menores')
EXE = mc.copia_exe(BASE)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA, exist_ok=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA}),
               nombre='ronda16', t=300)
call = srv.call


def motores():
    """Los motores DelphiLSP vivos de ESTE servidor (hijos de su proceso)."""
    out = subprocess.run(['powershell', '-NoProfile', '-Command',
                          "(Get-CimInstance Win32_Process -Filter \"ParentProcessId=%d and "
                          "Name='DelphiLSP.exe'\" | Measure-Object).Count" % srv.p.pid],
                         capture_output=True, text=True).stdout.strip()
    return int(out) if out.isdigit() else -1


def proyecto(nombre, dir_):
    call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': dir_})
    return os.path.join(dir_, nombre + '.dpr'), os.path.join(dir_, nombre + '.dproj')


# R1: un .delphilsp.json que no es un objeto
for nombre, cuerpo in (('array', '[]'), ('settings_texto', '{"settings": "x"}'), ('numero', '42')):
    dpr, _ = proyecto('P', os.path.join(BASE, 'r1_' + nombre))
    open(os.path.join(os.path.dirname(dpr), 'P.delphilsp.json'), 'w').write(cuerpo)
    r = call('delphi_hover', {'path': dpr, 'line': 0, 'character': 9}, 300)
    # y contesta: no vale cualquier otro fallo (un timeout, otro INTERNAL)
    check('R1 un .delphilsp.json %s no es un INTERNAL: el hover contesta' % nombre,
          not mc.tiene(r, 'SYS-006') and 'typecast' not in r and not mc.fallo(r), r[:200])

# R2: references no arranca el motor de otro proyecto para calentar un candidato
comun = os.path.join(BASE, 'r2', 'comun')
os.makedirs(comun)
open(os.path.join(comun, 'UComun.pas'), 'w', newline='\r\n').write(
    'unit UComun;\ninterface\nprocedure Saluda;\nimplementation\nprocedure Saluda;\nbegin\nend;\nend.\n')
for prj, uso in (('Z', 'UsoZ'), ('B', 'UsoB')):  # B sale antes al buscar el .dproj de la comun
    d = os.path.join(BASE, 'r2', prj)
    _, dproj = proyecto('P' + prj, d)
    open(os.path.join(d, uso + '.pas'), 'w', newline='\r\n').write(
        'unit %s;\ninterface\nprocedure Llama;\nimplementation\nuses UComun;\n'
        'procedure Llama;\nbegin\n  Saluda;\nend;\nend.\n' % uso)
    for u in (os.path.join(d, uso + '.pas'), os.path.join(comun, 'UComun.pas')):
        call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': u})
uso_z = os.path.join(BASE, 'r2', 'Z', 'UsoZ.pas')
call('delphi_hover', {'path': uso_z, 'line': 7, 'character': 4}, 300)
antes = motores()
j = mc.como_json(call('delphi_references', {'path': uso_z, 'line': 7, 'character': 4}, 300))
check('R2 references confirma la llamada y las dos lineas de la comun',
      len(mc.aciertos(j, 'confirmed')) == 3, str(j)[:300])
check('R2 ...sin arrancar el motor del otro proyecto (%d -> %d)' % (antes, motores()),
      antes >= 1 and motores() == antes, (antes, motores()))

# R4: declaration va al motor que pregunta, no arranca el de la comun
antes = motores()
r = call('delphi_definition', {'path': uso_z, 'line': 7, 'character': 4, 'kind': 'declaration'}, 300)
check('R4 declaration de una rutina de la unidad compartida: la encuentra',
      'UComun' in r and not mc.fallo(r), r[:300])
check('R4 ...sin arrancar otro motor (%d -> %d) ni una nota LSP-021 falsa' % (antes, motores()),
      antes >= 1 and motores() == antes and not mc.tiene(r, 'LSP-021'), (antes, motores(), r[:300]))

# R3: el .delphilsp.json que el IDE escribe DESPUES se toma. Con su propio
# nombre: los settings fabricados se llaman <proyecto>-<hash>-..., y los
# tres P de R1 casaban con el mismo glob (revision de la 1.13.0)
dpr, _ = proyecto('PTres', os.path.join(BASE, 'r3'))
call('delphi_hover', {'path': dpr, 'line': 0, 'character': 9}, 300)
antes = motores()
fab = glob.glob(os.path.join(mc.cache_servidor('configs', APPDATA), 'PTres-*.delphilsp.json'))
check('R3 preparacion: los settings fabricados de PTres, y solo esos', len(fab) == 1, fab)
if fab:
    # el motor nuevo es el de los settings del IDE; el de los fabricados se
    # queda hasta que el barrendero lo pare por no usarse
    shutil.copy(fab[0], os.path.join(BASE, 'r3', 'PTres.delphilsp.json'))
    time.sleep(1)
    call('delphi_hover', {'path': dpr, 'line': 0, 'character': 9}, 300)
    check('R3 el del IDE que aparece despues se toma: un motor con SUS settings (%d -> %d)'
          % (antes, motores()), motores() == antes + 1, (antes, motores()))

srv.cierra()
mc.borra(BASE)
mc.fin('ronda16-menores battery')
