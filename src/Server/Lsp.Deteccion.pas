unit Lsp.Deteccion;

{ EL DETECTOR de codificacion: en que esta un fichero (DetectEnc, con la
  preferencia del IDE para lo que es ASCII y para lo que nace), la etiqueta
  que se ensena, el decodificador suelto, la regla de "esto no es texto" y la
  auditoria de unos bytes (Measure, sus contadores y la firma de un
  mojibake). Las dos inversas (DecodeBytes / EncodeText) y las clases que
  decide (TEncKind), en Lsp.Codificacion. Vivia en Lsp.Patch (V94 de la
  depuracion de la 1.23, B6 de la 1.28): se mudo sin cambiar una linea. }

interface

uses
  Lsp.Codificacion;

type
  TMetrics = record
    Bytes, CR, LF, CRLF, Loose, High, Corruption: Integer;
  end;

{ EL detector de codificacion, publico para que la suite DUnitX del motor
  (LspUnitTests) lo pruebe sin pasar por un fichero; sus dos inversas
  (DecodeBytes / EncodeText) y las clases que decide (TEncKind) estan en
  Lsp.Codificacion desde el 8-oct-2026. UTF-16 (LE y BE, siempre con BOM: es
  como lo escribe el IDE cuando se elige ese formato al ver un .dfm como
  texto) entro el 24-sep-2026; antes lo reconocia SOLO
  Lsp.Client.LoadSourceText por su cuenta. Un detector, no dos.
  AEsDesigner (EsRutaDeDesigner de su ruta): un form de TEXTO sin BOM es
  ANSI, lo sea o no como UTF-8 - asi lo leen dcc, el parser de forms del
  IDE y el renderizador (medido 9-oct-2026: 'Accion' acentuado en UTF-8 sin
  BOM se ejecuta como 'AcciÃ³n'); el servidor lo leia como UTF-8 (4.1 de la
  1.18.0, David: un parametro del detector, no un segundo detector). }
function DetectEnc(const B: TArray<Byte>; AEsDesigner: Boolean = False): TEncKind;
{ LA etiqueta que se ENSENA de la codificacion de un fichero (encoding= de
  delphi_read, delphi_edit y delphi_textedit): su EncName, salvo la de uno sin
  BOM y sin ningun byte alto (AEsAscii), que leen igual el UTF-8 y la ANSI:
  'ascii (utf8/ansi compatible)'. El detector lee ese ASCII en la preferencia
  del IDE para los ficheros NUEVOS (la cuenta EncAlEscribir para un fuente que
  nace en la llamada), y delphi_read decia utf8 de una unit que el IDE abre
  como ANSI (A41 de la 1.23, David 24-oct); el create de delphi_textedit ya lo
  decia asi, con su propia regla. Solo la etiqueta: los bytes no cambian. }
function EtiquetaDeCodificacion(K: TEncKind; AEsAscii: Boolean): string;
{ ...y la de unos bytes YA escritos (lo releido del disco): EL detector, con
  AEsDesigner como lee delphi_read un form, y LA etiqueta. Estaba a mano en
  delphi_textedit; delphi_create la dice tambien desde la 1.28 (B10). }
function EtiquetaDeLosBytes(const B: TArray<Byte>; AEsDesigner: Boolean = False): string;
function Measure(const B: TArray<Byte>): TMetrics;
{ Lo que dicen los contadores de Measure en una respuesta: 'audit=clean' con
  los acentos cuando no hay nada que mirar, y los contadores enteros cuando
  algo no cuadra; el antes y el despues de una escritura, en una linea si los
  dos estan limpios. }
function Auditoria(const M: TMetrics): string;
function AuditoriaAntesYDespues(const AAntes, ADespues: TMetrics): string;

{ El decodificador de delphi_read, suelto: bytes -> texto con SU encoding real
  (BOM de UTF-8 o UTF-16, UTF-8 estricto, y la ANSI solo cuando algun byte alto
  NO forma secuencia valida). Es EL detector: nadie mas decide codificaciones.
  Para quien ya tiene los bytes en la mano y no quiere leer el fichero dos
  veces. }
function DecodeSourceBytes(const B: TArray<Byte>; AEsDesigner: Boolean = False): string; // = TBytes

