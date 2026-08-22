"""E2E battery for v0.42.0-beta - project units (the IDE's Add/Remove from
project, done by the server so the agent never edits .dpr/.dproj by hand):

- delphi_create kind=unit: .pas skeleton + uses of the .dpr + DCCReference;
- delphi_create form-vcl now writes the <DCCReference> with Form/FormType;
- delphi_config add-unit / remove-unit on an EXISTING .pas (idempotent,
  file stays on disk, view lists units);
- delphi_delete of a unit: designer pair trashed + projects updated;
- delphi_move rename of a unit: designer pair moved, header rewritten,
  projects re-pointed;
- refusals: header/file mismatch, non-.pas, missing path, jail.
Every structural step is proven by a real MSBuild build.

Usage:  python tests/test_project_units.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, re, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'punits')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE, exist_ok=True)

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()


def reader():
    for line in proc.stdout:
        line = line.strip()
        if line:
            q.put(line)


threading.Thread(target=reader, daemon=True).start()
rid = [10]


def send(o):
    proc.stdin.write(json.dumps(o) + '\n')
    proc.stdin.flush()


def recv(r, t=300):
    dl = time.time() + t
    while time.time() < dl:
        try:
            line = q.get(timeout=1)
        except queue.Empty:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get('id') == r:
            return m
    return None


def call(name, args, t=300):
    rid[0] += 1
    send({"jsonrpc": "2.0", "id": rid[0], "method": "tools/call",
          "params": {"name": name, "arguments": args}})
    r = recv(rid[0], t)
    if r is None:
        return '(timeout)'
    if 'error' in r:
        return 'MCPERROR ' + json.dumps(r['error'])[:200]
    c = r['result'].get('content', [])
    return c[0].get('text', '') if c else '(no content)'


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "punits-battery", "version": "1"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

P = F = 0


def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('  PASS', name)
    else:
        F += 1
        print('  FAIL', name, '|', str(detail)[:400])


def build_ok(dproj):
    out = call('delphi_build', {"project": dproj, "platform": "Win64",
                                "config": "Debug", "target": "Build"}, 600)
    try:
        d = json.loads(out)
        return d['success'], json.dumps(d['errors'])[:200]
    except Exception:
        return False, out[:200]


def rd(p):
    return open(p, 'rb').read().decode('utf-8-sig')


VDIR = os.path.join(BASE, 'App')
DPR = os.path.join(VDIR, 'App.dpr')
DPROJ = os.path.join(VDIR, 'App.dproj')

print('== project units battery ==')
out = call('delphi_create', {"kind": "project-vcl", "dir": VDIR, "name": "App"})
check('create: proyecto VCL', out.startswith('CREADO'), out)

# ---- kind=unit ----
out = call('delphi_create', {"kind": "unit", "name": "UUtil", "project": DPR})
check('create unit: CREADA + registrada', out.startswith('CREADA') and 'ANADIDA' in out, out[:300])
check('create unit: fichero esqueleto', os.path.exists(os.path.join(VDIR, 'UUtil.pas')))
dpr = rd(DPR)
check('create unit: uses del .dpr', "UUtil in 'UUtil.pas'" in dpr, dpr)
check('create unit: sin CreateForm (no es form)', 'CreateForm(TUUtil' not in dpr, dpr)
xml = rd(DPROJ)
check('create unit: DCCReference autocerrado en el .dproj', '<DCCReference Include="UUtil.pas"/>' in xml, xml[-900:])
out = call('delphi_create', {"kind": "unit", "name": "UUtil", "project": DPR})
check('create unit: jamas sobreescribe (sugiere add-unit)', 'RECHAZADO' in out and 'add-unit' in out, out)
out = call('delphi_create', {"kind": "unit", "name": "1Mal", "project": DPR})
check('create unit: identificador invalido rechazado', 'RECHAZADO' in out, out)
out = call('delphi_create', {"kind": "unit", "name": "UOtra", "project": DPROJ})
check('create unit: acepta el .dproj como project', out.startswith('CREADA'), out[:200])

# ---- form-vcl now writes the DCCReference ----
out = call('delphi_create', {"kind": "form-vcl", "name": "UClientes", "project": DPR})
check('create form: CREADO + alta', out.startswith('CREADO') and 'ANADIDA' in out, out[:300])
dpr = rd(DPR)
check('create form: uses con {FormUClientes}', "UClientes in 'UClientes.pas' {FormUClientes}" in dpr, dpr)
check('create form: CreateForm', 'Application.CreateForm(TFormUClientes, FormUClientes);' in dpr, dpr)
xml = rd(DPROJ)
m = re.search(r'<DCCReference Include="UClientes.pas">\s*<Form>FormUClientes</Form>\s*<FormType>dfm</FormType>\s*</DCCReference>', xml)
check('create form: DCCReference con Form + FormType dfm (forma del IDE)', bool(m), xml[-1200:])
# order: after the main form's reference, before BuildConfiguration
check('create form: DCCReference antes de BuildConfiguration',
      xml.index('Include="UClientes.pas"') < xml.index('<BuildConfiguration'), '')
ok, err = build_ok(DPROJ)
check('build: unit + form nuevos COMPILAN', ok, err)

# ---- CreateForm goes AFTER the last existing CreateForm (main form first) ----
i_main = dpr.index('CreateForm(TFormMain')
i_cli = dpr.index('CreateForm(TFormUClientes')
check('create form: CreateForm despues del form principal', i_main < i_cli, dpr)

# ---- view lists units ----
out = call('delphi_config', {"project": DPROJ})
try:
    d = json.loads(out)
    units = {u['unit']: u for u in d.get('units', [])}
    check('view: units listadas', {'UMain', 'UUtil', 'UOtra', 'UClientes'} <= set(units), list(units))
    check('view: form del designer', units.get('UClientes', {}).get('form') == 'FormUClientes', units.get('UClientes'))
    check('view: todas en el .dproj (sin dproj:false)', all('dproj' not in u for u in units.values()), units)
except Exception as e:
    check('view: parsea', False, '%s | %s' % (e, out[:200]))

# ---- add-unit on an EXISTING .pas written by hand (the agent's usual case) ----
hand = os.path.join(VDIR, 'UManual.pas')
open(hand, 'wb').write(('unit UManual;\r\n\r\ninterface\r\n\r\nfunction Dos: Integer;\r\n\r\n'
                        'implementation\r\n\r\nfunction Dos: Integer;\r\nbegin\r\n  Result := 2;\r\nend;\r\n\r\nend.\r\n').encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": hand})
check('add-unit: ANADIDA', out.startswith('ANADIDA'), out[:300])
dpr = rd(DPR)
check('add-unit: uses del .dpr', "UManual in 'UManual.pas'" in dpr, dpr)
check('add-unit: DCCReference', '<DCCReference Include="UManual.pas"/>' in rd(DPROJ), '')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": hand})
check('add-unit: idempotente', 'ya estaba' in out, out[:200])
check('add-unit: sin duplicar en el .dpr', rd(DPR).count("UManual in") == 1, rd(DPR))
check('add-unit: sin duplicar en el .dproj', rd(DPROJ).count('Include="UManual.pas"') == 1, '')

# subfolder unit -> relative include with backslash
sub = os.path.join(VDIR, 'src')
os.makedirs(sub, exist_ok=True)
subpas = os.path.join(sub, 'USub.pas')
open(subpas, 'wb').write('unit USub;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": subpas})
check('add-unit: subcarpeta', out.startswith('ANADIDA'), out[:200])
check('add-unit: include relativo con backslash', "USub in 'src\\USub.pas'" in rd(DPR), rd(DPR))
check('add-unit: DCCReference relativo', 'Include="src\\USub.pas"' in rd(DPROJ), '')
ok, err = build_ok(DPROJ)
check('build: con add-unit x2 COMPILA', ok, err)

# ---- refusals ----
bad = os.path.join(VDIR, 'UMal.pas')
open(bad, 'wb').write(b'unit UOtroNombre;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": bad})
check('add-unit: cabecera != fichero rechazado', 'RECHAZADO' in out and 'UOtroNombre' in out, out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'App.dpr')})
check('add-unit: no .pas rechazado', 'RECHAZADO' in out, out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit"})
check('add-unit: sin path -> pide path y reconectar', 'Falta "path"' in out and 'reconecta' in out, out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'NoExiste.pas')})
check('add-unit: inexistente sugiere delphi_create', 'RECHAZADO' in out and 'delphi_create' in out, out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": r'C:\Windows\win.ini'})
check('add-unit: fuera de la jaula rechazado', 'RECHAZADO' in out or 'error' in out.lower(), out[:200])

# ---- remove-unit: file stays ----
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": hand})
check('remove-unit: QUITADA', out.startswith('QUITADA'), out[:300])
check('remove-unit: fuera del .dpr', 'UManual' not in rd(DPR), rd(DPR))
check('remove-unit: fuera del .dproj', 'UManual' not in rd(DPROJ), '')
check('remove-unit: el fichero sigue en disco', os.path.exists(hand))
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": hand})
check('remove-unit: ausente informa', 'no esta en el proyecto' in out, out)
# remove a form: CreateForm goes too
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": os.path.join(VDIR, 'UClientes.pas')})
check('remove-unit form: QUITADA + CreateForm', out.startswith('QUITADA') and 'CreateForm' in out, out[:300])
dpr = rd(DPR)
check('remove-unit form: sin uses ni CreateForm', 'UClientes' not in dpr and 'FormUClientes' not in dpr, dpr)
check('remove-unit form: .dproj limpio', 'UClientes' not in rd(DPROJ), '')
ok, err = build_ok(DPROJ)
check('build: tras remove-unit COMPILA', ok, err)
# and back in (the .pas + .dfm still exist): form detected from the designer
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'UClientes.pas')})
check('add-unit form existente: detecta el form', 'FormUClientes' in out and 'CreateForm' in out, out[:300])
dpr = rd(DPR)
check('add-unit form existente: uses + CreateForm de vuelta',
      "{FormUClientes}" in dpr and 'CreateForm(TFormUClientes, FormUClientes)' in dpr, dpr)
check('add-unit form existente: DCCReference con Form', '<Form>FormUClientes</Form>' in rd(DPROJ), '')

# ---- delphi_delete of a unit: pair + projects ----
out = call('delphi_delete', {"path": os.path.join(VDIR, 'UClientes.pas')})
check('delete unit: BORRADO', out.startswith('BORRADO'), out[:300])
check('delete unit: designer a la papelera tambien', 'UClientes.dfm' in out and not os.path.exists(os.path.join(VDIR, 'UClientes.dfm')), out)
check('delete unit: proyecto actualizado (1)', 'proyectos actualizados (1)' in out, out)
dpr = rd(DPR)
check('delete unit: sin rastro en el .dpr', 'UClientes' not in dpr, dpr)
check('delete unit: sin rastro en el .dproj', 'UClientes' not in rd(DPROJ), '')
ok, err = build_ok(DPROJ)
check('build: tras delete COMPILA', ok, err)
# a unit nobody lists: plain delete, note says so
out = call('delphi_delete', {"path": hand})
check('delete unit suelta: nota "ningun .dpr"', out.startswith('BORRADO') and 'ningun .dpr' in out, out[:300])

# ---- delphi_move rename of a unit ----
out = call('delphi_create', {"kind": "form-vcl", "name": "UVenta", "project": DPR})
check('create form UVenta', out.startswith('CREADO'), out[:200])
out = call('delphi_move', {"path": os.path.join(VDIR, 'UVenta.pas'), "dest": os.path.join(VDIR, 'UVentas.pas')})
check('move rename: MOVIDO', out.startswith('MOVIDO'), out[:400])
check('move rename: designer movido', os.path.exists(os.path.join(VDIR, 'UVentas.dfm')) and not os.path.exists(os.path.join(VDIR, 'UVenta.dfm')), out)
src = rd(os.path.join(VDIR, 'UVentas.pas'))
check('move rename: cabecera reescrita', 'unit UVentas;' in src, src[:80])
check('move rename: proyecto reapuntado', 'proyectos actualizados (1)' in out and 'REAPUNTADA' in out, out)
dpr = rd(DPR)
check('move rename: uses nuevo con form', "UVentas in 'UVentas.pas' {FormUVenta}" in dpr and "UVenta in" not in dpr, dpr)
check('move rename: CreateForm intacto (la clase no cambia)', 'CreateForm(TFormUVenta, FormUVenta)' in dpr, dpr)
xml = rd(DPROJ)
check('move rename: DCCReference nuevo, viejo fuera', 'Include="UVentas.pas"' in xml and 'Include="UVenta.pas"' not in xml, '')
ok, err = build_ok(DPROJ)
check('build: tras rename COMPILA', ok, err)
# move into a subfolder keeps the name
out = call('delphi_move', {"path": os.path.join(VDIR, 'UOtra.pas'), "dest": os.path.join(sub, 'UOtra.pas')})
check('move a subcarpeta: MOVIDO + reapuntado', out.startswith('MOVIDO') and 'REAPUNTADA' in out, out[:300])
check('move a subcarpeta: include relativo', "UOtra in 'src\\UOtra.pas'" in rd(DPR), rd(DPR))
out = call('delphi_move', {"path": os.path.join(VDIR, 'UUtil.pas'), "dest": os.path.join(VDIR, 'UUtil.txt')})
check('move unit a .txt rechazado', 'RECHAZADO' in out, out)
out = call('delphi_move', {"path": os.path.join(VDIR, 'UUtil.pas'), "dest": os.path.join(VDIR, '2Mal.pas')})
check('move unit a identificador invalido rechazado', 'RECHAZADO' in out, out)
ok, err = build_ok(DPROJ)
check('build: final COMPILA', ok, err)

# ---- frames and data modules (VCL project) ----
out = call('delphi_create', {"kind": "frame-vcl", "name": "UFrameLista", "project": DPR})
check('frame-vcl: CREADO frame', out.startswith('CREADO frame'), out[:300])
src = rd(os.path.join(VDIR, 'UFrameLista.pas'))
check('frame-vcl: clase TFrameUFrameLista = class(TFrame)', 'TFrameUFrameLista = class(TFrame)' in src, src)
check('frame-vcl: sin variable global (como el IDE)', 'FrameUFrameLista: TFrameUFrameLista;' not in src, src)
dfm = rd(os.path.join(VDIR, 'UFrameLista.dfm'))
check('frame-vcl: dfm con TabOrder', dfm.startswith('object FrameUFrameLista: TFrameUFrameLista') and 'TabOrder = 0' in dfm, dfm)
dpr = rd(DPR)
check('frame-vcl: uses con {FrameUFrameLista: TFrame}', "UFrameLista in 'UFrameLista.pas' {FrameUFrameLista: TFrame}" in dpr, dpr)
check('frame-vcl: SIN CreateForm', 'CreateForm(TFrameUFrameLista' not in dpr, dpr)
xml = rd(DPROJ)
m = re.search(r'<DCCReference Include="UFrameLista.pas">\s*<Form>FrameUFrameLista</Form>\s*<FormType>dfm</FormType>\s*<DesignClass>TFrame</DesignClass>\s*</DCCReference>', xml)
check('frame-vcl: DCCReference con DesignClass TFrame', bool(m), xml[-1500:])

out = call('delphi_create', {"kind": "datamodule", "name": "UDatos", "project": DPR, "formname": "DMDatos"})
check('datamodule: CREADO data module', out.startswith('CREADO data module'), out[:300])
src = rd(os.path.join(VDIR, 'UDatos.pas'))
check('datamodule: clase + var + CLASSGROUP Vcl', 'TDMDatos = class(TDataModule)' in src and 'DMDatos: TDMDatos;' in src
      and "{%CLASSGROUP 'Vcl.Controls.TControl'}" in src, src)
check('datamodule: dfm Height/Width', 'Height = 480' in rd(os.path.join(VDIR, 'UDatos.dfm')), '')
dpr = rd(DPR)
check('datamodule: uses con {DMDatos: TDataModule}', "UDatos in 'UDatos.pas' {DMDatos: TDataModule}" in dpr, dpr)
check('datamodule: CreateForm SI', 'Application.CreateForm(TDMDatos, DMDatos);' in dpr, dpr)
check('datamodule: DCCReference con DesignClass TDataModule', '<DesignClass>TDataModule</DesignClass>' in rd(DPROJ), '')
ok, err = build_ok(DPROJ)
check('build: frame + datamodule COMPILAN', ok, err)
# rename a frame: DesignClass preserved, still no CreateForm
out = call('delphi_move', {"path": os.path.join(VDIR, 'UFrameLista.pas'), "dest": os.path.join(VDIR, 'UFrameListado.pas')})
check('move frame: reapuntado con DesignClass', out.startswith('MOVIDO') and 'REAPUNTADA' in out, out[:300])
dpr = rd(DPR)
check('move frame: uses nuevo {FrameUFrameLista: TFrame}', "UFrameListado in 'UFrameListado.pas' {FrameUFrameLista: TFrame}" in dpr, dpr)
check('move frame: sigue sin CreateForm', 'CreateForm(TFrameUFrameLista' not in dpr, dpr)
# delete the data module: CreateForm goes too
out = call('delphi_delete', {"path": os.path.join(VDIR, 'UDatos.pas')})
check('delete datamodule: BORRADO + proyecto', out.startswith('BORRADO') and 'proyectos actualizados (1)' in out, out[:300])
dpr = rd(DPR)
check('delete datamodule: sin uses ni CreateForm', 'UDatos' not in dpr and 'DMDatos' not in dpr, dpr)
ok, err = build_ok(DPROJ)
check('build: tras frame rename + dm delete COMPILA', ok, err)

# ---- FMX project: frame-fmx, datamodule (FMX classgroup), form-fmx ----
FDIR = os.path.join(BASE, 'Movil')
FDPR = os.path.join(FDIR, 'Movil.dpr')
FDPROJ = os.path.join(FDIR, 'Movil.dproj')
out = call('delphi_create', {"kind": "project-fmx", "dir": FDIR, "name": "Movil"})
check('create: proyecto FMX', out.startswith('CREADO'), out[:200])
out = call('delphi_create', {"kind": "frame-fmx", "name": "UFrameFicha", "project": FDPROJ})
check('frame-fmx: CREADO frame', out.startswith('CREADO frame'), out[:300])
fmx = rd(os.path.join(FDIR, 'UFrameFicha.fmx'))
check('frame-fmx: fmx con Size.PlatformDefault', 'Size.PlatformDefault = False' in fmx, fmx)
check('frame-fmx: DCCReference FormType fmx + TFrame',
      re.search(r'Include="UFrameFicha.pas">\s*<Form>FrameUFrameFicha</Form>\s*<FormType>fmx</FormType>\s*<DesignClass>TFrame</DesignClass>', rd(FDPROJ)) is not None, rd(FDPROJ)[-1200:])
out = call('delphi_create', {"kind": "datamodule", "name": "UDM", "project": FDPROJ})
check('datamodule FMX: CREADO', out.startswith('CREADO data module'), out[:200])
src = rd(os.path.join(FDIR, 'UDM.pas'))
check('datamodule FMX: CLASSGROUP FMX', "{%CLASSGROUP 'FMX.Controls.TControl'}" in src, src)
check('datamodule FMX: designer .dfm (no .fmx)', os.path.exists(os.path.join(FDIR, 'UDM.dfm')) and not os.path.exists(os.path.join(FDIR, 'UDM.fmx')), '')
check('datamodule FMX: DCCReference FormType dfm', re.search(r'Include="UDM.pas">\s*<Form>DMUDM</Form>\s*<FormType>dfm</FormType>\s*<DesignClass>TDataModule', rd(FDPROJ)) is not None, rd(FDPROJ)[-1200:])
out = call('delphi_create', {"kind": "form-fmx", "name": "USegunda", "project": FDPROJ})
check('form-fmx: CREADO', out.startswith('CREADO form'), out[:200])
ok, err = build_ok(FDPROJ)
check('build: FMX con frame + datamodule + form COMPILA', ok, err)

# ---- delete of a plain (non-unit) file untouched by all this ----
txt = os.path.join(VDIR, 'notas.txt')
open(txt, 'wb').write(b'x')
out = call('delphi_delete', {"path": txt})
check('delete fichero normal: sin notas de proyecto', out.startswith('BORRADO') and 'proyectos' not in out and 'ningun .dpr' not in out, out)

print()
print('== project units battery: %d PASS / %d FAIL ==' % (P, F))
proc.stdin.close()
time.sleep(1)
proc.kill()
sys.exit(1 if F else 0)
