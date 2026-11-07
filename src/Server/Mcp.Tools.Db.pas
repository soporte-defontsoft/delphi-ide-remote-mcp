unit Mcp.Tools.Db;

{ delphi_db (1.29): las bases de datos con nombre que define el operador
  (Lsp.Conexiones) y abre a cada workspace con DbAllowedProjects=, por
  OPERACIONES y nunca por SQL: el agente pide, el servidor compone y FireDAC
  traduce a cada motor (David, 6-nov-2026: "el agente no puede escribir sql",
  como las tools de tablas del Centro de IA de la casa; Lsp.BaseDeDatos).

  Primera parte: connections, las bases de ESTA sesion por su nombre
  <proyecto>/<alias>, su motor y si son de solo lectura; las declaradas mal,
  aparte con el porque (un fragmento: un SR_ no va en un campo JSON).
  Segunda: tables, fields, rows y summary, en una transaccion que se
  deshace. Tercera: insert, update y delete, solo donde el json dice
  readonly:false (la primera barrera, antes de conectar), y update y delete
  solo con filters (tampoco una lista vacia: tocaria todas las filas).
  Todas, con plazo para la llamada ENTERA (EnLaBase): la base que abre y
  calla a mitad ya no deja a quien llama esperando sin fin (CH11). }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Attributes, // JsonComoTexto: las listas
  Lsp.Texts;

