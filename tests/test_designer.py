"""E2E battery for v0.52.0-beta - delphi_designer phase 1 (read + lint):
class metadata from the designer tables (since 1.12.0 read from the source
of the active Delphi, Lsp.DesignerMetaGen), component tree of text
designers, one component's block, and the designer lint on demand.

Usage:  python tests/test_designer.py [path-to-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer')
EXE = mc.copia_exe(BASE)

env = mc.entorno({'DELPHI_MCP_ROOTS': BASE})
srv = mc.Stdio(EXE, env, nombre='dg')
call = srv.call

def J(t):
    try: return json.loads(t)
    except Exception: return {}

# ---- fixtures: a hand-made VCL dfm (valid + broken bits) and a binary one
DFM = os.path.join(BASE, 'Main.dfm')
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormMain: TFormMain
  Caption = 'Prueba'
  ClientHeight = 300
  object PanelTop: TPanel
    Align = alTop
    Caption = 'panel'
    object BotonUno: TButton
      Caption = 'Uno'
      TabOrder = 0
    end
  end
  object EditNombre: TEdit
    Text = 'hola'
  end
end
""")
BAD = os.path.join(BASE, 'Roto.dfm')
open(BAD, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormRoto: TFormRoto
  object B1: TButton
    Caption = 'x'
    Alineacion = alTop
    Align = alMarte
  end
  object Raro: TClaseInventada
    Color = clRed
  end
  object ImagenesLista: TImageList
    Left = 320
    Top = 200
  end
end
""")
BIN = os.path.join(BASE, 'Bin.dfm')
open(BIN, 'wb').write(b'TPF0\x08TFormBin\x00')
# The REAL on-disk shape of a binary .dfm is NOT a raw TPF0 stream: the IDE
# wraps it in a 16-bit resource header starting $FF (FF 0A 00 + the UPPERCASED
# form name + the TPF0 stream around offset 19). Measured 2026-08-25: the write
# layer refused both shapes, but delphi_designer only knew TPF0 - so lint, tree
# and check-binding happily parsed the commonest binary form as if it were
# text. Lint answering about garbage is worse than lint refusing.
RESBIN = os.path.join(BASE, 'ResBin.dfm')
open(RESBIN, 'wb').write(b'\xff\x0a\x00FORMBIN\x00\x00\x00\x00'
                         b'TPF0\x08TFormBin\x00')

# ---- info ----
j = J(call('delphi_designer', {'command': 'info', 'class': 'TButton', 'framework': 'vcl'}))
props = [p['name'] for p in j.get('properties', [])]
check('info TButton (VCL): Caption y TabOrder publicados', 'Caption' in props and 'TabOrder' in props, str(j)[:250])
check('info: eventos aparte (OnClick)', any('OnClick' in e for e in j.get('events', [])), str(j.get('events'))[:200])
j = J(call('delphi_designer', {'command': 'info', 'class': 'TButton', 'framework': 'vcl', 'filter': 'Cap'}))
check('info con filter acota', j.get('total', 99) <= 3 and any(p['name'] == 'Caption' for p in j.get('properties', [])), str(j)[:200])
# un filtro que no casa con nada lo DICE (DSGN-048): total:0 a secas se leia como
# un fallo de RTTI (Hermes, 28-sep-2026: TLabel FMX con filter=Font)
j = J(call('delphi_designer', {'command': 'info', 'class': 'TLabel', 'framework': 'fmx', 'filter': 'Font'}))
check('info con filter sin resultado: total 0 y la pista DSGN-048 (no es un fallo de RTTI)',
      j.get('total') == 0 and mc.es(j.get('hint', ''), 'SN_DESIGNER_INFO_FILTRO_VACIO_FMT') and 'TextSettings' in j.get('hint', ''),
      str(j)[:250])
j = J(call('delphi_designer', {'command': 'info', 'class': 'TButton', 'framework': 'vcl', 'filter': 'Colour'}))
check('info VCL con filter sin resultado: DSGN-048 sin la coda FMX de TextSettings (salia siempre)',
      j.get('total') == 0 and mc.es(j.get('hint', ''), 'SN_DESIGNER_INFO_FILTRO_VACIO_FMT') and 'TextSettings' not in j.get('hint', ''),
      str(j)[:250])
r = call('delphi_designer', {'command': 'prop', 'class': 'TButton', 'framework': 'vcl', 'prop': 'Caption', 'filter': 'x'})
check('prop con filter: DSGN-047 nombra classname, el parametro real (decia class)',
      mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_NO_VA_CON_COMANDO_FMT') and 'classname' in r, r[:200])
r = call('delphi_designer', {'command': 'info', 'class': 'TClaseInventada', 'framework': 'vcl'})
# el rechazo CONCRETO de la tabla de clases, no uno cualquiera
check('info clase desconocida rechazada',
      mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_CLASS_FMT') and '"TClaseInventada"' in r and 'VCL' in r, r[:150])
j = J(call('delphi_designer', {'command': 'info', 'class': 'TLayout', 'framework': 'fmx'}))
check('info FMX (TLayout)', j.get('class') == 'TLayout' and j.get('framework') == 'FMX', str(j)[:150])

# ---- prop ----
j = J(call('delphi_designer', {'command': 'prop', 'class': 'TPanel', 'prop': 'Align', 'framework': 'vcl'}))
check('prop TPanel.Align: enum con miembros', j.get('kind') == 'enum' and 'alTop' in (j.get('members') or ''), str(j)[:250])
r = call('delphi_designer', {'command': 'prop', 'class': 'TPanel', 'prop': 'NoExiste', 'framework': 'vcl'})
check('prop inexistente rechazada con pista',
      mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_PROP_FMT') and 'info' in r, r[:200])

# ---- tree ----
j = J(call('delphi_designer', {'command': 'tree', 'path': DFM}))
root = j.get('root') or {}
kids = root.get('children', [])
check('tree: raiz FormMain', root.get('name') == 'FormMain' and root.get('class') == 'TFormMain', str(root)[:200])
check('tree: jerarquia (Panel con Button dentro)',
      any(k.get('name') == 'PanelTop' and any(g.get('name') == 'BotonUno' for g in k.get('children', [])) for k in kids), str(kids)[:300])
check('tree: lineas 1-based', root.get('line') == 1, root.get('line'))

# ---- get ----
r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'BotonUno'})
check('get: bloque del componente', 'BotonUno (TButton)' in r and "Caption = 'Uno'" in r, r[:250])
r = call('delphi_designer', {'command': 'get', 'path': DFM, 'component': 'NoEsta'})
# el form SI se leyo y el componente no esta en el (no un fichero ilegible)
check('get: componente inexistente',
      mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_COMPONENT_FMT') and '"NoEsta"' in r, r[:150])

# ---- lint ----
r = call('delphi_designer', {'command': 'lint', 'path': DFM})
check('lint limpio en el form bueno', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:200])
r = call('delphi_designer', {'command': 'lint', 'path': BAD})
# una clase DESCONOCIDA no es aviso: los componentes de terceros no estan en
# las tablas y son legitimos; sus propiedades simplemente no se comprueban
# los negativos del lint exigen que el lint HAYA CORRIDO sobre ese fichero
# (su cabecera de avisos): un timeout o un error tampoco nombran clRed
check('lint NO inventa avisos dentro de la clase desconocida',
      mc.abre(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Roto.dfm' in r and 'clRed' not in r and 'Color' not in r, r[:400])
check('lint pilla la propiedad no publicada', 'Alineacion' in r, r[:400])
check('lint pilla el valor de enum inexistente', 'alMarte' in r, r[:400])
# field report 2026-08-24: Left/Top on non-visual components are the form
# designer's own placement - the IDE writes them in every form with a
# TImageList/TPopupMenu and no class publishes them: pure noise
check('lint NO avisa de Left/Top de componentes no visuales',
      mc.abre(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'Roto.dfm' in r and '"Left"' not in r and '"Top"' not in r, r[:400])

# ---- doctrina ----
r = call('delphi_designer', {'command': 'tree', 'path': BIN})
check('designer binario (TPF0) rechazado',
      mc.abre(r, 'SR_DSGN_BINARIO_DANADO_FMT'), r[:200])
for cmd in ('tree', 'get', 'lint', 'check-binding'):
    args = {'command': cmd, 'path': RESBIN}
    if cmd == 'get':
        args['component'] = 'X'
    r = call('delphi_designer', args)
    check('binario envuelto en recurso ($FF) rechazado por ' + cmd + ' (el mismo mensaje en todos)',
          mc.abre(r, 'SR_DSGN_BINARIO_DANADO_FMT'), r[:200])
r = call('delphi_designer', {'command': 'tree', 'path': os.path.join(BASE, 'nx.dfm')})
check('fichero inexistente',
      mc.resultado(r) == 'NOT_FOUND' and mc.es(r, 'SR_NO_EXISTE_FMT') and 'nx.dfm' in r, r[:150])
r = call('delphi_designer', {'command': 'tree', 'path': 'C:\\Windows\\win.ini'})
# la puerta que para esta ruta es la JAULA (win.ini esta fuera de las raices)
check('fuera de jaula / no designer rechazado',
      mc.rechazado(r) and mc.es(r, 'SR_JAIL_FMT'), r[:150])
r = call('delphi_designer', {'command': 'volar'})
check('comando invalido', mc.es(r, 'SR_DESIGNER_CMD') and not mc.sin_respuesta(r), r[:120])

# ---- eventos por nombre contra el .pas pareja, en lint, al ESCRIBIR y en insert=metodo ----
# hermes 25-sep-2026: OnClick = btnHelpClick con el handler en public (insert=metodo
# sin visibility lo deja al final de la clase): build verde, "Invalid property value"
# al cargar el form en Zorin. check-binding ya lo sabia; nadie lo llamaba.
EVP = os.path.join(BASE, 'UEv.pas')
EV = os.path.join(BASE, 'UEv.dfm')
open(EVP, 'w', encoding='utf-8', newline='\r\n').write(
"""unit UEv;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TFormEv = class(TForm)
    btnOk: TButton;
    btnHelp: TButton;
    btnNada: TButton;
    procedure btnOkClick(Sender: TObject);
  private
    procedure btnHelpClick(Sender: TObject);
  public
    { Public declarations }
  end;

implementation

{$R *.dfm}

procedure TFormEv.btnOkClick(Sender: TObject);
begin
end;

procedure TFormEv.btnHelpClick(Sender: TObject);
begin
end;

end.
""")
open(EV, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormEv: TFormEv
  Caption = 'Ev'
  object btnOk: TButton
    Caption = 'Ok'
    OnClick = btnOkClick
  end
  object btnHelp: TButton
    Caption = '?'
    OnClick = btnHelpClick
  end
  object btnNada: TButton
    Caption = 'x'
    OnClick = btnNadaClick
  end
end
""")
r = call('delphi_designer', {'command': 'lint', 'path': EV})
check('lint: el handler en private se avisa (el cargador solo ve published)', 'btnHelpClick' in r and 'is NOT in published' in r, r[:600])
check('lint: el handler inexistente se avisa', 'btnNadaClick' in r and 'is not declared' in r, r[:600])
check('lint: el handler published NO se avisa',
      mc.abre(r, 'SN_DESIGNER_LINT_BAD_FMT') and 'UEv.dfm' in r and 'btnOkClick' not in r, r[:600])
