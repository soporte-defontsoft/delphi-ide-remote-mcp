unit Mcp.Tools.TextEdit;

{ delphi_textedit: safe editing of plain-text NON-Delphi files (docs, tests,
  scripts, config) so a remote agent can maintain a whole project - README,
  CHANGELOG, test batteries, .gitignore - through this MCP. Engine in
  Lsp.TextEdit; Delphi sources stay on delphi_edit. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.TextEdit;

type
  TDelphiTextEditParams = class
  private
    FPath: string;
    FOld: string;
    FNew: string;
    FAtLine: Integer;
    FEdits: string;
    FDelete: Boolean;
    FCreate: Boolean;
    FContent: string;
    FEol: string;
  public
    [SchemaDescription('Absolute path of the text file (.md .txt .html .js .css .sql .py .bat .ini .json .yml .xml ... any plain text - Delphi files are refused, use delphi_edit)')]
    [Required]
    property Path: string read FPath write FPath;
    [SchemaDescription('EDIT mode: the exact line to replace - ONE full line copied literally from delphi_read (everything after the | bar). Leading indentation may be omitted')]
    property Old: string read FOld write FOld;
    [SchemaDescription('EDIT mode: the new text; may be several lines. Empty = blank the line')]
    property New: string read FNew write FNew;
    [SchemaDescription('EDIT mode tie-break when the anchor appears on several lines: 1-based line number of the exact occurrence')]
    property AtLine: Integer read FAtLine write FAtLine;
    [SchemaDescription('VARIAS ediciones sobre ESTE MISMO fichero, en una sola llamada y TODO O NADA: un array JSON [{"old":"...","new":"...","atline":12},...] que se aplica EN ORDEN. Cada entrada admite dos formas de ancla: UNA LINEA (igual que una edicion suelta) o un BLOQUE de varias lineas seguidas en "old", que se busca entero y en orden - es la forma de tocar un parrafo largo de documentacion sin pegarlo dos veces. Si el ancla aparece mas de una vez, desempata con "occurrence": 1, 2... (mejor que "atline" dentro de una tanda: los numeros de linea SE MUEVEN segun las entradas anteriores anaden o quitan lineas). "delete": true quita la linea. Si una entrada falla, el fichero vuelve byte a byte a como estaba y te digo cual fallo. Si el cambio toca VARIOS ficheros, eso es delphi_changeset. Cuando mandas "edits" se ignoran old/new/atline/delete')]
    property Edits: string read FEdits write FEdits;
    [SchemaDescription('DELETE mode: true = quita ENTERA la linea anclada en "old" (old + new vacio solo la deja en blanco). Aqui no va "new"')]
    property Delete: Boolean read FDelete write FDelete;
    [SchemaDescription('CREATE mode: true = create a NEW file (never overwrites). UTF-8, parent directories created')]
    property Create_: Boolean read FCreate write FCreate;
    [SchemaDescription('CREATE mode: the initial content of the new file (may be empty)')]
    property Content: string read FContent write FContent;
    [SchemaDescription('CREATE mode: line endings, "crlf" (default) or "lf"')]
    property Eol: string read FEol write FEol;
  end;

  TDelphiTextEditTool = class(TMCPToolBase<TDelphiTextEditParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiTextEditParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration;

{ TDelphiTextEditTool }

constructor TDelphiTextEditTool.Create;
begin
  inherited;
  FName := 'delphi_textedit';
  FDescription := 'SAFE editing of plain-text NON-Delphi files (.md .txt ' +
    '.html .js .css .sql .py .bat .ini .json .yml .xml - ANY plain text): ' +
    'docs, web assets, tests, scripts, config. Same ' +
    'discipline as delphi_edit - one-full-line unique anchor (old/new, ' +
    'atline tie-break), DELETE mode (delete=true + old), several edits on ' +
    'the SAME file in one all-or-nothing call ("edits", where an anchor may ' +
    'be ONE line or a contiguous BLOCK), ' +
    'real encoding preserved (UTF-8 +/- BOM / CP1252), ' +
    'line endings preserved, automatic backup, atomic write - without the ' +
    'Pascal gates. CREATE mode (create=true + content) for new files, never ' +
    'overwrites. Whole-file rewrites are refused. Delphi sources/designers ' +
    'are refused (use delphi_edit) and so are .dproj and binaries. Read ' +
    'first with delphi_read and copy the anchor exactly.';
end;

function TDelphiTextEditTool.ExecuteWithParams(const Params: TDelphiTextEditParams): string;
var
  A: TTextEditArgs;
begin
  if Params.Edits.Trim <> '' then
    Exit(ExecuteTextEdits(Params.Path, Params.Edits));
  A := Default(TTextEditArgs);
  A.Path := Params.Path;
  A.OldLine := Params.Old;
  A.NewText := Params.New;
  A.HasOld := Params.Old <> '';
  A.HasNew := (Params.New <> '') or A.HasOld;
  A.AtLine := Params.AtLine;
  A.DeleteLine := Params.Delete;
  A.CreateFile_ := Params.Create_;
  A.Content := Params.Content;
  A.Eol := Params.Eol;
  Result := ExecuteTextEdit(A);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_textedit',
    function: IMCPTool begin Result := TDelphiTextEditTool.Create; end);

end.
