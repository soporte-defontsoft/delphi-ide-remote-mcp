unit LspTests.ReclamaArbol;

// V9 de la 1.23: una carpeta que un test deja NACIDA CERRADA (una DACL vacia
// PROTEGIDA puesta en el propio CreateDirectory, que no necesita WRITE_DAC) se
// quedaba imborrable en la casa del servidor: el recorredor da GUARD-040 al no
// poder listarla. ReclamaArbol -SOLO en la casa del servidor (ServerTempDir),
// nunca cruzando un enlace- le pone una DACL vacia NO protegida con
// SetNamedSecurityInfo, con lo que hereda de la casa y el dueno recupera el
// acceso; despues BorraArbol la borra.
//
// El reclamo es una ESCRITURA DE SEGURIDAD privilegiada: el contenedor fail-
// closed de delphi_test no la puede hacer (el SID lowbox no esta en las ACE
// heredables de la casa, medido 26-oct-2026), asi que TReclamoDeDaclTests mide
// el reclamo REAL solo en la pasada DIRECTA de test_engine_dunitx (token
// completo), NO en PURAS. La guarda -fuera de la casa no se reclama-
// (TReclamoFueraDeLaCasaTests) se mide igual en la pasada directa, NO en el
// contenedor: una cerrada plantada dentro de el solo la limpiaria un servidor
// con V9, y dejarla imborrable tumbaria la siguiente pasada.
//
// Al juez de verdad, Windows, no a un texto: GetSecurityDescriptorControl
// (SE_DACL_AUTO_INHERITED puesto, SE_DACL_PROTECTED sin poner) + la DACL no
// nula (nil seria NO_ACCESS_CONTROL, el error pDacl=nil) + GetAce (ningun ACE
// de Todos SIN heredar). El SDDL, solo en el mensaje de un fallo. El end-to-end
// por el servidor real lo mide test_casa_ilegible_1230.

interface

uses
  DUnitX.TestFramework;

type
  // el reclamo REAL (positivo + el mutante pDacl=nil): escribe seguridad, token
  // completo -> solo en la pasada directa de test_engine_dunitx, NO en PURAS
  [TestFixture]
  TReclamoDeDaclTests = class
  private
    FCasa, FVictima: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure LaDaclReclamadaHeredaYNoEsNil;
    [Test] procedure LaUnionDeLaCasaNoTocaSuDestino;
  end;

  // la guarda de lugar: no escribe nada (ReclamaArbol corta antes); en la
  // pasada directa, NO en PURAS (no planta una cerrada en el contenedor)
  [TestFixture]
  TReclamoFueraDeLaCasaTests = class
  private
    FRaiz: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure UnaCerradaEnUnaRaizNoSeReclama;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.AccCtrl,       // SE_FILE_OBJECT
  Winapi.AclAPI,        // GetNamedSecurityInfoW, SetNamedSecurityInfoW
  Lsp.Guard,            // ReclamaArbol, EntradasDeCarpeta, EsEnlace
  Lsp.Casa,             // ServerTempDir, FragmentoUnico
  LspTests.FormRender;  // CreaUnion

const
  SDDL_REVISION_1 = 1;

// no esta en ninguna unidad de la RTL (medido): se declara a pelo, solo para el
// SDDL del mensaje de un fallo
function ConvertSecurityDescriptorToStringSecurityDescriptorW(SecurityDescriptor: Pointer;
  RequestedStringSDRevision, SecurityInformation: DWORD; var StringSecurityDescriptor: PWideChar;
  StringSecurityDescriptorLen: Pointer): BOOL; stdcall; external 'advapi32.dll';

type
  TAceLeida = packed record
    AceType: Byte;
    AceFlags: Byte;
    AceSize: Word;
    Mask: DWORD;
    SidStart: DWORD; // el primer DWORD del SID; @SidStart es el SID
  end;
  PAceLeida = ^TAceLeida;

  TVeredicto = record
    Leida: Boolean;          // GetNamedSecurityInfo contesto
    DaclNoNula: Boolean;     // presente y NO nula (nil = NO_ACCESS_CONTROL)
    AutoHeredada: Boolean;   // SE_DACL_AUTO_INHERITED
    Protegida: Boolean;      // SE_DACL_PROTECTED
    TodosExplicito: Boolean; // un ACE de Todos SIN heredar (lo que el reclamo NO anade)
    Sddl: string;            // solo para el mensaje
  end;

// crea ADir NACIDA CERRADA: la DACL vacia PROTEGIDA va en la propia creacion
// (no hace falta WRITE_DAC), que es como un test la puede dejar
function CreaCerrada(const ADir: string): Boolean;
const
  ACL_REVISION = 2;
var
  SD: TSecurityDescriptor;
  Acl: array [0 .. 63] of Byte;
  SA: TSecurityAttributes;
