unit LspTests.ReclamaArbol;

// V9 de la 1.23: una carpeta que un test deja NACIDA CERRADA (una DACL vacia
// PROTEGIDA puesta en el propio CreateDirectory, que no necesita WRITE_DAC) se
// quedaba imborrable en la casa del servidor: el recorredor da GUARD-040 al no
// poder listarla. ReclamaArbol -SOLO en la casa del servidor (ServerTempDir)-
// le da, como UN objeto y SIN propagar, una DACL PROTEGIDA con UNA sola ACE de
// permitir para la cuenta del servidor (el SID de su token) con lo justo para
// listar y borrar; despues BorraArbol la borra.
//
// Por que UN objeto sin propagar (medido 26-oct, v9_propaga_junction): el
// reclamo de hoy no debe propagar la herencia a los hijos -eso es un recorrido
// de arbol que hace Windows, y los arboles solo los recorre RecorreSinEnlaces,
// que nunca cruza un enlace-. SetNamedSecurityInfo propaga (medido: no cruza
// una junction de dentro, pero reescribe los hijos); SetFileSecurity fija ESTE
// objeto y no recorre nada.
//
// El reclamo es una ESCRITURA de seguridad: el contenedor fail-closed de
// delphi_test no la puede hacer (el SID lowbox no esta en las ACE heredables de
// la casa), asi que TReclamoDeDaclTests se mide en la pasada DIRECTA de
// test_engine_dunitx (token completo), NO en PURAS. La guarda -fuera de la casa
// no se reclama- tambien directa: TReclamoFueraDeLaCasaTests.
//
// Al juez de verdad, Windows, no a un texto: GetSecurityDescriptorControl (DACL
// PROTEGIDA, no heredada) + GetSecurityDescriptorDacl (no nula) + GetAce (UNA
// sola ACE, para el SID del token, con la mascara justa, ninguna de Todos). El
// SDDL, solo en el mensaje de un fallo. El end-to-end por el servidor real lo
// mide test_casa_ilegible_1230.

interface

uses
  DUnitX.TestFramework;

type
  // el reclamo REAL (positivo + el mutante de dar la ACE a Todos): escribe
  // seguridad, token completo -> pasada directa de test_engine_dunitx, NO PURAS
  [TestFixture]
  TReclamoDeDaclTests = class
  private
    FCasa, FVictima: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure LaDaclReclamadaEsUnaAceDelDuenoSinTodos;
    [Test] procedure ElReclamoNoCruzaUnaJunctionAlBorrar;
  end;

  // la guarda de lugar: no escribe nada (ReclamaArbol corta antes); directa,
  // NO en PURAS (no planta una cerrada en el contenedor)
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
  Winapi.AclAPI,        // GetNamedSecurityInfoW
  Lsp.Guard,            // ReclamaArbol, BorraArbol, EntradasDeCarpeta, EsEnlace
  Lsp.Casa,             // ServerTempDir, FragmentoUnico
  LspTests.FormRender;  // CreaUnion

const
  SDDL_REVISION_1 = 1;
  // lo justo para que el dueno liste y borre su casa (= lo que fija ReclamaDaclHeredada)
  RECLAMO_MASK = FILE_LIST_DIRECTORY or FILE_TRAVERSE or FILE_READ_ATTRIBUTES or
    FILE_DELETE_CHILD or $00010000 {DELETE} or SYNCHRONIZE;

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
    Leida: Boolean;        // GetNamedSecurityInfo contesto
    DaclNoNula: Boolean;   // presente y NO nula (nil = NO_ACCESS_CONTROL)
    Protegida: Boolean;    // SE_DACL_PROTECTED (un objeto, sin herencia que propague)
    NumAces: Integer;
    SoloElDueno: Boolean;  // TODAS las ACE (>=1) son para el SID del token
    HayTodos: Boolean;     // alguna ACE para S-1-1-0 (Everyone)
    MaskDueno: DWORD;      // la mascara de la ACE del dueno
    Sddl: string;          // solo para el mensaje
  end;

// el SID del token del proceso, copiado en Buf (el puntero apunta dentro de Buf)
function SidDelToken(var Buf: TBytes): PSID;
var
  Tok: THandle;
  Tam: DWORD;
