"""E2E battery - EL lector de clases (Lsp.PascalDecl.LeeFuentePascal), 4-oct-2026.

Six places of the server read classes line by line, each with its own regex
and its own idea of where a class ends (the first 'end;', or counting
depth): check-binding, insert=metodo, the class of a method and the
inheritance map of delphi_references, the ancestor chain of add-unit, the
owner of each member in the folder digest of delphi_symbols. A nested
record, a nested type with its own 'public', a class written on one line
or a method of the same name in a nested type fooled them. They all read
the token reader now, and the ancestor chain is ONE (CadenaDeAncestros).
What each check measures, through the real server (every one of them was
seen red against the line readers, the 1.12.1 exe):

  C1  insert=metodo visibility=public goes to the class's public, not to the
      public of a nested type declared before it
  C2  insert=metodo into a NESTED class qualifies the implementation with
      its whole name (TOuter.TInner.X), and the project compiles
  C3  a class that opens and closes on one line: EDIT-120, nothing written
  C4  a method of the same name in a nested type is not "already declared"
      in the outer class: both halves are written and it compiles
  C5  check-binding: a nested record does not end the form class (its later
      published field and method were "missing")
  C6  folder digest: the members after a nested record keep their owner
  C7  references: a call that resolves to an override declared after a
      nested type whose 'end;' is at four spaces (an abstract override:
      the definition is the declaration in the class) is the same method,
      not a homonym. With an implementation the line reader was rescued by
      the qualified 'procedure THija.Pinta;' (measured: the first version of
      this check passed against the 1.12.1 exe; an abstract BASE does not
      resolve at all, LSP-003)
  C8  ONE list of routine directives (Lsp.Pascal): insert=metodo did not
      know noreturn, and left it on the implementation

Usage:  python tests/test_lector_clases.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('lector_clases')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='lector', t=300)
call = srv.call
J = mc.como_json
rd = mc.lee


def build_ok(dproj):
    return mc.build_ok(call, dproj)


def escribe(ruta, texto):
    open(ruta, 'w', encoding='utf-8-sig', newline='\r\n').write(texto)


print('== lector-clases battery ==')
PRJ = os.path.join(BASE, 'Lector')
DPR = os.path.join(PRJ, 'Lector.dpr')
DPROJ = os.path.join(PRJ, 'Lector.dproj')
r = call('delphi_create', {'kind': 'project-console', 'name': 'Lector', 'dir': PRJ})
assert mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r

# ---- C1 / C2 / C4: una clase con un tipo anidado ----
r = call('delphi_create', {'kind': 'unit', 'name': 'UAnidada', 'project': DPR})
UANI = os.path.join(PRJ, 'UAnidada.pas')
escribe(UANI, """unit UAnidada;

interface

type
  TOuter = class
  private
    type
      TInner = class
      public
        procedure DeDentro;
        procedure Hola;
      end;
  public
    procedure DeFuera;
  end;

implementation

procedure TOuter.TInner.DeDentro;
begin
end;

procedure TOuter.TInner.Hola;
begin
end;

procedure TOuter.DeFuera;
begin
end;

end.
""")
r = call('delphi_edit', {'path': UANI, 'insert': 'metodo', 'inclass': 'TOuter', 'visibility': 'public',
                         'code': 'procedure Nuevo;\nbegin\nend;'})
u = rd(UANI)
interno = u[u.index('TInner = class'):u.index('  public\r\n    procedure DeFuera;')]
check('C1 visibility=public: en el public de LA clase, no en el del tipo anidado',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and
      u.index('procedure DeFuera;') < u.index('procedure Nuevo;') < u.index('implementation') and
      'Nuevo' not in interno, r[:300] + ' | ' + u[:700])
r = call('delphi_edit', {'path': UANI, 'insert': 'metodo', 'inclass': 'TInner',
                         'code': 'procedure Otro;\nbegin\nend;'})
u = rd(UANI)
check('C2 insert en una clase ANIDADA: la implementacion con su nombre completo',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure TOuter.TInner.Otro;' in u,
      r[:300] + ' | ' + u[-500:])
r = call('delphi_edit', {'path': UANI, 'insert': 'metodo', 'inclass': 'TOuter',
                         'code': 'procedure Hola;\nbegin\nend;'})
u = rd(UANI)
check('C4 un metodo que se llama como uno de la anidada: las DOS mitades en la de fuera',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure TOuter.Hola;' in u and
      u.count('procedure Hola;') == 2, r[:300] + ' | ' + u[:800])
ok, err = build_ok(DPROJ)
check('C2b/C4b ...y el proyecto COMPILA', ok, err)

# ---- C3: la clase de una linea ----
r = call('delphi_create', {'kind': 'unit', 'name': 'UUnaLinea', 'project': DPR})
UUNA = os.path.join(PRJ, 'UUnaLinea.pas')
escribe(UUNA, """unit UUnaLinea;

interface

type
  TUna = class(TObject) end;
  TOtra = class
  public
    procedure X;
  end;

implementation

procedure TOtra.X;
begin
end;