r = call('delphi_edit', {'path': EV, 'old': "    Caption = '?'", 'new': "    Caption = 'Ayuda'"})
check('ESCRIBIR el designer avisa al momento del evento no resoluble', mc.abre(r, 'SK_EDIT_ESCRITO_EN_FMT') and 'btnHelpClick' in r and mc.es(r, 'SN_DESIGNER_BINDING_LINT_HEADER'), r[:700])
r = call('delphi_edit', {'path': EVP, 'insert': 'metodo', 'inclass': 'TFormEv', 'code': 'procedure btnNadaClick(Sender: TObject);\nbegin\nend;'})
src = open(EVP, encoding='utf-8').read()
check('insert=metodo sin visibility + evento cableado en el designer -> published, y lo dice', mc.es(r, 'SN_PATCH_INSERT_PUBLISHED_BY_EVENT_FMT') and src.index('procedure btnNadaClick') < src.index('  private'), r[:500])
r = call('delphi_designer', {'command': 'lint', 'path': EV})
check('tras el insert, el lint ya no avisa de btnNadaClick (y sigue avisando de btnHelpClick)', 'btnNadaClick' not in r and 'btnHelpClick' in r, r[:500])
r = call('delphi_designer', {'command': 'lint', 'path': DFM})
check('lint de un designer SIN .pas pareja sigue limpio (no hay contra que comparar)', mc.abre(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:200])

r = call('delphi_designer', {'command': 'totext', 'path': BIN})
# aceptado = llego al conversor (el BIN de prueba esta danado: lo dice el)
check('to-text sin guion (totext) se acepta como alias: no es "comando invalido"',
      not mc.es(r, 'SR_DESIGNER_CMD') and 'could not convert it to text' in r, r[:200])

srv.mata()
mc.fin('designer battery')