{ La regla UNICA de "esto no es texto": un byte NUL en los primeros 64 KB,
  salvo que el detector diga UTF-16, donde los NUL son la mitad de cada
  caracter ASCII. Vivia dos veces (delphi_read con 4 KB y delphi_textedit
  con 64 KB) y ninguna sabia de UTF-16 (24-sep-2026). }
function LooksBinaryBytes(const B: TArray<Byte>): Boolean;

{ Las lineas (desde 1) con la firma de un mojibake: UTF-8 leido como ANSI o
  como Latin-1. Lo pregunta el aviso de un texto nuevo que lo trae; en la
  interfaz para el DUnitX, que la mide en otras paginas. }
function MojibakeLines(const T: string): TArray<Integer>;

{ Encoding for NEW Delphi files, honouring the IDE's configured default
  (Tools > Options > Editor): 'utf8-bom' when the IDE is set to UTF-8,
  the machine's ANSI page (EncName(ekAnsi), 'cp1252' on a Western Windows)
  when ANSI. }
function NewFileEncName: string;
{ La codificacion en que NACE un fichero, la de todo el que crea uno: un
  fuente o un form, la del IDE (NewFileEncName; un form la ajusta
  EncDeFormNuevo, y una ANSI que no cabe, EncAlEscribir al escribir); el XML
  del IDE (EsXmlDelIde: proyecto, grupo, manifiesto), UTF-8 con BOM, como lo
  escriben el IDE y nuestro generador del manifiesto; lo demas, UTF-8 sin BOM
  (git no quita un BOM: un .gitignore con el romperia su primera regla). Eran
  tres reglas: delphi_create, el create de un changeset - que escribia un
  .dproj SIN BOM - y los de delphi_edit y delphi_textedit (A21 de la 1.23). }
function EncDeFicheroNuevo(const APath: string): string;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  Lsp.Discovery,   // DiscoverRadStudio, IdeDefaultUtf8 y su vigia: la preferencia del IDE
  Lsp.Extensiones, // EsDelMotorPascal, EsXmlDelIde: en que nace un fichero
  Lsp.Lineas,      // SplitToLines: el troceador de todos
  Lsp.Texts;

var
  GIdeUtf8: Boolean = False;
  GIdeUtf8Cache: TCacheVigilada; // LA cache vigilada (Lsp.Discovery): la clave Editor
  GIdeUtf8Candado: TObject;

{ The IDE's configured default encoding (registry, active install), cached
  while its key does not change: EL vigia del registro, como la zona de
  biblioteca (Lsp.Lugares). Se cacheaba para siempre, y cambiar en el IDE la
  codificacion por defecto no llegaba al servidor hasta reiniciarlo (V207 de
  la 1.23.1). }
function IdeWantsUtf8: Boolean;
var
  Info: TRadStudioInfo;
begin
  TMonitor.Enter(GIdeUtf8Candado);
  try
    Info := DiscoverRadStudio;
    if GIdeUtf8Cache.TocaCargar(VigiasDelEditor) then
    begin
      GIdeUtf8 := Info.Found and IdeDefaultUtf8(Info.Version);
      GIdeUtf8Cache.Cargada := True;
    end;
    Result := GIdeUtf8;
  finally
    TMonitor.Exit(GIdeUtf8Candado);
  end;
end;

function NewFileEncName: string;
begin
  if IdeWantsUtf8 then
    Result := EncName(ekUtf8Bom)
  else
    Result := EncName(ekAnsi);
end;

function EncDeFicheroNuevo(const APath: string): string;
begin
  if EsDelMotorPascal(APath) then
    Result := NewFileEncName
  else if EsXmlDelIde(APath) then
    Result := EncName(ekUtf8Bom)
  else
    Result := EncName(ekUtf8);
end;

function EtiquetaDeCodificacion(K: TEncKind; AEsAscii: Boolean): string;
begin
  if AEsAscii and (K in [ekUtf8, ekAnsi]) then
    Result := MsgText(SF_TEXT_ASCII_COMPATIBLES)
  else
    Result := EncName(K);
end;

function EtiquetaDeLosBytes(const B: TArray<Byte>; AEsDesigner: Boolean): string;
begin
  Result := EtiquetaDeCodificacion(DetectEnc(B, AEsDesigner), not HayByteAlto(B));
end;