begin
  Result := nil;
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Tok) then
    Exit;
  try
    Tam := 0;
    GetTokenInformation(Tok, TokenUser, nil, 0, Tam);
    if Tam = 0 then
      Exit;
    SetLength(Buf, Tam);
    if GetTokenInformation(Tok, TokenUser, @Buf[0], Tam, Tam) then
      Result := PTokenUser(@Buf[0])^.User.Sid;
  finally
    CloseHandle(Tok);
  end;
end;

// crea ADir NACIDA CERRADA: la DACL vacia PROTEGIDA va en la propia creacion
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

// cierra ADir YA existente (DACL vacia protegida): como un test que cierra su
// carpeta despues de llenarla; el dueno a pelo (token completo) puede
procedure CierraDacl(const ADir: string);
const
  ACL_REVISION = 2;
var
  SD: TSecurityDescriptor;
  Acl: array [0 .. 63] of Byte;
begin
  InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
  InitializeAcl(PACL(@Acl)^, SizeOf(Acl), ACL_REVISION);
  SetSecurityDescriptorDacl(@SD, True, PACL(@Acl), False);
  SetSecurityDescriptorControl(@SD, SE_DACL_PROTECTED, SE_DACL_PROTECTED);
  SetFileSecurityW(PChar(ADir), DACL_SECURITY_INFORMATION, @SD);
end;

// recupera ADir para el dueno (una ACE suya con la mascara justa) para que la
// limpieza pueda borrarlo aunque quedara cerrado (fuera de la casa)
procedure AbreDacl(const ADir: string);
const
  ACL_REVISION = 2;
var
  Buf: TBytes;
  Sid: PSID;
  SD: TSecurityDescriptor;
  Acl: array [0 .. 127] of Byte;
begin
  if not DirectoryExists(ADir) then
    Exit;
  Sid := SidDelToken(Buf);
  if Sid = nil then
    Exit;
  InitializeAcl(PACL(@Acl)^, SizeOf(Acl), ACL_REVISION);
  AddAccessAllowedAce(PACL(@Acl)^, ACL_REVISION, RECLAMO_MASK, Sid);
  InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
  SetSecurityDescriptorDacl(@SD, True, PACL(@Acl), False);
  SetSecurityDescriptorControl(@SD, SE_DACL_PROTECTED, SE_DACL_PROTECTED);
  SetFileSecurityW(PChar(ADir), DACL_SECURITY_INFORMATION, @SD);
end;

// la DACL de ADir juzgada por Windows (no por el texto); el SDDL queda para el
// mensaje de un fallo
function JuzgaDacl(const ADir: string): TVeredicto;
var
  pSD: PSECURITY_DESCRIPTOR;
  Control: Word;
  Rev: DWORD;
  DaclPresent, DaclDef: BOOL;
  pDacl: PACL;
  pAce: Pointer;
  sidTodos: PSID;
  TokBuf: TBytes;
  sidTok: PSID;
  i: Integer;
  s: PWideChar;
begin
  Result := Default(TVeredicto);
  Result.SoloElDueno := True;
  sidTok := SidDelToken(TokBuf);
  pSD := nil;
  if (GetNamedSecurityInfoW(PChar(ADir), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
    nil, nil, nil, nil, @pSD) <> ERROR_SUCCESS) or (pSD = nil) then
    Exit;
  try
    Result.Leida := True;
    if GetSecurityDescriptorControl(PSecurityDescriptor(pSD), Control, Rev) then
      Result.Protegida := (Control and SE_DACL_PROTECTED) <> 0;
    pDacl := nil;
    if GetSecurityDescriptorDacl(PSecurityDescriptor(pSD), DaclPresent, pDacl, DaclDef) then
      Result.DaclNoNula := DaclPresent and (pDacl <> nil);
    if ConvertStringSidToSidW(PChar('S-1-1-0'), sidTodos) then
      try
        if pDacl <> nil then
        begin
          Result.NumAces := pDacl^.AceCount;
          for i := 0 to Integer(pDacl^.AceCount) - 1 do
            if GetAce(pDacl, DWORD(i), pAce) then
            begin
              if EqualSid(@PAceLeida(pAce)^.SidStart, sidTodos) then
                Result.HayTodos := True;
              if (sidTok <> nil) and EqualSid(@PAceLeida(pAce)^.SidStart, sidTok) then
                Result.MaskDueno := PAceLeida(pAce)^.Mask
              else
                Result.SoloElDueno := False;
            end;
          if Result.NumAces = 0 then
            Result.SoloElDueno := False;
        end
        else
          Result.SoloElDueno := False;
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

