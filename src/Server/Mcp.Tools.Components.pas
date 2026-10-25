unit Mcp.Tools.Components;

{ delphi_components: what does this server have installed to program with?
  The GENERAL answer (operator clarification 2026-08-21: "la lista de
  componentes disponibles en general", not just GetIt): the design packages
  REGISTERED in the IDE - Known Packages in the registry, the same list RAD
  Studio loads into its palette - whatever the install channel: GetIt, a
  vendor installer, or a hand registration. A GetIt-only listing misses
  everything installed outside GetIt; this one cannot.

  Read-only in the strictest sense: a registry read, no process is even
  spawned. No install BY DESIGN (operator decision): installing packages
  mutates the whole IDE and stays a human decision - a missing library is
  reported with delphi_report.

  Measured 2026-08-21 on the reference machine: Known Packages 152 (HKCU)
  + Known Packages x64 118 + HKLM 83, 3 disabled; Known IDE Packages (72)
  are IDE plumbing with no components and are deliberately excluded. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiComponentsParams = class
  private
    FFilter: string;
    FPlatform: string;
  public
    [SchemaDescription(SP_COMPONENTS_FILTER)]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription(SP_COMPONENTS_PLATFORM)]
    property Platform: string read FPlatform write FPlatform;
  end;

  TDelphiComponentsTool = class(TMCPToolBase<TDelphiComponentsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiComponentsParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Generics.Collections,
  MCPServer.Registration,
  Lsp.Discovery,
  Lsp.Dproj,
  Lsp.Guard, // ParametroQueNoVa: lo que no va con el modo, como en las hermanas
  Lsp.NetDrives;

{ Apunta que la carpeta AClave la registra la plataforma APlat (las
  plataformas, 'Win32, Win64'). La vista por plataforma lo escribia a mano y
  miraba con Contains, donde Win64 esta dentro de Win64x. }
procedure AnotaPlataforma(ACarpetas: TDictionary<string, string>; const AClave, APlat: string);
var
  V: string;
begin
  if not ACarpetas.TryGetValue(AClave, V) then
    ACarpetas.Add(AClave, APlat)
  else if not MatchText(APlat, V.Split([', '])) then
    ACarpetas[AClave] := V + ', ' + APlat;
end;

{ Las lineas 'carpeta (registered in: plataformas)', por orden de carpeta (un
  diccionario no tiene orden). }
function LineasDeCarpetas(ACarpetas: TDictionary<string, string>): string;
var
  Claves: TArray<string>;
  K: string;
  Sb: TStringBuilder;
begin
  Claves := ACarpetas.Keys.ToArray;
  TArray.Sort<string>(Claves);
  Sb := TStringBuilder.Create;
  try
    for K in Claves do
      Sb.AppendLine(MsgFmt(SF_COMP_REGISTRADO_EN_FMT, [K, ACarpetas[K]]));
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ Las carpetas del Library Search Path del IDE, de cualquier plataforma, cuya
  ruta contiene AFiltro, con las plataformas que las registran. Una biblioteca
  sin paquete (solo unidades) vive solo ahi, y filter contestaba "ningun
  paquete la tiene" de una que compila (David, 23-oct-2026: superobject). }
function CarpetasConFiltro(const AInfo: TRadStudioInfo; const AFiltro: string): TDictionary<string, string>;
var
  Plat, P: string;
begin
  Result := TDictionary<string, string>.Create;
  for Plat in IdeLibraryPlatforms(AInfo.Version) do
    for P in IdePlatformLibraryPaths(AInfo, Plat) do
      if ContainsText(P, AFiltro) then
        AnotaPlataforma(Result, P, Plat);
end;

{ platform=X: the IDE's Library Search Path of that platform, expanded, and
  the component roots other platforms register that this one does not - the
  list to walk when a build on a NEW platform fails with F2613. }
function PlatformPathsView(const AInfo: TRadStudioInfo; const ARawPlatform: string): string;
var
  Plat, Other, P, Root: string;
  Mine, Others: TArray<string>;
  MineRoots: TList<string>;
  Missing: TDictionary<string, string>; // root -> platforms that have it
  Sb: TStringBuilder;
  N: Integer;
  UserDocs, CommonDocs: string;

  function UnderMine(const ARoot: string): Boolean;
  var
    M: string;
  begin
    for M in Mine do
      if StartsText(IncludeTrailingPathDelimiter(M), IncludeTrailingPathDelimiter(ARoot)) then
        Exit(True);
    Result := False;
  end;

begin
  Plat := CanonicalPlatform(ARawPlatform);
  if Plat = '' then
    Exit(NegativaDePlataforma(ARawPlatform)); // LA de toda tool (A36 de la 1.23: era COMP-008, el mismo hecho)
  Mine := IdePlatformLibraryPaths(AInfo, Plat);
  UserDocs := PrefijoSinBarra(BdsUserDir(AInfo));
  CommonDocs := PrefijoSinBarra(BdsCommonDir(AInfo));
  Sb := TStringBuilder.Create;
  MineRoots := TList<string>.Create;
  Missing := TDictionary<string, string>.Create;
  try
    Sb.AppendLine(MsgFmt(SN_COMPONENTS_PLATFORM_HEAD_FMT, [Plat, AInfo.Version, Length(Mine)]));
    for P in Mine do
    begin
      Sb.Append('  ').Append(P);
      if not TDirectory.Exists(P) then
        Sb.Append(MsgText(SF_COMP_NO_EXISTE));
      Sb.AppendLine;
      Root := ComponentRootOf(P);
      if (Root <> '') and not MineRoots.Contains(Root) then
        MineRoots.Add(Root);
    end;
    // what the OTHER platforms register and this one lacks, by install root
    for Other in IdeLibraryPlatforms(AInfo.Version) do
    begin
      if SameText(Other, Plat) then
        Continue;
      Others := IdePlatformLibraryPaths(AInfo, Other);
      for P in Others do
      begin
        Root := ComponentRootOf(P);
        if (Root = '') or MineRoots.Contains(Root) then
          Continue;
        // the IDE's own trees (install, user and common documents) are not
        // components, and a root already under one of THIS platform's
        // registered folders is already reachable
        if StartsText(IncludeTrailingPathDelimiter(AInfo.RootDir), Root) or
           SameText(Root, UserDocs) or SameText(Root, CommonDocs) or
           UnderMine(Root) then
          Continue;
        AnotaPlataforma(Missing, Root, Other);
      end;
    end;
    N := Missing.Count;
    Sb.AppendLine;
    if N = 0 then
      Sb.AppendLine(MsgFmt(SN_COMPONENTS_PLATFORM_COMPLETE_FMT, [Plat]))
    else
    begin
      Sb.AppendLine(MsgFmt(SN_COMPONENTS_PLATFORM_MISSING_FMT, [N, Plat]));
      Sb.Append(LineasDeCarpetas(Missing));
      Sb.AppendLine;
      Sb.AppendLine(MsgText(SN_COMPONENTS_PLATFORM_HINT));
    end;
    Result := Sb.ToString.TrimRight;
  finally
    Missing.Free;
    MineRoots.Free;
    Sb.Free;
  end;
end;

{ TDelphiComponentsTool }

constructor TDelphiComponentsTool.Create;
begin
  inherited;
  FName := 'delphi_components';
  FDescription := SD_COMPONENTS;
end;

function TDelphiComponentsTool.ExecuteWithParams(const Params: TDelphiComponentsParams): string;
var
  Info: TRadStudioInfo;
  Packages: TArray<TIdePackage>;
  P: TIdePackage;
  Filter: string;
  Sb: TStringBuilder;
  Shown, Off: Integer;
  Carpetas: TDictionary<string, string>;
begin
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(MsgText(SR_COMPONENTS_MISSING));
  // platform= switches to a completely different view (the library paths of
  // that platform), where "filter" means nothing. It used to be dropped
  // without a word (measured 2026-08-25). Despues fue una nota y la respuesta
  // seguia; ahora se niega como en las hermanas (Lsp.Guard.ParametroQueNoVa;
  // Opus en Hermes, 1.22.1)
  var Suyos, VaCon: string;
  var Modo := IfThen(Params.Platform.Trim <> '', 'platform=', 'packages');
  var Sobra := ParametroQueNoVa(Modo, ['platform=', 'platform', 'packages', 'filter'],
    ['platform', Params.Platform, '', 'filter', Params.Filter, ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_COMPONENTS_NO_VA_CON_MODO_FMT, [Sobra, Modo, Modo, Suyos]) + VaCon);
  if Params.Platform.Trim <> '' then
    Exit(PlatformPathsView(Info, Params.Platform.Trim));

  Packages := IdeKnownPackages(Info.Version);
  Filter := Params.Filter.Trim;

  Carpetas := nil;
  Sb := TStringBuilder.Create;
  try
    Shown := 0;
    Off := 0;
    for P in Packages do
    begin
      if (Filter <> '') and not (ContainsText(P.Description, Filter) or
        ContainsText(P.BplFile, Filter)) then
        Continue;
      Inc(Shown);
      if P.Disabled then
        Inc(Off);
      Sb.Append(P.Description).Append('  [').Append(P.BplFile).Append(']');
      if P.Disabled then
        Sb.Append(MsgText(SF_COMP_DESHABILITADO));
      Sb.AppendLine;
    end;
    // con filter, tambien las carpetas del Library Search Path: lo que se
    // puede poner en un uses no es solo lo que trae un paquete
    if Filter <> '' then
      Carpetas := CarpetasConFiltro(Info, Filter);
    if (Shown = 0) and ((Carpetas = nil) or (Carpetas.Count = 0)) then
      Exit(MsgFmt(SN_COMPONENTS_NONE_FMT, [Filter]));
    Result := '';
    if Shown > 0 then
      Result := MsgFmt(SN_COMPONENTS_DESIGN_PACKAGES_FMT,
        [Shown, Info.Version,
         IfThen(Filter <> '', MsgFmt(SF_COMP_CON_FILTRO_FMT, [Filter]), ''),
         IfThen(Off > 0, MsgFmt(SF_COMP_DESHABILITADOS_FMT, [Off]), '')]) +
        sLineBreak + sLineBreak + Sb.ToString.TrimRight;
    if (Carpetas <> nil) and (Carpetas.Count > 0) then
      Result := Result + IfThen(Result <> '', sLineBreak + sLineBreak) +
        MsgFmt(SN_COMPONENTS_PATH_HEAD_FMT, [Carpetas.Count, Filter]) +
        sLineBreak + LineasDeCarpetas(Carpetas).TrimRight;
    if Shown > 0 then
      Result := Result + sLineBreak + sLineBreak + MsgText(SN_COMPONENTS_NOTE);
  finally
    Carpetas.Free;
    Sb.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_components',
    function: IMCPTool begin Result := TDelphiComponentsTool.Create; end);

end.