type
  TDelphiDbParams = class
  private
    FCommand, FDb, FTable, FFields, FFilters, FOrder, FGroup, FValues: string;
    FLimit, FOffset: Integer;
  public
    [SchemaDescription(SP_DB_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_DB_DB)]
    property Db: string read FDb write FDb;
    [SchemaDescription(SP_DB_TABLE)]
    property Table: string read FTable write FTable;
    [SchemaDescription(SP_DB_FIELDS)]
    [JsonComoTexto('string')]
    property Fields: string read FFields write FFields;
    [SchemaDescription(SP_DB_FILTERS)]
    [JsonComoTexto]
    property Filters: string read FFilters write FFilters;
    [SchemaDescription(SP_DB_ORDER)]
    property Order: string read FOrder write FOrder;
    [SchemaDescription(SP_DB_LIMIT)]
    property Limit: Integer read FLimit write FLimit;
    [SchemaDescription(SP_DB_OFFSET)]
    property Offset: Integer read FOffset write FOffset;
    [SchemaDescription(SP_DB_GROUP)]
    [JsonComoTexto('string')]
    property Group: string read FGroup write FGroup;
    [SchemaDescription(SP_DB_VALUES)]
    [JsonComoTexto]
    property Values: string read FValues write FValues;
  end;

  TDelphiDbTool = class(TMCPToolBase<TDelphiDbParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDbParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.JSON, System.StrUtils, System.Variants, System.DateUtils, System.Math,
  Data.DB, Data.FmtBcd,
  FireDAC.Comp.Client,
  MCPServer.Registration,
  Lsp.Pascal, // SinMayusculas: EL pliegue de lo que no es una ruta
  Lsp.Json, // ListaJson, ListaDeTextos: las listas de los parametros
  Lsp.Guard, // ParametroQueNoVa: lo que no es del comando se dice
  Lsp.Settings, // LeeSiNo: LA gramatica del si/no
  Lsp.Conexiones,
  Lsp.Listas, // PrincipioDeTexto: cortar sin partir un par UTF-16
  Lsp.Mascara, // ExpandDriveValue: EL inverso de la mascara de unidades
  Lsp.BaseDeDatos, // TrabajoConLaBase: el plazo de la llamada entera (EnLaBase)
  System.Rtti, // CopiaDeParams: los parametros, campo a campo
  System.SyncObjs; // TInterlocked: la llamada abandonada

const
  LIMITE_FILAS_DB = 100;
  LIMITE_GRUPOS_DB = 50;
  LIMITE_MAXIMO_DB = 500;
  // lo que cabe en una respuesta de rows o summary (caracteres de su JSON):
  // al menos una fila, y lo que no cabe se dice (truncated) - la leccion de
  // las tools de tablas de la casa: un "cuantos hay" no se trae las filas
  PRESUPUESTO_FILAS_DB = 60000;
  // ...y lo que cabe de UN texto de una celda: la primera fila de una pagina va
  // siempre, y un memo de 1 MB entraba entero en la respuesta (DB-P4 de la
  // 1.29). Un tercio: caben tres asi en una fila sin pasar del presupuesto
  LIMITE_TEXTO_CELDA_DB = PRESUPUESTO_FILAS_DB div 3;
  // las operaciones del agente: listas NUESTRAS (no hay juez; son el
  // contrato de la tool), cada una con lo que compone el servidor
  OPS_DE_FILTRO: array [0 .. 9] of string = ('equals', 'not_equals', 'greater',
    'less', 'greater_or_equal', 'less_or_equal', 'contains', 'starts_with', 'words',
    'empty');
  OPS_DE_VALOR: array [0 .. 4] of string = ('sum', 'avg', 'min', 'max', 'count');
  PARTES_DE_FECHA: array [0 .. 3] of string = ('year', 'month', 'day', 'hour');
  // la funcion de escape de FireDAC de cada parte: la traduce el a cada motor
  // (YEAR -> DATEPART en MSSQL, TO_CHAR en PG: medido el 6-nov-2026)
  FUNCIONES_DE_PARTE: array [0 .. 3] of string = ('YEAR', 'MONTH', 'DAYOFMONTH', 'HOUR');

type
  TParametroDb = record
    Nombre: string;
    Tipo: TFieldType;
    Valor: Variant;
  end;

  TLlamadaDb = class;

  { Lo que tiene abierto una operacion: la entrada del json, su conexion y la
    llamada que la espera (EnLaBase). }
  TSesionDb = record
    Conexion: TConexionDb;
    Conn: TFDConnection;
    Llamada: TLlamadaDb;
    { EL commit de una operacion: solo si quien la pidio sigue esperando. A
      una llamada vencida ya se le contesto DB-022, y lo que su hilo haga
      despues no se confirma: la operacion la deshace en su finally. }
    procedure Confirma;
  end;

  { Una llamada a una base con el plazo de la llamada ENTERA (EnLaBase): su
    sesion, su copia de los parametros, lo que contesta y si quien la pidio
    se fue (Abandonada, por TInterlocked). La libera quien acabe el ultimo
    (Lsp.ConPlazo), y con ella su conexion y su copia. }
  TLlamadaDb = class
  public
    S: TSesionDb;
    P: TDelphiDbParams;
    Respuesta: string;
    Abandonada: Integer;
    SinConfirmar: Boolean; // Confirma no confirmo: se habia vencido
    destructor Destroy; override;
  end;

  { Lo que hace una orden con la base ya abierta. }
  TOperacionDb = reference to function(const S: TSesionDb; const P: TDelphiDbParams): string;

function EsTexto(T: TFieldType): Boolean;
begin
  Result := T in [ftString, ftWideString, ftMemo, ftWideMemo, ftFixedChar, ftFixedWideChar];
end;

function EsBinario(T: TFieldType): Boolean;
begin
  Result := T in [ftBytes, ftVarBytes, ftBlob, ftGraphic, ftTypedBinary, ftOraBlob, ftStream];
end;

function EsNumero(T: TFieldType): Boolean;
begin
  Result := T in [ftSmallint, ftInteger, ftWord, ftLargeint, ftShortint, ftByte, ftLongWord,
    ftAutoInc, ftFloat, ftSingle, ftExtended, ftCurrency, ftBCD, ftFMTBcd];
end;

function EsFecha(T: TFieldType): Boolean;
begin
  Result := T in [ftDate, ftTime, ftDateTime, ftTimeStamp, ftOraTimeStamp];
end;

{ AValor convertido al tipo de ACampo, con los jueces de la RTL (ISO 8601,
  el BCD y el flotante en la forma invariante) y LA gramatica del si/no; el
  parametro se tipa con el tipo del campo, que PG no compara un entero con un
  texto. False si no cabe. }
function ValorParaCampo(AValor: TJSONValue; const ACampo: TCampoDb; out AVar: Variant): Boolean;
var
  S: string;
  I: Int64;
  D: Double;
  F: TDateTime;
  B: Boolean;
  Bcd: TBcd;
begin
  Result := False;
  AVar := Null;
  if not ((AValor is TJSONBool) or (AValor is TJSONNumber) or (AValor is TJSONString)) then
    Exit;
  S := TextoDeValor(AValor);
  case ACampo.TipoDeCampo of
    ftBoolean:
      begin
        if not LeeSiNo(S, B) then
          Exit;
        AVar := B;
      end;
    ftSmallint, ftInteger, ftWord, ftLargeint, ftShortint, ftByte, ftLongWord, ftAutoInc:
      begin
        if not TryStrToInt64(S, I) then
          Exit;
        AVar := I;
      end;
    ftFloat, ftSingle, ftExtended, ftCurrency:
      begin
        if not TryStrToFloat(S, D, TFormatSettings.Invariant) then
          Exit;
        AVar := D;
      end;
    ftBCD, ftFMTBcd:
      begin
        if not TryStrToBcd(S, Bcd, TFormatSettings.Invariant) then
          Exit;
        AVar := VarFMTBcdCreate(Bcd);
      end;
    ftDate, ftTime, ftDateTime, ftTimeStamp, ftOraTimeStamp:
      begin
        // AReturnUTC=True: una fecha SIN zona queda como se escribe y una con
        // zona pasa a UTC por su desplazamiento. Con False la RTL toma la que
        // no trae zona por UTC y la pasa a la hora local de esta maquina
        // (System.DateUtils.AdjustDateTime; medido el 6-nov-2026: 04:05 se
        // guardaba como 05:05 y un equals de una fecha no encontraba nada)
        if not TryISO8601ToDate(S, F, True) then
          Exit;
        AVar := VarFromDateTime(F);
      end;
  else
    if not EsTexto(ACampo.TipoDeCampo) and (ACampo.TipoDeCampo <> ftGuid) then
      Exit;
    // Lo que la base dice sale por la mascara de unidades (D:\ -> srvd:\), y
    // el agente lo devuelve tal cual: un update escribia srvd:\ en la base y
    // un equals no lo encontraba (CH7 del revisor del paisaje de la 1.29). De
    // vuelta, por EL inverso de la mascara, el de los argumentos de toda
    // llamada: un valor entero que empieza por una unidad servida.
    AVar := ExpandDriveValue(S);
  end;
  Result := True;
end;

{ El valor de F en el JSON de la respuesta: su tipo JSON (numero, booleano,
  null), una fecha en ISO 8601, un decimal exacto, y lo binario dicho por su
  tamano. }
function ValorDeCampo(F: TField): TJSONValue;
begin
  if F.IsNull then
    Exit(TJSONNull.Create);
  case F.DataType of
    ftBoolean:
      Result := TJSONBool.Create(F.AsBoolean);
    ftSmallint, ftInteger, ftWord, ftLargeint, ftShortint, ftByte, ftLongWord, ftAutoInc:
      Result := TJSONNumber.Create(F.AsLargeInt);
    ftFloat, ftSingle, ftExtended, ftCurrency:
      Result := TJSONNumber.Create(F.AsFloat);
    ftBCD, ftFMTBcd:
      Result := TJSONNumber.Create(BcdToStr(F.AsBCD, TFormatSettings.Invariant));
    ftDate:
      Result := TJSONString.Create(FormatDateTime('yyyy"-"mm"-"dd', F.AsDateTime));
    ftTime:
      Result := TJSONString.Create(FormatDateTime('hh":"nn":"ss', F.AsDateTime));
    ftDateTime, ftTimeStamp, ftOraTimeStamp:
      Result := TJSONString.Create(FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', F.AsDateTime));
  else
    if EsBinario(F.DataType) then
      Result := TJSONString.Create(MsgFmt(SF_DB_BINARIO_FMT, [Length(F.AsBytes)]))
    else
    begin
      var Texto := F.AsWideString;
      if Length(Texto) <= LIMITE_TEXTO_CELDA_DB then
        Exit(TJSONString.Create(Texto));
      // cortado, y dicho: el principio (sin partir un par UTF-16) y lo que mide
      var Cortado := TJSONObject.Create;
      Cortado.AddPair('text', PrincipioDeTexto(Texto, LIMITE_TEXTO_CELDA_DB));
      Cortado.AddPair('length', TJSONNumber.Create(Length(Texto)));
      Cortado.AddPair('truncated', TJSONBool.Create(True));
      Result := Cortado;
    end;
  end;
end;

{ Un texto como patron de LIKE con ESCAPE '\': sus comodines, literales. }
function SinComodines(const S: string): string;
begin
  Result := S.Replace('\', '\\').Replace('%', '\%').Replace('_', '\_');
end;

function OperadorDe(const AOp: string): string;
begin
  case IndexText(AOp, ['equals', 'not_equals', 'greater', 'less', 'greater_or_equal']) of
    0: Result := '=';
    1: Result := '<>';
    2: Result := '>';
    3: Result := '<';
    4: Result := '>=';
  else
    Result := '<=';
  end;
end;

{ La base que nombra ADb, abierta, o la negativa: de la sesion, usable, y la
  conexion con su plazo (Lsp.BaseDeDatos.AbreBase). Para escribir
  (AEscribe), una que el json no declara de solo lectura: la primera
  barrera, antes de conectar. }
function AbreLaBase(const ACmd, ADb: string; AEscribe: Boolean; out S: TSesionDb): string;
var
  Por: string;
begin
  S := Default(TSesionDb);
  if ADb.Trim = '' then
    Exit(MsgFmt(SR_DB_FALTA_FMT, [ACmd, 'db']));
  if not ConexionDbDeLaSesion(ADb, S.Conexion, Result) then
    Exit;
  Por := DefectoDeConexion(S.Conexion);
  if Por <> '' then
    Exit(MsgFmt(SR_DB_INUTILIZABLE_FMT, [NombreDeConexion(S.Conexion), Por]));
  if AEscribe and S.Conexion.SoloLectura then
    Exit(MsgFmt(SR_DB_SOLO_LECTURA_FMT, [NombreDeConexion(S.Conexion), ACmd]));
  Result := AbreBase(S.Conexion, S.Conn);
end;

destructor TLlamadaDb.Destroy;
begin
  S.Conn.Free;
  P.Free;
  inherited;
end;

procedure TSesionDb.Confirma;
begin
  if (Llamada <> nil) and (TInterlocked.CompareExchange(Llamada.Abandonada, 0, 0) <> 0) then
  begin
    Llamada.SinConfirmar := True;
    Abort;
  end;
  Conn.Commit;
end;

{ Una copia de AParams para el hilo de la llamada (EnLaBase): el marco de las
  tools libera la suya al volver, y una llamada vencida sigue leyendo en su
  hilo. Campo a campo por RTTI: un parametro nuevo viaja sin tocar esto. }
function CopiaDeParams(const AParams: TDelphiDbParams): TDelphiDbParams;
var
  Ctx: TRttiContext;
begin
  Result := TDelphiDbParams.Create;
  try
    for var F in Ctx.GetType(TDelphiDbParams).GetFields do
      F.SetValue(Result, F.GetValue(AParams));
  except
    Result.Free;
    raise;
  end;
end;

{ ACmd sobre la base que nombra AParams.Db con plazo para la llamada ENTERA:
  abre en el hilo de quien llama (AbreLaBase: la base de ESTA sesion, con el
  plazo de abrir, DB-007) y corre AOperacion en su hilo con una copia de los
  parametros (Lsp.BaseDeDatos.TrabajoConLaBase, que le pasa la llamada). Si
  la base calla mas de PLAZO_LLAMADA_DB, DB-022: quien pidio se va, lo que el
  hilo haga despues no se confirma (TSesionDb.Confirma) y el hilo libera la
  conexion cuando la base conteste, la red caiga o, en PostgreSQL, el
  servidor salga (Lsp.BaseDeDatos, su finalization). Medido el 7-nov-2026
  con un proxy que calla
  tras abrir (CH11 de la 1.29): sin este plazo, tables no volvia en 240 s.
  Lo que dice la base, como siempre: NegativaDeLaBase. }
function EnLaBase(const ACmd: string; const AParams: TDelphiDbParams; AEscribe: Boolean;
  const AOperacion: TOperacionDb): string;
var
  L: TLlamadaDb;
  Nombre: string;
  Operacion: TOperacionDb;
begin
  L := TLlamadaDb.Create;
  try
    Result := AbreLaBase(ACmd, AParams.Db, AEscribe, L.S);
    if Result = '' then
      L.P := CopiaDeParams(AParams);
  except
    L.Free;
    raise;
  end;
  if Result <> '' then
  begin
    L.Free;
    Exit;
  end;
  L.S.Llamada := L;
  // antes del plazo: vencida, L es del hilo y la libera el
  Nombre := NombreDeConexion(L.S.Conexion);
  Operacion := AOperacion;
  if not TrabajoConLaBase(L.S.Conn,
    procedure
    begin
      try
        L.Respuesta := Operacion(L.S, L.P);
      except
        on E: Exception do
          if L.SinConfirmar then
            L.Respuesta := MsgFmt(SR_DB_CALLA_FMT, [Nombre, PLAZO_LLAMADA_DB])
          else
            L.Respuesta := NegativaDeLaBase(E, L.S.Conexion);
      end;
    end, PLAZO_LLAMADA_DB * 1000,
    // vencida: se anota antes de irse, y Confirma ya no confirma
    procedure
    begin
      TInterlocked.Exchange(L.Abandonada, 1);
    end,
    procedure
    begin
      L.Free;
    end) then
    Exit(MsgFmt(SR_DB_CALLA_FMT, [Nombre, PLAZO_LLAMADA_DB]));
  try
    Result := L.Respuesta;
  finally
    L.Free;
  end;
end;

{ El nombre de ATabla como lo da el catalogo (tablas y vistas); False con la
  negativa. }
function TablaDe(const S: TSesionDb; const ATabla: string; out ACanonica, ANeg: string): Boolean;
begin
  for var T in TablasDeBase(S.Conn, False) + TablasDeBase(S.Conn, True) do
    if SameText(T, ATabla.Trim) then
    begin
      ACanonica := T;
      Exit(True);
    end;
  ANeg := MsgFmt(SR_DB_TABLA_FMT, [ATabla.Trim, NombreDeConexion(S.Conexion)]);
  Result := False;
end;

function CampoDe(const ACampos: TArray<TCampoDb>; const ANombre, ATabla: string;
  out ACampo: TCampoDb; out ANeg: string): Boolean;
begin
  for var C in ACampos do
    if SameText(C.Nombre, ANombre.Trim) then
    begin
      ACampo := C;
      Exit(True);
    end;
  ANeg := MsgFmt(SR_DB_CAMPO_FMT, [ANombre.Trim, ATabla]);
  Result := False;
end;

{ El parametro siguiente de AParams (p1, p2...) con su valor y su tipo; el
  nombre, para la sentencia. Los de values y los de filters comparten la
  numeracion: un update lleva los dos. }
function NuevoParametro(var AParams: TArray<TParametroDb>; const AValor: Variant;
  ATipo: TFieldType): string;
begin
  Result := 'p' + IntToStr(Length(AParams) + 1);
  SetLength(AParams, Length(AParams) + 1);
  AParams[High(AParams)].Nombre := Result;
  AParams[High(AParams)].Tipo := ATipo;
  AParams[High(AParams)].Valor := AValor;
end;

{ La entrada I de una lista de filters o de values (AQue): un objeto con un
  "field" de ACampos; False con la negativa (AForma: como es una entrada). }
function EntradaConCampo(ALista: TJSONArray; const AQue: string; I: Integer; const AForma: string;
  const ACampos: TArray<TCampoDb>; const ATabla: string; out AObj: TJSONObject; out ACampo: TCampoDb;
  out ANeg: string): Boolean;
begin
  AObj := nil;
  if not (ALista.Items[I] is TJSONObject) then
  begin
    ANeg := MsgFmt(SR_DB_ENTRADA_FMT, [AQue, I + 1, AForma]);
    Exit(False);
  end;
  AObj := TJSONObject(ALista.Items[I]);
  Result := CampoDe(ACampos, TextoDeValor(AObj.GetValue('field')), ATabla, ACampo, ANeg);
end;

{ El WHERE de AFiltros (filters) y sus parametros, o la negativa. Cada campo
  del catalogo, cada op de la lista, cada valor tipado por su campo: nada de
  lo que escribe el agente viaja como texto a la base. La comparacion de
  texto, la misma en cada motor: el escape fn UCASE de FireDAC a los dos
  lados de un LIKE con ESCAPE (medido en MSSQL y PG el 6-nov-2026);
  mayusculas y acentos, como diga su collation. }
function ClausulaDeFiltros(const S: TSesionDb; const ATabla: string; const ACampos: TArray<TCampoDb>;
  const AFiltros: string; var AParams: TArray<TParametroDb>; out AWhere: string): string;
var
  Lista: TJSONArray;
  Obj: TJSONObject;
  C: TCampoDb;
  Op, Neg, Q, T: string;
  B: Boolean;
  V: Variant;
  I: Integer;

  function Como(const APatron: string): string;
  begin
    Result := '{fn UCASE(' + Q + ')} LIKE {fn UCASE(:' + NuevoParametro(AParams, APatron, ftWideString) +
      ')} ESCAPE ''\''';
  end;

begin
  Result := '';
  AWhere := '';
  if AFiltros.Trim = '' then
    Exit;
  Lista := ListaJson(AFiltros);
  if Lista = nil then
    Exit(MsgFmt(SR_DB_LISTA_FMT, ['filters', MsgText(SF_DB_FILTRO_FORMA)]));
  try
    for I := 0 to Lista.Count - 1 do
    begin
      if not EntradaConCampo(Lista, 'filters', I, MsgText(SF_DB_FILTRO_FORMA), ACampos, ATabla, Obj, C, Neg) then
        Exit(Neg);
      Op := SinMayusculas(TextoDeValor(Obj.GetValue('op')));
      if not MatchText(Op, OPS_DE_FILTRO) then
        Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['filters', I + 1, MsgFmt(SF_DB_FILTRO_OP_FMT, [Op])]));
      Q := CitaNombre(S.Conn, C.Nombre);
      if AWhere <> '' then
        AWhere := AWhere + ' AND ';
      // empty pregunta si es nulo, que vale tambien para un binario
      if Op = 'empty' then
      begin
        if not LeeSiNo(TextoDeValor(Obj.GetValue('value')), B) then
          Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['filters', I + 1, MsgFmt(SF_DB_VALOR_NO_CABE_FMT,
            [C.Nombre, 'true or false'])]));
        AWhere := AWhere + Q + IfThen(B, ' IS NULL', ' IS NOT NULL');
        Continue;
      end;
      if EsBinario(C.TipoDeCampo) then
        Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['filters', I + 1, MsgFmt(SF_DB_FILTRO_BINARIO_FMT, [C.Nombre])]));
      if MatchText(Op, ['contains', 'starts_with', 'words']) then
      begin
        if not EsTexto(C.TipoDeCampo) then
          Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['filters', I + 1, MsgFmt(SF_DB_FILTRO_TEXTO_FMT, [Op, C.Nombre, C.Tipo])]));
        // (una ruta que salio con su unidad virtual se busca con la real: CH7)
        T := ExpandDriveValue(TextoDeValor(Obj.GetValue('value')));
        // sin nada que buscar casaria con TODAS las filas: LIKE '%%', y un
        // update o un delete con ese filtro las tocaba todas pasando la guarda
        // del WHERE (CH6 del revisor del paisaje de la 1.29)
        if T.Trim = '' then
          Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['filters', I + 1, MsgFmt(SF_DB_FILTRO_VACIO_FMT, [Op, C.Nombre])]));
        if Op = 'contains' then
          AWhere := AWhere + Como('%' + SinComodines(T) + '%')
        else if Op = 'starts_with' then
          AWhere := AWhere + Como(SinComodines(T) + '%')
        else
        begin
          var Y := '';
          for var W in T.Split([' '], TStringSplitOptions.ExcludeEmpty) do
            Y := Y + IfThen(Y <> '', ' AND ') + Como('%' + SinComodines(W) + '%');
          if Y = '' then
            Y := Como('%');
          AWhere := AWhere + '(' + Y + ')';
        end;
        Continue;
      end;
      if not ValorParaCampo(Obj.GetValue('value'), C, V) then
        Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['filters', I + 1, MsgFmt(SF_DB_VALOR_NO_CABE_FMT, [C.Nombre, C.Tipo])]));
      AWhere := AWhere + Q + ' ' + OperadorDe(Op) + ' :' + NuevoParametro(AParams, V, C.TipoDeCampo);
    end;
  finally
    Lista.Free;
  end;
  if AWhere <> '' then
    AWhere := ' WHERE ' + AWhere;