{ TReclamoDeDaclTests }

procedure TReclamoDeDaclTests.Prepara;
begin
  // la casa del ejecutor (junto al exe) y una victima FUERA de ella, a su lado
  FCasa := ServerTempDir('reclamo-' + FragmentoUnico);
  ForceDirectories(FCasa);
  FVictima := TPath.Combine(ExtractFileDir(ParamStr(0)), 'victima-' + FragmentoUnico);
end;

procedure TReclamoDeDaclTests.Limpia;
begin
  Barre(FCasa);
  RemoveDir(FCasa);
  Barre(FVictima);
  RemoveDir(FVictima);
end;

procedure TReclamoDeDaclTests.LaDaclReclamadaEsUnaAceDelDuenoSinTodos;
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
  // ahora se lista -el dueno recupero el acceso-: si lanzara, la prueba erraria aqui
  Assert.AreEqual(0, Integer(Length(EntradasDeCarpeta(Cerrada))), 'reclamada y vacia');
  // y se lo pregunto a Windows, no al texto: UN objeto, UNA ACE del dueno
  V := JuzgaDacl(Cerrada);
  Assert.IsTrue(V.Leida, 'se lee la seguridad: ' + V.Sddl);
  Assert.IsTrue(V.DaclNoNula, 'la DACL no es nula (nil seria NO_ACCESS_CONTROL): ' + V.Sddl);
  Assert.IsTrue(V.Protegida, 'protegida: un objeto, sin herencia que propague: ' + V.Sddl);
  Assert.AreEqual(1, V.NumAces, 'una sola ACE: ' + V.Sddl);
  Assert.IsTrue(V.SoloElDueno, 'la ACE es para el dueno (el SID del token): ' + V.Sddl);
  Assert.IsFalse(V.HayTodos, 'nada para Todos (S-1-1-0): ' + V.Sddl);
  Assert.AreEqual(Int64(RECLAMO_MASK), Int64(V.MaskDueno), 'con la mascara justa (list/traverse/read/delete-child/DELETE/sync): ' + V.Sddl);
end;

procedure TReclamoDeDaclTests.ElReclamoNoCruzaUnaJunctionAlBorrar;
var
  L, Enlace, Vhijo, vAntes, vhAntes: string;
begin
  // una victima V FUERA de la casa, con un hijo; una carpeta L de la casa con
  // una junction J -> V, y L CERRADA despues de poner J dentro. El barrido
  // reclama L (un objeto) y borra, SIN cruzar J: V y su hijo, intactos.
  Vhijo := TPath.Combine(FVictima, 'hijo');
  ForceDirectories(Vhijo);
  L := TPath.Combine(FCasa, 'L');
  ForceDirectories(L);
  Enlace := TPath.Combine(L, 'J');
  Assert.IsTrue(CreaUnion(Enlace, FVictima), 'la union se crea: ' + SysErrorMessage(GetLastError));
  CierraDacl(L); // L cerrada con J dentro
  vAntes := JuzgaDacl(FVictima).Sddl;
  vhAntes := JuzgaDacl(Vhijo).Sddl;
  ReclamaArbol(FCasa);
  BorraArbol(FCasa);
  Assert.IsFalse(TDirectory.Exists(FCasa), 'la casa se borro');
  Assert.AreEqual(vAntes, JuzgaDacl(FVictima).Sddl, 'la DACL de V no cambia (no se cruza la junction)');
  Assert.AreEqual(vhAntes, JuzgaDacl(Vhijo).Sddl, 'la DACL del hijo de V no cambia');
  Assert.IsTrue(TDirectory.Exists(Vhijo), 'el hijo de V sigue ahi');
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
  // listaria). El detalle de la DACL lo decide el entorno (el lowbox del
  // contenedor no honra SE_DACL_PROTECTED al crear, y aun asi niega listar), asi
  // que aqui no se juzga; el reclamo positivo lo mide, a pelo, TReclamoDeDaclTests.
end;

initialization

TDUnitX.RegisterTestFixture(TReclamoDeDaclTests);
TDUnitX.RegisterTestFixture(TReclamoFueraDeLaCasaTests);

end.
