unit Lsp.PackageMap;

{ Que paquete del IDE contiene cada unit (Vcl.Forms -> vcl, Data.DB -> dbrtl),
  LEIDO de los BPL que trae la instalacion (bin\*.bpl, recurso PACKAGEINFO por
  GetPackageInfo) y nunca de una tabla escrita a mano: es lo que el IDE sabe
  cuando ofrece "anadir al requires". El nombre del paquete es el del .dcp,
  no el del .bpl con su sufijo de version (vcl290.bpl -> vcl.dcp): se
  comprueba en la biblioteca Win32 del IDE (LibDelIde). Un mapa por instalacion, cargado la primera
  vez que hace falta (unos 300 BPL, menos de un segundo). Medido 2026-09-23:
  un paquete propio con una unit que usa Vcl.Dialogs compilaba en verde con
  25 W1033 y 4,6 MB de VCL dentro, y en quiet el agente no veia nada. }

interface

uses
  Lsp.Discovery; // TRadStudioInfo

{ El paquete que contiene AUnit en la instalacion AInfo, o '' si ningun BPL
  de la instalacion la declara. }
function PaqueteDeUnit(const AInfo: TRadStudioInfo; const AUnit: string): string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Lsp.Pascal, // ClaveDeIdentificador: el nombre de una unit, plegado entero
  Lsp.Rutas;  // BinDelIde

const
  // no esta en Winapi.Windows: el modulo se mapea como imagen de recursos,
  // sin ejecutar nada de el
  LOAD_LIBRARY_AS_IMAGE_RESOURCE = $20;

var
  GLock: TCriticalSection;
  GRoot: string;
  GMapa: TDictionary<string, string>;
  GPaqueteActual: string;

procedure Recoge(const Name: string; NameType: TNameType; Flags: Byte; Param: Pointer);
begin
  if NameType = ntContainsUnit then
    TDictionary<string, string>(Param).AddOrSetValue(ClaveDeIdentificador(Name), GPaqueteActual);
end;

{ vcl290.bpl -> vcl si existe vcl.dcp en ALib (la biblioteca Win32 del IDE); si
  no, el nombre entero: la instalacion decide, no una regla de sufijos. }
function NombreDePaquete(const ALib, ABpl: string): string;
var
  Stem, SinSufijo: string;
  I: Integer;
begin
  Stem := TPath.GetFileNameWithoutExtension(ABpl);
  I := Length(Stem);
  while (I > 0) and CharInSet(Stem[I], ['0'..'9']) do
    Dec(I);
  SinSufijo := Copy(Stem, 1, I);
  if (SinSufijo <> '') and (SinSufijo <> Stem) and
     TFile.Exists(TPath.Combine(ALib, SinSufijo + '.dcp')) then
    Result := SinSufijo
  else
    Result := Stem;
end;

procedure CargaMapa(const AInfo: TRadStudioInfo);
var
  Bin, Lib, F: string;
  H: HMODULE;
  Flags: Integer;
begin
  GMapa.Clear;
  GRoot := AInfo.RootDir;
  Bin := BinDelIde(AInfo.RootDir);
  Lib := LibDelIde(AInfo, 'Win32'); // los BPL del IDE son de 32 bits
  if not TDirectory.Exists(Bin) then
    Exit;
  for F in TDirectory.GetFiles(Bin, '*.bpl') do
  begin
    // Solo los recursos: no se ejecuta nada del paquete
    H := LoadLibraryEx(PChar(F), 0, LOAD_LIBRARY_AS_DATAFILE or LOAD_LIBRARY_AS_IMAGE_RESOURCE);
    if H = 0 then
      Continue;
    try
      GPaqueteActual := NombreDePaquete(Lib, F);
      try
        Flags := 0;
        GetPackageInfo(H, GMapa, Flags, Recoge);
      except
        // un .bpl sin PACKAGEINFO no es un paquete Delphi: se ignora
      end;
    finally
      FreeLibrary(H);
    end;
  end;
end;

function PaqueteDeUnit(const AInfo: TRadStudioInfo; const AUnit: string): string;
begin
  Result := '';
  if (AInfo.RootDir = '') or (AUnit = '') then
    Exit;
  GLock.Enter;
  try
    // una ruta, como el disco: tambien la Ñ, y no lo que el locale junta (V105)
    if not SameFileName(GRoot, AInfo.RootDir) then
      CargaMapa(AInfo);
    if not GMapa.TryGetValue(ClaveDeIdentificador(AUnit), Result) then
      Result := '';
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GMapa := TDictionary<string, string>.Create;

finalization
  GMapa.Free;
  GLock.Free;

end.
