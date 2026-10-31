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
    FOps: string;
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
    [SchemaDescription(SP_CHANGESET_OPS)]
    [JsonComoTexto]
    [Contenido]
    property Ops: string read FOps write FOps;
    [SchemaDescription(SP_CHANGESET_N)]
    property N: Integer read FN write FN;
  end;

  TDelphiChangesetTool = class(TMCPToolBase<TDelphiChangesetParams>)
  private
    function ApilaVarias(const AId, AOps: string): string;
  protected
    function ExecuteWithParams(const Params: TDelphiChangesetParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  System.JSON,
  MCPServer.Registration,
  MCPServer.Serializer,
  Lsp.Guard,
  Lsp.Mascara, // MaskDriveText: la ruta delante de cada aviso, como el commit
  Lsp.Patch,   // AvisosDelLector: el lector del IDE, fuera del cerrojo
  Lsp.Pascal,  // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.TextEdit, // NotaDeEstiloFmx: lo que FMX dice de un .style, fuera del cerrojo
  Lsp.Changeset;

constructor TDelphiChangesetTool.Create;
begin
  inherited;
  FName := 'delphi_changeset';
  FDescription := SD_CHANGESET;
end;

{ stage con "ops": varias operaciones en una llamada, todas o ninguna. Cada una
  entra por LA MISMA puerta que una suelta (ToolCallDenied: unidades virtuales,
  UNC, nombre largo, el suelo de la jaula) y por el mismo Execute (sus campos, lo
  que no va con su kind): una ruta de dentro de ops no tiene otra puerta, que
  seria un segundo lector de lo mismo. Si una se niega, las ya apiladas se
  retiran, y el agente corrige y manda la lista entera otra vez. }
function TDelphiChangesetTool.ApilaVarias(const AId, AOps: string): string;
const
  TOPE_OPS = 50;

  function Uno(const AElemento: TJSONValue; ANumero, ATotal: Integer; out ALinea: string): string;
  begin
    Result := '';
    if not (AElemento is TJSONObject) then
      Exit(MsgFmt(SR_CHANGESET_OP_NEGADA_FMT, [ANumero, ATotal, MsgFmt(SR_CHANGESET_OPS_LISTA_FMT, [TOPE_OPS])]));
    var Args := AElemento.Clone as TJSONObject;
    try
      for var P in Args do
        if MatchStr(TMCPSerializer.NormalizeKey(P.JsonString.Value), ['command', 'id', 'ops']) then
          Exit(MsgFmt(SR_CHANGESET_OP_CAMPO_FMT, [ANumero, P.JsonString.Value]));
      Args.AddPair('command', 'stage');
      Args.AddPair('id', AId);
      var Negada := ToolCallDenied('delphi_changeset', Args);
      if Negada <> '' then
        Exit(MsgFmt(SR_CHANGESET_OP_NEGADA_FMT, [ANumero, ATotal, MaskDriveText('', Negada)]));
      try
        ALinea := Execute(Args).AsString;
      except
        on E: Exception do
          Exit(MsgFmt(SR_CHANGESET_OP_NEGADA_FMT, [ANumero, ATotal, E.Message]));
      end;
      if not HasMsg(ALinea, SN_CHANGESET_STAGED_FMT) then
        Exit(MsgFmt(SR_CHANGESET_OP_NEGADA_FMT, [ANumero, ATotal, ALinea]));
    finally
      Args.Free;
    end;
  end;

var
  Valor: TJSONValue;
  Linea, Negativa: string;
begin
  Result := '';
  Valor := TJSONObject.ParseJSONValue(AOps);
  try
    if not (Valor is TJSONArray) or (TJSONArray(Valor).Count = 0) or
       (TJSONArray(Valor).Count > TOPE_OPS) then
      Exit(MsgFmt(SR_CHANGESET_OPS_LISTA_FMT, [TOPE_OPS]));
    var Lista := TJSONArray(Valor);
    for var I := 0 to Lista.Count - 1 do
    begin
      Negativa := Uno(Lista.Items[I], I + 1, Lista.Count, Linea);
      if Negativa <> '' then
      begin
        for var K := 1 to I do
        begin
          var Retira := TJSONObject.Create;
          try
            Retira.AddPair('command', 'unstage');
            Retira.AddPair('id', AId);
            Execute(Retira);
          finally
            Retira.Free;
          end;
        end;
        Exit(Negativa);
      end;
      // lo que vale para todas, una vez: con 50 eran 18 KB de lo mismo (medido en vivo)
      AnadeLinea(Result, Linea.Replace(MsgText(SF_CHANGESET_TRAS_STAGED), ''));
    end;
    Result := Result + MsgText(SF_CHANGESET_TRAS_STAGED);
  finally
    Valor.Free;
  end;
end;

function TDelphiChangesetTool.ExecuteWithParams(const Params: TDelphiChangesetParams): string;
begin
  // lo que no va con el COMANDO se dice (Lsp.Guard.ParametroQueNoVa): commit
  // o preview con kind / path / old / n se ignoraban (octava revision). Lo
  // de cada kind lo mira stage (CHSET-030)
  var Suyos, VaCon: string;
  var Modo := SinMayusculas(Params.Command.Trim);
  if (Modo = 'stage') and (Params.Ops.Trim <> '') then
    Modo := 'stage ops';
  var Sobra := ParametroQueNoVa(Modo, [
      'begin', '',
      'status', '', // status lista TODOS: su tabla decia id y SP_CHANGESET_ID no (novena)
      'stage', 'id kind path dest old new content atline fragment',
      'stage ops', 'id ops',
      'unstage', 'id n', 'undo', 'id n',
      'preview', 'id', 'commit', 'id', 'rollback', 'id'],
    ['id', Params.Id, '', 'kind', Params.Kind, '', 'path', Params.Path, '',
     'dest', Params.Dest, '', 'old', Params.Old, '', 'new', Params.New, '',
     'content', Params.Content, '', 'fragment', Params.Fragment, '',
     'ops', Params.Ops, '',
     'atline', IfThen(Params.AtLine <> 0, IntToStr(Params.AtLine)), '',
     'n', IfThen(Params.N <> 0, IntToStr(Params.N)), ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_CHANGESET_NO_VA_CON_COMANDO_FMT, [Sobra, Modo, Modo, ONinguno(Suyos)]) + VaCon);
  if Modo = 'stage ops' then
    Exit(ApilaVarias(Params.Id, Params.Ops));
  var Forms: TArray<TFormEscrito>;
  Result := ChangesetExecuteYForms(Params.Command, Params.Id, SinMayusculas(Params.Kind.Trim),
    Params.Path, Params.Dest, Params.Old, Params.New, Params.Content,
    Params.AtLine, Forms, Params.N, Params.Fragment);
  // los forms que el commit escribio, al LECTOR del IDE ya fuera de los
  // cerrojos, con su ruta delante como los avisos del lote (DSGN-061 de la 1.20);
  // con su texto de antes, lo que el lote les trae (V154 de la 1.23.1)
  var Avisos := '';
  for var F in Forms do
    if EsRutaDeEstilo(F.Ruta) then
    begin
      // un .style: lo que dice FMX, la nota de textedit (V173f de la 1.23.1)
      var Nota := NotaDeEstiloFmx(F.Ruta, '').Trim;
      if Nota <> '' then
        AnadeLineaDeRuta(Avisos, MaskDriveText('', F.Ruta), Nota);
    end
    else
      for var L in AvisosDelLector(F.Ruta, F.Antes) do
        AnadeLineaDeRuta(Avisos, MaskDriveText('', F.Ruta), L);
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
