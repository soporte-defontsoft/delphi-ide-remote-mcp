unit Lsp.DesignerForma;

{ La FORMA de un .dfm/.fmx en disco, UNA vez, para el servidor y para los
  renderizadores de src\Render, que no enlazan nada mas del servidor:

    dsText      lo que escribe el IDE por defecto (tambien en UTF-16: FF FE)
    dsTpf0      un flujo a pelo, 'TPF0' (lo que escribe un WriteComponent)
    dsResource  el binario del IDE en disco: cabecera de recurso de 16 bits
                (FF 0A 00, el tipo RT_RCDATA), su nombre y el flujo TPF0

  TestStreamFormat de la RTL no vale para esto: llama binario a todo lo que
  empieza por $FF, el texto UTF-16 incluido, y TReader no se salta la
  cabecera del recurso ("Invalid stream format" en preview de un .dfm binario
  del IDE: medido el 7-oct-2026, revision de la 1.17.0). }

interface

uses
  System.Classes;

type
  TDesignerShape = (dsText, dsTpf0, dsResource);

{ La forma por sus primeros bytes (con menos de cuatro, texto) }
function DesignerShapeOf(const ABytes: TArray<Byte>): TDesignerShape;

{ El form como el flujo TPF0 que lee TReader, sea cual sea su forma en disco:
  AEntrada entera (desde el principio) se escribe en ASalida desde su
  posicion. Un texto pasa por ObjectTextToBinary (el de UTF-16, en UTF-8 con
  BOM: TParser no lee otra cosa); lo que no es un form sale
  con su excepcion. }
procedure DesignerAFlujo(AEntrada, ASalida: TStream);

