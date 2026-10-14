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

implementation

uses
  System.SysUtils,
  System.Classes; // TStringList: los pares a reescribir

function ObjetoJson(const ATexto: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(ATexto);
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

end.
