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

implementation

uses
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
begin
  if not Assigned(AArguments) then
    Exit;
  Names := TStringList.Create;
  Vals := TStringList.Create;
  try
    for I := 0 to AArguments.Count - 1 do
    begin
      P := AArguments.Pairs[I];
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
  finally
    Names.Free;
    Vals.Free;
  end;
end;

end.
