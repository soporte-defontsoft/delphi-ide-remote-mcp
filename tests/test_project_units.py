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
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('punits')
# su PROPIA copia del servidor (antes corria el compilado en su sitio)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

env = mc.entorno({'DELPHI_MCP_ROOTS': BASE})
srv = mc.Stdio(EXE, env, nombre='punits-battery', t=300)  # el plazo de esta bateria
call = srv.call


# los de la casa (mcp_cliente): un build y un fichero (que tiene que existir)
def build_ok(dproj):
    return mc.build_ok(call, dproj)


def rd(p):
    """El fichero, que TIENE que existir: aqui casi todo lo que se mide es que
    algo NO esta ('UManual' not in rd(DPR)), y con mc.lee a secas (vacio si no
    existe) eso pasaba con el .dpr borrado (revision de la 1.13.0)."""
    if not os.path.exists(p):
        check('el fichero que se lee existe: %s' % p, False, p)
    return mc.lee(p)


VDIR = os.path.join(BASE, 'App')
DPR = os.path.join(VDIR, 'App.dpr')
DPROJ = os.path.join(VDIR, 'App.dproj')

print('== project units battery ==')
out = call('delphi_create', {"kind": "project-vcl", "dir": VDIR, "name": "App"})
check('create: proyecto VCL', mc.abre(out, 'SK_CREATE_CREADO_PROYECTO_FMT'), out)

# ---- kind=unit ----
out = call('delphi_create', {"kind": "unit", "name": "UUtil", "project": DPR})
check('create unit: CREADA + registrada', mc.abre(out, 'SK_CREATE_CREADA_UNIT_LINEAS_FMT') and mc.es(out, 'SN_UNIT_ADDED_FMT'), out[:300])
check('create unit: fichero esqueleto', os.path.exists(os.path.join(VDIR, 'UUtil.pas')))
dpr = rd(DPR)
check('create unit: uses del .dpr', "UUtil in 'UUtil.pas'" in dpr, dpr)
# los "sin CreateForm" miran un .dpr que SI recibio la unit: si la
# operacion no llega, el .dpr tampoco tiene CreateForm y pasaban igual
check('create unit: sin CreateForm (no es form)',
      "UUtil in 'UUtil.pas'" in dpr and 'CreateForm(TUUtil' not in dpr, dpr)
# v0.46.2: the clause keeps its indent (it was re-indented to 4 spaces on every edit)
_u = dpr[dpr.index('uses'):dpr.index(';', dpr.index('uses'))]
_lines = [l for l in _u.split('\n')[1:] if l.strip()]
check('uses: cada entrada con DOS espacios (sin reindentar)', all(l.startswith('  ') and not l.startswith('   ') for l in _lines), _u[:300])
xml = rd(DPROJ)
check('create unit: DCCReference autocerrado en el .dproj', '<DCCReference Include="UUtil.pas"/>' in xml, xml[-900:])
out = call('delphi_create', {"kind": "unit", "name": "UUtil", "project": DPR})
check('create unit: jamas sobreescribe (sugiere add-unit)', mc.rechazado(out) and mc.es(out, 'SR_CREATE_UNIT_YA_EXISTE_ADD_UNIT_FMT') and 'add-unit' in out, out)
out = call('delphi_create', {"kind": "unit", "name": "1Mal", "project": DPR})
check('create unit: identificador invalido rechazado', mc.rechazado(out) and mc.es(out, 'SR_CREATE_BADNAME_FMT'), out)
out = call('delphi_create', {"kind": "unit", "name": "UOtra", "project": DPROJ})
check('create unit: acepta el .dproj como project', mc.abre(out, 'SK_CREATE_CREADA_UNIT_LINEAS_FMT'), out[:200])

# ---- form-vcl now writes the DCCReference ----
out = call('delphi_create', {"kind": "form-vcl", "name": "UClientes", "project": DPR})
check('create form: CREADO + alta', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and mc.es(out, 'SN_UNIT_ADDED_FORM_FMT'), out[:300])
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
out = call('delphi_config', {"project": DPROJ, "section": "units"})
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
check('add-unit: ANADIDA', mc.abre(out, 'SN_UNIT_ADDED_FMT'), out[:300])
dpr = rd(DPR)
check('add-unit: uses del .dpr', "UManual in 'UManual.pas'" in dpr, dpr)
check('add-unit: DCCReference', '<DCCReference Include="UManual.pas"/>' in rd(DPROJ), '')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": hand})
check('add-unit: idempotente', mc.es(out, 'SN_UNIT_PRESENT_FMT'), out[:200])
check('add-unit: sin duplicar en el .dpr', rd(DPR).count("UManual in") == 1, rd(DPR))
check('add-unit: sin duplicar en el .dproj', rd(DPROJ).count('Include="UManual.pas"') == 1, '')

# el // que va detras del ; final del .dpr es de su ULTIMA entrada (1.10.0):
# la unit anadida va detras y no se lo lleva (salia en la nueva, medido el
# 2-oct-2026 con add-unit y con adduses, el mismo escritor)
_b = open(DPR, 'rb').read()
_bom = b'\xef\xbb\xbf' if _b.startswith(b'\xef\xbb\xbf') else b''
_t = _b[len(_bom):].decode('utf-8')
_n = _t.count("UManual in 'UManual.pas';")
open(DPR, 'wb').write(_bom + _t.replace("UManual in 'UManual.pas';",
                                        "UManual in 'UManual.pas'; // a mano", 1).encode('utf-8'))
check('add-unit: la prueba del // final parte de UManual como ultima entrada', _n == 1, _t)

