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
  del IDE: medido el 7-oct-2026, revision de la 1.17.0). SI vale para la otra
  pregunta, si el lector de forms del IDE lo toma por un form de texto: es
  el que da ese "Invalid stream format" al reabrir un .dfm de texto en UTF-16
  o UTF-32 (medido el 24-oct-2026, A28 de la 1.23): ElIdeNoLoTomaPorForm. }

interface

uses
  System.Classes;

type
  TDesignerShape = (dsText, dsTpf0, dsResource);

{ La forma por sus primeros bytes (con menos de cuatro, texto) }
function DesignerShapeOf(const ABytes: TArray<Byte>): TDesignerShape;
{ Los ACuantos primeros bytes de APath (menos si es mas corto; ninguno si no
  se puede abrir): EL lector de los que reconocen un fichero por su
  cabecera - la forma de un designer, su BOM, la firma de un estilo FMX, la
  de un binario ELF -. Eran cuatro TFileStream a mano, dos que se rendian
  con un fichero corto y dos dentro de un try (V11 y V34 de la 1.23). Sin
  puerta: la pasa antes quien llama. }
function PrimerosBytes(const APath: string; ACuantos: Integer): TArray<Byte>;
{ Si un designer de TEXTO (DesignerShapeOf) es uno que el lector de forms del
  IDE no toma por texto, por sus primeros bytes: lo dice la RTL
  (TestStreamFormat, el juez de la forma del flujo): un $FF inicial lo toma
  por binario, y FE FF o 00 00 FE FF por desconocido - un UTF-16 o un UTF-32,
  que el editor del IDE deja guardar y su disenador no reabre (A28 de la
  1.23). Con menos de cuatro bytes, o uno binario, False. Lo pregunta el
  renderizador al buscar un ancestro en la carpeta. }
function ElIdeNoLoTomaPorForm(const ABytes: TArray<Byte>): Boolean;

{ El form como el flujo TPF0 que lee TReader, sea cual sea su forma en disco:
  AEntrada entera (desde el principio) se escribe en ASalida desde su
  posicion. Un texto pasa TAL CUAL por ObjectTextToBinary, como en el IDE: un
  UTF-16 o un UTF-32 lo niega (A28 de la 1.23); lo que no es un form sale
  con su excepcion. }
procedure DesignerAFlujo(AEntrada, ASalida: TStream);

{ Lo que dice EL parser del IDE (ObjectTextToBinary, por DesignerAFlujo) de un
  designer de TEXTO, dados sus BYTES como estan (o estaran) en disco - con su
  codificacion: un nombre no ASCII en un form ANSI no lo lee, y en UTF-8 con
  BOM si -: '' si lo lee; si no, su mensaje tal cual ("Identifier expected on
  line 2", como lo da la RTL) y ALinea con la linea que nombra (0 si no nombra
  ninguna). 8.10 y 9.B de la 1.18.0: lint y los escritores del disenador
  preguntaban a una gramatica propia y no al parser - un // en un .fmx pasaba
  hasta que el IDE lo rechazaba al cargarlo -. La linea, por el formato del
  propio mensaje de la RTL (SParseError), no por un texto escrito aqui. }
function ErrorDelParserDeForm(const ABytes: TArray<Byte>; out ALinea: Integer): string;
{ La linea que nombra un mensaje del parser ('... on line 3', SParseError de
  la RTL); 0 si no nombra ninguna. EL lector de ese formato: lo leian este y
  to-binary (R2 del revisor propio del punto 4 de la 1.18.2). }
function LineaDeErrorDelParser(const AMensaje: string): Integer;

{ El numero de coma flotante de un VALOR de form (0.5, -2E3, 45123.5d, 1.5s,
  12.5c) como lo lee el parser de forms de la RTL (TParser, el tokenizador de
  ObjectTextToBinary: el punto decimal SIEMPRE, el sufijo de su tipo, el signo
  delante como en ConvertValue), para quien aplica un valor de form sin pasar
  por el binario. False si no es uno. El state= del preview lo convertia por un
  Variant con el LOCALE del usuario: en un Windows es-ES, Position.X=10.5 era
  105 (V121 de la 1.23.1, medido). La inversa de FlotanteDeForm (el escritor,
  Lsp.DesignerBin); aqui y no alli porque el ayudante de render la usa. }
function LeeFlotanteDeForm(const AValor: string; out AF: Extended): Boolean;