end.
""")
antes = open(UUNA, 'rb').read()
r = call('delphi_edit', {'path': UUNA, 'insert': 'metodo', 'inclass': 'TUna',
                         'code': 'procedure Y;\nbegin\nend;'})
check('C3 una clase de una linea: rechazado (EDIT-120) y nada escrito',
      mc.rechazado(r) and mc.es(r, 'SR_EDIT_CLASE_EN_UNA_LINEA_FMT') and open(UUNA, 'rb').read() == antes,
      r[:300])

# ---- C5: check-binding con un record anidado en la clase del form ----
FP = os.path.join(PRJ, 'UFormRec.pas')
escribe(FP, """unit UFormRec;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, System.Classes;

type
  TFormRec = class(TForm)
    lblUno: TLabel;
  private
    type
      TReg = record
        A: Integer;
      end;
  published
    lblTarde: TLabel;
    procedure lblTardeClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TFormRec.lblTardeClick(Sender: TObject);
begin
end;

end.
""")
FD = os.path.join(PRJ, 'UFormRec.dfm')
escribe(FD, """object FormRec: TFormRec
  object lblUno: TLabel
  end
  object lblTarde: TLabel
    OnClick = lblTardeClick
  end
end
""")
d = J(call('delphi_designer', {'command': 'check-binding', 'path': FD}))
check('C5 check-binding: un record anidado no cierra la clase del form',
      d.get('clean') is True and not d.get('componentsWithoutField') and not d.get('eventsWithoutMethod'),
      str(d)[:500])

# ---- C6: el resumen de carpeta, detras de un record anidado ----
DIG = os.path.join(BASE, 'Dig')
os.makedirs(DIG, exist_ok=True)
escribe(os.path.join(DIG, 'UDig2.pas'), """unit UDig2;

interface

type
  TCosa2 = class
  private
    type
      TR = record
        A: Integer;
      end;
  public
    procedure Despues;
  end;

implementation

procedure TCosa2.Despues;
begin
end;

end.
""")
d = J(call('delphi_symbols', {'path': DIG}))
decl = {x.get('decl'): x.get('of', '') for u_ in d.get('units', []) for x in u_.get('declares', [])}
check('C6 digest: lo de detras de un record anidado sigue siendo de su clase',
      decl.get('procedure Despues;') == 'TCosa2' and decl.get('A: Integer;') == 'TCosa2.TR', str(decl)[:400])

# ---- C7: references, el override detras de un tipo anidado ----
r = call('delphi_create', {'kind': 'unit', 'name': 'UFam', 'project': DPR})
UFAM = os.path.join(PRJ, 'UFam.pas')
FAM = """unit UFam;

interface

type
  TBase = class
  public
    procedure Pinta; virtual;
  end;

  THija = class(TBase)
  private type
    TReg = record
      A: Integer;
    end;
  public
    procedure Pinta; override; abstract;
  end;

procedure Usa(H: THija);

implementation

procedure TBase.Pinta;
begin
end;

procedure Usa(H: THija);
begin
  H.Pinta;
end;

end.
"""
escribe(UFAM, FAM)
ok, err = build_ok(DPROJ)
check('C7a el proyecto con la familia compila', ok, err)
lineas = FAM.split('\n')
base = next(i for i, l in enumerate(lineas) if l.strip() == 'procedure Pinta; virtual;')
j = J(call('delphi_references', {'path': UFAM, 'line': base,
                                 'character': lineas[base].index('Pinta') + 1}))
llamada = [c for c in j.get('confirmed', []) if 'H.Pinta' in c.get('text', '')]
check('C7 references: la llamada a un override de detras de un tipo anidado es el mismo metodo (via override)',
      len(llamada) == 1 and llamada[0].get('via') == 'override' and
      not any('H.Pinta' in c.get('text', '') for c in j.get('rejected', [])), str(j)[:600])

# ---- C8: la lista UNICA de directivas de rutina ----
r = call('delphi_create', {'kind': 'unit', 'name': 'UDirectiva', 'project': DPR})
UDIR = os.path.join(PRJ, 'UDirectiva.pas')
escribe(UDIR, """unit UDirectiva;

interface

uses
  System.SysUtils;

type
  TDir = class
  public
    procedure Base;
  end;

implementation

procedure TDir.Base;
begin
end;

end.
""")
r = call('delphi_edit', {'path': UDIR, 'insert': 'metodo', 'inclass': 'TDir',
                         'code': "procedure Fallar; noreturn;\nbegin\n  raise Exception.Create('x');\nend;"})
u = rd(UDIR)
clase = u[:u.index('implementation')]
impl = u[u.index('implementation'):]
check('C8 noreturn es una directiva: va con la declaracion, no con la implementacion',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure Fallar; noreturn;' in clase and
      'procedure TDir.Fallar;' in impl and 'noreturn' not in impl, r[:300] + ' | ' + u)
ok, err = build_ok(DPROJ)
check('C8b ...y el proyecto COMPILA', ok, err)

srv.cierra()
mc.fin('lector-clases battery')