# subfolder unit -> relative include with backslash
sub = os.path.join(VDIR, 'src')
os.makedirs(sub, exist_ok=True)
subpas = os.path.join(sub, 'USub.pas')
open(subpas, 'wb').write('unit USub;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": subpas})
check('add-unit: subcarpeta', mc.abre(out, 'SN_UNIT_ADDED_FMT'), out[:200])
check('add-unit: include relativo con backslash', "USub in 'src\\USub.pas'" in rd(DPR), rd(DPR))
check('add-unit: el // del ; final se queda con su entrada, la nueva va detras',
      "UManual in 'UManual.pas', // a mano" in rd(DPR) and "USub in 'src\\USub.pas';" in rd(DPR), rd(DPR))
check('add-unit: DCCReference relativo', 'Include="src\\USub.pas"' in rd(DPROJ), '')
ok, err = build_ok(DPROJ)
check('build: con add-unit x2 COMPILA', ok, err)

# ---- present by NAME but without the in clause (1.1.1, Hermes battery 1.2) ----
# The agent wrote "USinIn," by hand in the uses; dcc cannot find a unit of
# another folder without its path, and add-unit used to answer "ya estaba".
sinin = os.path.join(sub, 'USinIn.pas')
open(sinin, 'wb').write('unit USinIn;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
_d = rd(DPR)
_d = _d.replace("USub in 'src\\USub.pas'", "USub in 'src\\USub.pas',\r\n  USinIn", 1)
open(DPR, 'wb').write(_d.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": sinin})
check('add-unit: presente sin in -> COMPLETADA', mc.abre(out, 'SN_UNIT_COMPLETED_FMT') and 'F2613' in out, out[:300])
check('add-unit: la entrada gana su clausula in', "USinIn in 'src\\USinIn.pas'" in rd(DPR), rd(DPR))
check('add-unit: sin duplicar la entrada completada', rd(DPR).count('USinIn in') == 1, rd(DPR))
check('add-unit: DCCReference de la completada', 'Include="src\\USinIn.pas"' in rd(DPROJ), '')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": sinin})
check('add-unit: completada es idempotente', mc.es(out, 'SN_UNIT_PRESENT_FMT'), out[:200])
ok, err = build_ok(DPROJ)
check('build: con la entrada completada COMPILA', ok, err)

# ---- la cabecera y el uses de un .dpr se buscan en su CODIGO (1.10.0) ----
# un 'program viejo; uses X;' dentro de un comentario de arriba era la
# cabecera, y add-unit escribia en el uses COMENTADO contestando ADDED (sonda
# del lexico, 2-oct-2026). Un proyecto aparte: el de arriba lo cuentan otros
CDIR = os.path.join(BASE, 'Cab')
out = call('delphi_create', {"kind": "project-console", "dir": CDIR, "name": "PCab"})
CDPR = os.path.join(CDIR, 'PCab.dpr')
_b = open(CDPR, 'rb').read()
_bom = b'\xef\xbb\xbf' if _b.startswith(b'\xef\xbb\xbf') else b''
open(CDPR, 'wb').write(_bom + b'{\r\nprogram viejo;\r\nuses UNoExiste;\r\n}\r\n' + _b[len(_bom):])
open(os.path.join(CDIR, 'UCab.pas'), 'wb').write(b'unit UCab;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
out = call('delphi_config', {"project": os.path.join(CDIR, 'PCab.dproj'), "command": "add-unit",
                             "path": os.path.join(CDIR, 'UCab.pas')})
_d = rd(CDPR)
check('add-unit: al uses de verdad, no al comentado de arriba',
      mc.abre(out, 'SN_UNIT_ADDED_FMT') and '{\r\nprogram viejo;\r\nuses UNoExiste;\r\n}' in _d
      and "UCab in 'UCab.pas'" in _d and _d.index('UCab in') > _d.index('program PCab;'), out[:200] + ' | ' + _d)
# la clase de un form se lee en su CODIGO (1.10.0): una declaracion comentada
# con otro ancestro, delante de la de verdad, lo hacia pasar por un frame
out = call('delphi_create', {"kind": "form-vcl", "name": "UFormCom", "project": DPR})
fpas = os.path.join(VDIR, 'UFormCom.pas')
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": fpas})
_s = open(fpas, 'rb').read()
_n = _s.count(b'  TFormUFormCom = class(TForm)')
open(fpas, 'wb').write(_s.replace(b'  TFormUFormCom = class(TForm)',
                                  b'  { TFormUFormCom = class(TFrame) era antes }\r\n  TFormUFormCom = class(TForm)', 1))
check('add-unit: la prueba de la clase comentada parte de su linea de clase', _n == 1, _s[:300])
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": fpas})
check('add-unit: la clase del form se lee en su codigo, no en un comentario',
      mc.abre(out, 'SN_UNIT_ADDED_FORM_FMT') and "UFormCom in 'UFormCom.pas' {FormUFormCom}" in rd(DPR)
      and 'TFrame' not in rd(DPR), out[:200] + ' | ' + rd(DPR))

# ---- lo que encontro el revisor de codigo de la 1.10.0 (medido antes con una
# sonda contra el exe de entonces) ----
# una entrada se reescribe con lo que lleva DETRAS: renombrar (delphi_move) y
# completar (add-unit) la rehacian con lo de delante solo, el {$IFDEF DEBUG}
# se iba, el .dpr no compilaba y la tool decia que si
def pon_uses(dpr, clausula):
    _d = rd(dpr)
    _i = _d.index('uses')
    open(dpr, 'wb').write((_d[:_i] + clausula + _d[_d.index(';', _i) + 1:]).encode('utf-8-sig'))


DDIR = os.path.join(BASE, 'Dir')
call('delphi_create', {"kind": "project-console", "dir": DDIR, "name": "PDir"})
DDPR = os.path.join(DDIR, 'PDir.dpr')
for _u in ('UnitA', 'UnitB', 'DebugU'):
    open(os.path.join(DDIR, _u + '.pas'), 'wb').write(
        ('unit %s;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n' % _u).encode('ascii'))
pon_uses(DDPR, "uses\r\n  System.SysUtils,\r\n  UnitA in 'UnitA.pas' {$IFDEF DEBUG},\r\n"
               "  DebugU in 'DebugU.pas' {$ENDIF},\r\n  UnitB {$IFDEF DEBUG},\r\n"
               "  DebugU2 {$ENDIF};")
out = call('delphi_move', {"path": os.path.join(DDIR, 'UnitA.pas'), "dest": os.path.join(DDIR, 'UnitZ.pas')})
check('move rename: la directiva de DETRAS de la entrada se queda',
      mc.abre(out, 'SK_MOVE_MOVIDO_FMT') and "UnitZ in 'UnitZ.pas' {$IFDEF DEBUG},\r\n" in rd(DDPR),
      out[:200] + ' | ' + rd(DDPR))
out = call('delphi_config', {"project": os.path.join(DDIR, 'PDir.dproj'), "command": "add-unit",
                             "path": os.path.join(DDIR, 'UnitB.pas')})
check('add-unit: completar una entrada conserva la directiva de detras',
      mc.abre(out, 'SN_UNIT_COMPLETED_FMT') and "UnitB in 'UnitB.pas' {$IFDEF DEBUG},\r\n" in rd(DDPR),
      out[:200] + ' | ' + rd(DDPR))
# DebugU2 no existe: el condicional entero fuera para compilar lo que queda
pon_uses(DDPR, rd(DDPR)[rd(DDPR).index('uses'):].split(';')[0].replace(
    "  UnitB in 'UnitB.pas' {$IFDEF DEBUG},\r\n  DebugU2 {$ENDIF}", "  UnitB in 'UnitB.pas'") + ';')
ok, err = build_ok(os.path.join(DDIR, 'PDir.dproj'))
check('build: la renombrada con su condicional COMPILA', ok, err + ' | ' + rd(DDPR))
# el CreateForm se escribe y se quita en el CODIGO del .dpr: un
# Application.Run comentado encima del de verdad se lo llevaba DENTRO del
# comentario, uno comentado de la misma clase pasaba por "ya esta", y quitar
# uno que esta en un comentario que cierra en su linea se llevaba la llave
FDIR = os.path.join(BASE, 'Frm')
call('delphi_create', {"kind": "project-vcl", "dir": FDIR, "name": "PFrm"})
FDPR = os.path.join(FDIR, 'PFrm.dpr')
_d = rd(FDPR)
_n = _d.count('  Application.Initialize;')
open(FDPR, 'wb').write(_d.replace('  Application.Initialize;',
                                  '  (* la vieja:\r\n  Application.Run;\r\n  *)\r\n'
                                  '  //Application.CreateForm(TFormUF3, FormUF3);\r\n'
                                  '  Application.Initialize;', 1).encode('utf-8-sig'))
check('CreateForm: la prueba parte de un Application.Initialize', _n == 1, _d)
out = call('delphi_create', {"kind": "form-vcl", "name": "UF2", "project": FDPR})
_d = rd(FDPR)
check('CreateForm: delante del Application.Run de verdad, no del comentado',
      mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and
      '(* la vieja:\r\n  Application.Run;\r\n  *)' in _d and
      _d.index('Application.CreateForm(TFormUF2') > _d.index('*)'), _d)
out = call('delphi_create', {"kind": "form-vcl", "name": "UF3", "project": FDPR})
_d = rd(FDPR)
check('CreateForm: uno comentado de la misma clase no es "ya esta"',
      mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and _d.count('Application.CreateForm(TFormUF3, FormUF3);') == 2,
      _d)
open(FDPR, 'wb').write(_d.replace('  Application.Initialize;',
                                  '  { quitado:\r\n  Application.CreateForm(TFormUF2, FormUF2); }\r\n'
                                  '  Application.Initialize;', 1).encode('utf-8-sig'))
out = call('delphi_config', {"project": os.path.join(FDIR, 'PFrm.dproj'), "command": "remove-unit",
                             "path": os.path.join(FDIR, 'UF2.pas')})
_d = rd(FDPR)
check('remove-unit: el CreateForm de un comentario se queda, y su llave con el',
      mc.abre(out, 'SN_UNIT_REMOVED_FMT') and
      '  { quitado:\r\n  Application.CreateForm(TFormUF2, FormUF2); }\r\n' in _d and
      _d.count('CreateForm(TFormUF2') == 1, _d)
# ...y de una linea que lleva algo mas que el CreateForm (el cierre de un
# comentario de encima) se va la sentencia sola, no la linea
_n = _d.count('  Application.CreateForm(TFormUF3, FormUF3);')
open(FDPR, 'wb').write(_d.replace('  Application.CreateForm(TFormUF3, FormUF3);',
                                  '  { nota\r\n  } Application.CreateForm(TFormUF3, FormUF3);', 1).encode('utf-8-sig'))
out = call('delphi_config', {"project": os.path.join(FDIR, 'PFrm.dproj'), "command": "remove-unit",
                             "path": os.path.join(FDIR, 'UF3.pas')})
_d = rd(FDPR)
check('remove-unit: de una linea con el cierre de un comentario se va el CreateForm, no la llave',
      _n == 1 and mc.abre(out, 'SN_UNIT_REMOVED_FMT') and '  { nota\r\n  }\r\n' in _d and
      '//Application.CreateForm(TFormUF3, FormUF3);' in _d, _d)
ok, err = build_ok(os.path.join(FDIR, 'PFrm.dproj'))
check('build: el .dpr con sus CreateForm comentados COMPILA', ok, err + ' | ' + _d)

# ---- refusals ----
bad = os.path.join(VDIR, 'UMal.pas')
open(bad, 'wb').write(b'unit UOtroNombre;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": bad})
check('add-unit: cabecera != fichero rechazado', mc.rechazado(out) and mc.es(out, 'SR_UNIT_HEADER_MISMATCH_FMT') and 'UOtroNombre' in out, out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'App.dpr')})
check('add-unit: no .pas rechazado', mc.rechazado(out) and mc.es(out, 'SR_UNIT_NOT_PAS_FMT'), out)
# accented unit name: dcc compiles it (measured 2026-09-23), and since
# 4-oct-2026 the server reads it too (EL identificador, Lsp.Pascal): add-unit
# takes it, and the builds below compile it. Until then it was refused with
# CFG-038 (Hermes, 1.2 G.19); CFG-038 is now for a header that is not a unit
# name at all - and it still says THAT, not "no header"
acc = os.path.join(VDIR, 'UÁrbol.pas')
open(acc, 'wb').write('unit UÁrbol;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": acc})
check('add-unit: unit acentuada -> ANADIDA (dcc la compila y el servidor ya la lee)',
      mc.abre(out, 'SN_UNIT_ADDED_FMT') and "UÁrbol in 'UÁrbol.pas'" in rd(DPR), out)
mal = os.path.join(VDIR, 'U-Mal.pas')
open(mal, 'wb').write('unit U-Mal;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": mal})
check('add-unit: cabecera que no es un nombre de unit -> RECHAZADO con la causa real',
      mc.rechazado(out) and mc.es(out, 'SR_UNIT_HEADER_NONASCII_FMT') and 'U-Mal' in out and 'U-Mal' not in rd(DPR), out)
check('add-unit: ...y no dice "no tiene cabecera"',
      mc.rechazado(out) and mc.es(out, 'SR_UNIT_HEADER_NONASCII_FMT') and not mc.es(out, 'SR_UNIT_NO_HEADER_FMT'), out)
# un FRAME cuyo ancestro es 'class abstract(TFrame)': la cadena de ancestros
# se leia con 'class\s*\(' y no pasaba de TMarcoBase, asi que add-unit lo
# tomaba por un form y le escribia un CreateForm (medido el 4-oct-2026;
# PATRON_ABRE_CLASE). Los builds de abajo lo compilan
mar = os.path.join(VDIR, 'UMarcoAbs.pas')
open(mar, 'wb').write(('unit UMarcoAbs;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.Controls, System.Classes;\r\n\r\n'
                       'type\r\n  TMarcoBase = class abstract(TFrame)\r\n  end;\r\n  TMarcoAbs = class(TMarcoBase)\r\n  end;\r\n\r\n'
                       'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n').encode('utf-8-sig'))
open(os.path.join(VDIR, 'UMarcoAbs.dfm'), 'wb').write(
    b'object MarcoAbs: TMarcoAbs\r\n  Left = 0\r\n  Top = 0\r\n  Width = 320\r\n  Height = 240\r\n  TabOrder = 0\r\nend\r\n')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": mar})
check('add-unit: un frame de ancestro class abstract(TFrame) entra SIN CreateForm',
      mc.abre(out, 'SN_UNIT_ADDED_FORM_FMT') and "UMarcoAbs in 'UMarcoAbs.pas'" in rd(DPR) and
      'CreateForm(TMarcoAbs' not in rd(DPR) and 'TFrame' in rd(DPROJ)[rd(DPROJ).find('UMarcoAbs.pas'):][:300],
      out + ' | ' + rd(DPR))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit"})
check('add-unit: sin path -> pide path y reconectar', mc.es(out, 'SR_UNIT_NEED_PATH'), out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'NoExiste.pas')})
check('add-unit: inexistente sugiere delphi_create', mc.rechazado(out) and mc.es(out, 'SR_UNIT_PAS_MISSING_FMT') and 'delphi_create' in out, out)
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": r'C:\Windows\win.ini'})
check('add-unit: fuera de la jaula rechazado', mc.rechazado(out) and mc.es(out, 'SR_JAIL_FMT'), out[:200])

# ---- remove-unit: file stays ----
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": hand})
check('remove-unit: QUITADA', mc.abre(out, 'SN_UNIT_REMOVED_FMT'), out[:300])
check('remove-unit: fuera del .dpr', 'UManual' not in rd(DPR), rd(DPR))
# el '// a mano' iba detras de la coma de UManual: quitada ella, se pegaba a la
# de antes ('{FormUClientes}, // a mano', medido el 2-oct-2026); se queda en
# una linea suya (un comentario no se borra)
_lin = [l for l in rd(DPR).splitlines() if '// a mano' in l]
check('remove-unit: el // de la quitada se queda en una linea suya, no pegado a otra entrada',
      len(_lin) == 1 and _lin[0].strip() == '// a mano', rd(DPR))
check('remove-unit: fuera del .dproj', 'UManual' not in rd(DPROJ), '')
check('remove-unit: el fichero sigue en disco', os.path.exists(hand))
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": hand})
check('remove-unit: ausente informa', mc.es(out, 'SN_UNIT_ABSENT_FMT'), out)
# remove a form: CreateForm goes too
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": os.path.join(VDIR, 'UClientes.pas')})
check('remove-unit form: QUITADA + CreateForm', mc.abre(out, 'SN_UNIT_REMOVED_FMT') and 'CreateForm' in out, out[:300])
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
check('delete unit: BORRADO', mc.abre(out, 'SK_FILE_BORRADO_PAPELERA_FMT'), out[:300])
check('delete unit: designer a la papelera tambien', 'UClientes.dfm' in out and not os.path.exists(os.path.join(VDIR, 'UClientes.dfm')), out)
check('delete unit: proyecto actualizado (1)', mc.es(out, 'SN_FILE_PROJECTS_UPDATED_FMT') and mc.ids(out).count(mc.id_de('SN_UNIT_REMOVED_GONE_FMT')) == 1, out)
dpr = rd(DPR)
check('delete unit: sin rastro en el .dpr', 'UClientes' not in dpr, dpr)
check('delete unit: sin rastro en el .dproj', 'UClientes' not in rd(DPROJ), '')
ok, err = build_ok(DPROJ)
check('build: tras delete COMPILA', ok, err)
# a unit nobody lists: plain delete, note says so
out = call('delphi_delete', {"path": hand})
check('delete unit suelta: nota "ningun .dpr"', mc.abre(out, 'SK_FILE_BORRADO_PAPELERA_FMT') and mc.es(out, 'SN_FILE_PROJECTS_NONE'), out[:300])

# ---- delphi_move rename of a unit ----
out = call('delphi_create', {"kind": "form-vcl", "name": "UVenta", "project": DPR})
check('create form UVenta', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT'), out[:200])
# a unit that USES UVenta and names it qualified: both must follow the rename
# (Hermes, 2026-09-22, test 19: the .dpr kept UBatHelper.Bat11Sum and the
# build died with E2003). A 'UVenta.' inside a string literal must NOT move.
usa = os.path.join(VDIR, 'UUsaVenta.pas')
open(usa, 'wb').write(b"unit UUsaVenta;\r\n\r\ninterface\r\n\r\nuses\r\n  UVenta;\r\n\r\nfunction HayVenta: string;\r\n\r\nimplementation\r\n\r\nfunction HayVenta: string;\r\nbegin\r\n  { it's } Result := UVenta.FormUVenta.Name; // de UVenta\r\n  if UVenta.FormUVenta <> nil then\r\n    Result := 'UVenta.FormUVenta'\r\n  else\r\n    Result := '';\r\nend;\r\n\r\nend.\r\n")
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": usa})
check('unit que usa UVenta anadida al proyecto', mc.abre(out, 'SN_UNIT_ADDED_FMT'), out[:200])
# un // detras de la coma de UVenta es suyo y la sigue con su nombre nuevo (la
# entrada se cambia EN SU SITIO: 1.10.0, la duena del // ya no se busca por el
# nombre, que el rename cambia)
_b = open(DPR, 'rb').read()
_bom = b'\xef\xbb\xbf' if _b.startswith(b'\xef\xbb\xbf') else b''
_t = _b[len(_bom):].decode('utf-8')
_n = _t.count("UVenta in 'UVenta.pas' {FormUVenta},")
open(DPR, 'wb').write(_bom + _t.replace("UVenta in 'UVenta.pas' {FormUVenta},",
                                        "UVenta in 'UVenta.pas' {FormUVenta}, // la venta", 1).encode('utf-8'))
check('move rename: la prueba del // parte de UVenta en medio de la clausula', _n == 1, _t)
out = call('delphi_move', {"path": os.path.join(VDIR, 'UVenta.pas'), "dest": os.path.join(VDIR, 'UVentas.pas')})
check('move rename: MOVIDO', mc.abre(out, 'SK_MOVE_MOVIDO_FMT'), out[:400])
check('move rename: designer movido', os.path.exists(os.path.join(VDIR, 'UVentas.dfm')) and not os.path.exists(os.path.join(VDIR, 'UVenta.dfm')), out)
src = rd(os.path.join(VDIR, 'UVentas.pas'))
check('move rename: cabecera reescrita', 'unit UVentas;' in src, src[:80])
check('move rename: proyecto reapuntado', mc.es(out, 'SN_FILE_PROJECTS_UPDATED_FMT') and mc.ids(out).count(mc.id_de('SN_UNIT_RENAMED_FMT')) == 1, out)
dpr = rd(DPR)
check('move rename: uses nuevo con form', "UVentas in 'UVentas.pas' {FormUVenta}" in dpr and "UVenta in" not in dpr, dpr)
check('move rename: el // de la renombrada se queda con ella',
      "UVentas in 'UVentas.pas' {FormUVenta}, // la venta" in dpr, dpr)
check('move rename: CreateForm intacto (la clase no cambia)', 'CreateForm(TFormUVenta, FormUVenta)' in dpr, dpr)
xml = rd(DPROJ)
check('move rename: DCCReference nuevo, viejo fuera', 'Include="UVentas.pas"' in xml and 'Include="UVenta.pas"' not in xml, '')
usa_src = rd(usa)
check('move rename: el uses de OTRA unit sigue el rename', '  UVentas;' in usa_src and '  UVenta;' not in usa_src, usa_src)
check('move rename: el calificador UVenta.X sigue el rename', 'if UVentas.FormUVenta' in usa_src, usa_src)
check('move rename: dentro de una cadena NO se toca', "'UVenta.FormUVenta'" in usa_src, usa_src)
# una referencia detras de un comentario de llave con un apostrofo se quedaba
# sin renombrar (E2003) y el // que nombra la unit si se renombraba; ahora
# solo el CODIGO (sonda del lexico y David, 2-oct-2026)
check('move rename: la referencia detras de un comentario con apostrofo SI, el comentario NO',
      "{ it's } Result := UVentas.FormUVenta.Name; // de UVenta\r\n" in usa_src, usa_src)
check('move rename: la respuesta cuenta las referencias reescritas', mc.es(out, 'SN_UNIT_RENAMED_FMT'), out)
ok, err = build_ok(DPROJ)
check('build: tras rename COMPILA', ok, err)
# move into a subfolder keeps the name
out = call('delphi_move', {"path": os.path.join(VDIR, 'UOtra.pas'), "dest": os.path.join(sub, 'UOtra.pas')})
check('move a subcarpeta: MOVIDO + reapuntado', mc.abre(out, 'SK_MOVE_MOVIDO_FMT') and mc.es(out, 'SN_UNIT_RENAMED_FMT'), out[:300])
check('move a subcarpeta: sin renombrar no reescribe referencias (cuenta 0)', mc.es(out, 'SN_UNIT_RENAMED_FMT') and 'References rewritten: 0 in 0 file(s)' in out, out[:300])
check('move a subcarpeta: include relativo', "UOtra in 'src\\UOtra.pas'" in rd(DPR), rd(DPR))
out = call('delphi_move', {"path": os.path.join(VDIR, 'UUtil.pas'), "dest": os.path.join(VDIR, 'UUtil.txt')})
check('move unit a .txt rechazado', mc.rechazado(out) and mc.es(out, 'SR_MOVE_UNIT_SOLO_SE_MUEVE_FMT'), out)
out = call('delphi_move', {"path": os.path.join(VDIR, 'UUtil.pas'), "dest": os.path.join(VDIR, '2Mal.pas')})
check('move unit a identificador invalido rechazado', mc.rechazado(out) and mc.es(out, 'SR_FILE_IDENTIFICADOR_UNIT_FMT'), out)
# move HACIA la carpeta de un proyecto que vive DEBAJO de la unit: el .dpr/.dpk
# que la lista esta en el destino, no encima del origen (Hermes, 2026-09-23:
# la unit volvia a la carpeta de su paquete y la contains se quedaba vieja)
abajo = os.path.join(VDIR, 'abajo')
out = call('delphi_create', {"kind": "project-console", "dir": abajo, "name": "Abajo"})
check('move hacia abajo: proyecto creado', mc.abre(out, 'SK_CREATE_CREADO_PROYECTO_FMT'), out[:200])
arriba = os.path.join(VDIR, 'UArriba.pas')
open(arriba, 'wb').write(b"unit UArriba;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n")
out = call('delphi_config', {"project": os.path.join(abajo, 'Abajo.dproj'), "command": "add-unit", "path": arriba})
check('move hacia abajo: unit de ARRIBA registrada en el proyecto de abajo',
      mc.abre(out, 'SN_UNIT_ADDED_FMT') and "..\\UArriba.pas" in rd(os.path.join(abajo, 'Abajo.dpr')), out[:200])
out = call('delphi_move', {"path": arriba, "dest": os.path.join(abajo, 'UArriba.pas')})
check('move hacia abajo: REAPUNTADA (el proyecto vive en el destino, no encima del origen)',
      mc.abre(out, 'SK_MOVE_MOVIDO_FMT') and mc.es(out, 'SN_UNIT_RENAMED_FMT'), out[:300])
check('move hacia abajo: include nuevo sin ..\\', "UArriba in 'UArriba.pas'" in rd(os.path.join(abajo, 'Abajo.dpr')),
      rd(os.path.join(abajo, 'Abajo.dpr')))
ok, err = build_ok(DPROJ)
check('build: final COMPILA', ok, err)

# ---- frames and data modules (VCL project) ----
out = call('delphi_create', {"kind": "frame-vcl", "name": "UFrameLista", "project": DPR})
check('frame-vcl: CREADO frame', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and ' frame ' in out.split('\n')[0], out[:300])
src = rd(os.path.join(VDIR, 'UFrameLista.pas'))
check('frame-vcl: clase TFrameUFrameLista = class(TFrame)', 'TFrameUFrameLista = class(TFrame)' in src, src)
check('frame-vcl: sin variable global (como el IDE)', 'FrameUFrameLista: TFrameUFrameLista;' not in src, src)
dfm = rd(os.path.join(VDIR, 'UFrameLista.dfm'))
check('frame-vcl: dfm con TabOrder', dfm.startswith('object FrameUFrameLista: TFrameUFrameLista') and 'TabOrder = 0' in dfm, dfm)
dpr = rd(DPR)
check('frame-vcl: uses con {FrameUFrameLista: TFrame}', "UFrameLista in 'UFrameLista.pas' {FrameUFrameLista: TFrame}" in dpr, dpr)
check('frame-vcl: SIN CreateForm',
      "UFrameLista in 'UFrameLista.pas'" in dpr and 'CreateForm(TFrameUFrameLista' not in dpr, dpr)
xml = rd(DPROJ)
m = re.search(r'<DCCReference Include="UFrameLista.pas">\s*<Form>FrameUFrameLista</Form>\s*<FormType>dfm</FormType>\s*<DesignClass>TFrame</DesignClass>\s*</DCCReference>', xml)
check('frame-vcl: DCCReference con DesignClass TFrame', bool(m), xml[-1500:])

out = call('delphi_create', {"kind": "datamodule", "name": "UDatos", "project": DPR, "formname": "DMDatos"})
check('datamodule: CREADO data module', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and ' data module ' in out.split('\n')[0], out[:300])
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
check('move frame: reapuntado con DesignClass', mc.abre(out, 'SK_MOVE_MOVIDO_FMT') and mc.es(out, 'SN_UNIT_RENAMED_FMT'), out[:300])
dpr = rd(DPR)
check('move frame: uses nuevo {FrameUFrameLista: TFrame}', "UFrameListado in 'UFrameListado.pas' {FrameUFrameLista: TFrame}" in dpr, dpr)
check('move frame: sigue sin CreateForm',
      "UFrameListado in 'UFrameListado.pas'" in dpr and 'CreateForm(TFrameUFrameLista' not in dpr, dpr)
# delete the data module: CreateForm goes too
out = call('delphi_delete', {"path": os.path.join(VDIR, 'UDatos.pas')})
check('delete datamodule: BORRADO + proyecto', mc.abre(out, 'SK_FILE_BORRADO_PAPELERA_FMT') and mc.es(out, 'SN_FILE_PROJECTS_UPDATED_FMT') and mc.ids(out).count(mc.id_de('SN_UNIT_REMOVED_GONE_FMT')) == 1, out[:300])
dpr = rd(DPR)
check('delete datamodule: sin uses ni CreateForm', 'UDatos' not in dpr and 'DMDatos' not in dpr, dpr)
ok, err = build_ok(DPROJ)
check('build: tras frame rename + dm delete COMPILA', ok, err)

# ---- FMX project: frame-fmx, datamodule (FMX classgroup), form-fmx ----
FDIR = os.path.join(BASE, 'Movil')
FDPR = os.path.join(FDIR, 'Movil.dpr')
FDPROJ = os.path.join(FDIR, 'Movil.dproj')
out = call('delphi_create', {"kind": "project-fmx", "dir": FDIR, "name": "Movil"})
check('create: proyecto FMX', mc.abre(out, 'SK_CREATE_CREADO_PROYECTO_FMT'), out[:200])
out = call('delphi_create', {"kind": "frame-fmx", "name": "UFrameFicha", "project": FDPROJ})
check('frame-fmx: CREADO frame', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and ' frame ' in out.split('\n')[0], out[:300])
fmx = rd(os.path.join(FDIR, 'UFrameFicha.fmx'))
check('frame-fmx: fmx con Size.PlatformDefault', 'Size.PlatformDefault = False' in fmx, fmx)
check('frame-fmx: DCCReference FormType fmx + TFrame',
      re.search(r'Include="UFrameFicha.pas">\s*<Form>FrameUFrameFicha</Form>\s*<FormType>fmx</FormType>\s*<DesignClass>TFrame</DesignClass>', rd(FDPROJ)) is not None, rd(FDPROJ)[-1200:])
out = call('delphi_create', {"kind": "datamodule", "name": "UDM", "project": FDPROJ})
check('datamodule FMX: CREADO', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and ' data module ' in out.split('\n')[0], out[:200])
src = rd(os.path.join(FDIR, 'UDM.pas'))
check('datamodule FMX: CLASSGROUP FMX', "{%CLASSGROUP 'FMX.Controls.TControl'}" in src, src)
check('datamodule FMX: designer .dfm (no .fmx)', os.path.exists(os.path.join(FDIR, 'UDM.dfm')) and not os.path.exists(os.path.join(FDIR, 'UDM.fmx')), '')
check('datamodule FMX: DCCReference FormType dfm', re.search(r'Include="UDM.pas">\s*<Form>DMUDM</Form>\s*<FormType>dfm</FormType>\s*<DesignClass>TDataModule', rd(FDPROJ)) is not None, rd(FDPROJ)[-1200:])
out = call('delphi_create', {"kind": "form-fmx", "name": "USegunda", "project": FDPROJ})
check('form-fmx: CREADO', mc.abre(out, 'SK_CREATE_CREADO_FORM_FMT') and ' form ' in out.split('\n')[0], out[:200])
ok, err = build_ok(FDPROJ)
check('build: FMX con frame + datamodule + form COMPILA', ok, err)

# ---- v0.42.1: review fixes ----
# (2) comment/directive-aware uses parser
RDIR = os.path.join(BASE, 'Rev')
os.makedirs(RDIR, exist_ok=True)
RDPR = os.path.join(RDIR, 'Rev.dpr')
open(RDPR, 'wb').write(("{\r\n  header comment\r\n  uses nothing, really; honest\r\n}\r\n"
    "program Rev;\r\n\r\n{$APPTYPE CONSOLE}\r\n\r\nuses\r\n  System.SysUtils, // it's the RTL, see; below\r\n"
    "  {$IFDEF DEBUG}\r\n  UDebug in 'UDebug.pas',\r\n  {$ENDIF}\r\n  UMain in 'UMain.pas';\r\n\r\n"
    "begin\r\n  Writeln('hola');\r\nend.\r\n").encode('utf-8-sig'))
for u in ('UDebug', 'UMain', 'UNueva'):
    open(os.path.join(RDIR, u + '.pas'), 'wb').write(('unit %s;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n' % u).encode('utf-8-sig'))
out = call('delphi_config', {"project": RDPR, "command": "add-unit", "path": os.path.join(RDIR, 'UDebug.pas')})
check('parser: unit dentro de {$IFDEF} reconocida como presente', mc.es(out, 'SN_UNIT_PRESENT_FMT'), out[:200])
out = call('delphi_config', {"project": RDPR, "command": "add-unit", "path": os.path.join(RDIR, 'UNueva.pas')})
check('parser: add-unit con comentarios // y directivas', mc.abre(out, 'SN_UNIT_ADDED_FMT'), out[:200])
dpr = rd(RDPR)
check('parser: cabecera con "uses" en comentario intacta', dpr.startswith('{\r\n  header comment\r\n  uses nothing, really; honest\r\n}'), dpr[:80])
check('parser: program Rev; intacto', 'program Rev;' in dpr, dpr)
check('parser: comentario // intacto (sin "stuff" suelto)', "// it's the RTL, see; below" in dpr, dpr)
check('parser: {$IFDEF}/{$ENDIF} conservados', dpr.count('{$IFDEF DEBUG}') == 1 and dpr.count('{$ENDIF}') == 1, dpr)
check('parser: UNueva anadida una vez', dpr.count("UNueva in 'UNueva.pas'") == 1 and dpr.count('UDebug in') == 1, dpr)
out = call('delphi_config', {"project": RDPR})
units = {u['unit']: u for u in json.loads(out).get('units', [])}
check('parser: view sin blobs', set(units) == {'UDebug', 'UMain', 'UNueva'}, list(units))
out = call('delphi_config', {"project": RDPR, "command": "remove-unit", "path": os.path.join(RDIR, 'UDebug.pas')})
dpr = rd(RDPR)
check('parser: remove-unit dentro de IFDEF mantiene las directivas balanceadas',
      mc.abre(out, 'SN_UNIT_REMOVED_FMT') and 'UDebug' not in dpr and dpr.count('{$IFDEF DEBUG}') == 1 and dpr.count('{$ENDIF}') == 1, dpr)
check('parser: UMain sigue', "UMain in 'UMain.pas'" in dpr, dpr)

# (3) qualified ancestor + suffix heuristics
open(os.path.join(VDIR, 'UPanel.pas'), 'wb').write(("unit UPanel;\r\n\r\ninterface\r\n\r\nuses\r\n  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,\r\n"
    "  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs;\r\n\r\ntype\r\n  TFramePanel = class(Vcl.Forms.TFrame)\r\n  private\r\n  public\r\n  end;\r\n\r\n"
    "implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n").encode('utf-8-sig'))
open(os.path.join(VDIR, 'UPanel.dfm'), 'wb').write(b'object FramePanel: TFramePanel\r\n  Left = 0\r\n  Top = 0\r\n  Width = 320\r\n  Height = 240\r\n  TabOrder = 0\r\nend\r\n')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'UPanel.pas')})
dpr = rd(DPR)
check('ancestro cualificado: frame sin CreateForm', mc.abre(out, 'SN_UNIT_ADDED_FORM_FMT') and 'CreateForm(TFramePanel' not in dpr, out[:200] + dpr)
check('ancestro cualificado: {FramePanel: TFrame} + DesignClass', '{FramePanel: TFrame}' in dpr and '<DesignClass>TFrame</DesignClass>' in rd(DPROJ), dpr)
open(os.path.join(VDIR, 'UHost.pas'), 'wb').write(("unit UHost;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms;\r\n\r\ntype\r\n  TMainframeForm = class(TForm)\r\n  end;\r\n  TFormHost = class(TMainframeForm)\r\n  end;\r\n\r\nvar\r\n  FormHost: TFormHost;\r\n\r\nimplementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n").encode('utf-8-sig'))
open(os.path.join(VDIR, 'UHost.dfm'), 'wb').write(b'object FormHost: TFormHost\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 100\r\n  ClientWidth = 100\r\nend\r\n')
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'UHost.pas')})
dpr = rd(DPR)
check('ancestro "Mainframe": es un form (CreateForm, sin DesignClass)', 'CreateForm(TFormHost, FormHost)' in dpr and '{FormHost}' in dpr, dpr)
ok, err = build_ok(DPROJ)
check('build: frame cualificado + form heredado COMPILAN', ok, err)

