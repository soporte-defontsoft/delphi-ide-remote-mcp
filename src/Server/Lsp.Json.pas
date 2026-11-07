unit Lsp.Json;

{ Leer un JSON que tiene que ser un OBJETO. ObjetoJson nacio en Lsp.Client
  (ronda 16: cinco 'ParseJSONValue(...) as TJSONObject' caian con "Invalid
  class typecast" si el texto era un array) y su cuerpo seguia en linea en el
  disenador, en la puerta y en el renombrado, que no tienen el cliente LSP a
  mano (revision de paisaje de la 1.13.0). Aqui, sin mas dependencias que
  la RTL, lo llama cualquiera.

  Y el recorrido que reescribe EN SU SITIO los argumentos de texto de una
  llamada (ReescribeCadenas): lo comparten las dos normalizaciones de la
  entrada, la de la jaula y la de las unidades virtuales, asi que vive
  debajo de las dos. Llega de Lsp.Guard el 8-oct-2026, sin cambiar una
  linea. }

interface

uses
  System.JSON;

{ ATexto como objeto JSON; nil si no es JSON o si es otra cosa (un array, un
  numero, una cadena), que se libera. Quien llama libera el resultado. }
function ObjetoJson(const ATexto: string): TJSONObject;

{ ATexto como valor JSON de cualquier clase (objeto, lista, numero, cadena,
  booleano, null); nil si no es JSON. El cuerpo de una respuesta de
  delphi_api, que puede ser una lista. Quien llama libera el resultado. }
function ValorJson(const ATexto: string): TJSONValue;

type
  TTraduceArg = reference to function(const ANombre, AValor: string): string;

{ Reescribe EN SU SITIO los argumentos de texto de una llamada: ATraduce
  recibe el nombre y el valor y devuelve el valor nuevo (el mismo = sin
  tocar). El recorrido de las dos normalizaciones de la entrada -la unidad
  virtual (ExpandVirtualDrives) y el nombre largo (AlargaRutas)-, escrito
  una vez: la tercera, si llega, es otra ATraduce. }
procedure ReescribeCadenas(const AArguments: TJSONObject; const ATraduce: TTraduceArg);

{ Los TEXTOS de un valor de argumento: el suyo si es un texto, cada uno si
  es una lista de textos ([JsonComoTexto('string')]: "paths" de delphi_git,
  1.19.0); nada si es otra cosa. Lo leen el recorrido de arriba y el suelo
  de la jaula (ArgPathOutsideDenied): una ruta dentro de una lista no se
  salta ni la traduccion de la unidad virtual ni la jaula. }
function CadenasDeValor(const AValor: TJSONValue): TArray<string>;

{ El texto de un parametro [JsonComoTexto('string')] como su lista: True y
  ALista si es un array JSON de textos; False si no lo es (un texto suelto,
  un array con otra cosa dentro). '' = la lista vacia. }
function ListaDeTextos(const ATexto: string; out ALista: TArray<string>): Boolean;

{ El texto de un parametro [JsonComoTexto] que es una LISTA de lo que sea (los
  edits de una tanda, las ops de un changeset) como su array; nil si no lo es.
  Un cliente que codifica dos veces la manda como CADENA JSON (hermes,
  25-sep-2026): se desenvuelve UNA vez. Lo hacia solo la tanda, y el mismo
  cliente fallaba con ops (revisor del paisaje de la 1.26). Quien llama libera
  el resultado. }
function ListaJson(const ATexto: string): TJSONArray;

{ La primera clave de AObj que no es una de ACampos ('' si todas lo son), con
  sus mayusculas: lo que una entrada de una lista no lee no se ignora en
  silencio. Estaba tres veces (las entradas de edits, EDIT-012; las de items
  de delphi_designer; las columnas de delphi_db create-table, C5 de la 1.29). }
function ClaveQueNoVa(const AObj: TJSONObject; const ACampos: array of string): string;

{ ATexto como lo escribe DENTRO de una cadena el codificador JSON de la casa
  (TJSONString.ToJSON, sin sus comillas): las barras dobladas y lo que no es
  ASCII como \uXXXX. EL juez de como viaja una ruta en el JSON de una tool: lo
  preguntaba a mano el enmascarador de la casa (Lsp.Mascara) y lo imitaba el de
  las rutas de red (Lsp.Lugares.FormaDeclaradaEnTexto), que con un acento no
  casaba y dejaba el nombre de la maquina (revisor del paisaje de la 1.26, B). }
function TextoEnJson(const ATexto: string): string;

{ El texto de un valor JSON: una cadena tal cual, un numero como lo escribe el
  JSON (ToString: con punto, sin la configuracion regional; en esta RTL un
  TJSONNumber NO es un TJSONString, medido el 6-nov-2026), un booleano como
  true/false; '' si no hay o es otra cosa. Estaba dos veces (el valor de un
  filtro de delphi_db y un campo del fichero de conexiones) y delphi_api
  hacia la tercera. }
function TextoDeValor(const AValor: TJSONValue): string;

{ AValores como un array JSON de cadenas, en su orden (lo libera quien lo
  recibe, o el objeto al que se anade). Estaba local en delphi_designer y
  delphi_db hacia la segunda. }
function ArrayDeTextos(const AValores: TArray<string>): TJSONArray;

implementation

uses
  System.SysUtils,
  System.Classes; // TStringList: los pares a reescribir

function TextoDeValor(const AValor: TJSONValue): string;
begin
  if AValor is TJSONBool then
  begin
    if TJSONBool(AValor).AsBoolean then
      Result := 'true'
    else
      Result := 'false';
  end
  else if AValor is TJSONNumber then
    Result := TJSONNumber(AValor).ToString
  else if AValor is TJSONString then
    Result := TJSONString(AValor).Value
  else
    Result := '';
end;

function TextoEnJson(const ATexto: string): string;
var
  J: TJSONString;
begin
  J := TJSONString.Create(ATexto);
  try
    Result := J.ToJSON;
    Result := Result.Substring(1, Length(Result) - 2); // sin las comillas
  finally
    J.Free;
  end;
end;

function ValorJson(const ATexto: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(ATexto);
end;

function ObjetoJson(const ATexto: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := ValorJson(ATexto);
  if V is TJSONObject then
    Exit(TJSONObject(V));
  V.Free;
  Result := nil;
end;

procedure ReescribeCadenas(const AArguments: TJSONObject; const ATraduce: TTraduceArg);
var
  I: Integer;
  P: TJSONPair;
  Names, Vals: TStringList;
  V, N: string;
  NombresDeLista: TStringList;   // las listas que cambian...
  Listas: TArray<TJSONArray>;    // ...y su lista nueva, en el mismo orden
begin
  if not Assigned(AArguments) then
    Exit;
  Names := TStringList.Create;
  Vals := TStringList.Create;
  NombresDeLista := TStringList.Create;
  Listas := nil;
  try
    for I := 0 to AArguments.Count - 1 do
    begin
      P := AArguments.Pairs[I];
      // una lista de TEXTOS, elemento a elemento: si cambia alguno se rehace
      // entera y se sustituye abajo, como un texto (1.19.0). Una lista con
      // otra cosa dentro ("edits": objetos) no es de este recorrido
      if (P.JsonValue is TJSONArray) and (TJSONArray(P.JsonValue).Count > 0) and
         (Length(CadenasDeValor(P.JsonValue)) = TJSONArray(P.JsonValue).Count) then
      begin
        var Cambia := False;
        var Nueva := TJSONArray.Create;
        for V in CadenasDeValor(P.JsonValue) do
        begin
          N := ATraduce(P.JsonString.Value, V);
          Cambia := Cambia or (N <> V);
          Nueva.Add(N);
        end;
        if Cambia then
        begin
          NombresDeLista.Add(P.JsonString.Value);
          Listas := Listas + [Nueva];
        end
        else
          Nueva.Free;
        Continue;
      end;
      if not (P.JsonValue is TJSONString) then
        Continue;
      V := TJSONString(P.JsonValue).Value;
      N := ATraduce(P.JsonString.Value, V);
      if N <> V then
      begin
        Names.Add(P.JsonString.Value);
        Vals.Add(N);
      end;
    end;
    for I := 0 to Names.Count - 1 do
    begin
      AArguments.RemovePair(Names[I]).Free;
      AArguments.AddPair(Names[I], Vals[I]);
    end;
    for I := 0 to NombresDeLista.Count - 1 do
    begin
      AArguments.RemovePair(NombresDeLista[I]).Free;
      AArguments.AddPair(NombresDeLista[I], Listas[I]);
      Listas[I] := nil; // ya es del objeto
    end;
  finally
    for var L in Listas do
      L.Free; // solo las que no llegaron a entrar (una excepcion a medias)
    NombresDeLista.Free;
    Names.Free;
    Vals.Free;
  end;
end;

function CadenasDeValor(const AValor: TJSONValue): TArray<string>;
begin
  Result := nil;
  if AValor is TJSONString then
    Exit(TArray<string>.Create(TJSONString(AValor).Value));
  // (TJSONNumber ES un TJSONString en la RTL: un numero no es un texto)
  if AValor is TJSONArray then
    for var E in TJSONArray(AValor) do
      if (E is TJSONString) and not (E is TJSONNumber) then
        Result := Result + [TJSONString(E).Value];
end;

function ListaJson(const ATexto: string): TJSONArray;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(ATexto);
  if V is TJSONString then
  begin
    var Una := TJSONString(V).Value;
    V.Free;
    V := TJSONObject.ParseJSONValue(Una);
  end;
  if V is TJSONArray then
    Exit(TJSONArray(V));
  V.Free;
  Result := nil;
end;

function ClaveQueNoVa(const AObj: TJSONObject; const ACampos: array of string): string;
begin
  for var Par in AObj do
  begin
    var Esta := False;
    for var Campo in ACampos do
      if Par.JsonString.Value = Campo then
        Esta := True;
    if not Esta then
      Exit(Par.JsonString.Value);
  end;
  Result := '';
end;

function ListaDeTextos(const ATexto: string; out ALista: TArray<string>): Boolean;
var
  V: TJSONValue;
begin
  ALista := nil;
  if ATexto.Trim = '' then
    Exit(True);
  V := TJSONObject.ParseJSONValue(ATexto);
  try
    Result := (V is TJSONArray) and
      (Length(CadenasDeValor(V)) = TJSONArray(V).Count);
    if Result then
      ALista := CadenasDeValor(V);
  finally
    V.Free;
  end;
end;

function ArrayDeTextos(const AValores: TArray<string>): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var V in AValores do
    Result.Add(V);
end;

end.
