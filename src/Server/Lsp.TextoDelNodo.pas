unit Lsp.TextoDelNodo;

{ El texto que el servidor manda al nodo de escritorio (lo que escribe type), por
  la linea de su programa. El nodo lo lee con ParamStr de Delphi, que no puede
  recibir una comilla: en un destino Windows el lanzador compone la linea con
  ComillasSinEscape, donde una comilla solo agrupa (revisor del paisaje de la
  1.26, C: 'di "hola"' se tecleaba 'di \hola\', medido con un eco Delphi). EL
  codificador y su inversa, en un sitio: lo escribe el servidor
  (Mcp.Tools.Desktop) y lo lee el nodo (McpDesktopNode, su unico lector de
  texto). Sin dependencias que Linux no tenga: el nodo se compila para los dos. }

interface

{ ATexto para la linea del nodo: el % y la comilla, como %25 y %22 }
function TextoParaElNodo(const ATexto: string): string;
{ Su inversa: el texto que el servidor quiso mandar }
function TextoDelServidor(const AArgumento: string): string;

implementation

uses
  System.SysUtils;

function TextoParaElNodo(const ATexto: string): string;
begin
  // primero el %, para que el de un %22 no se confunda con uno escrito
  Result := ATexto.Replace('%', '%25').Replace('"', '%22');
end;

function TextoDelServidor(const AArgumento: string): string;
begin
  // al reves: un %22 no aparece dentro de un %25 seguido de 22 (el % solo abre)
  Result := AArgumento.Replace('%22', '"').Replace('%25', '%');
end;

end.