# (5) CreateForm right before Application.Run even with an {$IFDEF} CreateForm
dpr = rd(DPR).replace('  Application.CreateForm(TFormHost, FormHost);\r\n', '')
dpr = dpr.replace('  Application.Run;', '{$IFDEF DEBUG}\r\n  Application.CreateForm(TFormHost, FormHost);\r\n{$ENDIF}\r\n  Application.Run;')
open(DPR, 'wb').write(dpr.encode('utf-8-sig'))
out = call('delphi_create', {"kind": "form-vcl", "name": "UTardia", "project": DPR})
dpr = rd(DPR)
i_new = dpr.index('CreateForm(TFormUTardia'); i_endif = dpr.index('{$ENDIF}'); i_run = dpr.index('Application.Run')
check('CreateForm: fuera del {$IFDEF}, justo antes de Application.Run', i_endif < i_new < i_run, dpr)

# (6) out-of-tree unit -> ..\ relative include
SH = os.path.join(BASE, 'shared')
os.makedirs(SH, exist_ok=True)
open(os.path.join(SH, 'UCommon.pas'), 'wb').write('unit UCommon;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(SH, 'UCommon.pas')})
dpr = rd(DPR)
check('fuera del arbol: include relativo ..\\shared', "UCommon in '..\\shared\\UCommon.pas'" in dpr, dpr)
check('fuera del arbol: DCCReference relativo', 'Include="..\\shared\\UCommon.pas"' in rd(DPROJ), '')
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": os.path.join(SH, 'UCommon.pas')})
check('fuera del arbol: remove limpia .dpr y .dproj', 'UCommon' not in rd(DPR) and 'UCommon' not in rd(DPROJ), out[:200])

# (7) present by name from another path -> no second DCCReference
os.makedirs(os.path.join(VDIR, 'old'), exist_ok=True)
open(os.path.join(VDIR, 'old', 'UUtil.pas'), 'wb').write('unit UUtil;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n'.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "add-unit", "path": os.path.join(VDIR, 'old', 'UUtil.pas')})
check('presente por nombre: sin DCCReference duplicado', mc.es(out, 'SN_UNIT_PRESENT_FMT') and rd(DPROJ).count('UUtil.pas"') == 1 and 'old\\UUtil' not in rd(DPROJ), rd(DPROJ)[-800:])