end;

{ El ORDER BY de AOrden ("campo" o "campo desc", separados por comas): con
  AEtiquetas vacia, campos de ACampos; con ellas (summary), las columnas por
  su posicion, que es lo que todos los motores entienden igual. AUsados: lo que
  ordena, cada uno una vez (el nombre del campo, o su posicion en summary),
  para quien desempata detras sin repetirlo (SQL Server niega una columna dos
  veces en un ORDER BY). }
function ClausulaDeOrden(const S: TSesionDb; const AOrden, ATabla: string;
  const ACampos: TArray<TCampoDb>; const AEtiquetas: TArray<string>; out AOrderBy: string;
  out AUsados: TArray<string>): string;
var
  Partes: TArray<string>;
  C: TCampoDb;
  Neg, Item: string;
  Pos: Integer;
begin
  Result := '';
  AOrderBy := '';
  AUsados := [];
  for var Trozo in AOrden.Split([',']) do
  begin
    Partes := Trozo.Trim.Split([' '], TStringSplitOptions.ExcludeEmpty);
    if Length(Partes) = 0 then
      Continue;
    if (Length(Partes) > 2) or ((Length(Partes) = 2) and not MatchText(Partes[1], ['asc', 'desc'])) then
      Exit(MsgFmt(SR_DB_ORDEN_FMT, [AOrden]));
    if Length(AEtiquetas) > 0 then
    begin
      Pos := IndexText(Partes[0], AEtiquetas);
      if Pos < 0 then
        Exit(MsgFmt(SR_DB_ORDEN_FMT, [AOrden]));
      Item := IntToStr(Pos + 1);
      AUsados := AUsados + [Item];
    end
    else
    begin
      if not CampoDe(ACampos, Partes[0], ATabla, C, Neg) then
        Exit(Neg);
      Item := CitaNombre(S.Conn, C.Nombre);
      AUsados := AUsados + [C.Nombre];
    end;
    if (Length(Partes) = 2) and SameText(Partes[1], 'desc') then
      Item := Item + ' DESC';
    AOrderBy := AOrderBy + IfThen(AOrderBy <> '', ', ') + Item;
  end;
  if AOrderBy <> '' then
    AOrderBy := ' ORDER BY ' + AOrderBy;