begin
  InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
  InitializeAcl(PACL(@Acl)^, SizeOf(Acl), ACL_REVISION); // 0 ACEs = niega a todos
  SetSecurityDescriptorDacl(@SD, True, PACL(@Acl), False);
  SetSecurityDescriptorControl(@SD, SE_DACL_PROTECTED, SE_DACL_PROTECTED);
  SA.nLength := SizeOf(SA);
  SA.lpSecurityDescriptor := @SD;
  SA.bInheritHandle := False;
  Result := CreateDirectory(PChar(ADir), @SA);
end;

// reclama ADir como dueno (DACL vacia NO protegida): el ejecutor es dueno y
// conserva WRITE_DAC (DACL vacia, sin OWNER_RIGHTS), asi que puede; para que la
// limpieza borre una cerrada que no se reclamo (fuera de la casa)
procedure AbreDacl(const ADir: string);
const
  ACL_REVISION = 2;
  UNPROTECTED_DACL_SECURITY_INFORMATION = DWORD($20000000);
var
  Acl: array [0 .. 63] of Byte;
begin
  if not DirectoryExists(ADir) then
    Exit;
  InitializeAcl(PACL(@Acl)^, SizeOf(Acl), ACL_REVISION);
  SetNamedSecurityInfoW(PChar(ADir), SE_FILE_OBJECT,
    DACL_SECURITY_INFORMATION or UNPROTECTED_DACL_SECURITY_INFORMATION, nil, nil, PACL(@Acl), nil);
end;

// la DACL de ADir juzgada por Windows (no por el texto); el SDDL queda para el
// mensaje de un fallo
function JuzgaDacl(const ADir: string): TVeredicto;
const
  INHERITED_ACE = $10;
  ACCESS_ALLOWED_ACE_TYPE = 0;
var
  pSD: PSECURITY_DESCRIPTOR;
  Control: Word;
  Rev: DWORD;
  DaclPresent, DaclDef: BOOL;
  pDacl: PACL;
  pAce: Pointer;
  sidTodos: PSID;
  i: Integer;
  s: PWideChar;
begin
  Result := Default(TVeredicto);
  pSD := nil;
  if (GetNamedSecurityInfoW(PChar(ADir), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
    nil, nil, nil, nil, @pSD) <> ERROR_SUCCESS) or (pSD = nil) then
    Exit;
  try
    Result.Leida := True;
    if GetSecurityDescriptorControl(PSecurityDescriptor(pSD), Control, Rev) then
    begin
      Result.AutoHeredada := (Control and SE_DACL_AUTO_INHERITED) <> 0;
      Result.Protegida := (Control and SE_DACL_PROTECTED) <> 0;
    end;
    pDacl := nil;
    if GetSecurityDescriptorDacl(PSecurityDescriptor(pSD), DaclPresent, pDacl, DaclDef) then
      Result.DaclNoNula := DaclPresent and (pDacl <> nil);
    if (pDacl <> nil) and ConvertStringSidToSidW(PChar('S-1-1-0'), sidTodos) then
      try
        for i := 0 to Integer(pDacl^.AceCount) - 1 do
          if GetAce(pDacl, DWORD(i), pAce) then
            if (PAceLeida(pAce)^.AceType = ACCESS_ALLOWED_ACE_TYPE) and
              ((PAceLeida(pAce)^.AceFlags and INHERITED_ACE) = 0) and
              EqualSid(@PAceLeida(pAce)^.SidStart, sidTodos) then
              Result.TodosExplicito := True;
      finally
        LocalFree(HLOCAL(sidTodos));
      end;
    s := nil;
    if ConvertSecurityDescriptorToStringSecurityDescriptorW(pSD, SDDL_REVISION_1,
      DACL_SECURITY_INFORMATION, s, nil) and (s <> nil) then
      try
        Result.Sddl := s;
      finally
        LocalFree(HLOCAL(s));
      end;
  finally
    LocalFree(HLOCAL(pSD));
  end;
end;

{ TReclamoDeDaclTests }

procedure TReclamoDeDaclTests.Prepara;
begin
  // la casa del ejecutor (junto al exe) y una victima FUERA de ella, a su lado
  FCasa := ServerTempDir('reclamo-' + FragmentoUnico);
  ForceDirectories(FCasa);
  FVictima := TPath.Combine(ExtractFileDir(ParamStr(0)), 'victima-' + FragmentoUnico);
end;

procedure TReclamoDeDaclTests.Limpia;

  procedure Barre(const ADir: string);
  begin
    if not DirectoryExists(ADir) then
      Exit;
    for var E in TDirectory.GetDirectories(ADir) do
      if EsEnlace(E) then
        RemoveDir(E) // el enlace se quita como enlace: su destino no se toca
      else
      begin
        AbreDacl(E); // una cerrada que quedo se recupera por el dueno
        Barre(E);
        RemoveDir(E);
      end;
    for var F in TDirectory.GetFiles(ADir) do
      TFile.Delete(F);
  end;

begin
  Barre(FCasa);
  RemoveDir(FCasa);
  AbreDacl(FVictima);
  RemoveDir(FVictima);
