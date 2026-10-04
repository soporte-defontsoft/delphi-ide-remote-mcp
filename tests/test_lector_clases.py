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

And what the review of 1.13.0 found in the reader itself:

  C9  a class helper has methods: insert=metodo found it with the old regex
      and not with the reader (it skipped the helper whole)
  C10 a generic class qualifies its implementation with its parameters
      (TCaja<T>.X; TCaja.X does not compile) and sees the one already there
  C11 an interposer class (TBaseInter = class(UBaseInter.TBaseInter)) is
      not a cycle: check-binding called the inherited components missing
  C12 a class header repeated in the two branches of an IFDEF is not a
      nested type: everything after it was nested in it
  C13 a routine body repeated in the two branches is not the main block:
      the implementation classes after it were gone
  C14 the header of a generic class is a header: missing from the digest,
      and its first field glued to it by symbols filter
  C15 the fields of a 'class var' are class fields (the record said so and
      nobody set it): a component with only a class var has no field

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

# ---- C9..C14: lo que dejo la revision de la 1.13.0 ----
def unidad(nombre, texto):
    call('delphi_create', {'kind': 'unit', 'name': nombre, 'project': DPR})
    ruta = os.path.join(PRJ, nombre + '.pas')
    escribe(ruta, texto)
    return ruta


# C9: un class helper tiene metodos (el lector lo saltaba y insert no lo veia)
UAYU = unidad('UAyuda', """unit UAyuda;

interface

uses
  System.Classes;

type
  TListaAyuda = class helper for TStringList
  public
    function Cuantas: Integer;
  end;

implementation

function TListaAyuda.Cuantas: Integer;
begin
  Result := Count;
end;

end.
""")
r = call('delphi_edit', {'path': UAYU, 'insert': 'metodo', 'inclass': 'TListaAyuda',
                         'code': 'function Vacia: Boolean;\nbegin\n  Result := Count = 0;\nend;'})
u = rd(UAYU)
check('C9 insert=metodo en un class helper: las dos mitades',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'function TListaAyuda.Vacia: Boolean;' in u,
      r[:300] + ' | ' + u[-400:])

# C10: una clase generica se cualifica con sus parametros (TCaja.X no compila)
UCAJA = unidad('UCaja', """unit UCaja;

interface

type
  TCaja<T: class, constructor> = class(TObject)
  private
    FValor: T;
  public
    procedure Pon(const AValor: T);
  end;

implementation

procedure TCaja<T>.Pon(const AValor: T);
begin
  FValor := AValor;
end;

end.
""")
r = call('delphi_edit', {'path': UCAJA, 'insert': 'metodo', 'inclass': 'TCaja',
                         'code': 'procedure Vacia;\nbegin\n  FValor := Default(T);\nend;'})
u = rd(UCAJA)
check('C10 insert=metodo en una generica: TCaja<T>.Vacia en la implementacion',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure TCaja<T>.Vacia;' in u,
      r[:300] + ' | ' + u[-400:])
antes = open(UCAJA, 'rb').read()
r = call('delphi_edit', {'path': UCAJA, 'insert': 'metodo', 'inclass': 'TCaja',
                         'code': 'procedure Pon(const AValor: T);\nbegin\nend;'})
check('C10b ...y la que ya estaba (TCaja<T>.Pon) se ve: entera, nada escrito',
      mc.rechazado(r) and mc.es(r, 'SR_EDIT_EXISTE_ENTERO_DECLARACION_LINEA_FMT') and
      open(UCAJA, 'rb').read() == antes, r[:300])

# C11: la clase interpuesta (TBaseInter = class(UBaseInter.TBaseInter)) no es un
# ciclo: la cadena sale de la unidad y lo heredado no "falta"
FI_PAS = os.path.join(PRJ, 'UFormInter.pas')
escribe(FI_PAS, """unit UFormInter;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, System.Classes, UBaseInter;

type
  TBaseInter = class(UBaseInter.TBaseInter)
  end;

  TFormInter = class(TBaseInter)
    lblPropio: TLabel;
  end;

implementation

{$R *.dfm}

end.
""")
FI_DFM = os.path.join(PRJ, 'UFormInter.dfm')
escribe(FI_DFM, """inherited FormInter: TFormInter
  inherited lblHeredado: TLabel
  end
  object lblPropio: TLabel
  end
end
""")
d = J(call('delphi_designer', {'command': 'check-binding', 'path': FI_DFM}))
check('C11 check-binding con una interpuesta: lo heredado no falta y se dice que la cadena sale',
      d.get('clean') is True and not d.get('componentsWithoutField') and 'partialNote' in d,
      str(d)[:500])