end;

procedure PonParametros(Q: TFDQuery; const APars: TArray<TParametroDb>);
begin
  for var P in APars do
  begin
    Q.ParamByName(P.Nombre).DataType := P.Tipo;
    Q.ParamByName(P.Nombre).Value := P.Valor;
  end;
end;

{ Las filas abiertas en Q como el array "rows" de la respuesta, con el
  presupuesto: al menos una, y ATruncado si quedaron fuera. AEtiquetas, los
  nombres de las columnas en el JSON (los del campo si esta vacia). }
function FilasEnJson(Q: TFDQuery; const AEtiquetas: TArray<string>; out ATruncado: Boolean): TJSONArray;
var
  Fila: TJSONObject;
  Usado, Tam, K: Integer;
begin
  Result := TJSONArray.Create;
  ATruncado := False;
  Usado := 0;
  while not Q.Eof do
  begin
    Fila := TJSONObject.Create;
    for K := 0 to Q.FieldCount - 1 do
      if K < Length(AEtiquetas) then
        Fila.AddPair(AEtiquetas[K], ValorDeCampo(Q.Fields[K]))
      else
        Fila.AddPair(Q.Fields[K].FieldName, ValorDeCampo(Q.Fields[K]));
    Tam := Length(Fila.ToJSON);
    if (Result.Count > 0) and (Usado + Tam > PRESUPUESTO_FILAS_DB) then
    begin
      Fila.Free;
      ATruncado := True;
      Break;
    end;
    Result.AddElement(Fila);
    Inc(Usado, Tam);
    Q.Next;
  end;