{ Un designer BINARIO, con o sin la cabecera de recurso, como el texto que
  escribe el IDE ("Ver como texto": ASCII con CRLF, lo que no cabe como #N).
  Lanza si esta danado; un texto pasa por DesignerAFlujo y sale como lo
  normaliza el IDE. EL conversor: lo escribian el servidor
  (DesignerBinaryToText, que le pone sus mensajes) y el renderizador
  (Cabecera), cada uno con su llamada a la RTL (P10 de la segunda revision
  de la 1.17.0). Lo corre SOLO un proceso de 32 bits, como el IDE: en Win64
  Extended es Double, y un flotante salia con otras cifras (V71 de la
  1.23.1). El servidor se lo pide al renderizador (--convert). }
function DesignerBinarioATexto(const ABytes: TArray<Byte>): string;
{ ...y la vuelta: los BYTES de un designer de texto, tal cual (el parser los
  lee como el IDE: ASCII, la ANSI de la maquina o UTF-8 con BOM), como el
  binario que escribe el IDE en disco, con su cabecera de recurso. Lanza lo
  que diga el parser. Tambien solo en 32 bits: el valor de un flotante,
  redondeado a Double, eran otros bytes (V71). }
function DesignerTextoARecurso(const ABytes: TArray<Byte>): TArray<Byte>;

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
  IDE). Escrita a mano en cuatro sitios hasta la 1.17.0. Una VISTA de un form
  FMX (UMain.Windows.fmx) no tiene .pas propio: la suya es la del maestro
  (UMain.pas) si este la declara (VistasDeUnidad); el texto, por la puerta de
  leer del servidor (GTextoDeUnidad), y en los renderizadores, el .pas del
  mismo nombre (alli la vista la lee MaestroDeVista). }
function UnidadDeDesigner(const ADesigner: string): string;

{ LAS VISTAS de un form FMX que declara su unidad (AUnidad, el .pas; ATexto,
  su texto): una por directiva R '*.<Vista>.fmx ...' - como las escribe el
  IDE, por EL lector de directivas (Lsp.Pascal.DirectivasPascal: una comentada
  no cuenta) -, cada una <unidad>.<Vista>.fmx en la carpeta de la unidad. EL
  juez de "es una vista" del servidor y del ayudante: el servidor la buscaba
  por el nombre (<unidad>.<Vista>.pas) y el ayudante por la directiva, y
  insert, delete, rename y check-binding negaban una vista (V122 de la 1.23.1,
  medido). }
function VistasDeUnidad(const AUnidad, ATexto: string): TArray<string>;
{ El maestro que tendria ADesigner si fuera una vista (<unidad>.<Vista><ext>
  -> <unidad><ext>), por su NOMBRE; '' si el nombre no lleva vista. Que LO SEA
  lo dice VistasDeUnidad sobre el .pas de ese maestro. }
function MaestroPorNombre(const ADesigner: string): string;
{ El maestro de ADesigner si es una vista que su .pas DECLARA (las dos de
  arriba, con el texto por GTextoDeUnidad); '' si no lo es, o en los
  renderizadores (alli, MaestroDeVista). }
function MaestroDeVistaDeclarada(const ADesigner: string): string;

{ True si ADesigner es de FMX, como decide el IDE: un .fmx; y un .dfm cuya
  unidad lo dice con el grupo de clases que el IDE escribe en un modulo de
  datos (la marca CLASSGROUP 'FMX.Controls.TControl': un TDataModule de un proyecto
  FMX vive en un .dfm - Property Editors\FMX.ActnRes del propio IDE -, y se
  juzgaba con la VCL: "Property Source does not exist" en su TImageList;
  corpus del 18-oct-2026). La preguntaban a mano siete sitios del servidor,
  de tres formas (2.3 de la 1.18.0). La unidad se lee por GTextoDeUnidad. }
function EsDesignerFmx(const ADesigner: string): Boolean;
{ ...y su otra mitad: un .dfm que no es de FMX. layout la preguntaba por la
  extension y media con la VCL un modulo de datos de FMX (A13 de la 1.23). }
function EsDesignerVcl(const ADesigner: string): Boolean;

var
  { El texto de la unidad de un designer por la puerta de leer del servidor
    ('' si no se puede): lo pone el servidor al arrancar. En los
    renderizadores queda nil: alli el marco lo da el propio ejecutable. }
  GTextoDeUnidad: function(const APas: string): string = nil;

implementation

uses
  System.SysUtils,
  System.RTLConsts,   // SParseError: el formato del mensaje del parser
  System.RegularExpressions,
  Lsp.Pascal;         // GrupoDeClasesDe: el {%CLASSGROUP} de un modulo de datos

function PrimerosBytes(const APath: string; ACuantos: Integer): TArray<Byte>;
var
  S: TFileStream;
