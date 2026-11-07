unit Lsp.TextoDelNodo;

{ El texto que el servidor manda al nodo de escritorio (lo que escribe type), por
  la linea de su programa. El nodo lo lee con ParamStr de Delphi, que no puede
  recibir una comilla: en un destino Windows el lanzador compone la linea con
  ComillasSinEscape, donde una comilla solo agrupa (revisor del paisaje de la
  1.26, C: 'di "hola"' se tecleaba 'di \hola\', medido con un eco Delphi). EL
  codificador y su inversa, en un sitio: lo escribe el servidor
  (Mcp.Tools.Desktop) y lo lee el nodo (McpDesktopNode, su unico lector de
  texto). Sin dependencias que Linux no tenga: el nodo se compila para los dos.
  Los saltos de linea viajan igual, codificados: el fichero de trabajo lleva un
  argumento por linea y un salto partiria el texto en dos (J10 de la 1.28: type
  negaba el salto con DESK-027; desde la 1.29 el nodo lo teclea como Intro). }

interface

{ ATexto para la linea del nodo: el %, la comilla y los saltos (LF y CR), como
  %25, %22, %0A y %0D }
function TextoParaElNodo(const ATexto: string): string;
{ Su inversa: el texto que el servidor quiso mandar }
function TextoDelServidor(const AArgumento: string): string;
{ El texto tal como lo repite el nodo en SU salida: en una linea, cada salto
  como \n. El servidor lee esa salida por lineas (NodeProtocolo.inc): un salto
  dejaria una linea del texto del agente donde se busca el protocolo
  (CAPTURE=, WINDOW ...). }
function TextoEnUnaLinea(const ATexto: string): string;
{ Una linea de la lista de ventanas que el nodo escribe con cada captura
  ('  WINDOW x y ancho alto <titulo>', NodeProtocolo.inc): EL compositor, el
  de los dos escritorios del nodo, con el titulo en una linea
  (TextoEnUnaLinea), y su lector, el del servidor, sobre lo que sigue a la
  marca (LineaDelNodo); False si no es una (sin titulo, o un numero que no lo
  es). Estaban a mano en los dos nodos y en Mcp.Tools.Desktop (E7 del revisor
  del paisaje de la 1.28). }
function LineaDeVentana(AX, AY, AAncho, AAlto: Integer; const ATitulo: string): string;
function LeeLineaDeVentana(const AValor: string; out AX, AY, AAncho, AAlto: Integer;
  out ATitulo: string): Boolean;
{ La cabecera de esa lista: '  <n> visible windows:' }
function CabeceraDeVentanas(ACuantas: Integer): string;

implementation

uses
  System.SysUtils;

const
  { las palabras del protocolo con el servidor: NODO_VENTANA, NODO_VENTANAS }
  {$I ..\DesktopNode\NodeProtocolo.inc}

function TextoParaElNodo(const ATexto: string): string;
begin
  // primero el %, para que el de un %22 no se confunda con uno escrito
  Result := ATexto.Replace('%', '%25').Replace('"', '%22').Replace(#10, '%0A').Replace(#13, '%0D');
end;

function TextoDelServidor(const AArgumento: string): string;
begin
  // al reves, y el %25 el ULTIMO: tras codificar, todo % escrito va seguido de
  // 25, asi que un %22, %0A o %0D solo puede ser una marca (el % solo abre)
  Result := AArgumento.Replace('%0D', #13).Replace('%0A', #10).Replace('%22', '"').Replace('%25', '%');
end;

function TextoEnUnaLinea(const ATexto: string): string;
begin
  Result := ATexto.Replace(#13#10, '\n').Replace(#10, '\n').Replace(#13, '\n');
end;

function LineaDeVentana(AX, AY, AAncho, AAlto: Integer; const ATitulo: string): string;
begin
  Result := Format('  ' + NODO_VENTANA + '%d %d %d %d %s', [AX, AY, AAncho, AAlto, TextoEnUnaLinea(ATitulo)]);
end;

function LeeLineaDeVentana(const AValor: string; out AX, AY, AAncho, AAlto: Integer;
  out ATitulo: string): Boolean;
var
  Resto: string;
  N: array[0..3] of Integer;
begin
  Result := False;
  AX := 0; AY := 0; AAncho := 0; AAlto := 0;
  ATitulo := '';
  // cuatro numeros y, tras el cuarto espacio, el titulo con sus espacios
  Resto := AValor.TrimLeft;
  for var K := 0 to 3 do
  begin
    var Esp := Resto.IndexOf(' ');
    if (Esp < 0) or not TryStrToInt(Resto.Substring(0, Esp), N[K]) then
      Exit;
    Resto := Resto.Substring(Esp + 1).TrimLeft;
  end;
  ATitulo := Resto.Trim([#13, ' ']);
  if ATitulo = '' then
    Exit;
  AX := N[0]; AY := N[1]; AAncho := N[2]; AAlto := N[3];
  Result := True;
end;

function CabeceraDeVentanas(ACuantas: Integer): string;
begin
  Result := Format('  %d ' + NODO_VENTANAS, [ACuantas]);
end;

end.
