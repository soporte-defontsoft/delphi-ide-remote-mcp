unit Mcp.Tools.GetIt;

{ delphi_getit: what does this server have installed to program with? Lists
  the GetIt packages of the server's RAD Studio through the IDE's own
  GetItCmd.exe (never a parallel catalog reader) - so a remote agent knows
  which component libraries it can lean on BEFORE writing uses clauses that
  will not compile.

  Read-only BY DESIGN (operator decision 2026-08-21): no install, no
  uninstall - installing packages mutates the whole IDE and that stays a
  human decision. A missing package is reported with delphi_report.

  Measured (bin exploration 2026-08-21): "GetItCmd -l= -f=installed" reads
  the LOCAL catalog and prints a parseable Id/Version/Description table;
  -s= sorts by name/vendor/date. The banner and the closing success line
  are stripped here - the agent gets the table and one note. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiGetItParams = class
  private
    FSort: string;
  public
    [SchemaDescription(SP_GETIT_SORT)]
    property Sort: string read FSort write FSort;
  end;

  TDelphiGetItTool = class(TMCPToolBase<TDelphiGetItParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiGetItParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Discovery,
  Lsp.BuildRunner;

{ TDelphiGetItTool }

constructor TDelphiGetItTool.Create;
begin
  inherited;
  FName := 'delphi_getit';
  FDescription := SD_GETIT;
end;

function TDelphiGetItTool.ExecuteWithParams(const Params: TDelphiGetItParams): string;
var
  Info: TRadStudioInfo;
  Exe, SortBy, Output, L: string;
  ExitCode: Cardinal;
  Lines: TArray<string>;
  Sb: TStringBuilder;
begin
  SortBy := Params.Sort.Trim.ToLower;
  if SortBy = '' then
    SortBy := 'name';
  // The whitelist IS the sanitizer: nothing else ever reaches the command
  // line, same lesson as every argument filter in Lsp.Guard.
  if not MatchText(SortBy, ['name', 'vendor', 'date']) then
    Exit(Format(SR_GETIT_SORT_FMT, [Params.Sort.Trim]));

  Info := DiscoverRadStudio;
  if not Info.Found then
    Exit(SR_GETIT_MISSING);
  Exe := TPath.Combine(Info.RootDir, 'bin\GetItCmd.exe');
  if not TFile.Exists(Exe) then
    Exit(SR_GETIT_MISSING);

  Output := RunCaptured('"' + Exe + '" -l= -f=installed -s=' + SortBy +
    ' -v=minimal', 60000, ExitCode);
  if ExitCode <> 0 then
    Exit('GetItCmd fallo (exit ' + IntToStr(ExitCode) + '):' + sLineBreak +
      Output.Trim);

  // Strip the banner (product name + copyright) and the closing success
  // line - the agent pays context for the TABLE, not for ceremony.
  Sb := TStringBuilder.Create;
  try
    Lines := Output.Split([#13#10, #10]);
    for L in Lines do
    begin
      if L.Trim = '' then Continue;
      if L.StartsWith('GetIt Package Manager') then Continue;
      if L.StartsWith('Copyright (c)') then Continue;
      if L.StartsWith('Command finished') then Continue;
      Sb.AppendLine(L.TrimRight);
    end;
    Result := Sb.ToString.TrimRight + sLineBreak + sLineBreak + SN_GETIT_NOTE;
  finally
    Sb.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_getit',
    function: IMCPTool begin Result := TDelphiGetItTool.Create; end);

end.
