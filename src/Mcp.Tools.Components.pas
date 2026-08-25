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
  Lsp.Guard;

{ The install root a registered library entry belongs to: one level above
  the entry (X\Source -> X, X\Lib\Linux64 -> X\Lib), the same rule the
  read jail applies. '' for a drive root. }
function ComponentRootOf(const APath: string): string;
begin
  Result := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(APath));
  if (Length(Result) <= 3) or (TPath.GetDirectoryName(Result) = '') then
    Result := '';
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
  Pair: TPair<string, string>;
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
    Exit(Format(SR_COMPONENTS_PLATFORM_FMT, [ARawPlatform]));
  Mine := IdePlatformLibraryPaths(AInfo.Version, Plat);
  UserDocs := ExcludeTrailingPathDelimiter(BdsUserDir(AInfo));
  CommonDocs := ExcludeTrailingPathDelimiter(BdsCommonDir(AInfo));
  Sb := TStringBuilder.Create;
  MineRoots := TList<string>.Create;
  Missing := TDictionary<string, string>.Create;
  try
    Sb.AppendLine(Format(SN_COMPONENTS_PLATFORM_HEAD_FMT, [Plat, AInfo.Version, Length(Mine)]));
    for P in Mine do
    begin
      Sb.Append('  ').Append(P);
      if not TDirectory.Exists(P) then
        Sb.Append('  (no existe)');
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
      Others := IdePlatformLibraryPaths(AInfo.Version, Other);
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
        if Missing.ContainsKey(Root) then
        begin
          if not Missing[Root].Contains(Other) then
            Missing[Root] := Missing[Root] + ', ' + Other;
        end
        else
          Missing.Add(Root, Other);
      end;
    end;
    N := Missing.Count;
    Sb.AppendLine;
    if N = 0 then
      Sb.AppendLine(Format(SN_COMPONENTS_PLATFORM_COMPLETE_FMT, [Plat]))
    else
    begin
      Sb.AppendLine(Format(SN_COMPONENTS_PLATFORM_MISSING_FMT, [N, Plat]));
      for Pair in Missing do
        Sb.AppendLine(Format('  %s   (registrado en: %s)', [Pair.Key, Pair.Value]));
      Sb.AppendLine;
      Sb.AppendLine(SN_COMPONENTS_PLATFORM_HINT);
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
begin
  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(SR_COMPONENTS_MISSING);
  if Params.Platform.Trim <> '' then
  begin
    // platform= switches to a completely different view (the library paths of
    // that platform), where "filter" means nothing. It used to be dropped
    // without a word, so a caller who sent both got an answer that ignored
    // half the question and never said so (measured 2026-08-25).
    Result := PlatformPathsView(Info, Params.Platform.Trim);
    if Params.Filter.Trim <> '' then
      Result := Result + #10#10 + Format(SN_COMPONENTS_FILTER_IGNORED_FMT,
        [Params.Filter.Trim]);
    Exit;
  end;

  Packages := IdeKnownPackages(Info.Version);
  Filter := Params.Filter.Trim;

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
        Sb.Append(' (DESHABILITADO)');
      Sb.AppendLine;
    end;
    if Shown = 0 then
      Exit(Format(SN_COMPONENTS_NONE_FMT, [Filter]));
    Result := Format('%d design packages en RAD Studio %s%s%s:',
      [Shown, Info.Version,
       IfThen(Filter <> '', ' con "' + Filter + '"', ''),
       IfThen(Off > 0, Format(' (%d deshabilitados)', [Off]), '')]) +
      sLineBreak + sLineBreak + Sb.ToString.TrimRight +
      sLineBreak + sLineBreak + SN_COMPONENTS_NOTE;
  finally
    Sb.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_components',
    function: IMCPTool begin Result := TDelphiComponentsTool.Create; end);

end.
