unit Lsp.Json;

{ Leer un JSON que tiene que ser un OBJETO. ObjetoJson nacio en Lsp.Client
  (ronda 16: cinco 'ParseJSONValue(...) as TJSONObject' caian con "Invalid
  class typecast" si el texto era un array) y su cuerpo seguia en linea en el
  disenador, en la puerta y en el renombrado, que no tienen el cliente LSP a
  mano (revision de paisaje de la 1.13.0). Aqui, sin mas dependencias que
  System.JSON, lo llama cualquiera. }

interface

uses
  System.JSON;

{ ATexto como objeto JSON; nil si no es JSON o si es otra cosa (un array, un
  numero, una cadena), que se libera. Quien llama libera el resultado. }
function ObjetoJson(const ATexto: string): TJSONObject;

implementation

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

end.