end;

function NuevaConsulta(const S: TSesionDb; const ASql: string; const APars: TArray<TParametroDb>): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := S.Conn;
    Result.FetchOptions.Unidirectional := True;
    Result.SQL.Text := ASql;
    PonParametros(Result, APars);
  except
    Result.Free;
    raise;
  end;
end;

function Limite(ADado, APorDefecto: Integer): Integer;
begin
  Result := ADado;
  if Result <= 0 then
    Result := APorDefecto;
  Result := Min(Result, LIMITE_MAXIMO_DB);
end;

function TablesEn(const S: TSesionDb; const P: TDelphiDbParams): string;
var
  R: TJSONObject;
  L: TJSONArray;
begin
  R := TJSONObject.Create;
  try
    R.AddPair('db', NombreDeConexion(S.Conexion));
    L := TJSONArray.Create;
    R.AddPair('tables', L);
    for var T in TablasDeBase(S.Conn, False) do
      L.Add(T);
    L := TJSONArray.Create;
    R.AddPair('views', L);
    for var T in TablasDeBase(S.Conn, True) do
      L.Add(T);
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

function FieldsEn(const S: TSesionDb; const P: TDelphiDbParams): string;
var
  R, O: TJSONObject;
  L: TJSONArray;
  Tabla, Neg: string;
begin
  if not TablaDe(S, P.Table, Tabla, Neg) then
    Exit(Neg);
  R := TJSONObject.Create;
  try
    R.AddPair('db', NombreDeConexion(S.Conexion));
    R.AddPair('table', Tabla);
    L := TJSONArray.Create;
    R.AddPair('fields', L);
    for var C in CamposDeTabla(S.Conn, Tabla) do
    begin
      O := TJSONObject.Create;
      L.AddElement(O);
      O.AddPair('name', C.Nombre);
      O.AddPair('type', C.Tipo);
      if C.Longitud > 0 then
        O.AddPair('length', TJSONNumber.Create(C.Longitud));
      if C.Precision > 0 then
      begin
        O.AddPair('precision', TJSONNumber.Create(C.Precision));
        O.AddPair('scale', TJSONNumber.Create(C.Escala));
      end;
      O.AddPair('nullable', TJSONBool.Create(C.Nulo));
      if C.Clave then
        O.AddPair('key', TJSONBool.Create(True));
    end;
    // como se relaciona con las demas y por que se busca rapido, del
    // catalogo de la base (DB-P5 de la 1.29)
    L := TJSONArray.Create;
    R.AddPair('foreignKeys', L);
    for var K in ClavesAjenasDeTabla(S.Conn, Tabla) do
    begin
      O := TJSONObject.Create;
      L.AddElement(O);
      O.AddPair('name', K.Nombre);
      O.AddPair('fields', ArrayDeTextos(K.Campos));
      O.AddPair('references', K.Tabla);
      O.AddPair('referencedFields', ArrayDeTextos(K.CamposDeAlla));
    end;
    L := TJSONArray.Create;
    R.AddPair('indexes', L);
    for var Ix in IndicesDeTabla(S.Conn, Tabla) do
    begin
      O := TJSONObject.Create;
      L.AddElement(O);
      O.AddPair('name', Ix.Nombre);
      O.AddPair('fields', ArrayDeTextos(Ix.Campos));
      if Ix.Primario then
        O.AddPair('primary', TJSONBool.Create(True))
      else if Ix.Unico then
        O.AddPair('unique', TJSONBool.Create(True));
    end;
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

function Fields(const P: TDelphiDbParams): string;
begin
  if P.Table.Trim = '' then
    Exit(MsgFmt(SR_DB_FALTA_FMT, ['fields', 'table']));
  Result := EnLaBase('fields', P, False, FieldsEn);
end;

function RowsEn(const S: TSesionDb; const P: TDelphiDbParams): string;
var
  Campos, Elegidos: TArray<TCampoDb>;
  Pars: TArray<TParametroDb>;
  Nombres: TArray<string>;
  Tabla, Neg, Where, OrderBy, Cols, Desde: string;
  Ordenados: TArray<string>;
  C: TCampoDb;
  Q: TFDQuery;
  R: TJSONObject;
  Filas: TJSONArray;
  Total: Int64;
  Lim: Integer;
  Truncado: Boolean;