begin
  Result := nil;
  if ACuantos <= 0 then
    Exit;
  try
    S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, ACuantos);
      SetLength(Result, S.Read(Result[0], ACuantos));
    finally
      S.Free;
    end;
  except
    Result := nil;
  end;
end;

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

function ElIdeNoLoTomaPorForm(const ABytes: TArray<Byte>): Boolean;
var
  S: TBytesStream;
begin
  Result := False;
  if (Length(ABytes) < 4) or (DesignerShapeOf(ABytes) <> dsText) then
    Exit;
  S := TBytesStream.Create(Copy(ABytes, 0, 4));
  try
    Result := not (TestStreamFormat(S) in [sofText, sofUTF8Text]);
  finally
    S.Free;
  end;
end;

procedure DesignerAFlujo(AEntrada, ASalida: TStream);
var
  Cabeza: TArray<Byte>;
  Resto: Int64;
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
      // los bytes TAL CUAL a TParser, el parser del IDE: lee ASCII, la ANSI de
      // la maquina (sin BOM; la misma de la casa, Lsp.Codificacion.PaginaAnsi)
      // o UTF-8 con BOM, y niega cualquier otro BOM (System.Classes,
      // TParser.Create: SAnsiUTF8Expected). Un texto que el editor del IDE
      // guardo en UTF-16 se le daba antes en UTF-8 (segunda revision de la
      // 1.17.0: un frame UTF-16 tumbaba el preview), y el IDE NO lo carga: su
      // disenador dice "Invalid stream format" (medido el 24-oct-2026, A28 de
      // la 1.23). El servidor lo niega antes, con la causa (DSGN-122); aqui,
      // lo que diga TParser
      ObjectTextToBinary(AEntrada, ASalida);
    end;
  end;
end;

function ErrorDelParserDeForm(const ABytes: TArray<Byte>; out ALinea: Integer): string;
var
  Entrada: TBytesStream;
  Salida: TMemoryStream;
begin
  Result := '';
  ALinea := 0;
  Entrada := TBytesStream.Create(ABytes);
  Salida := TMemoryStream.Create;
  try
    try
      DesignerAFlujo(Entrada, Salida);
    except
      on E: Exception do
      begin
        Result := E.Message;
        ALinea := LineaDeErrorDelParser(E.Message);
      end;
    end;
  finally
    Salida.Free;
    Entrada.Free;
  end;
end;

function LeeFlotanteDeForm(const AValor: string; out AF: Extended): Boolean;
var
  V: string;
  Negativo: Boolean;
  Flujo: TStringStream;
  P: TParser;
begin
  Result := False;
  AF := 0;
  V := AValor.Trim;
  Negativo := V.StartsWith('-');
  if Negativo then
    V := V.Substring(1);
  if V = '' then
    Exit;
  Flujo := TStringStream.Create(V, TEncoding.ASCII);
  try
    try
      P := TParser.Create(Flujo, TFormatSettings.Invariant);
      try
        case P.Token of
          toInteger: AF := P.TokenInt;
          toFloat: AF := P.TokenFloat;
        else
          Exit;
        end;
        Result := P.NextToken = toEOF;
      finally
        P.Free;
      end;
    except
      Result := False; // un numero que no cabe, o lo que el parser no lee
    end;
  finally
    Flujo.Free;
  end;
  if Result and Negativo then
    AF := -AF;
end;

function LineaDeErrorDelParser(const AMensaje: string): Integer;
begin
  Result := 0;
  // SParseError es '%s on line %d': su forma, escapada, con los huecos
  var Patron := '^' + TRegEx.Escape(SParseError).Replace('%s', '(.*)').Replace('%d', '(\d+)') + '$';
  var M := TRegEx.Match(AMensaje.Trim, Patron);
  if M.Success and (M.Groups.Count > 2) then
    Result := StrToIntDef(M.Groups[2].Value, 0);
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

function DesignerTextoARecurso(const ABytes: TArray<Byte>): TArray<Byte>;
var
  Entrada: TBytesStream;
  Salida: TMemoryStream;
begin
  Entrada := TBytesStream.Create(ABytes);
  Salida := TMemoryStream.Create;
  try
    // los bytes TAL CUAL al parser, como DesignerAFlujo, y el envoltorio de
    // recurso que escribe el IDE (FF 0A 00, el nombre de la clase, TPF0)
    ObjectTextToResource(Entrada, Salida);
    SetLength(Result, Salida.Size);
    if Salida.Size > 0 then
      Move(Salida.Memory^, Result[0], Salida.Size);
  finally
    Salida.Free;
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
    AClave := SinMayusculas(M.Groups[1].Value);
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
  if not Result and Assigned(GTextoDeUnidad) and SameText(ExtractFileExt(ADesigner.Trim), '.dfm') then
    Result := GrupoDeClasesDe(GTextoDeUnidad(UnidadDeDesigner(ADesigner.Trim))).StartsWith('FMX.', True);
