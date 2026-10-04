unit Mcp.Tools.Docs;

// delphi_docs (1.10.0): the RAD Studio help installed with Delphi - what the
// IDE opens with F1 - as a wiki an agent searches and reads in small pieces,
// so that it stops guessing APIs. The engine is Lsp.Docs; this unit is the
// contract: search gives a short list, read gives one page in chunks.
//
// Measured 2026-10-02 before writing it: 32 real concepts and classes, the
// right page among the first five in all of them; a list of 10 results costs
// about 145 tokens, and half of the pages no more than 170. With the tool
// written, 37 of them, the right page FIRST in all (test_delphi_docs D2).
//
// It asks for no switch (David, 2-oct-2026): it opens only the .chm files
// the IDE itself registers, an id never leaves its .chm, and what comes back
// is the product's documentation. LibraryZone=0 is there to keep the SOURCES
// of the installed components out of reach; the help is not them.

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts;

type
  TDelphiDocsParams = class
  private
    FCommand: string;
    FQuery: string;
    FId: string;
    FFramework: string;
    FOffset: Integer;
    FLimit: Integer;
  public
    [SchemaDescription(SP_DOCS_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_DOCS_QUERY)]
    property Query: string read FQuery write FQuery;
    [SchemaDescription(SP_DOCS_ID)]
    property Id: string read FId write FId;
    [SchemaDescription(SP_DOCS_FRAMEWORK)]
    property Framework: string read FFramework write FFramework;
    [SchemaDescription(SP_DOCS_OFFSET)]
    [SchemaDefault('0')]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription(SP_DOCS_LIMIT)]
    [SchemaDefault('10')]
    property Limit: Integer read FLimit write FLimit;
  end;

  TDelphiDocsTool = class(TMCPToolBase<TDelphiDocsParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDocsParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.JSON,
  MCPServer.Registration,
  Lsp.Discovery,
  Lsp.Guard,  // MaskDriveText
  Lsp.Docs;

const
  // lo que se da de una pagina de una vez, unos 2.000 tokens (medido: la
  // mitad de las paginas no pasa de 700 caracteres)
  TROZO = 8000;

constructor TDelphiDocsTool.Create;
begin
  inherited;
  FName := 'delphi_docs';
  FDescription := SD_DOCS;
end;

{ Lo que la tool devuelve TAL CUAL de lo que le pidieron (la consulta, el id,
  la seccion): delphi_docs esta entre las tools cuyo eco no se enmascara (su
  texto es la ayuda), y lo que entro ya paso por la expansion de las unidades
  virtuales: un \\srvhost\... salia con el nombre real (revision de la
  1.10.0). La obligacion de la lista de exentas: lo propio, por MaskDriveText. }
function Eco(const S: string): string;
begin
  Result := MaskDriveText('', S);
end;

function Busca(const Params: TDelphiDocsParams; const AFramework: string;
  const AAyudas: TArray<TAyudaInstalada>): string;
var
  Total, Limite, Abiertas: Integer;
  Res: TArray<TResultadoDoc>;
  Ret: TJSONObject;
  Arr: TJSONArray;
begin
  // sin palabras (vacia, o solo comillas y signos) no hay consulta
  if Length(PalabrasDeConsulta(Params.Query)) = 0 then
    Exit(MsgText(SR_DOCS_SIN_CONSULTA));
  Limite := Params.Limit;
  if Limite <= 0 then
    Limite := 10;
  Limite := Min(Limite, 25);
  Res := BuscaEnLaAyuda(AAyudas, Params.Query, AFramework, Limite, Total, Abiertas);
  if Length(Res) = 0 then
    if Abiertas = 0 then
      Exit(MsgText(SR_DOCS_NINGUNA_ABRE))
    else
      Exit(MsgFmt(SR_DOCS_NADA_FMT, [Params.Query.Trim]));
  Ret := TJSONObject.Create;
  try
    Ret.AddPair('query', Eco(Params.Query.Trim));
    Arr := TJSONArray.Create;
    for var R in Res do
      Arr.AddElement(TJSONObject.Create.AddPair('id', R.Id).AddPair('title', R.Titulo));
    Ret.AddPair('results', Arr);
    Ret.AddPair('total', TJSONNumber.Create(Total));
    Ret.AddPair('note', MsgText(SN_DOCS_BUSQUEDA));
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

function Lee(const Params: TDelphiDocsParams; const AAyudas: TArray<TAyudaInstalada>): string;
var
  Id, Corto, Pagina, Ancla, Nota: string;
  Pag: TPaginaDoc;
  Ayuda: TAyudaInstalada;
  Desde, Hasta, Total, Corte: Integer;
  Entrada: Boolean;
  Ret: TJSONObject;
  Arr: TJSONArray;
begin
  Id := Params.Id.Trim;
  if Id = '' then
    Exit(MsgText(SR_DOCS_SIN_ID));
  case LeePaginaDeLaAyuda(AAyudas, Id, Pag, Ayuda) of
    ldIdMalFormado:
      Exit(MsgFmt(SR_DOCS_ID_MAL_FMT, [Params.Id.Trim]));
    ldSinPagina:
      Exit(MsgFmt(SR_DOCS_NO_PAGINA_FMT, [Params.Id.Trim]));
    ldNoAbre:
      Exit(MsgFmt(SR_DOCS_NO_ABRE_FMT, [ExtractFileName(Ayuda.Fichero)]));
  end;
  PartesDeId(Id, Corto, Pagina, Ancla);
  // la seccion pedida por su titulo contesta con su ancla
  if Pag.AnclaEncontrada then
    Ancla := Pag.Ancla;
  Total := Length(Pag.Texto);
  Desde := EnsureRange(Params.Offset, 0, Total);
  Hasta := Min(Desde + TROZO, Total);
  // el corte, en un fin de linea si lo hay en el ultimo quinto del trozo
  if Hasta < Total then
  begin
    Corte := Pag.Texto.LastIndexOf(#10, Hasta - 1, Hasta - Desde);
    if Corte > Desde + (TROZO * 4) div 5 then
      Hasta := Corte + 1;
  end;
  // la primera lectura de una pagina larga con secciones es su entrada: lo
  // que dice antes de su primer titulo, y la lista de secciones para ir a la
  // que haga falta (lo justo para entender y navegar; 8.000 caracteres de
  // golpe: Declarations and Statements eran 11.300 caracteres y su entrada,
  // 1.515, medido el 2-oct-2026). El resto sigue con offset. Una seccion que
  // la pagina no tiene da lo mismo: la lista para elegir la buena
  Entrada := ((Ancla = '') or not Pag.AnclaEncontrada) and (Desde = 0) and
    (Hasta < Total) and (Length(Pag.Secciones) > 0);
  if Entrada then
  begin
    // un titulo del texto empieza por ## (HtmlATexto nunca escribe menos); un
    // # suelto puede ser una linea de codigo (#13#10, un #include)
    Corte := Pag.Texto.IndexOf(#10'##');
    if (Corte >= 0) and (Corte + 1 < Hasta) then
      Hasta := Corte + 1;
  end;
  Ret := TJSONObject.Create;
  try
    // la ayuda y la pagina ya estan validadas (son de una ayuda instalada); lo
    // libre es la seccion. Enmascarar el id entero estropeaba el de una ayuda
    // de nombre de una letra (x:Pagina.htm parece una unidad)
    Ret.AddPair('id', IdDePagina(Corto, Pagina, Eco(Ancla)));
    Ret.AddPair('title', Pag.Titulo);
    Ret.AddPair('text', Pag.Texto.Substring(Desde, Hasta - Desde));
    Ret.AddPair('length', TJSONNumber.Create(Total));
    if Desde > 0 then
      Ret.AddPair('offset', TJSONNumber.Create(Desde));
    if Hasta < Total then
      Ret.AddPair('nextOffset', TJSONNumber.Create(Hasta));
    // sus secciones, solo el ancla, que se lee como el titulo; repetir el id
    // de la pagina y el titulo en cada una era un tercio del primer trozo
    // (3.300 de 11.300 caracteres en Declarations and Statements, medido el
    // 2-oct-2026)
    if Entrada then
    begin
      Arr := TJSONArray.Create;
      for var S in Pag.Secciones do
        Arr.Add(S.Ancla);
      Ret.AddPair('sections', Arr);
    end;
    // la que acaba en su primer subtitulo: los que siguen, por su ancla
    if Length(Pag.Subsecciones) > 0 then
    begin
      Arr := TJSONArray.Create;
      for var A in Pag.Subsecciones do
        Arr.Add(A);
      Ret.AddPair('subsections', Arr);
    end;
    // las de alrededor: el padre y, en una clase, su unidad y sus listas de
    // miembros, con su id (de lo que cuelga Y lo que cuelga de ella)
    if (Desde = 0) and (Length(Pag.Enlaces) > 0) then
    begin
      Arr := TJSONArray.Create;
      for var E in Pag.Enlaces do
      begin
        var EId := IdDeEnlace(E.Href, Corto);
        if EId <> '' then
          Arr.AddElement(TJSONObject.Create.AddPair('id', EId).AddPair('title', E.Texto));
      end;
      if Arr.Count > 0 then
        Ret.AddPair('related', Arr)
      else
        Arr.Free;
    end;
    Nota := MsgFmt(SN_DOCS_FUENTE_FMT, [ExtractFileName(Ayuda.Fichero),
      FormatDateTime('yyyy-mm-dd', Ayuda.Fecha)]);
    if (Ancla <> '') and not Pag.AnclaEncontrada then
      Nota := MsgFmt(SN_DOCS_SIN_SECCION_FMT, [Eco(Ancla)]) + ' ' + Nota;
    if Length(Pag.Subsecciones) > 0 then
      Nota := MsgText(SN_DOCS_SUBSECCIONES) + ' ' + Nota;
    if Hasta < Total then
      Nota := Nota + ' ' + MsgFmt(SN_DOCS_SIGUE_FMT, [Hasta, Total, Hasta]);
    Ret.AddPair('note', Nota);
    Result := Ret.ToJSON;
  finally
    Ret.Free;
  end;
end;

function TDelphiDocsTool.ExecuteWithParams(const Params: TDelphiDocsParams): string;
var
  Cmd, Fw, Version: string;
  Ayudas: TArray<TAyudaInstalada>;
begin
  Cmd := Params.Command.Trim.ToLower;
  if Cmd = '' then
    if Params.Id.Trim <> '' then
      Cmd := 'read'
    else
      Cmd := 'search';
  if not MatchText(Cmd, ['search', 'read']) then
    Exit(MsgText(SR_DOCS_CMD));
  // las ayudas, UNA vez por llamada (eran tres: aqui, en la busqueda y en la
  // lectura, con la version de bds.exe leida cada vez)
  Ayudas := AyudasInstaladas;
  if Length(Ayudas) = 0 then
  begin
    Version := DiscoverRadStudio.Version;
    Exit(MsgFmt(SR_DOCS_SIN_AYUDA_FMT, [IfThen(Version <> '', Version, '-')]));
  end;
  if Cmd = 'read' then
    Exit(Lee(Params, Ayudas));
  // framework es de la busqueda: en una lectura no se mira
  Fw := Params.Framework.Trim.ToLower;
  if (Fw <> '') and not MatchText(Fw, ['vcl', 'fmx']) then
    Exit(MsgFmt(SR_DOCS_FRAMEWORK_FMT, [Params.Framework.Trim]));
  Result := Busca(Params, Fw, Ayudas);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_docs',
    function: IMCPTool begin Result := TDelphiDocsTool.Create; end);

end.