# (8) remove by class, not by variable name alone
dpr = rd(DPR).replace('  Application.Run;', '  Application.CreateForm(TSplashMain, FormHost);\r\n  Application.Run;')
open(DPR, 'wb').write(dpr.encode('utf-8-sig'))
out = call('delphi_config', {"project": DPROJ, "command": "remove-unit", "path": os.path.join(VDIR, 'UHost.pas')})
dpr = rd(DPR)
check('remove por clase: CreateForm de otra unit con la misma variable sobrevive',
      'CreateForm(TFormHost' not in dpr and 'CreateForm(TSplashMain, FormHost)' in dpr, dpr)
dpr = rd(DPR).replace('  Application.CreateForm(TSplashMain, FormHost);\r\n', '')
open(DPR, 'wb').write(dpr.encode('utf-8-sig'))

# (1) a project in the parent folder INSIDE the jail is still handled (BASE is the
# root here); the outside-jail refusal text is exercised by the guard path
PDPR = os.path.join(VDIR, 'Padre.dpr')
open(PDPR, 'wb').write(("program Padre;\r\n\r\n{$APPTYPE CONSOLE}\r\n\r\nuses\r\n  System.SysUtils,\r\n  UOtra in 'src\\UOtra.pas';\r\n\r\nbegin\r\nend.\r\n").encode('utf-8-sig'))
out = call('delphi_delete', {"path": os.path.join(sub, 'UOtra.pas')})
check('padre dentro de la jaula: proyectos actualizados (2)', mc.es(out, 'SN_FILE_PROJECTS_UPDATED_FMT') and mc.ids(out).count(mc.id_de('SN_UNIT_REMOVED_GONE_FMT')) == 2, out[:400])
check('padre dentro de la jaula: Padre.dpr limpio', 'UOtra' not in rd(PDPR), rd(PDPR))
ok, err = build_ok(DPROJ)
check('build: tras las correcciones COMPILA', ok, err)