end;

procedure TReclamoDeDaclTests.LaDaclReclamadaHeredaYNoEsNil;
var
  Cerrada: string;
  V: TVeredicto;
begin
  Cerrada := TPath.Combine(FCasa, 'cerrada');
  Assert.IsTrue(CreaCerrada(Cerrada), 'la carpeta nace cerrada: ' + SysErrorMessage(GetLastError));
  // nacida cerrada: Windows no la deja listar, ni al dueno (GUARD-040)
  Assert.WillRaise(
    procedure
    begin
      EntradasDeCarpeta(Cerrada);
    end, nil, 'una DACL vacia no deja listar: GUARD-040');
  // el barrido de la casa la reclama (ReclamaArbol pasa su guarda de lugar)
  ReclamaArbol(FCasa);
  // ahora se lista -hereda de la casa-: si lanzara, la prueba erraria aqui
  Assert.AreEqual(0, Integer(Length(EntradasDeCarpeta(Cerrada))), 'reclamada y vacia');
  // y se lo pregunto a Windows, no al texto
  V := JuzgaDacl(Cerrada);
  Assert.IsTrue(V.Leida, 'se lee la seguridad: ' + V.Sddl);
  Assert.IsTrue(V.DaclNoNula, 'la DACL no es nula (nil seria NO_ACCESS_CONTROL): ' + V.Sddl);
  Assert.IsTrue(V.AutoHeredada, 'la DACL hereda (SE_DACL_AUTO_INHERITED): ' + V.Sddl);
  Assert.IsFalse(V.Protegida, 'ya no esta protegida (SE_DACL_PROTECTED): ' + V.Sddl);
  Assert.IsFalse(V.TodosExplicito, 'el reclamo no anade a Todos (ningun ACE de Todos sin heredar): ' + V.Sddl);
end;

procedure TReclamoDeDaclTests.LaUnionDeLaCasaNoTocaSuDestino;
var
  Enlace: string;
  Antes, Despues: TVeredicto;
begin
  // una victima CERRADA fuera de la casa y una union de la casa que apunta a
  // ella: si ReclamaArbol cruzara el enlace, le reclamaria (tocaria) la DACL
  Assert.IsTrue(CreaCerrada(FVictima), 'la victima nace cerrada: ' + SysErrorMessage(GetLastError));
  Enlace := TPath.Combine(FCasa, 'enlace');
  Assert.IsTrue(CreaUnion(Enlace, FVictima), 'la union se crea: ' + SysErrorMessage(GetLastError));
  Antes := JuzgaDacl(FVictima);
  ReclamaArbol(FCasa);
  Despues := JuzgaDacl(FVictima);
  // la victima, intacta: el recorredor no entra en el enlace y ReclamaArbol mira EsEnlace
  Assert.IsTrue(Despues.Protegida, 'la victima sigue protegida: ' + Despues.Sddl);
  Assert.IsFalse(Despues.AutoHeredada, 'la victima no hereda (no la toco el reclamo): ' + Despues.Sddl);
  Assert.AreEqual(Antes.Sddl, Despues.Sddl, 'la DACL de la victima no cambia');
  Assert.WillRaise(
    procedure
    begin
      EntradasDeCarpeta(FVictima);
    end, nil, 'la victima sigue cerrada (GUARD-040)');
end;

{ TReclamoFueraDeLaCasaTests }

procedure TReclamoFueraDeLaCasaTests.Prepara;
begin
  // una raiz FUERA de la casa del servidor (junto al exe): la jaula del agente
  FRaiz := TPath.Combine(ExtractFileDir(ParamStr(0)), 'raiz-' + FragmentoUnico);
end;

procedure TReclamoFueraDeLaCasaTests.Limpia;
begin
  AbreDacl(FRaiz);
  RemoveDir(FRaiz);
end;

procedure TReclamoFueraDeLaCasaTests.UnaCerradaEnUnaRaizNoSeReclama;
begin
  Assert.IsTrue(CreaCerrada(FRaiz), 'nace cerrada: ' + SysErrorMessage(GetLastError));
  ReclamaArbol(FRaiz); // su guarda de lugar la deja fuera: no se reclama
  Assert.WillRaise(
    procedure
    begin
      EntradasDeCarpeta(FRaiz);
    end, nil, 'fuera de la casa sigue GUARD-040: la jaula del agente no se reclama');
  // "sigue cerrada" es GUARD-040 arriba: la invariante (si se reclamara, se
  // listaria). El detalle de la DACL -protegida o no- lo decide el entorno (el
  // lowbox del contenedor no honra SE_DACL_PROTECTED al crear, y aun asi niega
  // listar), asi que aqui no se juzga; el reclamo positivo lo mide, a pelo,
  // TReclamoDeDaclTests.
end;

initialization

TDUnitX.RegisterTestFixture(TReclamoDeDaclTests);
TDUnitX.RegisterTestFixture(TReclamoFueraDeLaCasaTests);

end.