function DetectEnc(const B: TBytes; AEsDesigner: Boolean): TEncKind;
begin
  // el BOM de UTF-8 y los de UTF-16 y UTF-32, por EL lector de un BOM (Codificacion).
  // UTF-16 solo por BOM: sin el, ningun fuente Delphi es UTF-16 (el IDE lo
  // escribe siempre con marca) y adivinarlo por ceros seria otro detector.
  if KindDeBom(B, Result) then
    Exit;
  // un form de texto sin BOM: ANSI (PaginaAnsi, la de la maquina), como lo leen dcc y el parser de forms
  // (medido 9-oct-2026; 4.1 de la 1.18.0). Lo que ya esta se lee y se
  // escribe con los mismos bytes, y un acento nuevo va como dcc lo lee
  if AEsDesigner then
    Exit(ekAnsi);
  // Pure ASCII without BOM is ambiguous: honour the encoding the IDE is
  // configured to use (Tools > Options > Editor). Guessing the other way
  // writes the first new accent in the wrong codec and the IDE shows
  // mojibake - in BOTH directions (measured). Para un FUENTE o un texto (M4) esto es solo
  // como se lee: en que se ESCRIBE su primer caracter no ASCII lo decide
  // EncAlEscribir, como el IDE al guardar (4.1 de la 1.18.0)
  if not HayByteAlto(B) then
  begin
    if IdeWantsUtf8 then
      Exit(ekUtf8);
    Exit(ekAnsi);
  end;
  // UTF-8 cuando TODO byte alto forma secuencias validas (estricto: el juez de
  // la RTL, TEncoding.UTF8.IsBufferValid); si no, ANSI. Asi deciden el IDE
  // (detecta un UTF-8 sin BOM: medido el 9-oct-2026) y TFile.ReadAllText. Una
  // regla propia de "UTF-8 danado" contradecia a los dos y dejaba sin editar
  // un ANSI legitimo (revisor propio de la 4.1; David: "si hay juez lo
  // seguimos hasta que se demuestre que el juez es tonto")
  if ValidUtf8(B, 0) then
    Result := ekUtf8
  else
    Result := ekAnsi;
end;

function Measure(const B: TBytes): TMetrics;
var
  I, Start: Integer;
  K: TEncKind;
  Cuerpo: TBytes;
begin
  Result := Default(TMetrics);
  Result.Bytes := Length(B);
  // El BOM es fontaneria del fichero, no texto: contar sus bytes como
  // "acentos" confundia la cuenta que ve el agente (medido). Cuantos bytes
  // son lo dice el MISMO detector que decide la codificacion, no otro if.
  K := DetectEnc(B);
  Cuerpo := B;
  Start := PreambleLen(K);
  if K in ENC_ANCHAS then
  begin
    // En UTF-16 (y UTF-32) cada caracter son dos (cuatro) bytes: un 0D 00 0A 00 no es un CRLF
    // byte a byte. Se mide el cuerpo en UTF-8, las mismas cuentas que un
    // fichero utf8 (un acento = 2 bytes altos); HighCount hace lo mismo.
    Cuerpo := EncodeText(DecodeBytes(B, K), ekUtf8, False); // medir, no escribir
    Start := 0;
  end;
  for I := Start to High(Cuerpo) do
  begin
    if Cuerpo[I] = 13 then
      Inc(Result.CR)
    else if Cuerpo[I] = 10 then
    begin
      Inc(Result.LF);
      if (I > 0) and (Cuerpo[I - 1] = 13) then
        Inc(Result.CRLF);
    end
    else if Cuerpo[I] > 127 then
      Inc(Result.High);
    if (I + 2 <= High(Cuerpo)) and (Cuerpo[I] = $EF) and (Cuerpo[I + 1] = $BF) and (Cuerpo[I + 2] = $BD) then
      Inc(Result.Corruption);
  end;
  Result.Loose := Result.LF - Result.CRLF;
end;

function Summary(const M: TMetrics): string;
begin
  // "saltos" and not "lineas": this counts LINE BREAKS, and a file whose last
  // line ends in one has one more line than it has breaks. Calling it lines
  // put "lineas=38" three words away from "Lineas 1-39 de 39" in the same
  // answer, and the reader had to decide which of the two was lying
  // (measured 2026-08-25). Neither was: they counted different things.
  // los saltos son LF y CR suelto: un fichero de solo CR decia breaks=0
  Result := MsgFmt(SF_EDIT_METRICAS_FMT,
    [M.Bytes, M.LF + M.CR - M.CRLF, M.CRLF, M.Loose, M.High, M.Corruption]);