end;

function EsDesignerVcl(const ADesigner: string): Boolean;
begin
  Result := SameText(ExtractFileExt(ADesigner.Trim), '.dfm') and not EsDesignerFmx(ADesigner);
end;

function UnidadDeDesigner(const ADesigner: string): string;
var
  Maestro: string;
begin
  Result := ChangeFileExt(ADesigner, '.pas');
  if FileExists(Result) then
    Exit;
  Maestro := MaestroDeVistaDeclarada(ADesigner);
  if Maestro <> '' then
    Result := UnidadDeDesigner(Maestro);
end;

function MaestroDeVistaDeclarada(const ADesigner: string): string;
var
  Maestro, Pas: string;
begin
  Result := '';
  Maestro := MaestroPorNombre(ADesigner);
  if (Maestro = '') or not Assigned(GTextoDeUnidad) then
    Exit;
  Pas := UnidadDeDesigner(Maestro);
  for var V in VistasDeUnidad(Pas, GTextoDeUnidad(Pas)) do
    if SameText(ExtractFileName(V), ExtractFileName(ADesigner)) then
      Exit(Maestro);
end;

{ Si ABase + '.' + AResto (una vista de la unidad ABase) es un fichero de SU
  carpeta y con ESE nombre, como lo resuelve Windows (GetFullPathName, por
  ExpandFileName): ni un separador - '\' o '/' -, ni '..', ni lo que Windows
  recorta. El juez es Windows: ExtractFileName(AResto) = AResto, el de V165,
  no veia '/' (solo corta por '\' y ':'), y '*./../../x.fmx' nombraba un .fmx
  de fuera de la jaula (V165b de la 1.23.1, medido). }
function VistaEnSuCarpeta(const ABase, AResto: string): Boolean;
var
  Compuesta, Full: string;
begin
  Compuesta := ABase + '.' + AResto;
  Full := ExpandFileName(Compuesta);
  Result := SameFileName(ExtractFilePath(Full), ExtractFilePath(ExpandFileName(ABase))) and
    (ExtractFileName(Full) = ExtractFileName(Compuesta));
end;

function VistasDeUnidad(const AUnidad, ATexto: string): TArray<string>;
var
  Base, Resto: string;
begin
  Result := [];
  Base := ChangeFileExt(AUnidad, '');
  for var D in DirectivasPascal(ATexto) do
    if (D.Nombre = 'R') or (D.Nombre = 'RESOURCE') then
      // su primer trozo, por EL troceador de las directivas de fichero: '*.fmx'
      // es el maestro; '*.<Vista>.fmx', una vista
      for var T in TrozosDeDirectiva(D.Argumento, 1) do
        if T.Texto.StartsWith('*.') and EsDesignerFmx(T.Texto) then
        begin
          Resto := T.Texto.Substring(2);
          // una vista es un nombre SUELTO, no una ruta: '*.\..\..\fuera\x.fmx'
          // componia Base + '.\..\..\fuera\x.fmx', una ruta FUERA de la carpeta,
          // y los consumidores (AvisosDelPar, InspectUnit, Patch, DesignerBinding,
          // Config) la tocaban con TFile.Exists y la nombraban - oraculo de
          // existencia de un .fmx de fuera de la jaula (V165 de la 1.23.1). El
          // juez, Windows: la vista compuesta sigue en la carpeta de la unidad
          // y con su nombre (VistaEnSuCarpeta; con '/' se escapaba, V165b)
          if Resto.Contains('.') and VistaEnSuCarpeta(Base, Resto) then
            Result := Result + [Base + '.' + Resto];
        end;
end;

function MaestroPorNombre(const ADesigner: string): string;
var
  Nombre, Base: string;
  P: Integer;
begin
  Result := '';
  Nombre := ExtractFileName(ADesigner);
  Base := ChangeFileExt(Nombre, '');
  P := Base.LastIndexOf('.');
  if P <= 0 then
    Exit;
  Result := ExtractFilePath(ADesigner) + Base.Substring(0, P) + ExtractFileExt(Nombre);
end;

function ComponeLineaDeObjeto(const AClave, ANombre, AClase: string): string;
begin
  if ANombre = '' then
    Result := AClave + ' ' + AClase
  else
    Result := AClave + ' ' + ANombre + ': ' + AClase;
end;

end.
