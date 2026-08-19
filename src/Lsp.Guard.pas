unit Lsp.Guard;

{ Workspace jail. When workspace roots are configured - DELPHI_MCP_ROOTS
  environment variable or settings.ini [Workspace] Roots (semicolon-
  separated), next to the server exe - EVERY tool that touches the disk
  must stay inside them: reads, edits, scaffolding, builds, lint, search,
  listing, git. Paths are canonicalized before comparison so ..\ tricks and
  prefix cousins (D:\Foo vs D:\FooBar) do not escape.

  With NO roots configured there is no restriction (local trusted mode);
  for remote exposure configure roots AND the Bearer token. }

interface

{ '' = allowed; otherwise the rejection message to return to the agent. }
function PathDenied(const APath: string): string;

{ The configured roots (empty array = unrestricted). }
function WorkspaceRoots: TArray<string>;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IniFiles,
  System.IOUtils;

var
  GLoaded: Boolean = False;
  GRoots: TArray<string>;

function WorkspaceRoots: TArray<string>;
var
  Raw, IniPath, R: string;
  Ini: TIniFile;
  List: TStringList;
begin
  if not GLoaded then
  begin
    Raw := GetEnvironmentVariable('DELPHI_MCP_ROOTS');
    if Raw = '' then
    begin
      IniPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'settings.ini');
      if TFile.Exists(IniPath) then
      begin
        Ini := TIniFile.Create(IniPath);
        try
          Raw := Ini.ReadString('Workspace', 'Roots', '');
        finally
          Ini.Free;
        end;
      end;
    end;
    List := TStringList.Create;
    try
      for R in Raw.Split([';']) do
        if R.Trim <> '' then
        try
          List.Add(IncludeTrailingPathDelimiter(TPath.GetFullPath(R.Trim)));
        except
          // an unparseable root is ignored, never crashes the server
        end;
      GRoots := List.ToStringArray;
    finally
      List.Free;
    end;
    GLoaded := True;
  end;
  Result := GRoots;
end;

function PathDenied(const APath: string): string;
var
  Roots: TArray<string>;
  Full, R: string;
begin
  Result := '';
  Roots := WorkspaceRoots;
  if Length(Roots) = 0 then
    Exit; // no jail configured
  try
    Full := TPath.GetFullPath(APath);
  except
    Exit('RECHAZADO: ruta invalida: ' + APath);
  end;
  for R in Roots do
    if StartsText(R, IncludeTrailingPathDelimiter(Full)) then
      Exit;
  Result := Format('RECHAZADO: "%s" esta FUERA de los workspaces permitidos. ' +
    'Este servidor solo opera dentro de: %s (configurado en DELPHI_MCP_ROOTS ' +
    'o settings.ini [Workspace] Roots).', [APath, string.Join(' | ', Roots)]);
end;

end.