begin
  // leer, siempre en una transaccion que se deshace: la segunda barrera
  S.Conn.StartTransaction;
  try
    if not TablaDe(S, P.Table, Tabla, Neg) then
      Exit(Neg);
    Campos := CamposDeTabla(S.Conn, Tabla);
    Elegidos := [];
    if P.Fields.Trim <> '' then
    begin
      if not ListaDeTextos(P.Fields, Nombres) then
        Exit(MsgFmt(SR_DB_LISTA_FMT, ['fields', 'field names']));
      for var N in Nombres do
      begin
        if not CampoDe(Campos, N, Tabla, C, Neg) then
          Exit(Neg);
        Elegidos := Elegidos + [C];
      end;
    end
    else
      for var Cada in Campos do
        if not EsBinario(Cada.TipoDeCampo) then
          Elegidos := Elegidos + [Cada];
    Cols := '';
    for var Cada in Elegidos do
      Cols := Cols + IfThen(Cols <> '', ', ') + CitaNombre(S.Conn, Cada.Nombre);
    Pars := [];
    Result := ClausulaDeFiltros(S, Tabla, Campos, P.Filters, Pars, Where);
    if Result <> '' then
      Exit;
    Result := ClausulaDeOrden(S, P.Order, Tabla, Campos, [], OrderBy, Ordenados);
    if Result <> '' then
      Exit;
    // Un orden TOTAL, para que una pagina y la siguiente no repitan ni salten
    // filas: lo pedido y, detras, la clave primaria (sin orden, la clave sola).
    // Sin ORDER BY ningun motor garantiza el mismo orden dos veces, y SQL
    // Server solo pagina en el motor con el (OFFSET...FETCH; sin el, FireDAC
    // pide TOP offset+limit y tira aqui lo de delante: leido en su generador,
    // FireDAC.Phys.MSSQLMeta, GetLimitSelect). DB-P1 de la 1.29. Una tabla
    // sin clave no tiene ese orden: la nota lo dice.
    var Desempate := '';
    var SinClave := True;
    for var K in Campos do
      if K.Clave then
      begin
        SinClave := False;
        if not MatchText(K.Nombre, Ordenados) then
          Desempate := Desempate + ', ' + CitaNombre(S.Conn, K.Nombre);
      end;
    if Desempate <> '' then
      if OrderBy = '' then
        OrderBy := ' ORDER BY ' + Desempate.Substring(2)
      else
        OrderBy := OrderBy + Desempate;
    Desde := ' FROM ' + CitaNombre(S.Conn, Tabla) + Where;
    Q := NuevaConsulta(S, 'SELECT COUNT(*)' + Desde, Pars);
    try
      Q.Open;
      Total := Q.Fields[0].AsLargeInt;
    finally
      Q.Free;
    end;
    Lim := Limite(P.Limit, LIMITE_FILAS_DB);
    Q := NuevaConsulta(S, 'SELECT ' + Cols + Desde + OrderBy, Pars);
    try
      if P.Offset > 0 then
        Q.FetchOptions.RecsSkip := P.Offset;
      Q.FetchOptions.RecsMax := Lim;
      Q.Open;
      R := TJSONObject.Create;
      try
        R.AddPair('db', NombreDeConexion(S.Conexion));
        R.AddPair('table', Tabla);
        R.AddPair('total', TJSONNumber.Create(Total));
        R.AddPair('offset', TJSONNumber.Create(Max(P.Offset, 0)));
        R.AddPair('limit', TJSONNumber.Create(Lim));
        Filas := FilasEnJson(Q, [], Truncado);
        R.AddPair('returned', TJSONNumber.Create(Filas.Count));
        if Truncado then
          R.AddPair('truncated', TJSONBool.Create(True));
        R.AddPair('rows', Filas);
        R.AddPair('note', MsgText(SN_DB_ROWS));
        if SinClave and (Total > Filas.Count) then
          R.AddPair('pagingNote', MsgText(SN_DB_SIN_CLAVE));
        Result := R.ToJSON;
      finally
        R.Free;
      end;
    finally
      Q.Free;
    end;
  finally
    if S.Conn.InTransaction then
      S.Conn.Rollback;
  end;
end;

function Rows(const P: TDelphiDbParams): string;
begin
  if P.Table.Trim = '' then
    Exit(MsgFmt(SR_DB_FALTA_FMT, ['rows', 'table']));
  Result := EnLaBase('rows', P, False, RowsEn);
end;

function SummaryEn(const S: TSesionDb; const P: TDelphiDbParams): string;
var
  Campos: TArray<TCampoDb>;
  Pars: TArray<TParametroDb>;
  Grupos, Etiquetas: TArray<string>;
  Tabla, Neg, Where, OrderBy, Sel, GroupBy, Expr, Op: string;
  Ordenados: TArray<string>;
  C: TCampoDb;
  Valores: TJSONArray;
  Obj: TJSONObject;
  Q: TFDQuery;
  R: TJSONObject;
  Filas: TJSONArray;
  Truncado: Boolean;
  I, Parte: Integer;
