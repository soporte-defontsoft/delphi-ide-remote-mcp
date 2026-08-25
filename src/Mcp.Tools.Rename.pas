unit Mcp.Tools.Rename;

{ delphi_rename_symbol: semantic rename, preview only in this version.
  See Lsp.Rename for the applicability rule. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiRenameParams = class
  private
    FPath: string;
    FLine: Integer;
    FCharacter: Integer;
    FNewName: string;
    FMode: string;
  public
    [SchemaDescription(SP_RENAME_PATH)]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_RENAME_LINE)]
    [Required]
    property Line: Integer read FLine write FLine;
    [SchemaDescription(SP_RENAME_CHARACTER)]
    [Required]
    property Character: Integer read FCharacter write FCharacter;
    [SchemaDescription(SP_RENAME_NEWNAME)]
    [Required]
    property NewName: string read FNewName write FNewName;
    [SchemaDescription(SP_RENAME_MODE)]
    property Mode: string read FMode write FMode;
  end;

  TDelphiRenameTool = class(TMCPToolBase<TDelphiRenameParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiRenameParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Rename;

constructor TDelphiRenameTool.Create;
begin
  inherited;
  FName := 'delphi_rename_symbol';
  FDescription := SD_RENAME;
end;

function TDelphiRenameTool.ExecuteWithParams(const Params: TDelphiRenameParams): string;
var
  Mode: string;
  Ret: TJSONObject;
begin
  Mode := Params.Mode.Trim.ToLower;
  if Mode = '' then
    Mode := 'preview';
  if Mode = 'apply' then
    Exit(SR_RENAME_APPLY_NOT_YET);
  if Mode <> 'preview' then
    Exit(SR_RENAME_MODE);
  if Params.Path.Trim = '' then
    Exit(SR_RENAME_NEED_PATH);
  if Params.NewName.Trim = '' then
    Exit(SR_RENAME_NEED_NEWNAME);
  Result := ReadPathDenied(Params.Path); // preview only reads
  if Result <> '' then
    Exit;
  try
    Ret := RenamePreview(Params.Path, Params.Line, Params.Character,
      Params.NewName.Trim);
    try
      Result := Ret.ToJSON;
    finally
      Ret.Free;
    end;
  except
    on E: Exception do
      Result := 'error: ' + E.Message;
  end;
  Result := MaskDriveText('delphi_rename_symbol', Result);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_rename_symbol',
    function: IMCPTool begin Result := TDelphiRenameTool.Create; end);

end.
