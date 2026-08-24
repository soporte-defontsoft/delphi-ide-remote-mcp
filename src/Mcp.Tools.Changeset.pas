unit Mcp.Tools.Changeset;

{ delphi_changeset: multi-file transactions. See Lsp.Changeset for the
  engine and the invariants. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiChangesetParams = class
  private
    FCommand: string;
    FId: string;
    FKind: string;
    FPath: string;
    FDest: string;
    FOld: string;
    FNew: string;
    FContent: string;
    FAtLine: Integer;
  public
    [SchemaDescription(SP_CHANGESET_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_CHANGESET_ID)]
    property Id: string read FId write FId;
    [SchemaDescription(SP_CHANGESET_KIND)]
    property Kind: string read FKind write FKind;
    [SchemaDescription(SP_CHANGESET_PATH)]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_CHANGESET_DEST)]
    property Dest: string read FDest write FDest;
    [SchemaDescription(SP_CHANGESET_OLD)]
    property Old: string read FOld write FOld;
    [SchemaDescription(SP_CHANGESET_NEW)]
    property New: string read FNew write FNew;
    [SchemaDescription(SP_CHANGESET_CONTENT)]
    property Content: string read FContent write FContent;
    [SchemaDescription(SP_CHANGESET_ATLINE)]
    property AtLine: Integer read FAtLine write FAtLine;
  end;

  TDelphiChangesetTool = class(TMCPToolBase<TDelphiChangesetParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiChangesetParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Changeset;

constructor TDelphiChangesetTool.Create;
begin
  inherited;
  FName := 'delphi_changeset';
  FDescription := SD_CHANGESET;
end;

function TDelphiChangesetTool.ExecuteWithParams(const Params: TDelphiChangesetParams): string;
begin
  Result := ChangesetExecute(Params.Command, Params.Id, Params.Kind.Trim.ToLower,
    Params.Path, Params.Dest, Params.Old, Params.New, Params.Content,
    Params.AtLine);
  Result := MaskDriveText('delphi_changeset', Result);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_changeset',
    function: IMCPTool begin Result := TDelphiChangesetTool.Create; end);

end.