begin
  S.Conn.StartTransaction;
  try
    if not TablaDe(S, P.Table, Tabla, Neg) then
      Exit(Neg);
    Campos := CamposDeTabla(S.Conn, Tabla);
    Sel := '';
    GroupBy := '';
    Etiquetas := [];
    Grupos := [];
    if (P.Group.Trim <> '') and not ListaDeTextos(P.Group, Grupos) then
      Exit(MsgFmt(SR_DB_LISTA_FMT, ['group', 'field names']));
    for var G in Grupos do
    begin
      var Trozos := G.Trim.Split([':']);
      if (Length(Trozos) > 2) then
        Exit(MsgFmt(SR_DB_PARTE_FMT, [G]));
      if not CampoDe(Campos, Trozos[0], Tabla, C, Neg) then
        Exit(Neg);
      Expr := CitaNombre(S.Conn, C.Nombre);
      if Length(Trozos) = 2 then
      begin
        Parte := IndexText(Trozos[1].Trim, PARTES_DE_FECHA);
        if (Parte < 0) or not EsFecha(C.TipoDeCampo) then
          Exit(MsgFmt(SR_DB_PARTE_FMT, [G]));
        Expr := '{fn ' + FUNCIONES_DE_PARTE[Parte] + '(' + Expr + ')}';
        Etiquetas := Etiquetas + [C.Nombre + ':' + PARTES_DE_FECHA[Parte]];
      end
      else
        Etiquetas := Etiquetas + [C.Nombre];
      Sel := Sel + IfThen(Sel <> '', ', ') + Expr;
      GroupBy := GroupBy + IfThen(GroupBy <> '', ', ') + Expr;
    end;
    if P.Values.Trim <> '' then
    begin
      Valores := ListaJson(P.Values);
      if Valores = nil then
        Exit(MsgFmt(SR_DB_LISTA_FMT, ['values', MsgText(SF_DB_AGREGADO_FORMA)]));
      try
        for I := 0 to Valores.Count - 1 do
        begin
          if not EntradaConCampo(Valores, 'values', I, MsgText(SF_DB_AGREGADO_FORMA), Campos, Tabla, Obj, C,
            Neg) then
            Exit(Neg);
          Op := SinMayusculas(TextoDeValor(Obj.GetValue('op')));
          if not MatchText(Op, OPS_DE_VALOR) then
            Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['values', I + 1, MsgText(SF_DB_AGREGADO_FORMA)]));
          if MatchText(Op, ['sum', 'avg']) and not EsNumero(C.TipoDeCampo) then
            Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['values', I + 1, MsgFmt(SF_DB_AGREGADO_NUMERO_FMT, [C.Nombre])]));
          Sel := Sel + IfThen(Sel <> '', ', ') + UpperCase(Op) + '(' + CitaNombre(S.Conn, C.Nombre) + ')';
          Etiquetas := Etiquetas + [Op + '_' + C.Nombre];
        end;
      finally
        Valores.Free;
      end;
    end;
    Sel := Sel + IfThen(Sel <> '', ', ') + 'COUNT(*)';
    Etiquetas := Etiquetas + ['n'];
    Pars := [];
    Result := ClausulaDeFiltros(S, Tabla, Campos, P.Filters, Pars, Where);
    if Result <> '' then
      Exit;
    Result := ClausulaDeOrden(S, P.Order, Tabla, Campos, Etiquetas, OrderBy, Ordenados);
    if Result <> '' then
      Exit;
    // por defecto, el primer valor (o n) de mayor a menor: "el que mas"
    if (OrderBy = '') and (GroupBy <> '') then
    begin
      var Primero := IntToStr(Min(Length(Grupos) + 1, Length(Etiquetas)));
      OrderBy := ' ORDER BY ' + Primero + ' DESC';
      Ordenados := [Primero];
    end;
    // ...y detras, los grupos: un orden TOTAL, para que una pagina y la
    // siguiente no repitan ni salten grupos (cada grupo es unico; DB-P3 de la
    // 1.29, como el de rows)
    if GroupBy <> '' then
      for I := 1 to Length(Grupos) do
        if not MatchText(IntToStr(I), Ordenados) then
          OrderBy := OrderBy + IfThen(OrderBy = '', ' ORDER BY ', ', ') + IntToStr(I);
    Q := NuevaConsulta(S, 'SELECT ' + Sel + ' FROM ' + CitaNombre(S.Conn, Tabla) + Where +
      IfThen(GroupBy <> '', ' GROUP BY ' + GroupBy) + OrderBy, Pars);
    try
      if P.Offset > 0 then
        Q.FetchOptions.RecsSkip := P.Offset;
      Q.FetchOptions.RecsMax := Limite(P.Limit, LIMITE_GRUPOS_DB);
      Q.Open;
      R := TJSONObject.Create;
      try
        R.AddPair('db', NombreDeConexion(S.Conexion));
        R.AddPair('table', Tabla);
        R.AddPair('offset', TJSONNumber.Create(Max(P.Offset, 0)));
        R.AddPair('limit', TJSONNumber.Create(Limite(P.Limit, LIMITE_GRUPOS_DB)));
        Filas := FilasEnJson(Q, Etiquetas, Truncado);
        R.AddPair('returned', TJSONNumber.Create(Filas.Count));
        if Truncado then
          R.AddPair('truncated', TJSONBool.Create(True));
        R.AddPair('groups', Filas);
        Result := R.ToJSON;
      finally
        R.Free;
      end;
    finally
      Q.Free;
    end;
  finally
    if S.Conn.InTransaction then
      S.Conn.Rollback;
  end;
end;

function Summary(const P: TDelphiDbParams): string;
begin
  if P.Table.Trim = '' then
    Exit(MsgFmt(SR_DB_FALTA_FMT, ['summary', 'table']));
  Result := EnLaBase('summary', P, False, SummaryEn);
end;

{ Los values de insert y update (objetos con field y value): las columnas citadas y
  las marcas de sus parametros, cada valor tipado por su campo (null escribe
  NULL; un binario, solo NULL: el JSON no lo trae); o la negativa. }
function ValoresParaEscribir(const S: TSesionDb; const ATabla: string; const ACampos: TArray<TCampoDb>;
  const AValores: string; var AParams: TArray<TParametroDb>; out ACols, AMarcas: TArray<string>): string;
var
  Lista: TJSONArray;
  Obj: TJSONObject;
  Valor: TJSONValue;
  C: TCampoDb;
  V: Variant;
  Neg: string;
  I: Integer;
begin
  Result := '';
  ACols := [];
  AMarcas := [];
  Lista := ListaJson(AValores);
  if Lista = nil then
    Exit(MsgFmt(SR_DB_LISTA_FMT, ['values', MsgText(SF_DB_VALOR_FORMA)]));
  try
    for I := 0 to Lista.Count - 1 do
    begin
      if not EntradaConCampo(Lista, 'values', I, MsgText(SF_DB_VALOR_FORMA), ACampos, ATabla, Obj, C, Neg) then
        Exit(Neg);
      Valor := Obj.GetValue('value');
      if Valor = nil then
        Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['values', I + 1, MsgText(SF_DB_VALOR_FORMA)]));
      if Valor is TJSONNull then
        V := Null
      else if EsBinario(C.TipoDeCampo) then
        Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['values', I + 1, MsgFmt(SF_DB_VALOR_BINARIO_FMT, [C.Nombre])]))
      else if not ValorParaCampo(Valor, C, V) then
        Exit(MsgFmt(SR_DB_ENTRADA_FMT, ['values', I + 1, MsgFmt(SF_DB_VALOR_NO_CABE_FMT, [C.Nombre, C.Tipo])]));
      ACols := ACols + [CitaNombre(S.Conn, C.Nombre)];
      AMarcas := AMarcas + [':' + NuevoParametro(AParams, V, C.TipoDeCampo)];
    end;
  finally
    Lista.Free;
  end;
end;

{ insert, update y delete (ACmd): solo donde el json dice readonly:false (lo
  niega AbreLaBase antes de conectar), y update y delete solo con filters que
  seleccionen algo. La sentencia la compone el servidor como las lecturas
  (nombres del catalogo citados por FireDAC, valores por parametro tipado) y
  va en una transaccion que solo se confirma si la base la acepta. La
  respuesta dice cuantas filas toco. }
function EscribeEn(const ACmd: string; const S: TSesionDb; const P: TDelphiDbParams): string;
var
  Campos: TArray<TCampoDb>;
  Pars: TArray<TParametroDb>;
  Cols, Marcas: TArray<string>;
  Tabla, Neg, Where, Sql, Sets: string;
  Q: TFDQuery;
  R: TJSONObject;
  Tocadas: Int64;
