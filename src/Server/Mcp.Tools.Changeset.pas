unit Mcp.Tools.Changeset;

{ delphi_changeset: multi-file transactions. See Lsp.Changeset for the
  engine and the invariants. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

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
    FFragment: string;
    FN: Integer;
  public
    [SchemaDescription(SP_CHANGESET_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_CHANGESET_ID)]
    property Id: string read FId write FId;
    [SchemaDescription(SP_CHANGESET_KIND)]
    property Kind: string read FKind write FKind;
    [SchemaDescription(SP_CHANGESET_PATH)]
    [RutaDelServidor]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_CHANGESET_DEST)]
    [RutaDelServidor]
    property Dest: string read FDest write FDest;
    [SchemaDescription(SP_CHANGESET_OLD)]
    [Contenido]
    property Old: string read FOld write FOld;
    [SchemaDescription(SP_CHANGESET_NEW)]
    [Contenido]
    property New: string read FNew write FNew;
    [SchemaDescription(SP_CHANGESET_CONTENT)]
    [Contenido]
    property Content: string read FContent write FContent;
    [SchemaDescription(SP_CHANGESET_ATLINE)]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription(SP_PATCH_FRAGMENT)]
    [Contenido]
    property Fragment: string read FFragment write FFragment;
    [SchemaDescription(SP_CHANGESET_N)]
    property N: Integer read FN write FN;
  end;

  TDelphiChangesetTool = class(TMCPToolBase<TDelphiChangesetParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiChangesetParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Mascara, // MaskDriveText: la ruta delante de cada aviso, como el commit
  Lsp.Patch,   // AvisosDelLector: el lector del IDE, fuera del cerrojo
  Lsp.Pascal,  // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Changeset;

constructor TDelphiChangesetTool.Create;
begin
  inherited;
  FName := 'delphi_changeset';
  FDescription := SD_CHANGESET;
end;

function TDelphiChangesetTool.ExecuteWithParams(const Params: TDelphiChangesetParams): string;
begin
  // lo que no va con el COMANDO se dice (Lsp.Guard.ParametroQueNoVa): commit
  // o preview con kind / path / old / n se ignoraban (octava revision). Lo
  // de cada kind lo mira stage (CHSET-030)
  var Suyos, VaCon: string;
  var Sobra := ParametroQueNoVa(SinMayusculas(Params.Command.Trim), [
      'begin', '',
      'status', '', // status lista TODOS: su tabla decia id y SP_CHANGESET_ID no (novena)
      'stage', 'id kind path dest old new content atline fragment',
      'unstage', 'id n', 'undo', 'id n',
      'preview', 'id', 'commit', 'id', 'rollback', 'id'],
    ['id', Params.Id, '', 'kind', Params.Kind, '', 'path', Params.Path, '',
     'dest', Params.Dest, '', 'old', Params.Old, '', 'new', Params.New, '',
     'content', Params.Content, '', 'fragment', Params.Fragment, '',
     'atline', IfThen(Params.AtLine <> 0, IntToStr(Params.AtLine)), '',
     'n', IfThen(Params.N <> 0, IntToStr(Params.N)), ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_CHANGESET_NO_VA_CON_COMANDO_FMT, [Sobra, SinMayusculas(Params.Command.Trim),
      SinMayusculas(Params.Command.Trim), ONinguno(Suyos)]) + VaCon);
  var Forms: TArray<string>;
  Result := ChangesetExecuteYForms(Params.Command, Params.Id, SinMayusculas(Params.Kind.Trim),
    Params.Path, Params.Dest, Params.Old, Params.New, Params.Content,
    Params.AtLine, Forms, Params.N, Params.Fragment);
  // los forms que el commit escribio, al LECTOR del IDE ya fuera de los
  // cerrojos, con su ruta delante como los avisos del lote (DSGN-061 de la 1.20)
  var Avisos := '';
  for var F in Forms do
    for var L in AvisosDelLector(F) do
      Avisos := Avisos + IfThen(Avisos <> '', #10, '') + Format('  %s: %s', [MaskDriveText('', F), L]);
  if Avisos <> '' then
    Result := Result + #10 + IfThen(HasMsg(Result, SN_CHANGESET_AVISOS_FMT), Avisos,
      MsgFmt(SN_CHANGESET_AVISOS_FMT, [Avisos]));
  // (lo enmascara el filtro de salida, Lsp.Host: aqui se enmascaraba otra vez
  // con el nombre de la tool, que gasta las citas del disco de la llamada - la
  // linea real de una negativa salia enmascarada; revision del 4-oct-2026)
end;

initialization
  TMCPRegistry.RegisterTool('delphi_changeset',
    function: IMCPTool begin Result := TDelphiChangesetTool.Create; end);

end.