# C12: las dos ramas de un IFDEF con la cabecera repetida: lo de detras no es
# un tipo anidado (insert escribia TDos.TDetras.Tres)
UDOS = unidad('UDosRamas', """unit UDosRamas;

interface

type
{$IFDEF NUNCA_DEFINIDO}
  TDos = class(TInterfacedObject)
{$ELSE}
  TDos = class(TObject)
{$ENDIF}
  public
    procedure Uno;
  end;

  TDetras = class
  public
    procedure Dos;
  end;

implementation

procedure TDos.Uno;
begin
end;

procedure TDetras.Dos;
begin
end;

end.
""")
r = call('delphi_edit', {'path': UDOS, 'insert': 'metodo', 'inclass': 'TDetras',
                         'code': 'procedure Tres;\nbegin\nend;'})
u = rd(UDOS)
check('C12 detras de una cabecera repetida por un IFDEF: TDetras.Tres, no TDos.TDetras.Tres',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure TDetras.Tres;' in u and
      'TDos.TDetras' not in u, r[:300] + ' | ' + u[-500:])

# C13: el cuerpo de una rutina repetido en las dos ramas: las clases del
# implementation de detras siguen ahi
UCUE = unidad('UCuerpoDoble', """unit UCuerpoDoble;

interface

procedure Suma;

implementation

procedure Suma;
{$IFDEF NUNCA_DEFINIDO}
begin
end;
{$ELSE}
begin
end;
{$ENDIF}

type
  TDetrasImpl = class
  public
    procedure Hola;
  end;

procedure TDetrasImpl.Hola;
begin
end;

end.
""")
r = call('delphi_edit', {'path': UCUE, 'insert': 'metodo', 'inclass': 'TDetrasImpl',
                         'code': 'procedure Adios;\nbegin\nend;'})
u = rd(UCUE)
check('C13 una clase del implementation detras de un cuerpo repetido: insert la encuentra',
      mc.abre(r, 'SK_EDIT_INSERT_METODO_DOS_MITADES_FMT') and 'procedure TDetrasImpl.Adios;' in u,
      r[:300] + ' | ' + u[-400:])
ok, err = build_ok(DPROJ)
check('C9b..C13b ...y el proyecto COMPILA (helper, generica, dos ramas, cuerpo doble)', ok, err)

# C14: la cabecera de una generica (TGen<T: class, constructor> = class) es
# una cabecera: sale en el resumen y no se le pega su primer campo
UGEN = os.path.join(DIG, 'UDigGen.pas')
escribe(UGEN, """unit UDigGen;

interface

type
  TGen<T: class, constructor> = class(TObject)
  protected
    FDato: T;
  end;

implementation

end.
""")
d = J(call('delphi_symbols', {'path': DIG}))
decls = [x for u_ in d.get('units', []) if u_.get('unit') == 'UDigGen' for x in u_.get('declares', [])]
cab = [x for x in decls if x.get('decl', '').startswith('TGen<')]
check('C14 digest: la cabecera de una generica sale, sin su primer campo',
      len(cab) == 1 and 'FDato' not in cab[0]['decl'] and
      any(x.get('decl') == 'FDato: T;' and x.get('of') == 'TGen' for x in decls), str(decls)[:500])
# (el texto tal cual: sin settings de proyecto, detras del JSON va la nota LSP-021)
f = call('delphi_symbols', {'path': UGEN, 'filter': 'TGen'})
check('C14b symbols filter: el decl de la generica no lleva pegado su primer campo',
      '"decl":"TGen<T: class, constructor> = class(TObject)"' in f, f[:500])

# C15: un class var no es el campo de un componente (el streaming busca campos
# de la instancia): el lector no marcaba los campos de un 'class var'. En la
# seccion published implicita, donde check-binding mira
CV_PAS = os.path.join(PRJ, 'UFormCV.pas')
escribe(CV_PAS, """unit UFormCV;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, System.Classes;

type
  TFormCV = class(TForm)
    lblBien: TLabel;
    class var lblDeClase: TLabel;
  end;

implementation

{$R *.dfm}

end.
""")
CV_DFM = os.path.join(PRJ, 'UFormCV.dfm')
escribe(CV_DFM, """object FormCV: TFormCV
  object lblBien: TLabel
  end
  object lblDeClase: TLabel
  end
end
""")
d = J(call('delphi_designer', {'command': 'check-binding', 'path': CV_DFM}))
check('C15 check-binding: el componente que solo tiene un class var no tiene campo',
      d.get('clean') is False and 'lblDeClase' in str(d.get('componentsWithoutField')) and
      'lblBien' not in str(d.get('componentsWithoutField')), str(d)[:500])

srv.cierra()
mc.fin('lector-clases battery')