begin
  S.Conn.StartTransaction;
  try
    if not TablaDe(S, P.Table, Tabla, Neg) then
      Exit(Neg);
    Campos := CamposDeTabla(S.Conn, Tabla);
    Pars := [];
    Cols := [];
    Marcas := [];
    if ACmd <> 'delete' then
    begin
      Result := ValoresParaEscribir(S, Tabla, Campos, P.Values, Pars, Cols, Marcas);
      if Result <> '' then
        Exit;
      if Length(Cols) = 0 then
        Exit(MsgFmt(SR_DB_FALTA_FMT, [ACmd, 'values']));
    end;
    Result := ClausulaDeFiltros(S, Tabla, Campos, P.Filters, Pars, Where);
    if Result <> '' then
      Exit;
    // filters = [] no selecciona nada: sin WHERE, update y delete tocarian
    // todas las filas
    if (ACmd <> 'insert') and (Where = '') then
      Exit(MsgFmt(SR_DB_FALTA_FMT, [ACmd, 'filters']));
    if ACmd = 'insert' then
      Sql := 'INSERT INTO ' + CitaNombre(S.Conn, Tabla) + ' (' + string.Join(', ', Cols) + ') VALUES (' +
        string.Join(', ', Marcas) + ')'
    else if ACmd = 'update' then
    begin
      Sets := '';
      for var K := 0 to High(Cols) do
        Sets := Sets + IfThen(Sets <> '', ', ') + Cols[K] + ' = ' + Marcas[K];
      Sql := 'UPDATE ' + CitaNombre(S.Conn, Tabla) + ' SET ' + Sets + Where;
    end
    else
      Sql := 'DELETE FROM ' + CitaNombre(S.Conn, Tabla) + Where;
    Q := NuevaConsulta(S, Sql, Pars);
    try
      Q.ExecSQL;
      Tocadas := Q.RowsAffected;
    finally
      Q.Free;
    end;
    // solo si quien la pidio sigue esperando (DB-022)
    S.Confirma;
    R := TJSONObject.Create;
    try
      R.AddPair('db', NombreDeConexion(S.Conexion));
      R.AddPair('table', Tabla);
      R.AddPair('affected', TJSONNumber.Create(Tocadas));
      Result := R.ToJSON;
    finally
      R.Free;
    end;
  finally
    if S.Conn.InTransaction then
      S.Conn.Rollback;
  end;
end;

function Escribe(const ACmd: string; const P: TDelphiDbParams): string;
var
  Cmd: string;
begin
  if P.Table.Trim = '' then
    Exit(MsgFmt(SR_DB_FALTA_FMT, [ACmd, 'table']));
  if (ACmd <> 'delete') and (P.Values.Trim = '') then
    Exit(MsgFmt(SR_DB_FALTA_FMT, [ACmd, 'values']));
  if (ACmd <> 'insert') and (P.Filters.Trim = '') then
    Exit(MsgFmt(SR_DB_FALTA_FMT, [ACmd, 'filters']));
  Cmd := ACmd;
  Result := EnLaBase(ACmd, P, True,
    function(const S: TSesionDb; const Q: TDelphiDbParams): string
    begin
      Result := EscribeEn(Cmd, S, Q);
    end);
end;

function Connections: string;
var
  Neg: string;
  Lista: TArray<TConexionDb>;
  R: TJSONObject;
  Bases, Inutiles: TJSONArray;
begin
  Lista := ConexionesDbDeLaSesion(Neg);
  if Neg <> '' then
    Exit(Neg);
  R := TJSONObject.Create;
  try
    R.AddPair('note', MsgText(SN_DB_CONNECTIONS));
    Bases := TJSONArray.Create;
    R.AddPair('databases', Bases);
    Inutiles := nil;
    for var C in Lista do
    begin
      var Por := DefectoDeConexion(C);
      if Por = '' then
      begin
        var B := TJSONObject.Create;
        Bases.AddElement(B);
        B.AddPair('db', NombreDeConexion(C));
        B.AddPair('engine', C.Motor);
        B.AddPair('readonly', TJSONBool.Create(C.SoloLectura));
      end
      else
      begin
        if Inutiles = nil then
        begin
          Inutiles := TJSONArray.Create;
          R.AddPair('unusable', Inutiles);
        end;
        var U := TJSONObject.Create;
        Inutiles.AddElement(U);
        U.AddPair('db', NombreDeConexion(C));
        U.AddPair('why', Por);
      end;
    end;
    Result := R.ToJSON;
  finally
    R.Free;
  end;
end;

{ TDelphiDbTool }

constructor TDelphiDbTool.Create;
begin
  inherited;
  FName := 'delphi_db';
  FDescription := SD_DB;
end;

function TDelphiDbTool.ExecuteWithParams(const Params: TDelphiDbParams): string;
var
  Cmd, Suyos, VaCon, Sobra: string;
begin
  Cmd := SinMayusculas(Params.Command.Trim);
  if Cmd = '' then
    Cmd := 'connections';
  // lo que no es del comando se dice (Lsp.Guard.ParametroQueNoVa)
  Sobra := ParametroQueNoVa(Cmd, [
      'connections', '',
      'tables', 'db',
      'fields', 'db table',
      'rows', 'db table fields filters order limit offset',
      'summary', 'db table filters group values order limit offset',
      'insert', 'db table values',
      'update', 'db table values filters',
      'delete', 'db table filters'],
    ['db', Params.Db, '', 'table', Params.Table, '', 'fields', Params.Fields, '',
     'filters', Params.Filters, '', 'order', Params.Order, '',
     'limit', IfThen(Params.Limit <> 0, IntToStr(Params.Limit)), '',
     'offset', IfThen(Params.Offset <> 0, IntToStr(Params.Offset)), '',
     'group', Params.Group, '', 'values', Params.Values, ''], Suyos, VaCon);
  if Sobra <> '' then
    Exit(MsgFmt(SR_DB_NO_VA_CON_COMANDO_FMT, [Sobra, Cmd, Cmd, Suyos]) + VaCon);
  case IndexText(Cmd, ['connections', 'tables', 'fields', 'rows', 'summary', 'insert', 'update', 'delete']) of
    0: Result := Connections;
    1: Result := EnLaBase('tables', Params, False, TablesEn);
    2: Result := Fields(Params);
    3: Result := Rows(Params);
    4: Result := Summary(Params);
    5, 6, 7: Result := Escribe(Cmd, Params);
  else
    Result := MsgText(SR_DB_COMANDO);
  end;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_db',
    function: IMCPTool begin Result := TDelphiDbTool.Create; end);

end.
