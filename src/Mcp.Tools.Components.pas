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
  public
    [SchemaDescription(SP_COMPONENTS_FILTER)]
    property Filter: string read FFilter write FFilter;
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
  MCPServer.Registration,
  Lsp.Discovery;

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