end;

{ Lo que dicen los contadores en las respuestas (la cabecera de una lectura,
  el eco de una escritura): cuando no hay nada que mirar -sin U+FFFD, sin CR
  suelto, un solo tipo de salto- basta 'audit=clean' con los acentos; los
  contadores enteros (Summary), solo cuando algo no cuadra. Iban siempre,
  dos veces en cada edicion (revisor de tokens, 4-oct-2026). }
function Limpio(const M: TMetrics): Boolean;
begin
  Result := (M.Corruption = 0) and (M.CR = M.CRLF) and ((M.Loose = 0) or (M.CRLF = 0));
end;

function Auditoria(const M: TMetrics): string;
begin
  if Limpio(M) then
    Result := MsgFmt(SF_EDIT_AUDITORIA_LIMPIA_FMT, [M.High])
  else
    Result := Summary(M);
end;

// El antes y el despues de una escritura: una linea si los dos estan limpios
function AuditoriaAntesYDespues(const AAntes, ADespues: TMetrics): string;
begin
  if Limpio(AAntes) and Limpio(ADespues) then
    Result := '  ' + Auditoria(ADespues)
  else
    Result := MsgFmt(SF_EDIT_ANTES_DESPUES_FMT, [Summary(AAntes), Summary(ADespues)]);
end;

{ Lines (1-based) carrying a mojibake signature: a UTF-8 lead byte followed
  by a continuation byte, "read" as ANSI chars (e.g. 'A-tilde+3' for 'o
  acute'). Measured: models IMITATE corrupt context in their new text. }
function MojibakeLines(const T: string): TArray<Integer>;
var
  L: TList<Integer>;
  Lines: TArray<string>;
  I, J, B1, B2: Integer;

  // De que byte pudo salir C al leer mal UTF-8: su byte ANSI (la regla
  // del codificador, ByteCp) y, si no tiene, el de la lectura Latin-1, que
  // da cada byte de 80 a FF tal cual (la E acentuada mayuscula es U+00C3 U+0089;
  // la tipografia E2 80 xx, U+00E2 U+0080 ...). Son dos preguntas: unirlas en ByteCp
  // dejo de ver ese mojibake (revisor propio, 9-oct-2026). Hasta FF: en una
  // maquina que no es 1252 la o con tilde leida en Latin-1 (U+00C3 U+00B3) no
  // tiene byte ANSI y se escribia sin aviso (medido el 24-oct-2026 con el
  // servidor en la 1251); en la 1252, de A0 a FF las dos dan el mismo byte
  function ByteLeido(C: Char): Integer;
  begin
    Result := ByteCp(C);
    if (Result < 0) and (Ord(C) >= $80) and (Ord(C) <= $FF) then
      Result := Ord(C);
  end;

begin
  L := TList<Integer>.Create;
  try
    Lines := SplitToLines(T); // el troceador de todos (el CR suelto es salto)
    for I := 0 to High(Lines) do
      for J := 1 to Length(Lines[I]) - 1 do
      begin
        B1 := ByteLeido(Lines[I][J]);
        B2 := ByteLeido(Lines[I][J + 1]);
        if (B1 >= $C2) and (B1 <= $F4) and (B2 >= $80) and (B2 <= $BF) then
        begin
          L.Add(I + 1);
          Break;
        end;
      end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function DecodeSourceBytes(const B: TArray<Byte>; AEsDesigner: Boolean): string;
begin
  Result := DecodeBytes(B, DetectEnc(B, AEsDesigner));
end;

function LooksBinaryBytes(const B: TArray<Byte>): Boolean;
var
  I: Integer;
begin
  if DetectEnc(B) in ENC_ANCHAS then
    Exit(False);
  for I := 0 to Min(Length(B), 65536) - 1 do
    if B[I] = 0 then
      Exit(True);
  Result := False;
end;

initialization
  GIdeUtf8Candado := TObject.Create;

finalization
  GIdeUtf8Cache.Suelta;
  GIdeUtf8Candado.Free;

end.