# ---- delete of a plain (non-unit) file untouched by all this ----
txt = os.path.join(VDIR, 'notas.txt')
open(txt, 'wb').write(b'x')
out = call('delphi_delete', {"path": txt})
check('delete fichero normal: sin notas de proyecto', mc.abre(out, 'SK_FILE_BORRADO_PAPELERA_FMT') and not mc.es(out, 'SN_FILE_PROJECTS_UPDATED_FMT') and not mc.es(out, 'SN_FILE_PROJECTS_NONE'), out)

print()
# ---- delphi_move copy=true: the same door, a different last step (1.2.2) ----
cdir = os.path.join(BASE, 'Copia')
os.makedirs(os.path.join(cdir, mc.PAPELERA, 'x'), exist_ok=True)
open(os.path.join(cdir, 'UOrig.pas'), 'wb').write(b'unit UOrig;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
open(os.path.join(cdir, 'UOrig.dfm'), 'wb').write(b'object FormOrig: TFormOrig\r\nend\r\n')
out = call('delphi_move', {"path": os.path.join(cdir, 'UOrig.pas'), "dest": os.path.join(cdir, 'UCopia.pas'), "copy": True})
check('copy unit: COPIADO y el origen sigue', mc.abre(out, 'SK_MOVE_COPIADO_FMT') and os.path.exists(os.path.join(cdir, 'UOrig.pas')), out[:300])
check('copy unit: cabecera de la copia reescrita', 'unit UCopia;' in rd(os.path.join(cdir, 'UCopia.pas')) and 'unit UOrig;' in rd(os.path.join(cdir, 'UOrig.pas')), out[:300])
check('copy unit: designer copiado, el original sigue', os.path.exists(os.path.join(cdir, 'UCopia.dfm')) and os.path.exists(os.path.join(cdir, 'UOrig.dfm')) and mc.es(out, 'SN_FILE_DESIGNER_TOO_FMT') and mc.catalogo()['SF_MOVE_COPIADO_CON_UNIT'] in out, out[:300])
check('copy unit: ningun proyecto reapuntado, y la respuesta lo dice', not mc.es(out, 'SN_UNIT_RENAMED_FMT') and mc.es(out, 'SN_FILE_COPY_NO_PROJECT') and 'add-unit' in out and not mc.es(out, 'SN_FILE_COPIA_SEGURIDAD_EN_FMT'), out[:400])
out = call('delphi_move', {"path": cdir, "dest": os.path.join(BASE, 'Copia2'), "copy": True})
check('copy carpeta: COPIADO, las dos existen, sin la papelera del origen', mc.abre(out, 'SK_MOVE_COPIADO_FMT') and os.path.exists(os.path.join(BASE, 'Copia2', 'UCopia.pas')) and os.path.isdir(cdir) and not os.path.isdir(os.path.join(BASE, 'Copia2', mc.PAPELERA)), out[:300])
out = call('delphi_move', {"path": VDIR, "dest": os.path.join(BASE, 'AppCopia'), "copy": True})
check('copy carpeta con .dproj: RECHAZADO (un proyecto nunca en dos sitios)', mc.rechazado(out) and mc.es(out, 'SR_MOVE_COPY_PROJECT_FMT') and not os.path.exists(os.path.join(BASE, 'AppCopia')), out[:300])
out = call('delphi_move', {"path": os.path.join(cdir, 'UOrig.pas'), "dest": os.path.join(cdir, 'UCopia.pas'), "copy": True})
check('copy sobre destino existente: RECHAZADO, no sobreescribe', mc.rechazado(out) and mc.es(out, 'SR_FILE_DESTINO_YA_EXISTE_FMT'), out[:200])

# ---- the destination of a move never lands in a dead folder (25-sep-2026,
# approved by David): temp, __history and trash are refused; moving OUT of
# them (restore, keep a capture) is the source and stays free. ----
mdir = os.path.join(BASE, 'MoveMuerto')
os.makedirs(os.path.join(mdir, '__delphi-temp'), exist_ok=True)
open(os.path.join(mdir, 'a.txt'), 'w').write('x')
open(os.path.join(mdir, '__delphi-temp', 'b.txt'), 'w').write('y')
out = call('delphi_move', {"path": os.path.join(mdir, 'a.txt'), "dest": os.path.join(mdir, '__delphi-temp', 'a.txt')})
check('move HACIA __delphi-temp: RECHAZADO, el origen sigue', mc.rechazado(out) and mc.es(out, 'SR_GUARD_DEAD_TEMP') and os.path.exists(os.path.join(mdir, 'a.txt')), out[:200])
out = call('delphi_move', {"path": os.path.join(mdir, 'a.txt'), "dest": os.path.join(mdir, '__history', 'a.txt')})
check('move HACIA __history: RECHAZADO', mc.rechazado(out) and mc.es(out, 'SR_GUARD_DEAD_IDE'), out[:200])
out = call('delphi_move', {"path": os.path.join(mdir, '__delphi-temp', 'b.txt'), "dest": os.path.join(mdir, 'b.txt')})
check('move DESDE __delphi-temp a una carpeta normal: permitido', mc.abre(out, 'SK_MOVE_MOVIDO_FMT') and os.path.exists(os.path.join(mdir, 'b.txt')), out[:200])

srv.cierra()
mc.fin('project units battery')