{ Un designer BINARIO, con o sin la cabecera de recurso, como el texto que
  escribe el IDE ("Ver como texto": ASCII con CRLF, lo que no cabe como #N).
  Lanza si esta danado; un texto pasa por DesignerAFlujo y sale como lo
  normaliza el IDE. EL conversor: lo escribian el servidor
  (DesignerBinaryToText, que le pone sus mensajes) y el renderizador
  (Cabecera), cada uno con su llamada a la RTL (P10 de la segunda revision
  de la 1.17.0). }
function DesignerBinarioATexto(const ABytes: TArray<Byte>): string;

{ LA linea RAIZ de un designer de texto: la primera que no esta en blanco,
  si es una linea de objeto (LineaDeObjeto); si no, False - un fichero que
  no empieza por su objeto no tiene raiz, y la de un objeto anidado no lo
  es. La leian el servidor (DesignerHeaderName) y el renderizador
  (Cabecera), este con la primera linea de objeto de CUALQUIER sitio (P10). }
function LineaRaizDeDesigner(const ALineas: TArray<string>;
  out AClave, ANombre, AClase: string): Boolean;

{ LA linea que abre un objeto en un designer de texto: 'object Nombre: TClase',
  'inherited ...' o 'inline ...', con o sin nombre ('object TMemo') y con o
  sin indice ('[2]'). True si lo es: AClave en minusculas (object, inherited
  o inline), ANombre ('' sin el) y AClase. El nombre y la clase por lo que
  los rodea, no por \w, que en TRegEx es ASCII: 'object lblDireccion: TLabel'
  con su acento se leia como la clase 'lblDirecci', y su end descolocaba el
  anidamiento. La leian seis regex - el lint, el binding (dos), tree
  (Lsp.Styles), el renombrado (Lsp.ProjectUnits) y layout -, cada una con su
  parte de la regla; lo destapo la prueba en vivo de la 1.12.0. Y una septima
  en los renderizadores (revision de la 1.17.0): por eso vive aqui. Una linea
  de propiedad ('Inline = True') no es una. }
function LineaDeObjeto(const ALinea: string; out AClave, ANombre, AClase: string): Boolean; overload;
// y AResto, lo que va detras de la clase (' [2]', el orden de un hijo)
function LineaDeObjeto(const ALinea: string; out AClave, ANombre, AClase, AResto: string): Boolean; overload;
{ Su inversa: 'object Nombre: TClase' (AClave object, inherited o inline;
  sin nombre, 'object TClase'). Sin sangria: la pone quien la coloca. }
function ComponeLineaDeObjeto(const AClave, ANombre, AClase: string): string;

{ La unidad de un form: el .pas de al lado con el mismo nombre (la regla del
  IDE). Escrita a mano en cuatro sitios hasta la 1.17.0. }
function UnidadDeDesigner(const ADesigner: string): string;

{ True si ADesigner es de FMX (un .fmx), por su extension, como decide el IDE;
  un .dfm es VCL. La preguntaban a mano siete sitios del servidor, de tres
  formas (EndsWith, ToLower.EndsWith, SameText de la extension; 2.3 de la
  1.18.0). }
function EsDesignerFmx(const ADesigner: string): Boolean;

implementation

uses
  System.SysUtils,
  System.RegularExpressions;

function DesignerShapeOf(const ABytes: TArray<Byte>): TDesignerShape;
begin
  Result := dsText;
  if Length(ABytes) < 4 then
    Exit;
  // La cabecera de recurso de 16 bits: $FF y el TIPO 10 (RT_RCDATA) en dos
  // bytes, FF 0A 00. Solo $FF no vale: un .dfm de TEXTO guardado en UTF-16 LE
  // desde el IDE (el selector de codificacion del editor) empieza por FF FE,
  // y las cuatro comprobaciones antiguas lo tomaban por binario (David,
  // 24-sep-2026).
  if (ABytes[0] = $FF) and (ABytes[1] = $0A) and (ABytes[2] = $00) then
    Exit(dsResource);
  if (ABytes[0] = $54) and (ABytes[1] = $50) and (ABytes[2] = $46) and (ABytes[3] = $30) then
    Exit(dsTpf0);
end;

procedure DesignerAFlujo(AEntrada, ASalida: TStream);
var
  Cabeza, Todo: TArray<Byte>;
  Resto: Int64;
  Cod: TEncoding;
  Bom: Integer;
  Utf8: TBytesStream;
begin
  SetLength(Cabeza, 4);
  AEntrada.Position := 0;
  SetLength(Cabeza, AEntrada.Read(Cabeza[0], 4));
  AEntrada.Position := 0;
  case DesignerShapeOf(Cabeza) of
    dsResource:
      begin
        AEntrada.ReadResHeader;
        Resto := AEntrada.Size - AEntrada.Position;
        // CopyFrom con 0 copiaria el flujo ENTERO desde el principio
        if Resto > 0 then
          ASalida.CopyFrom(AEntrada, Resto);
      end;
    dsTpf0:
      ASalida.CopyFrom(AEntrada, 0);
  else
    begin
      // TParser solo lee ASCII, ANSI o UTF-8 con BOM (System.Classes,
      // TParser.Create: SAnsiUTF8Expected con otro BOM): un texto que el
      // editor del IDE guardo en UTF-16 (FF FE / FE FF) se le da en UTF-8 con
      // BOM. Solo por el BOM, que lee la RTL; lo demas, como lo lee TParser,
      // el del IDE (segunda revision de la 1.17.0: un frame UTF-16 tumbaba el
      // preview; el lector del BOM de la casa vive en Lsp.Codificacion, que
      // arrastra Lsp.Texts y no se enlaza aqui). Sin BOM los bytes van tal cual
      // al parser, que los lee en la ANSI de la maquina: la misma de la casa
      // (Lsp.Codificacion.PaginaAnsi), y aqui no se define ninguna - era
      // TEncoding.Default, sin uso (r5 de la 1.18.0). Un form en UTF-32 (que
      // GetBufferEncoding toma por UTF-16) no llega: lo niega el servidor antes
      // de lanzar el renderizador (DSGN-122), y dcc tampoco lo compila (E2161)
      SetLength(Todo, AEntrada.Size);
      if Length(Todo) > 0 then
        AEntrada.ReadBuffer(Todo[0], Length(Todo));
      AEntrada.Position := 0;
      Cod := nil;
      Bom := TEncoding.GetBufferEncoding(Todo, Cod);
      if (Cod = TEncoding.Unicode) or (Cod = TEncoding.BigEndianUnicode) then
      begin
        Utf8 := TBytesStream.Create(TEncoding.UTF8.GetPreamble +
          TEncoding.UTF8.GetBytes(Cod.GetString(Todo, Bom, Length(Todo) - Bom)));
        try
          ObjectTextToBinary(Utf8, ASalida);
        finally
          Utf8.Free;
        end;
      end
      else
        ObjectTextToBinary(AEntrada, ASalida);
    end;
  end;
end;

function DesignerBinarioATexto(const ABytes: TArray<Byte>): string;
var
  Entrada, Flujo: TMemoryStream;
  Texto: TBytesStream;
begin
  Entrada := TMemoryStream.Create;
  Flujo := TMemoryStream.Create;
  Texto := TBytesStream.Create;
  try
    if Length(ABytes) > 0 then
      Entrada.WriteBuffer(ABytes[0], Length(ABytes));
    DesignerAFlujo(Entrada, Flujo);
    Flujo.Position := 0;
    ObjectBinaryToText(Flujo, Texto);
    // el texto de un .dfm es ASCII (lo que no cabe va como #N) salvo un NOMBRE
    // no ASCII, que va en UTF-8: UTF-8 lo lee tal cual
    Result := TEncoding.UTF8.GetString(Texto.Bytes, 0, Texto.Size);
    // ...y con ese nombre ObjectBinaryToText pone delante el BOM de UTF-8, que
    // es del FICHERO, no del texto: delante de 'object' la raiz no se leia
    // (tree: class ''), y to-text lo escribia como un caracter (EDIT-122).
    // Quien escriba el texto decide su BOM (revisor propio de la 4.1)
    if Result.StartsWith(#$FEFF) then
      Delete(Result, 1, 1);
  finally
    Texto.Free;
    Flujo.Free;
    Entrada.Free;
  end;
end;

function LineaRaizDeDesigner(const ALineas: TArray<string>;
  out AClave, ANombre, AClase: string): Boolean;
begin
  AClave := '';
  ANombre := '';
  AClase := '';
  for var L in ALineas do
    if L.Trim <> '' then
      Exit(LineaDeObjeto(L, AClave, ANombre, AClase));
  Result := False;
end;

function LineaDeObjeto(const ALinea: string; out AClave, ANombre, AClase, AResto: string): Boolean;
var
  M: TMatch;
  T: string;
begin
  AClave := '';
  ANombre := '';
  AClase := '';
  AResto := '';
  T := ALinea.Trim;
  M := TRegEx.Match(T,
    '(?i)^(object|inherited|inline)\s+(?:([^\s:=]+)\s*:\s*)?([^\s\[=:]+)');
  Result := M.Success;
  if Result then
  begin
    AClave := M.Groups[1].Value.ToLower;
    ANombre := M.Groups[2].Value;
    AClase := M.Groups[3].Value;
    AResto := Copy(T, M.Index + M.Length, MaxInt);
  end;
end;

function LineaDeObjeto(const ALinea: string; out AClave, ANombre, AClase: string): Boolean;
var
  Resto: string;
begin
  Result := LineaDeObjeto(ALinea, AClave, ANombre, AClase, Resto);
end;

function EsDesignerFmx(const ADesigner: string): Boolean;
begin
  Result := SameText(ExtractFileExt(ADesigner.Trim), '.fmx');
end;

function UnidadDeDesigner(const ADesigner: string): string;
begin
  Result := ChangeFileExt(ADesigner, '.pas');
end;

function ComponeLineaDeObjeto(const AClave, ANombre, AClase: string): string;
begin
  if ANombre = '' then
    Result := AClave + ' ' + AClase
  else
    Result := AClave + ' ' + ANombre + ': ' + AClase;
end;

end.
