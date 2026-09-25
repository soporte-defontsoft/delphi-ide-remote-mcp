unit Lsp.Patch;

{ Safe Delphi source editing engine - the port of an internally
  battle-tested tool (30+ measured test rounds against several LLMs, small
  and large). Every gate below exists because a model was measured breaking
  a file through that exact hole. Design rules:

  - Anchor = ONE full existing line (leading indentation may be omitted);
    never substrings, never multi-line anchors, never whole-file rewrites.
  - Encoding is detected (UTF-8 BOM / strict UTF-8 / CP1252 / UTF-16 by BOM) and preserved;
    a character that does not fit the file's codepage REJECTS the edit with
    the legitimate native-literal alternative spelled out.
  - Atomic writes (tmp + rename), automatic pre-edit backups under
    __delphi-patch\<yyyymmdd>\ next to the file, 2-step restore.
  - Binary designer files (TPF0) and IDE graveyards (__history/__recovery)
    are hard-rejected.
  - After every write the file is re-read from disk and audited: corruption
    marks, high-byte accounting, alien line endings, mojibake signatures,
    'end.' structure, routine-inserted-inside-a-method heuristic. }

interface

type
  TPatchArgs = record
    Path: string;
    OldLine: string;      // anchor (one full line)
    NewText: string;      // replacement (may be multi-line)
    HasOld, HasNew: Boolean;
    AtLine: Integer;      // 1-based disambiguation; 0 = unset
    ToLine: Integer;      // 1-based LAST line of the range; 0 = just the anchor
    DeleteLine: Boolean;  // true = remove the anchored line entirely
    Fragment: string;     // modo fragmento: un trozo de la linea AtLine
    Insert: string;       // '', 'rutina-global', 'metodo'
    Code: string;
    ClassName_: string;
    Visibility: string;
    Visible: Boolean;
    CreateUnit_: Boolean;
    Content: string;      // createunit: whole file content in one call
    Eol: string;          // 'lf' = LF endings; anything else = CRLF (default)
    Restore: Boolean;
    Confirm: Boolean;
  end;

function ExecutePatch(const A: TPatchArgs): string;

{ EL detector de codificacion y sus dos inversas, publicos para que la suite
  DUnitX del motor (LspUnitTests) los pruebe sin pasar por un fichero.
  UTF-16 (LE y BE, siempre con BOM: es como lo escribe el IDE cuando se elige
  ese formato al ver un .dfm como texto) entro el 24-sep-2026; antes lo
  reconocia SOLO Lsp.Client.LoadSourceText por su cuenta. Un detector, no dos. }
type
  TEncKind = (ekUtf8Bom, ekUtf8, ekCp1252, ekUtf16LE, ekUtf16BE);

  TMetrics = record
    Bytes, CR, LF, CRLF, Loose, High, Corruption: Integer;
  end;

function DetectEnc(const B: TArray<Byte>): TEncKind;
function DecodeBytes(const B: TArray<Byte>; K: TEncKind): string;
function EncodeText(const S: string; K: TEncKind): TArray<Byte>;
function EncName(K: TEncKind): string;
function EncKindOf(const AName: string): TEncKind;
function PreambleLen(K: TEncKind): Integer;
function Measure(const B: TArray<Byte>): TMetrics;

{ El decodificador de delphi_read, suelto: bytes -> texto con SU encoding real
  (BOM de UTF-8 o UTF-16, UTF-8 estricto, y CP1252 solo cuando algun byte alto
  NO forma secuencia valida). Es EL detector: nadie mas decide codificaciones.
  Para quien ya tiene los bytes en la mano y no quiere leer el fichero dos
  veces. }
function DecodeSourceBytes(const B: TArray<Byte>): string; // = TBytes

{ La regla UNICA de "esto no es texto": un byte NUL en los primeros 64 KB,
  salvo que el detector diga UTF-16, donde los NUL son la mitad de cada
  caracter ASCII. Vivia dos veces (delphi_read con 4 KB y delphi_textedit
  con 64 KB) y ninguna sabia de UTF-16 (24-sep-2026). }
function LooksBinaryBytes(const B: TArray<Byte>): Boolean;

{ Sustituye un BLOQUE CONTIGUO de lineas, comparado entero y por contenido
  (sin sangria). Encoding y finales de linea, los del fichero. Vivia dentro de
  delphi_edit y por eso delphi_textedit no podia tener anclas de bloque -
  editar un parrafo largo de documentacion obligaba a pegar el parrafo entero
  como ancla de una linea (medido el 2026-09-20 con TOOLS.md, que tiene
  parrafos de 3 KB en UNA linea). Es generico: solo usa PatchLoadText y
  PatchSaveText.
  AOccurrence: 0 = tiene que ser unico; 1, 2... = esa aparicion.
  AAtLine (1-based, 0 = sin usar): la linea donde empieza el bloque, YA
  resuelta por quien llama. Dentro de una tanda es obligatorio usarla: las
  ocurrencias se resuelven contra el fichero ORIGINAL y se arrastran, porque
  contarlas aqui seria contarlas sobre el fichero ya mutado. }
function ApplyBlockEdit(const APath, AOld, ANew: string;
  AOccurrence: Integer; AAtLine: Integer = 0): string;

{ EL rango, validado en un solo sitio.

  "old" ancla la PRIMERA linea y "toline" (1-based, incluida) dice hasta
  donde llega. Devuelve '' y el indice 0-based final en AFin, o el texto de
  rechazo si el rango no tiene sentido. ATarget0 es la linea del ancla ya
  resuelta (0-based) y ATotal cuantas lineas tiene el fichero.

  Vive aqui y no dentro de cada motor porque los motores son DOS -el de
  Pascal (DoEdit) y el de texto plano (DoEditLine)- y las reglas de un rango
  no tienen nada de Pascal. Escribirlas dos veces es como nacieron los tres
  bugs gemelos del 2026-09-20. }
function RangoHasta(const APath: string;
  ATarget0, AToLine, ATotal: Integer; out AFin: Integer): string;

{ EL modo fragmento, resuelto en un solo sitio.

  Convierte (fragmento + atline + new) en lo unico que entienden los motores:
  la linea COMPLETA que hay (AOld) y la linea COMPLETA que queda (ANewLine).
  Devuelve '' o el texto de rechazo. No escribe nada y no sabe nada de Pascal:
  despues, el motor de siempre vuelve a casar la linea entera en AtLine antes
  de tocar el disco, asi que la regla del ancla completa no se relaja - solo
  deja de teclearla quien llama. Si el fichero cambia entre medias, el ancla
  ya no casa y la edicion se rechaza.

  Lo llaman las cuatro puertas por las que entra una edicion: delphi_edit,
  delphi_textedit, las tandas (AplicaTanda) y el stage de delphi_changeset.
  AOtros: el nombre del parametro incompatible que venga puesto ('' si
  ninguno), para que la negativa sea la misma en las cuatro. }
function FragmentoALinea(const APath, AFrag, ANew: string; AAtLine: Integer;
  const AOtros: string; out AOld, ANewLine: string): string;

{ La linea (1-based) donde empieza la N-esima aparicion de un ancla de BLOQUE,
  0 si no hay tantas. El gemelo de NthOccurrenceLine para bloques, y por el
  mismo motivo: pre-resolver una tanda contra el fichero original. }
function NthBlockLine(const APath, AOld: string; AN: Integer): Integer;

{ La linea (1-based) de la N-esima aparicion de un ancla de UNA linea, 0 si no
  hay tantas. Desempata dentro de una tanda mejor que atline, porque los
  numeros de linea SE MUEVEN segun las entradas anteriores. }
function NthOccurrenceLine(const APath, AAnchor: string; AN: Integer): Integer;

{ Encoding-correct numbered read (also serves the remote file toolset). }
function ReadNumbered(const APath: string; AFrom, ATo: Integer): string;

{ Una posicion a la que nadie podria apuntar: linea o columna negativa, linea
  mas alla del final, columna mas alla de la linea, o fichero que no esta.
  '' cuando la posicion es real.

  Vive AQUI, y no en la unidad de una tool, porque la usan SEIS: definition,
  hover, signature, completion, references y rename_symbol. Estaba en la
  implementation de Mcp.Tools.DelphiLsp, o sea invisible para las otras dos
  unidades, y por eso cuatro validaban y dos no: delphi_completion contestaba
  ok:true con 16.835 candidatos a una columna NEGATIVA, y references lanzaba
  una excepcion cruda en ingles. Duplicarla en cada unidad habria sido repetir
  el fallo; se mueve al sitio donde ya miran todas. }
function PositionOutOfRange(const APath: string; ALine, AChar: Integer): string;

{ EL motor de tandas, escrito UNA vez.

  Aplica un array JSON de ediciones sobre UN fichero, EN ORDEN y TODO O NADA:
  parsea, pre-resuelve los "occurrence" contra el fichero ORIGINAL y los
  arrastra segun las entradas anteriores anaden o quitan lineas, maneja las
  anclas de bloque, acumula el eco y, si una falla, devuelve el fichero byte a
  byte. Lo unico que NO sabe es como se aplica UNA edicion suelta: eso lo pone
  quien llama, y es la unica linea en la que las dos tools se diferencian.

  Por que existe: esto vivia DUPLICADO en Mcp.Tools.DelphiPatch.ApplyEdits
  (delphi_edit) y en Lsp.TextEdit.TextEditsNucleo (delphi_textedit) - 132 y
  140 lineas con 103 identicas, un 78%. Y lo que cambiaba era cosmetico: el
  tipo del registro de argumentos, la llamada al motor de una edicion, y las
  variables renombradas al castellano (One/Una, Failed/Fallo,
  Snapshot/Copia), que es lo que impedia verlas como gemelas al leerlas.

  El precio de esa duplicacion se pago el 2026-09-20: el bug de "occurrence"
  -recontar sobre el fichero ya mutado, escribir en la linea equivocada y
  contestar OK- habia que arreglarlo DOS veces, y la segunda solo aparecio
  porque la sonda de verificacion uso por casualidad la tool que no se habia
  tocado. Con un solo motor, esta familia entera tiene una sola puerta. }
type
  TAplicaUnaEdicion = reference to function(const AOld, ANew: string;
    AAtLine, AToLine: Integer; ADelete: Boolean): string;

function AplicaTanda(const APath, AEditsJson: string;
  const AAplicaUna: TAplicaUnaEdicion): string;

{ Encoding-preserving load/save for other engines (scaffolder): text is
  decoded with the real encoding; save re-encodes with the SAME one, makes
  the pre-edit backup and writes atomically. AEncName as in delphi_read. }
function PatchLoadText(const APath: string; out AEncName: string): string;
procedure PatchSaveText(const APath, AText, AEncName: string);

{ EL cerrojo de escritura del servidor, prestado a los otros motores.

  delphi_edit entero corre dentro de el desde siempre; el problema es que
  editar un fichero es leer-modificar-escribir y ESO no es atomico, asi que
  dos caminos distintos sobre el mismo fichero (delphi_textedit, registrar una
  unidad en el .dpr, el designer...) se pisaban entre si aunque cada escritura
  suelta fuese atomica. Medido 2026-09-20 con la bateria de concurrencia: de
  12 ediciones simultaneas al mismo fichero llegaban 6 al disco.

  Es recursivo (TCriticalSection lo es), asi que un motor puede tomarlo y
  llamar por dentro a ExecutePatch sin bloquearse. Las escrituras son raras y
  cortas: un cerrojo unico no cuesta nada, igual que en el vault. }
procedure EnterFileEdit;
procedure LeaveFileEdit;

{ Encoding for NEW Delphi files, honouring the IDE's configured default
  (Tools > Options > Editor): 'utf8-bom' when the IDE is set to UTF-8,
  'cp1252' when ANSI. }
function NewFileEncName: string;

{ Makes a recoverable copy of a file into __delphi-patch\<date>\ before it is
  overwritten (once per file per day). Returns a note / the backup path.
  Exposed so binary writers (delphi_upload) can be non-destructive too. }
function BackupFile(const APath: string): string;
{ Escritura atomica de bytes (temporal + MoveFileEx): la usa to-binary del
  disenador para dejar un .dfm binario como lo escribiria el IDE. }
procedure AtomicWrite(const APath: string; const B: TArray<Byte>); // = TBytes

{ El nombre ORIGINAL de una copia de la papelera, o '' si ese nombre no lleva
  sello. Solo tiene sentido DENTRO de __delphi-patch.

  delphi_delete aparca los ficheros como "UFicha.pas-215825250": el sello de
  hora va DETRAS de la extension, que es lo que impide que dos borrados del
  mismo fichero se pisen... y lo que rompe a todo el que mire la extension.
  Quita tambien los sellos ENCADENADOS ("-215825250-215841305"), que es lo que
  deja restaurar algo ya restaurado.

  Medido el 2026-09-20 usando el servidor como cliente: TRES sintomas, UNA
  causa, y cada uno se habria "arreglado" por su lado en el sitio equivocado.
  - delphi_list includetrash=true ensenaba las copias de seguridad y NO lo
    BORRADO, que es justo lo que promete: la mascara *.pas no casa contra
    "UFicha.pas-215825250".
  - restaurar la unit de un formulario dejaba el .dfm dentro de la papelera:
    el camino de "esto es una unit" mira la extension, leia ".pas-215825250" y
    no entraba. Quedaba una unit sin su designer, que el IDE ya no abre.
  - restaurar hacia una copia de la copia DENTRO de la papelera, con el sello
    doblado. }
function TrashOriginalName(const AName: string): string;

{ EL NOMBRADOR de la papelera. Un solo sitio compone, un solo sitio lee, y el
  lector (TrashOriginalName) es la INVERSA de este.

  Por que existe, medido el 2026-09-20 contestando a David: habia TRES sitios
  componiendo rutas dentro de __delphi-patch con TRES convenciones distintas -
  "UFicha.pas-215825250" al borrar, "UMain.pas" a secas al editar, y
  "UMain.pas.antes-restaurar-221530" al restaurar-. El lector solo entendia la
  primera, asi que la copia previa a un restore ni la encontraba
  includetrash (la mascara *.pas-* no casa con ".pas.antes-restaurar-") ni se
  podia restaurar bien. Se habia arreglado el borde y dejado el punto.

  La regla: el sello SIEMPRE es '-hhnnsszzz' detras del nombre completo, y lo
  que distingue una copia de otra es la CARPETA, no el nombre. Asi el lector
  sirve para todas y una copia nueva no puede inventarse una convencion. }

{ La carpeta del dia dentro de la papelera, al lado del fichero.
  ASub: '' = la raiz del dia, 'deleted' / 'antes-restaurar' = su cajon. }
function TrashDayDir(const APath, ASub: string): string;

{ El nombre de una copia: el nombre real + el sello. La unica forma. }
function TrashStampedName(const AName: string): string;

{ El nombre de la carpeta de copias ('__delphi-patch'), para quien tenga que
  reconocerla. Estaba declarada DOS veces, aqui y en Mcp.Tools.FileOps. }
function TrashFolderName: string;

{ Tira las carpetas de dia caducadas (RETENTION_DAYS) de UNA papelera. Coste
  medido cuando no hay nada que tirar, que es casi siempre: 0,012 ms - leer
  una carpeta de tres entradas y comparar nombres. Nunca lanza.

  Se exporta porque la purga solo salia de BackupFile: una carpeta que se
  deja de EDITAR conservaba sus copias para siempre (lo vio David). Recorrer
  las raices al arrancar se midio y se descarto - 5,9 s en un arbol de 8.869
  carpetas, y una jaula puede ser un disco entero -; un hilo que lo haga
  cada hora tampoco hace falta: el recorredor de delphi_list / search /
  projects YA pasa por delante de cada papelera, asi que purga al pasar
  (PurgaAlPasar). Trabajo proporcional a la actividad, cero recorridos
  nuevos. }
procedure PurgeOldBackups(const ADir: string);

{ La purga oportunista, con sus dos frenos: una credencial de solo lectura
  no borra nada (un listado no tiene efectos), y PathDenied decide si esa
  papelera es NUESTRA para escribir - lo que deja fuera las ReadOnlyPaths,
  el subarbol confinado de otro agente y, sobre todo, una "papelera" que
  sea un junction hacia fuera de la jaula. }
procedure PurgaAlPasar(const ATrashDir: string);

implementation

uses
  System.Math,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.JSON,
  // AplicaTanda: el motor de tandas vive aqui desde 2026-09-20
  System.SyncObjs,
  System.Generics.Collections,
  System.RegularExpressions,
  Winapi.Windows,
  Lsp.Guard,
  Lsp.Discovery,
  Lsp.Texts,
  Lsp.DesignerMeta,
  Lsp.DesignerBin,
  Lsp.DesignerBinding;

const
  BACKUP_SUB = '__delphi-patch';
  RETENTION_DAYS = 15;
  MAX_READ_LINES = 400;
  SOURCE_EXTS: array [0 .. 3] of string = ('.pas', '.dpr', '.dpk', '.inc');
  DESIGNER_EXTS: array [0 .. 1] of string = ('.dfm', '.fmx');

var
  GLock: TCriticalSection;
  GCp1252: TEncoding;
  GHighMap: TDictionary<Char, Byte>; // CP1252 0x80-0x9F, derived from the codec


function EncName(K: TEncKind): string;
begin
  case K of
    ekUtf8Bom: Result := 'utf8-bom';
    ekUtf8: Result := 'utf8';
    ekUtf16LE: Result := 'utf16-le';
    ekUtf16BE: Result := 'utf16-be';
  else
    Result := 'cp1252';
  end;
end;

{ La inversa de EncName: el nombre que sale de una lectura vuelve a entrar
  como clase al guardar. Un nombre desconocido es cp1252, como siempre. }
function EncKindOf(const AName: string): TEncKind;
begin
  if AName = 'utf8-bom' then
    Result := ekUtf8Bom
  else if AName = 'utf8' then
    Result := ekUtf8
  else if AName = 'utf16-le' then
    Result := ekUtf16LE
  else if AName = 'utf16-be' then
    Result := ekUtf16BE
  else
    Result := ekCp1252;
end;

{ Bytes de BOM que preceden al texto en esa clase. }
function PreambleLen(K: TEncKind): Integer;
begin
  case K of
    ekUtf8Bom: Result := 3;
    ekUtf16LE, ekUtf16BE: Result := 2;
  else
    Result := 0;
  end;
end;

var
  GIdeUtf8Loaded: Boolean = False;
  GIdeUtf8: Boolean = False;

{ The IDE's configured default encoding, cached (registry, active install). }
function IdeWantsUtf8: Boolean;
var
  Info: TRadStudioInfo;
begin
  if not GIdeUtf8Loaded then
  begin
    Info := DiscoverRadStudio;
    if Info.Found then
      GIdeUtf8 := IdeDefaultUtf8(Info.Version);
    GIdeUtf8Loaded := True;
  end;
  Result := GIdeUtf8;
end;

function NewFileEncName: string;
begin
  if IdeWantsUtf8 then
    Result := 'utf8-bom'
  else
    Result := 'cp1252';
end;

function ValidUtf8(const B: TBytes; AOffset: Integer): Boolean;
var
  I, N, K: Integer;
begin
  I := AOffset;
  while I < Length(B) do
  begin
    if B[I] < $80 then
      Inc(I)
    else
    begin
      if (B[I] >= $C2) and (B[I] <= $DF) then
        N := 1
      else if (B[I] >= $E0) and (B[I] <= $EF) then
        N := 2
      else if (B[I] >= $F0) and (B[I] <= $F4) then
        N := 3
      else
        Exit(False);
      if I + N >= Length(B) then
        Exit(False);
      for K := 1 to N do
        if (B[I + K] < $80) or (B[I + K] > $BF) then
          Exit(False);
      Inc(I, N + 1);
    end;
  end;
  Result := True;
end;

function DetectEnc(const B: TBytes): TEncKind;
var
  I: Integer;
  HasHigh: Boolean;
begin
  if (Length(B) >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    Exit(ekUtf8Bom);
  // UTF-16 solo por BOM: sin el, ningun fuente Delphi es UTF-16 (el IDE lo
  // escribe siempre con marca) y adivinarlo por ceros seria otro detector.
  if (Length(B) >= 2) and (B[0] = $FF) and (B[1] = $FE) then
    Exit(ekUtf16LE);
  if (Length(B) >= 2) and (B[0] = $FE) and (B[1] = $FF) then
    Exit(ekUtf16BE);
  HasHigh := False;
  for I := 0 to High(B) do
    if B[I] > 127 then
    begin
      HasHigh := True;
      Break;
    end;
  // Pure ASCII without BOM is ambiguous: honour the encoding the IDE is
  // configured to use (Tools > Options > Editor). Guessing the other way
  // writes the first new accent in the wrong codec and the IDE shows
  // mojibake - in BOTH directions (measured).
  if not HasHigh then
  begin
    if IdeWantsUtf8 then
      Exit(ekUtf8);
    Exit(ekCp1252);
  end;
  // Only UTF-8 when EVERY high byte forms valid sequences (strict).
  if ValidUtf8(B, 0) then
    Result := ekUtf8
  else
    Result := ekCp1252;
end;

function DecodeBytes(const B: TBytes; K: TEncKind): string;
begin
  case K of
    ekUtf8Bom: Result := TEncoding.UTF8.GetString(B, 3, Length(B) - 3);
    ekUtf8: Result := TEncoding.UTF8.GetString(B);
    ekUtf16LE: Result := TEncoding.Unicode.GetString(B, 2, Length(B) - 2);
    ekUtf16BE: Result := TEncoding.BigEndianUnicode.GetString(B, 2, Length(B) - 2);
  else
    Result := GCp1252.GetString(B);
  end;
end;

function EncodeText(const S: string; K: TEncKind): TBytes;
var
  I: Integer;
  C: Char;
  BB: Byte;
  Body: TBytes;
begin
  case K of
    ekUtf16LE: Exit(TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(S));
    ekUtf16BE: Exit(TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes(S));
  end;
  if K <> ekCp1252 then
  begin
    Body := TEncoding.UTF8.GetBytes(S);
    if K = ekUtf8Bom then
    begin
      SetLength(Result, Length(Body) + 3);
      Result[0] := $EF; Result[1] := $BB; Result[2] := $BF;
      if Length(Body) > 0 then
        Move(Body[0], Result[3], Length(Body));
    end
    else
      Result := Body;
    Exit;
  end;
  SetLength(Result, Length(S));
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (Ord(C) <= $FF) and not ((Ord(C) >= $80) and (Ord(C) <= $9F)) then
      Result[I - 1] := Byte(Ord(C))
    else if GHighMap.TryGetValue(C, BB) then
      Result[I - 1] := BB
    else
      raise Exception.CreateFmt(
        'el caracter "%s" (U+%s) no existe en CP1252', [C, IntToHex(Ord(C), 4)]);
  end;
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
  if K in [ekUtf16LE, ekUtf16BE] then
  begin
    // En UTF-16 cada caracter son dos bytes: un 0D 00 0A 00 no es un CRLF
    // byte a byte. Se mide el cuerpo en UTF-8, las mismas cuentas que un
    // fichero utf8 (un acento = 2 bytes altos); HighCount hace lo mismo.
    Cuerpo := EncodeText(DecodeBytes(B, K), ekUtf8);
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
  Result := Format('bytes=%d saltos=%d CRLF=%d LFsueltos=%d acentos=%d corrupcion=%d',
    [M.Bytes, M.LF, M.CRLF, M.Loose, M.High, M.Corruption]);
end;

function ByteCp(C: Char): Integer;
var
  B: Byte;
begin
  if GHighMap.TryGetValue(C, B) then
    Exit(B);
  if Ord(C) <= $FF then
    Exit(Ord(C));
  Result := -1;
end;

{ Lines (1-based) carrying a mojibake signature: a UTF-8 lead byte followed
  by a continuation byte, "read" as CP1252 chars (e.g. 'A-tilde+3' for 'o
  acute'). Measured: models IMITATE corrupt context in their new text. }
function MojibakeLines(const T: string): TArray<Integer>;
var
  L: TList<Integer>;
  Lines: TArray<string>;
  I, J, B1, B2: Integer;
begin
  L := TList<Integer>.Create;
  try
    Lines := T.Replace(#13#10, #10).Split([#10]);
    for I := 0 to High(Lines) do
      for J := 1 to Length(Lines[I]) - 1 do
      begin
        B1 := ByteCp(Lines[I][J]);
        B2 := ByteCp(Lines[I][J + 1]);
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

procedure EnterFileEdit;
begin
  GLock.Enter;
end;

procedure LeaveFileEdit;
begin
  GLock.Leave;
end;

procedure AtomicWrite(const APath: string; const B: TBytes);
var
  Tmp: string;
begin
  // El temporal lleva un fragmento GUID: con nombre fijo, dos escrituras del
  // MISMO fichero por caminos distintos compartian el intermedio - una se
  // llevaba los bytes de la otra al renombrar y la segunda moria con "rename
  // atomico fallido" (medido 2026-09-20). El cerrojo de arriba ya las
  // serializa; esto protege ademas a quien escriba sin pasar por el.
  Tmp := TPath.Combine(TPath.GetDirectoryName(APath),
    '.' + TPath.GetFileName(APath) + '.' +
    LowerCase(TGUID.NewGuid.ToString.Substring(1, 8)) + '.delphi-patch-tmp');
  TFile.WriteAllBytes(Tmp, B);
  if not MoveFileEx(PChar(Tmp), PChar(APath), MOVEFILE_REPLACE_EXISTING) then
  begin
    TFile.Delete(Tmp);
    raise Exception.CreateFmt('rename atomico fallido (%d)', [GetLastError]);
  end;
end;

procedure PurgaAlPasar(const ATrashDir: string);
begin
  try
    if IsReadOnlyNow then
      Exit;
    if PathDenied(ATrashDir) <> '' then
      Exit;
    PurgeOldBackups(ATrashDir);
  except
    // purgar al pasar nunca rompe el listado que pasaba
  end;
end;

procedure PurgeOldBackups(const ADir: string);
var
  D, Limit: string;
begin
  try
    Limit := FormatDateTime('yyyymmdd', Now - RETENTION_DAYS);
    for D in TDirectory.GetDirectories(ADir) do
      if TRegEx.IsMatch(TPath.GetFileName(D), '^\d{8}$') and
         (TPath.GetFileName(D) < Limit) then
        BorraArbol(D); // sin cruzar enlaces: ver Lsp.Guard
  except
    // purging must never break an edit
  end;
end;

{ Makes the pre-edit copy (once per file per day). Returns a note. }
function BackupFile(const APath: string): string;
var
  Dir, DayDir, Dest: string;
begin
  Dir := TPath.Combine(TPath.GetDirectoryName(APath), BACKUP_SUB);
  // Esta copia NO lleva sello a proposito: es una por fichero y dia, la
  // version previa al primer cambio del dia. Pero la CARPETA la pone el
  // nombrador, como todas.
  DayDir := TrashDayDir(APath, '');
  Dest := TPath.Combine(DayDir, TPath.GetFileName(APath));
  // Lo que DEVUELVE esta funcion es para ENSENARLO (el "copia=" del eco de
  // delphi_edit, la respuesta de delphi_upload), nunca para volver a abrir
  // el fichero: por eso la ruta sale enmascarada, desde el unico sitio que
  // la compone. delphi_edit esta EXENTO del filtro de salida -su eco es
  // contenido literal del disco-, y esto no es eco: es una ruta NUESTRA, y
  // salia con la letra REAL del servidor. Mismo fallo que el "CREADO" de
  // delphi_textedit, en otro emisor de la misma tool; se me escapo el
  // 2026-09-21 por buscar el identificador en vez del FORMATO, y lo canto
  // la propia tool al cortar un release.
  //
  // OJO A DONDE VA LA MASCARA: solo en lo que SALE. Enmascarar la variable
  // Dest antes de usarla deja el TFile.Exists y el TFile.Copy apuntando a
  // una unidad virtual que no existe en el disco - es decir, se carga la
  // copia de seguridad entera. Escrito aqui porque lo hice al primer
  // intento, el mismo dia.
  if TFile.Exists(Dest) then
    Exit('ya existia (' + MaskDriveText('', Dest) + ')');
  CrearCarpeta(DayDir);
  // "Existe?" y "copia" no son un solo gesto: dos escrituras del mismo fichero
  // a la vez pasaban las dos por el if y la segunda moria con "Cannot create
  // file ... already exists", RECHAZANDO una edicion perfectamente valida
  // (medido 2026-09-20: era la causa dominante de las ediciones perdidas). La
  // copia ya esta hecha por el otro y vale igual: es la version PREVIA al
  // primer cambio del dia, que es justo lo que promete.
  try
    TFile.Copy(APath, Dest);
  except
    on E: Exception do
      if TFile.Exists(Dest) then
        Exit('ya existia (' + MaskDriveText('', Dest) + ')')
      else
        raise;
  end;
  PurgeOldBackups(Dir);
  Result := MaskDriveText('', Dest);
end;

function SplitToLines(const T: string): TArray<string>;
begin
  Result := T.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function IsAllWhitespace(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if (C <> ' ') and (C <> #9) then
      Exit(False);
  Result := True;
end;

function DecodeSourceBytes(const B: TArray<Byte>): string;
begin
  Result := DecodeBytes(B, DetectEnc(B));
end;

function LooksBinaryBytes(const B: TArray<Byte>): Boolean;
var
  I: Integer;
begin
  if DetectEnc(B) in [ekUtf16LE, ekUtf16BE] then
    Exit(False);
  for I := 0 to Min(Length(B), 65536) - 1 do
    if B[I] = 0 then
      Exit(True);
  Result := False;
end;

{ Una antiguedad en palabras para un agente: "12 min", "3 h 05 min",
  "2 dias". Para la vista previa de restore. }
function EdadLegible(ADias: Double): string;
var
  Mins: Int64;
begin
  Mins := Round(ADias * 24 * 60);
  if Mins < 0 then
    Mins := 0;
  if Mins < 60 then
    Result := Format('%d min', [Mins])
  else if Mins < 24 * 60 then
    Result := Format('%d h %.2d min', [Mins div 60, Mins mod 60])
  else
    Result := Format('%d dias', [Mins div (24 * 60)]);
end;

function TrashFolderName: string;
begin
  Result := BACKUP_SUB;
end;

function TrashDayDir(const APath, ASub: string): string;
begin
  Result := TPath.Combine(
    TPath.Combine(TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(APath)),
      BACKUP_SUB),
    FormatDateTime('yyyymmdd', Now));
  if ASub <> '' then
    Result := TPath.Combine(Result, ASub);
end;

function TrashStampedName(const AName: string): string;
begin
  Result := AName + '-' + FormatDateTime('hhnnsszzz', Now);
end;

function TrashOriginalName(const AName: string): string;
var
  M: TMatch;
begin
  Result := AName;
  // hhnnsszzz = 9 digitos. En bucle, porque restaurar una copia restaurada
  // encadena sellos.
  while True do
  begin
    M := TRegEx.Match(Result, '^(.+)-\d{9}$');
    if not M.Success then
      Break;
    Result := M.Groups[1].Value;
  end;
  if Result = AName then
    Result := '';
end;

function PatchLoadText(const APath: string; out AEncName: string): string;
var
  B: TBytes;
  K: TEncKind;
begin
  B := TFile.ReadAllBytes(APath);
  K := DetectEnc(B);
  AEncName := EncName(K);
  Result := DecodeBytes(B, K);
end;

procedure PatchSaveText(const APath, AText, AEncName: string);
var
  K: TEncKind;
begin
  K := EncKindOf(AEncName);
  if TFile.Exists(APath) then
    BackupFile(APath); // new files have nothing to back up
  AtomicWrite(APath, EncodeText(AText, K));
end;

function NthOccurrenceLine(const APath, AAnchor: string; AN: Integer): Integer;
var
  Lines: TArray<string>;
  Enc: string;
  I, Seen: Integer;
begin
  Result := 0;
  if (AN <= 0) or (AAnchor.Trim = '') then
    Exit;
  try
    Lines := PatchLoadText(APath, Enc).Replace(#13#10, #10).Split([#10]);
  except
    Exit;
  end;
  Seen := 0;
  for I := 0 to High(Lines) do
    if Lines[I].Trim = AAnchor.Trim then
    begin
      Inc(Seen);
      if Seen = AN then
        Exit(I + 1);
    end;
end;

{ EL escaneo del bloque, escrito una vez. Devuelve el indice 0-based donde
  empieza la ocurrencia pedida (-1 si no esta) y cuantas hay en total. Lo usan
  ApplyBlockEdit y NthBlockLine: escribirlo dos veces era precisamente como
  nacio el bug de "occurrence" que este release arregla. }
function BuscaBloque(const ALines, AOldLines: TArray<string>;
  AOccurrence: Integer; out ACuantas: Integer): Integer;
var
  I, J, Vistas: Integer;
  Ok: Boolean;
begin
  Result := -1;
  ACuantas := 0;
  Vistas := 0;
  for I := 0 to Length(ALines) - Length(AOldLines) do
  begin
    Ok := True;
    for J := 0 to High(AOldLines) do
      if ALines[I + J].Trim <> AOldLines[J].Trim then
      begin
        Ok := False;
        Break;
      end;
    if Ok then
    begin
      Inc(ACuantas);
      Inc(Vistas);
      if (AOccurrence > 0) and (Vistas = AOccurrence) then
      begin
        Result := I;
        ACuantas := 1;
        Exit;
      end;
      if AOccurrence = 0 then
        Result := I;
    end;
  end;
end;

{ Normaliza un ancla de bloque: sin CRLF y sin la linea vacia final que pone
  el editor de quien llama. }
function LineasDelAncla(const AOld: string): TArray<string>;
begin
  Result := AOld.Replace(#13#10, #10).Split([#10]);
  while (Length(Result) > 1) and (Result[High(Result)].Trim = '') do
    SetLength(Result, Length(Result) - 1);
end;

function NthBlockLine(const APath, AOld: string; AN: Integer): Integer;
var
  Enc: string;
  Cuantas: Integer;
begin
  Result := 0;
  if AN <= 0 then
    Exit;
  try
    var Idx := BuscaBloque(
      PatchLoadText(APath, Enc).Replace(#13#10, #10).Split([#10]),
      LineasDelAncla(AOld), AN, Cuantas);
    if Idx >= 0 then
      Result := Idx + 1; // 1-based, como atline
  except
    Result := 0;
  end;
end;

function ApplyBlockEdit(const APath, AOld, ANew: string;
  AOccurrence: Integer; AAtLine: Integer): string;
var
  Enc, Text, Eol: string;
  Lines, OldLines, NewLines: TArray<string>;
  I, J, Hit, Count: Integer;
  Sb: TStringBuilder;
begin
  Text := PatchLoadText(APath, Enc);
  if Text.Contains(#13#10) then
    Eol := #13#10
  else
    Eol := #10;
  Lines := Text.Replace(#13#10, #10).Split([#10]);
  OldLines := LineasDelAncla(AOld);
  if Length(OldLines) < 2 then
    Exit(SR_PATCH_BLOCK_SHORT);
  if AAtLine > 0 then
  begin
    // Linea YA resuelta por quien llama. Una tanda la resuelve contra el
    // fichero ORIGINAL y la arrastra segun las entradas anteriores anaden o
    // quitan lineas; volver a contar ocurrencias aqui, sobre el fichero ya
    // mutado, es el bug de "occurrence" por su tercera puerta - la de las
    // anclas de BLOQUE, que se quedo abierta cuando se cerraron las otras
    // dos (2026-09-20). Aqui solo se comprueba que el bloque SIGUE ahi.
    Hit := AAtLine - 1;
    Count := 1;
    if (Hit < 0) or (Hit + Length(OldLines) > Length(Lines)) then
      Hit := -1
    else
      for J := 0 to High(OldLines) do
        if Lines[Hit + J].Trim <> OldLines[J].Trim then
        begin
          Hit := -1;
          Break;
        end;
  end
  else
    Hit := BuscaBloque(Lines, OldLines, AOccurrence, Count);
  if Hit < 0 then
    Exit(Format(SR_PATCH_BLOCK_MISSING_FMT,
      [Length(OldLines), OldLines[0].Trim]));
  if Count > 1 then
    Exit(Format(SR_PATCH_BLOCK_AMBIGUOUS_FMT, [Count, OldLines[0].Trim]));
  NewLines := ANew.Replace(#13#10, #10).Split([#10]);
  while (Length(NewLines) > 1) and (NewLines[High(NewLines)].Trim = '') do
    SetLength(NewLines, Length(NewLines) - 1);
  Sb := TStringBuilder.Create;
  try
    for I := 0 to Hit - 1 do
      Sb.Append(Lines[I]).Append(Eol);
    if not ((Length(NewLines) = 1) and (NewLines[0] = '')) then
      for I := 0 to High(NewLines) do
        Sb.Append(NewLines[I]).Append(Eol);
    for I := Hit + Length(OldLines) to High(Lines) do
    begin
      Sb.Append(Lines[I]);
      if I < High(Lines) then
        Sb.Append(Eol);
    end;
    PatchSaveText(APath, Sb.ToString, Enc);
  finally
    Sb.Free;
  end;
  Result := Format(SN_PATCH_BLOCK_OK_FMT, [Length(OldLines), Hit + 1]);
end;

function FragmentoALinea(const APath, AFrag, ANew: string; AAtLine: Integer;
  const AOtros: string; out AOld, ANewLine: string): string;
var
  Enc, Linea: string;
  Lines: TArray<string>;
  Veces, P: Integer;
begin
  Result := '';
  AOld := '';
  ANewLine := '';
  if AOtros <> '' then
    Exit(Format(SR_FRAG_MIXED_FMT, [AOtros]));
  if AAtLine <= 0 then
    Exit(SR_FRAG_NEEDS_ATLINE);
  if (AFrag = '') or (Pos(#$FFFD, AFrag) > 0) then
    Exit(SR_FRAG_EMPTY);
  if AFrag.Contains(#10) or AFrag.Contains(#13) or
     ANew.Contains(#10) or ANew.Contains(#13) then
    Exit(SR_FRAG_MULTILINE);
  if AFrag = ANew then
    Exit(SR_FRAG_SAME);
  // Los rechazos de aqui ENSENAN la linea: que no sea la de un fichero que
  // este token no puede leer. La puerta ya lo mira; esto es el cinturon.
  Result := ReadPathDenied(APath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit(Format(SR_PATCH_EDITS_NOFILE_FMT, [APath]));
  Lines := PatchLoadText(APath, Enc).Replace(#13#10, #10).Replace(#13, #10)
    .Split([#10]);
  if (Length(Lines) > 0) and (Lines[High(Lines)] = '') then
    SetLength(Lines, Length(Lines) - 1); // la fantasma del salto final
  if AAtLine > Length(Lines) then
    Exit(Format(SR_FRAG_BEYOND_FMT,
      [AAtLine, TPath.GetFileName(APath), Length(Lines)]));
  Linea := Lines[AAtLine - 1];
  Veces := 0;
  P := Pos(AFrag, Linea);
  while P > 0 do
  begin
    Inc(Veces);
    P := Pos(AFrag, Linea, P + 1); // solapadas tambien cuentan: "aa" en "aaa"
  end;
  if Veces = 0 then
    Exit(Format(SR_FRAG_NOTFOUND_FMT, [AFrag, AAtLine, AAtLine, Linea]));
  if Veces > 1 then
    Exit(Format(SR_FRAG_SEVERAL_FMT, [AFrag, Veces, AAtLine, AAtLine, Linea]));
  P := Pos(AFrag, Linea);
  AOld := Linea;
  ANewLine := Copy(Linea, 1, P - 1) + ANew +
    Copy(Linea, P + Length(AFrag), MaxInt);
end;

function RangoHasta(const APath: string;
  ATarget0, AToLine, ATotal: Integer; out AFin: Integer): string;
begin
  Result := '';
  AFin := ATarget0;      // sin rango, el ancla es ella sola
  if AToLine <= 0 then
    Exit;
  if AToLine - 1 < ATarget0 then
    Exit(Format(SR_RANGE_BACKWARDS_FMT, [AToLine, ATarget0 + 1]));
  if AToLine > ATotal then
    Exit(Format(SR_RANGE_BEYOND_FMT,
      [AToLine, TPath.GetFileName(APath), ATotal]));
  // Un rango de la primera a la ultima es "vaciame el fichero" por otra
  // puerta, y estas tools ya rechazan reescribirlo entero. La puerta de al
  // lado es justo donde se cuelan los agujeros (medido tres veces el
  // 2026-09-20), asi que se cierra aqui, con el mismo criterio.
  if (ATarget0 = 0) and (AToLine >= ATotal) then
    Exit(Format(SR_RANGE_WHOLE_FMT, [ATotal]));
  AFin := AToLine - 1;
end;

function AplicaTanda(const APath, AEditsJson: string;
  const AAplicaUna: TAplicaUnaEdicion): string;
var
  Arr: TJSONArray;
  V: TJSONValue;
  Obj: TJSONObject;
  Copia: TBytes;
  Sb: TStringBuilder;
  Una, Anc, Nue: string;
  N, Fallo, EnLinea: Integer;
  Borra: Boolean;
begin
  V := TJSONObject.ParseJSONValue(AEditsJson);
  // Un cliente que codifica dos veces manda el array como CADENA JSON
  // (hermes, 25-sep-2026): se desenvuelve UNA vez. Lo que siga sin ser un
  // array se rechaza diciendo cuanto llego y como empieza, no solo "no es
  // array", que llevaba al cliente a reenviar lo mismo en bucle.
  if V is TJSONString then
  begin
    Una := TJSONString(V).Value;
    V.Free;
    V := TJSONObject.ParseJSONValue(Una);
  end;
  if not (V is TJSONArray) then
  begin
    V.Free;
    Exit(Format(SR_PATCH_EDITS_JSON_FMT,
      [Length(AEditsJson), Copy(AEditsJson.Trim, 1, 60)]));
  end;
  Arr := TJSONArray(V);
  try
    if Arr.Count = 0 then
      Exit(SR_PATCH_EDITS_EMPTY);
    if Arr.Count > 50 then
      Exit(SR_PATCH_EDITS_TOOMANY);
    if not TFile.Exists(APath) then
      Exit(Format(SR_PATCH_EDITS_NOFILE_FMT, [APath]));
    Copia := TFile.ReadAllBytes(APath); // la red: el fichero antes de nada
    Sb := TStringBuilder.Create;
    try
      // "occurrence" se resuelve AQUI, UNA VEZ, contra el fichero ORIGINAL, y
      // despues se ARRASTRA segun cada entrada aplicada anade o quita lineas.
      // Recontarlo dentro del bucle, sobre el fichero YA MUTADO, es justo lo
      // contrario de lo que promete la descripcion del parametro ("los
      // numeros de linea SE MUEVEN y occurrence no"): pedir las ocurrencias
      // 1, 2 y 3 dejaba la 2 y la 3 INTERCAMBIADAS, y borrar la 1 y la 2
      // borraba la 1 y la 3 - contestando "OK" a todo. Escribir en el sitio
      // equivocado y decir que fue bien es la peor forma de fallar que tiene
      // una tool de escritura.
      var Ocurr: TArray<Integer>;
      SetLength(Ocurr, Arr.Count);
      // El final de un RANGO es un numero de linea, o sea que se mueve
      // exactamente igual que los demas: se arrastra en el mismo bucle de
      // abajo. Dejarlo fijo seria el bug de "occurrence" otra vez, ahora
      // llevandose por delante lineas que no eran.
      var Hasta: TArray<Integer>;
      SetLength(Hasta, Arr.Count);
      for N := 0 to Arr.Count - 1 do
      begin
        Ocurr[N] := 0;
        Hasta[N] := 0;
        if Arr.Items[N] is TJSONObject then
        begin
          var O2 := TJSONObject(Arr.Items[N]);
          // Un campo que no existe se leia y se tiraba. Se compara SIN ignorar
          // mayusculas a proposito: "Old" tampoco lo lee nadie mas abajo, asi
          // que tampoco puede pasar por bueno.
          for var Par in O2 do
          begin
            var Conocido := False;
            for var Cl in ['old', 'new', 'atline', 'toline', 'delete',
                           'occurrence', 'fragment'] do
              if Par.JsonString.Value = Cl then
                Conocido := True;
            if not Conocido then
              Exit(Format(SR_PATCH_EDIT_KEY_FMT,
                [N + 1, Par.JsonString.Value]));
          end;
          Hasta[N] := O2.GetValue<Integer>('toline', 0);
          var Nth := O2.GetValue<Integer>('occurrence', 0);
          var Anc2 := O2.GetValue<string>('old', '');
          if (O2.GetValue<Integer>('atline', 0) = 0) and (Nth > 0) then
          begin
            // Las de BLOQUE tambien: era la tercera puerta del mismo bug y
            // se quedo abierta cuando se cerraron las de una linea.
            if Anc2.Contains(#10) then
              Ocurr[N] := NthBlockLine(APath, Anc2, Nth)
            else
              Ocurr[N] := NthOccurrenceLine(APath, Anc2, Nth);
            // Pedir la ocurrencia 5 de algo que aparece 3 veces devolvia 0,
            // el motor lo leia como "sin desempate" y la edicion caia en la
            // PRIMERA. El parametro que existe para no equivocarse de sitio
            // te llevaba al sitio equivocado, contestando OK.
            if Ocurr[N] = 0 then
            begin
              var Hay := 0;
              while Hay < 500 do
              begin
                var Sig: Integer;
                if Anc2.Contains(#10) then
                  Sig := NthBlockLine(APath, Anc2, Hay + 1)
                else
                  Sig := NthOccurrenceLine(APath, Anc2, Hay + 1);
                if Sig = 0 then
                  Break;
                Inc(Hay);
              end;
              Exit(Format(SR_PATCH_OCCURRENCE_FMT, [N + 1, Nth,
                Anc2.Split([#10])[0].Trim.Substring(0,
                  Min(60, Length(Anc2.Split([#10])[0].Trim))), Hay]));
            end;
          end;
        end;
      end;
      // Dos entradas que apuntan a la MISMA linea. occurrence cuenta sobre el
      // fichero de ANTES de la tanda (por eso no se mueve con las entradas
      // anteriores): pedir "occurrence 1" dos veces, esperando que la segunda
      // sea la siguiente aparicion, deja a la segunda sin ancla a mitad de
      // tanda con un mensaje que no explicaba nada (me paso dos veces el
      // 24-sep-2026 usando el servidor como agente). Se rechaza en la puerta.
      for N := 0 to Arr.Count - 1 do
        for var M := 0 to N - 1 do
          if (Ocurr[N] > 0) and (Ocurr[N] = Ocurr[M]) then
            Exit(Format(SR_PATCH_OCCURRENCE_DUP_FMT, [M + 1, N + 1, Ocurr[N]]));
      N := 0;
      Fallo := 0;
      for V in Arr do
      begin
        Inc(N);
        if not (V is TJSONObject) then
        begin
          Fallo := N;
          Sb.AppendLine(Format('  %d: no es un objeto {old,new}', [N]));
          Break;
        end;
        Obj := TJSONObject(V);
        Anc := Obj.GetValue<string>('old', '');
        Nue := Obj.GetValue<string>('new', '');
        // El antes, para saber DONDE cambio y CUANTO y arrastrar lo pendiente.
        // Se toma para las DOS ramas: antes solo lo hacia la de una linea,
        // porque la de bloque salia por Continue justo encima del arrastre -
        // asi que un bloque que anadia o quitaba lineas NO desplazaba las
        // ocurrencias pendientes. Con las dos ramas juntas el agujero se ve;
        // separadas no se veia.
        var EncTmp: string;
        var AntesL: TArray<string>;
        try
          AntesL := PatchLoadText(APath, EncTmp)
            .Replace(#13#10, #10).Split([#10]);
        except
          AntesL := nil;
        end;
        // Ancla de VARIAS lineas: se sustituye el bloque entero. La regla de
        // "una linea" protege a una edicion suelta, donde un ancla larga es
        // una ocasion larga de equivocarse; dentro de una tanda, donde quien
        // llama sustituye un cuerpo que acaba de copiar, era trabajo puro.
        // MODO FRAGMENTO: la entrada se convierte AQUI, contra el fichero
        // tal como esta en este momento de la tanda, en un ancla de linea
        // completa - y de ahi para abajo es una entrada como las demas.
        var Frag := Obj.GetValue<string>('fragment', '');
        if Frag <> '' then
        begin
          var Otros := '';
          if Anc <> '' then Otros := 'old'
          else if Obj.GetValue<Boolean>('delete', False) then Otros := 'delete'
          else if Hasta[N - 1] > 0 then Otros := 'toline'
          else if Obj.GetValue<Integer>('occurrence', 0) > 0 then
            Otros := 'occurrence';
          var NueLinea: string;
          var Mal := FragmentoALinea(APath, Frag, Nue,
            Obj.GetValue<Integer>('atline', 0), Otros, Anc, NueLinea);
          if Mal <> '' then
          begin
            Fallo := N;
            Sb.AppendLine(Format('  %d: %s', [N, Mal.Replace(#10, ' ')]));
            Break;
          end;
          Nue := NueLinea;
        end;
        var EsBloque := Anc.Contains(#10);
        if EsBloque and (Hasta[N - 1] > 0) then
        begin
          Fallo := N;
          Sb.AppendLine(Format('  %d: %s', [N, SR_RANGE_WITH_BLOCK]));
          Break;
        end;
        if EsBloque then
          Una := ApplyBlockEdit(APath, Anc, Nue,
            Obj.GetValue<Integer>('occurrence', 0), Ocurr[N - 1])
        else
        begin
          EnLinea := Obj.GetValue<Integer>('atline', 0);
          if EnLinea = 0 then
            EnLinea := Ocurr[N - 1]; // resuelto arriba y ya desplazado
          Borra := Obj.GetValue<Boolean>('delete', False);
          Una := AAplicaUna(Anc, Nue, EnLinea, Hasta[N - 1], Borra);
        end;
        var Eco := '';
        if (AntesL <> nil) and not (Una.StartsWith('RECHAZADO') or
                                    Una.StartsWith('error')) then
        try
          var DespuesL := PatchLoadText(APath, EncTmp)
            .Replace(#13#10, #10).Split([#10]);
          var Delta := Length(DespuesL) - Length(AntesL);
          // La primera linea que difiere: de ahi para abajo todo se mueve, y
          // ademas es DONDE cayo esta edicion.
          var Cambio := 0;
          while (Cambio < Length(AntesL)) and (Cambio < Length(DespuesL)) and
                (AntesL[Cambio] = DespuesL[Cambio]) do
            Inc(Cambio);
          if Delta <> 0 then
            for var K := N to High(Ocurr) do
            begin
              if Ocurr[K] > Cambio + 1 then // Ocurr 1-based, Cambio 0-based
                Inc(Ocurr[K], Delta);
              if Hasta[K] > Cambio + 1 then
                Inc(Hasta[K], Delta);
            end;
          // EL ECO DE VERIFICACION, releido del disco. Una edicion suelta lo
          // devuelve desde siempre; una TANDA solo decia "OK: <ancla>", que
          // es lo que PEDISTE, no lo que PASO. Y la propia tool recomienda
          // tandas para refactorizar, que es justo cuando hace mas falta: con
          // el bug de "occurrence" escribiendo en la linea equivocada, un
          // agente no tenia forma de enterarse (medido 2026-09-20).
          if Cambio < Length(DespuesL) then
            Eco := Format('%d| %s', [Cambio + 1, DespuesL[Cambio].Trim])
          else if Delta < 0 then
            Eco := Format('%d| (linea quitada)', [Cambio + 1]);
        except
          // si no se puede releer, mejor no tocar lo pendiente
        end;
        // El motor dice RECHAZADO / error cuando se nego; cualquier otra cosa
        // es una edicion aplicada con su auditoria.
        if Una.StartsWith('RECHAZADO') or Una.StartsWith('error') then
        begin
          Fallo := N;
          Sb.AppendLine(Format('  %d: %s', [N, Una.Replace(#10, ' ')]));
          Break;
        end;
        if EsBloque then
          Una := Format('  %d OK (bloque de %d lineas)',
            [N, Length(LineasDelAncla(Anc))])
        else
          Una := Format('  %d OK: %s',
            [N, Anc.Trim.Substring(0, Min(70, Length(Anc.Trim)))]);
        if Eco <> '' then
          Una := Una + '  ->  ' + Eco.Substring(0, Min(90, Length(Eco)));
        Sb.AppendLine(Una);
      end;
      if Fallo > 0 then
      begin
        TFile.WriteAllBytes(APath, Copia); // todo o nada, byte a byte
        Exit(Format(SR_PATCH_EDITS_ROLLED_FMT,
          [Fallo, Arr.Count, Sb.ToString.TrimRight]));
      end;
      Result := Format(SN_PATCH_EDITS_OK_FMT,
        [Arr.Count, TPath.GetFileName(APath), Sb.ToString.TrimRight]);
    finally
      Sb.Free;
    end;
  finally
    Arr.Free;
  end;
end;

function PositionOutOfRange(const APath: string; ALine, AChar: Integer): string;
var
  Lines: TArray<string>;
  Enc: string;
begin
  Result := '';
  if (ALine < 0) or (AChar < 0) then
    Exit(Format(SR_LSP_NEGATIVE_FMT, [ALine, AChar]));
  // Una ruta que no esta llegaba al motor y volvia como "Error executing
  // tool: File not found", que en las reglas de este servidor significa "me
  // he roto por dentro" y no era el caso (2026-08-25).
  if not TFile.Exists(APath) then
    Exit(Format(SR_LSP_NO_FILE_FMT, [APath]));
  try
    Lines := PatchLoadText(APath, Enc).Replace(#13#10, #10).Split([#10]);
  except
    Exit;
  end;
  if ALine >= Length(Lines) then
    Exit(Format(SR_LSP_LINE_RANGE_FMT,
      [ALine, TPath.GetFileName(APath), Length(Lines), Length(Lines) - 1]))
  else if AChar > Length(Lines[ALine]) then
    Exit(Format(SR_LSP_CHAR_RANGE_FMT,
      [AChar, ALine, Length(Lines[ALine]), Lines[ALine].Trim]));
end;

function ReadNumbered(const APath: string; AFrom, ATo: Integer): string;
var
  B: TBytes;
  K: TEncKind;
  M: TMetrics;
  Text, Eol, Body: string;
  Denied: string;
  Lines: TArray<string>;
  IniL, FinL, I: Integer;
  Sb: TStringBuilder;
  Cut, NotaBin: string;
begin
  Denied := ReadPathDenied(APath); // reading may enter the library zone
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(APath) then
  begin
    // "No esta" y "no es un fichero" son cosas distintas, y contestar la
    // primera cuando pasa la segunda manda al agente a buscar una ruta que
    // tiene delante: delphi_read sobre la raiz del repo contestaba "no
    // existe" de una carpeta con 20 entradas (medido 2026-09-20). Y el
    // prefijo era "RECHAZADO:", que por la regla 11 de las convenciones
    // significa "no insistas, cambia de camino"; un nombre mal escrito es
    // "corrige y repite", o sea "error:".
    if TDirectory.Exists(APath) then
      Exit(Format(SR_LSP_IS_FOLDER_FMT, [APath]));
    Exit(Format(SR_LSP_NO_FILE_FMT, [APath]));
  end;
  B := TFile.ReadAllBytes(APath);
  // Un .dfm BINARIO se lee al vuelo como texto ("Ver como texto" del IDE,
  // Lsp.DesignerBin) y se dice: un form legacy dejaba ciego al agente
  // (Hermes, 2026-09-24). Editarlo pide to-text; leerlo, no.
  NotaBin := '';
  if MatchText(TPath.GetExtension(APath), ['.dfm', '.fmx']) and IsBinaryDesignerBytes(B) then
  begin
    NotaBin := DesignerBinaryToText(B, Text);
    if NotaBin <> '' then
      Exit('RECHAZADO: ' + NotaBin);
    B := TEncoding.UTF8.GetBytes(Text);
    NotaBin := SN_READ_BINARY_DESIGNER + #10;
  end;
  // Un binario (un exe, un .res, un .bin.style) no es un texto que numerar:
  // 9 MB de mojibake quemaron un contexto para nada (medido 2026-08-24).
  // La regla es LooksBinaryBytes, la misma que delphi_textedit.
  if LooksBinaryBytes(B) then
    Exit('RECHAZADO: ' + APath + ' es un fichero BINARIO (byte NUL en los ' +
      'primeros 64 KB): no se puede leer como texto numerado. Para bajarlo ' +
      'usa delphi_fetch (o el campo download de /files).');
  K := DetectEnc(B);
  Text := DecodeBytes(B, K);
  M := Measure(B);
  if M.CRLF > M.Loose then Eol := 'CRLF' else Eol := 'LF';
  Lines := SplitToLines(Text);
  IniL := AFrom;
  if IniL < 1 then IniL := 1;
  if IniL > Length(Lines) then
    Exit(Format('%s  encoding=%s  finales=%s  %s'#10 +
      'El fichero tiene %d lineas; desde=%d esta mas alla del final.',
      [TPath.GetFileName(APath), EncName(K), Eol, Summary(M), Length(Lines), IniL]));
  FinL := ATo;
  if (FinL <= 0) or (FinL > Length(Lines)) then FinL := Length(Lines);
  // A range that runs backwards used to answer with a header and an EMPTY
  // body, which reads as "that stretch of the file is empty" (measured
  // 2026-08-25). It is a typo, and it gets told so.
  if FinL < IniL then
    Exit(Format(SR_READ_RANGE_FMT, [IniL, ATo, Length(Lines)]));
  Cut := '';
  if FinL - IniL + 1 > MAX_READ_LINES then
  begin
    FinL := IniL + MAX_READ_LINES - 1;
    Cut := Format(#10'... recortado en la linea %d de %d. Pide otro tramo con from/to.',
      [FinL, Length(Lines)]);
  end;
  Sb := TStringBuilder.Create;
  try
    for I := IniL to FinL do
      Sb.Append(I).Append('|').Append(Lines[I - 1]).Append(#10);
    Body := Sb.ToString.TrimRight([#10]);
  finally
    Sb.Free;
  end;
  Result := NotaBin + Format('%s  encoding=%s  finales=%s  %s'#10 +
    'Lineas %d-%d de %d (formato numero|contenido: el ancla se copia desde justo despues de la barra):'#10'%s%s',
    [TPath.GetFileName(APath), EncName(K), Eol, Summary(M), IniL, FinL,
     Length(Lines), Body, Cut]);
end;

// -------------------------------------------------------------------------
// The edit pipeline (also the primitive that the insert modes call).
// -------------------------------------------------------------------------

function DoEdit(const APath, AOld, ANew: string; AAtLine: Integer;
  AIsDesigner: Boolean; ADelete: Boolean = False;
  AToLine: Integer = 0): string; forward;

function FindUniqueLine(const Lines: TArray<string>;
  const APred: TFunc<string, Boolean>; out AIdx: Integer): Boolean;
var
  I, Cnt: Integer;
begin
  Cnt := 0;
  AIdx := -1;
  for I := 0 to High(Lines) do
    if APred(Lines[I]) then
    begin
      Inc(Cnt);
      AIdx := I;
    end;
  Result := Cnt = 1;
end;

function ExecutePatch(const A: TPatchArgs): string;
var
  Ext, PLower: string;
  IsDesigner, IsSource: Boolean;
  B: TBytes;
  K: TEncKind;
  Text: string;
  Lines, CodeLines: TArray<string>;
  I: Integer;
begin
  GLock.Enter;
  try
    try
      Result := WriteTargetDenied(A.Path); // jaula + carpetas muertas, UNA puerta
      if Result <> '' then
        Exit;
      // Las carpetas muertas (la papelera __delphi-patch, los temporales
      // __delphi-temp, el __history del IDE) no se editan. Su gemela
      // delphi_textedit lo comprobaba desde el principio y esta puerta no:
      // editar dentro de __delphi-temp dejaba el trabajo -y su copia- justo
      // donde la purga del arranque lo borra sin avisar (auditoria
      // 2026-09-21: la regla entro en 1 de los 3 guardianes y delphi_edit
      // era el que faltaba).
      // -> ahora dentro de WriteTargetDenied, arriba (25-sep-2026).
      Ext := LowerCase(TPath.GetExtension(A.Path));
      IsSource := False;
      for var E in SOURCE_EXTS do
        if E = Ext then IsSource := True;
      IsDesigner := False;
      for var E in DESIGNER_EXTS do
        if E = Ext then IsDesigner := True;
      if not IsSource and not IsDesigner then
        Exit(Format('RECHAZADO: extension "%s" no soportada. Esta tool es solo ' +
          'para ficheros Delphi; para texto no-Delphi (.md .py .html .js .ini ...) ' +
          'usa delphi_textedit.', [Ext]));

      PLower := LongCanonical(A.Path).ToLower.Replace('/', '\');
      if PLower.Contains('\' + BACKUP_SUB + '\') then
        Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la carpeta de copias de seguridad de esta tool. Copias muertas: no se leen, no se editan. El fichero vivo esta un nivel mas arriba.');
      if PLower.Contains('\__history\') or PLower.Contains('\__recovery\') then
        Exit('RECHAZADO: __history\ y __recovery\ son copias muertas del IDE. El fichero vivo esta en la carpeta del proyecto.');

      // MODO FRAGMENTO: se resuelve a un ancla de linea completa y sigue
      // por el motor de siempre (ver FragmentoALinea).
      if A.Fragment <> '' then
      begin
        var Otros := '';
        if A.HasOld and (A.OldLine <> '') then Otros := 'old'
        else if A.DeleteLine then Otros := 'delete'
        else if A.ToLine > 0 then Otros := 'toline'
        else if A.CreateUnit_ then Otros := 'createunit'
        else if A.Restore then Otros := 'restore'
        else if A.Insert <> '' then Otros := 'insert';
        var LineaVieja, LineaNueva: string;
        Result := FragmentoALinea(A.Path, A.Fragment, A.NewText, A.AtLine,
          Otros, LineaVieja, LineaNueva);
        if Result <> '' then
          Exit;
        Exit(DoEdit(A.Path, LineaVieja, LineaNueva, A.AtLine, IsDesigner,
          False, 0));
      end;

      // "toline" solo significa algo con un ancla: en los modos que no van
      // por lineas se rechaza en vez de tragarselo en silencio.
      if A.ToLine > 0 then
      begin
        if A.CreateUnit_ then
          Exit(Format(SR_RANGE_WRONG_MODE_FMT, ['createunit']));
        if A.Restore then
          Exit(Format(SR_RANGE_WRONG_MODE_FMT, ['restore']));
        if A.Insert <> '' then
          Exit(Format(SR_RANGE_WRONG_MODE_FMT, ['insert=' + A.Insert]));
      end;

      // ---------- CREATE UNIT ----------
      if A.CreateUnit_ then
      begin
        if Ext <> '.pas' then
          Exit('RECHAZADO: createunit solo crea units (.pas).');
        if TFile.Exists(A.Path) then
          Exit(Format('RECHAZADO: %s YA EXISTE. createunit jamas sobreescribe.', [TPath.GetFileName(A.Path)]));
        var UnitName := TPath.GetFileNameWithoutExtension(A.Path);
        // Dotted namespaces are legal Delphi and REQUIRED by modern projects
        // (Lsp.BuildRunner, System.SysUtils...): allow Ident(.Ident)*.
        if not TRegEx.IsMatch(UnitName, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$') then
          Exit(Format('RECHAZADO: ''%s'' no es un identificador Pascal valido para nombre de unit.', [UnitName]));
        var Skel: string;
        var Note: string;
        if A.Content <> '' then
        begin
          // Whole known content in ONE call (replicating a file you already
          // have beats a create + N anchored patches). EOL normalized to
          // CRLF - the JSON channel often arrives LF-only - and the result
          // is audited below like any other write.
          Skel := A.Content.Replace(#13#10, #10).Replace(#13, #10);
          if not SameText(A.Eol, 'lf') then
            Skel := Skel.Replace(#10, #13#10);
          if not Skel.EndsWith(#10) then
            if SameText(A.Eol, 'lf') then Skel := Skel + #10 else Skel := Skel + #13#10;
          Note := 'contenido aportado';
        end
        else
        begin
          Skel := Format('unit %s;'#13#10#13#10'interface'#13#10#13#10 +
            'implementation'#13#10#13#10'end.'#13#10, [UnitName]);
          Note := 'esqueleto estandar del IDE';
        end;
        CrearCarpeta(TPath.GetDirectoryName(TPath.GetFullPath(A.Path)));
        // New files honour the encoding the IDE is configured to use.
        var NewK := ekCp1252;
        if IdeWantsUtf8 then
          NewK := ekUtf8Bom;
        try
          AtomicWrite(A.Path, EncodeText(Skel, NewK));
        except
          on E: Exception do
            Exit('RECHAZADO al codificar el contenido: ' + E.Message +
              #10'Usa literales Pascal nativos (#$XXXX) para caracteres fuera del juego.');
        end;
        var CM := Measure(TFile.ReadAllBytes(A.Path));
        Exit(Format('CREADA %s (unit %s) - %s, encoding %s (el configurado en el IDE), %s.'#10 +
          'Verificacion (releido de disco): %s'#10 +
          'SIGUIENTE PASO - el ALTA en el uses del .dpr (sin alta, la unit no forma parte del proyecto). ' +
          'El .dproj lo mantiene el IDE: no lo edites.',
          [TPath.GetFileName(A.Path), UnitName, Note, EncName(NewK),
           IfThen(SameText(A.Eol, 'lf'), 'LF', 'CRLF'), Summary(CM)]));
      end;

      if not TFile.Exists(A.Path) then
        Exit('RECHAZADO: no existe ' + A.Path);

      B := TFile.ReadAllBytes(A.Path);
      // Two binary shapes exist (measured with the IDE's own convert.exe):
      // a raw stream starts 'TPF0'; the REAL on-disk binary .dfm/.fmx wraps
      // that stream in a 16-bit resource header whose first byte is $FF
      // (FF 0A 00 + UPPERCASED name + the TPF0 stream at ~offset 19). A text
      // form always begins with object/inherited/inline - never $FF.
      if IsDesigner and IsBinaryDesignerBytes(B) then
        Exit(Format('RECHAZADO: %s es un %s BINARIO (firma TPF0 o envoltorio de recurso $FF). ' +
          'No es texto y no se edita asi. Pasalo a texto con delphi_designer ' +
          'command=to-text (copia previa, la misma conversion que el IDE) y edita; ' +
          'delphi_read y delphi_designer ya lo LEEN al vuelo sin convertirlo.',
          [TPath.GetFileName(A.Path), Ext]));

      K := DetectEnc(B);
      if (K = ekUtf8Bom) and not ValidUtf8(B, 3) then
        Exit(Format('RECHAZADO: %s tiene BOM UTF-8 pero su contenido no es UTF-8 valido (fichero mezclado o danado). No lo toco.',
          [TPath.GetFileName(A.Path)]));
      Text := DecodeBytes(B, K);

      // ---------- RESTORE (2 steps) ----------
      if A.Restore then
      begin
        var DirBk := TPath.Combine(TPath.GetDirectoryName(A.Path), BACKUP_SUB);
        var Src := '';
        if TDirectory.Exists(DirBk) then
        begin
          var Days := TDirectory.GetDirectories(DirBk);
          TArray.Sort<string>(Days);
          for I := High(Days) downto 0 do
          begin
            var Cand := TPath.Combine(Days[I], TPath.GetFileName(A.Path));
            if TRegEx.IsMatch(TPath.GetFileName(Days[I]), '^\d{8}$') and TFile.Exists(Cand) then
            begin
              Src := Cand;
              Break;
            end;
          end;
        end;
        if Src = '' then
          Exit(Format('RECHAZADO: no hay copia de %s en %s\. Solo puedo restaurar lo que yo misma copie.',
            [TPath.GetFileName(A.Path), BACKUP_SUB]));

        var BkBytes := TFile.ReadAllBytes(Src);
        var NowLines := SplitToLines(Text);
        var BkSet := TDictionary<string, Boolean>.Create;
        var Losses := TStringList.Create;
        try
          for var L in SplitToLines(DecodeBytes(BkBytes, DetectEnc(BkBytes))) do
            BkSet.AddOrSetValue(L, True);
          for I := 0 to High(NowLines) do
            if (NowLines[I].Trim <> '') and not BkSet.ContainsKey(NowLines[I]) then
              Losses.Add(Format('  %d|%s', [I + 1, NowLines[I]]));

          if not A.Confirm then
          begin
            var Lista: string;
            if Losses.Count = 0 then
              Lista := '  (ninguna: el fichero actual no tiene lineas que no esten ya en la copia)'
            else
            begin
              var Top := Losses.Count;
              if Top > 25 then Top := 25;
              var SbL := TStringBuilder.Create;
              try
                for I := 0 to Top - 1 do SbL.AppendLine(Losses[I]);
                if Losses.Count > 25 then SbL.Append(Format('  ... y %d mas', [Losses.Count - 25]));
                Lista := SbL.ToString.TrimRight;
              finally
                SbL.Free;
              end;
            end;
            // "desde %s" sale al agente y delphi_edit esta EXENTA del filtro de
            // salida: la mascara va A MANO aqui y en el RESTAURADO de abajo,
            // como en BackupFile (la obligacion de la lista, ver Lsp.Guard).
            // La copia es la PRIMERA del dia de ese fichero y no sabe de quien
            // es: si otro agente lo edito despues, restaurar se lleva TAMBIEN
            // su trabajo. Decision de David (24-sep-2026): no se hace una copia
            // por agente; se dice la hora de la copia y se avisa de los demas.
            // Deshacer con precision es cosa de git (delphi_git).
            // Hora de CREACION de la copia: la de modificacion la hereda del
            // original (TFile.Copy) y puede ser de dias antes.
            var Sello := TFile.GetCreationTime(Src);
            Exit(Format('RESTAURAR %s desde %s: aun NO he hecho nada.'#10 +
              'La copia se hizo el %s (hace %s): es la PRIMERA de ese dia de este ' +
              'fichero, y no sabe quien lo ha editado desde entonces. Si otro agente lo ' +
              'toco despues de esa hora, restaurar se lleva TAMBIEN su trabajo; para ' +
              'deshacer con precision usa delphi_git (diff, stash).'#10 +
              'Estas %d lineas del fichero ACTUAL no estan en la copia y SE PERDERAN:'#10'%s'#10 +
              'Si de verdad quieres restaurar, repite con confirm: true.',
              [TPath.GetFileName(A.Path), MaskDriveText('', Src),
               FormatDateTime('yyyy-mm-dd hh:nn', Sello), EdadLegible(Now - Sello),
               Losses.Count, Lista]));
          end;

          // Antes se componia aqui a mano, con OTRA forma de sello
          // (".antes-restaurar-hhnnss"), y por eso el lector de la papelera no
          // la reconocia: ni salia en delphi_list includetrash ni se podia
          // restaurar como es debido. Ahora el sello lo pone el nombrador y
          // lo que distingue a esta copia es su CAJON, no su nombre.
          var PreCopy := TPath.Combine(TrashDayDir(A.Path, 'antes-restaurar'),
            TrashStampedName(TPath.GetFileName(A.Path)));
          CrearCarpeta(TPath.GetDirectoryName(PreCopy));
          TFile.Copy(A.Path, PreCopy);
          AtomicWrite(A.Path, BkBytes);
          Exit(Format('RESTAURADO %s desde %s'#10'  ahora: %s'#10 +
            '  OJO: se han perdido %d lineas que tenias escritas. Rehaz y RE-VERIFICA cada tarea de este fichero.'#10 +
            '  (estado previo guardado en %s)',
            [TPath.GetFileName(A.Path), MaskDriveText('', Src), Summary(Measure(TFile.ReadAllBytes(A.Path))),
             Losses.Count, MaskDriveText('', PreCopy)]));
        finally
          BkSet.Free;
          Losses.Free;
        end;
      end;

      // ---------- SEMANTIC INSERT ----------
      if A.Insert <> '' then
      begin
        if IsDesigner then
          Exit('RECHAZADO: insert es solo para fuentes Pascal, no para ficheros del designer.');
        if (A.Insert <> 'rutina-global') and (A.Insert <> 'metodo') then
          Exit('RECHAZADO: insert debe ser "rutina-global" o "metodo". Para statements dentro de un cuerpo usa old/new (ancla en una linea del metodo).');
        if A.Code.Trim = '' then
          Exit('RECHAZADO: el modo insert necesita "code" con el bloque COMPLETO (firma + begin..end;).');
        if TRegEx.IsMatch(A.Code, '^[ \t]*end\.[ \t]*$', [roMultiLine]) then
          Exit('RECHAZADO: el bloque trae un ''end.''. Solo hay un end. y es del fichero: quitalo del bloque.');

        CodeLines := SplitToLines(A.Code.TrimRight);
        var LastLine := '';
        for I := High(CodeLines) downto 0 do
          if CodeLines[I].Trim <> '' then
          begin
            LastLine := CodeLines[I].Trim;
            Break;
          end;
        var NoComment := TRegEx.Replace(LastLine, '//.*$', '').Trim;
        if not TRegEx.IsMatch(LastLine, '(^|[^\w])end\s*;$', [roIgnoreCase]) and
           not TRegEx.IsMatch(NoComment, '(^|[^\w])end\s*;$', [roIgnoreCase]) then
        begin
          if TRegEx.IsMatch(NoComment, '(^|[^\w])end$', [roIgnoreCase]) then
            Exit('RECHAZADO: el bloque termina en ''end'' SIN punto y coma (E2029). Anade el '';'' al end final.');
          Exit(Format('RECHAZADO: la ultima linea del bloque es |%s| y una rutina COMPLETA termina en ''end;''.',
            [Copy(LastLine, 1, 80)]));
        end;

        // La firma puede ocupar VARIAS lineas y venir precedida de un
        // comentario de documentacion (el estilo de la casa lo hace). Se busca
        // la primera linea que ES una firma - saltando blancos y comentarios -
        // y se sigue hasta el ';' que la CIERRA a profundidad de parentesis 0:
        // dentro de los parentesis el ';' solo separa grupos de parametros.
        // Medido en campo (18-sep): quedarse con la primera linea escribia la
        // declaracion TRUNCADA en la clase y, como esa linea acaba en ';', la
        // comprobacion de cierre la daba por buena - E2029 y cascada de
        // "identificador no declarado" lejos del sitio real, con el informe
        // diciendo "las DOS mitades".
        var IFirmaIni := -1;
        var EnComentario := False;
        for I := 0 to High(CodeLines) do
        begin
          var T := CodeLines[I].Trim;
          if EnComentario then
          begin
            if T.Contains('}') or T.Contains('*)') then
              EnComentario := False;
            Continue;
          end;
          if (T = '') or T.StartsWith('//') then
            Continue;
          if T.StartsWith('{') or T.StartsWith('(*') then
          begin
            if not (T.Contains('}') or T.Contains('*)')) then
              EnComentario := True;
            Continue;
          end;
          IFirmaIni := I;
          Break;
        end;
        var Firma := '';
        if IFirmaIni >= 0 then
          Firma := CodeLines[IFirmaIni].Trim;
        var MF := TRegEx.Match(Firma,
          '^(procedure|function|constructor|destructor)\s+([A-Za-z_]\w*)\s*([.(;:])?', [roIgnoreCase]);
        if not MF.Success then
          Exit(Format('RECHAZADO: el bloque no empieza por una firma de rutina (puede llevar comentario encima). Primera linea util: |%s|', [Copy(Firma, 1, 80)]));
        if MF.Groups[3].Value = '.' then
          Exit('RECHAZADO: la firma viene CUALIFICADA con clase. Pasala SIN cualificar; con insert:"metodo" la tool pone el prefijo.');
        var IFirmaFin := IFirmaIni;
        var PosCierre := 0;
        var FirmaCerrada := False;
        var ProfPar := 0;
        var EnCadena := False;
        for I := IFirmaIni to High(CodeLines) do
        begin
          var Ln := TRegEx.Replace(CodeLines[I], '//.*$', '');
          var Col := 0;
          for var Ch in Ln do
          begin
            Inc(Col);
            if Ch = '''' then
              EnCadena := not EnCadena
            else if not EnCadena then
            begin
              if Ch = '(' then
                Inc(ProfPar)
              else if Ch = ')' then
                Dec(ProfPar)
              else if (Ch = ';') and (ProfPar <= 0) then
              begin
                FirmaCerrada := True;
                PosCierre := Col;
              end;
            end;
            if FirmaCerrada then
              Break;
          end;
          IFirmaFin := I;
          if FirmaCerrada then
            Break;
        end;
        if not FirmaCerrada then
          Exit(Format('RECHAZADO: la firma no llega a cerrarse con '';''. Empieza en |%s|', [Copy(Firma, 1, 80)]));
        var FirmaLineas := TArray<string>.Create();
        for I := IFirmaIni to IFirmaFin do
          if I = IFirmaFin then
            FirmaLineas := FirmaLineas + [Copy(CodeLines[I], 1, PosCierre).Trim]
          else
            FirmaLineas := FirmaLineas + [CodeLines[I].Trim];

        Lines := SplitToLines(Text);

        // A program/library (.dpr) has no interface/implementation: a routine
        // is legal only BETWEEN the uses clause and the main begin..end.
        // Measured in the field (round 2, B3): inserting before 'end.' left
        // the .dpr uncompilable (E2070 + 2xE2029) - the post-write audit sees
        // structure, not grammar, so the placement must be right by design.
        if Ext = '.dpr' then
        begin
          if A.Insert = 'metodo' then
            Exit('RECHAZADO: insert:"metodo" no aplica a un .dpr (las clases ' +
              'van en units). Crea la unit con createunit e inserta alli.');
          var IUses := -1;
          var IAfter := -1;
          for I := 0 to High(Lines) do
            if TRegEx.IsMatch(Lines[I], '^[ \t]*uses\b', [roIgnoreCase]) then
            begin
              IUses := I;
              Break;
            end;
          if IUses >= 0 then
          begin
            for I := IUses to High(Lines) do
              if TRegEx.Replace(Lines[I], '//.*$', '').TrimRight.EndsWith(';') then
              begin
                IAfter := I;
                Break;
              end;
          end
          else
            for I := 0 to High(Lines) do
              if TRegEx.IsMatch(Lines[I], '^[ \t]*(program|library)\b', [roIgnoreCase]) and
                 TRegEx.Replace(Lines[I], '//.*$', '').TrimRight.EndsWith(';') then
              begin
                IAfter := I;
                Break;
              end;
          if IAfter = -1 then
            Exit('RECHAZADO: no encuentro el final de la cabecera/uses del .dpr ' +
              'para colocar la rutina.');
          var AnclaDpr := Lines[IAfter];
          var RDpr := DoEdit(A.Path, AnclaDpr,
            AnclaDpr + #10#10 + string.Join(#10, CodeLines), IAfter + 1, False);
          var NotaVis := '';
          if A.Visible then
            NotaVis := #10'(visible ignorado: un program no tiene seccion interface)';
          Exit(Format('INSERT rutina-global (.dpr): colocada DESPUES de la linea %d ' +
            '(|%s|), entre el uses y el bloque principal - la frontera legal en un program.'#10'%s%s',
            [IAfter + 1, AnclaDpr.Trim, RDpr, NotaVis]));
        end;

        var FrontIdx: Integer;
        var FoundFront := FindUniqueLine(Lines,
          function(L: string): Boolean
          begin
            Result := L.Trim.ToLower = 'initialization';
          end, FrontIdx);
        if not FoundFront then
          FoundFront := FindUniqueLine(Lines,
            function(L: string): Boolean
            begin
              Result := TRegEx.IsMatch(L, '^[ \t]*end\.[ \t]*$');
            end, FrontIdx);
        if not FoundFront then
          Exit('RECHAZADO: no encuentro la frontera del final de la unit (ni ''initialization'' unica ni ''end.'' unico).');
        var FrontLine := Lines[FrontIdx];

        if A.Insert = 'rutina-global' then
        begin
          var R := DoEdit(A.Path, FrontLine,
            string.Join(#10, CodeLines) + #10#10 + FrontLine, FrontIdx + 1, False);
          var Extra := '';
          if A.Visible and R.StartsWith('ESCRITO') then
          begin
            var ImpIdx: Integer;
            if FindUniqueLine(SplitToLines(DecodeBytes(TFile.ReadAllBytes(A.Path), K)),
              function(L: string): Boolean
              begin
                Result := L.Trim.ToLower = 'implementation';
              end, ImpIdx) then
            begin
              var Decl := string.Join(#10, FirmaLineas);
              if not Decl.EndsWith(';') then Decl := Decl + ';';
              var R2 := DoEdit(A.Path, 'implementation', Decl + #10#10 + 'implementation', ImpIdx + 1, False);
              if R2.StartsWith('ESCRITO') then
                Extra := #10'--- visible: declaracion ''' + Decl + ''' anadida al final del interface ---'#10 + R2
              else
                Extra := #10'*** visible: NO pude anadir la declaracion en interface - hazla con old/new. ***'#10 + R2;
            end
            else
              Extra := #10'*** visible: no encuentro una linea ''implementation'' unica; anade la declaracion con old/new. ***';
          end;
          Exit(Format('INSERT rutina-global: colocada ANTES de la linea %d (|%s|), la frontera legal elegida por la tool.'#10'%s%s',
            [FrontIdx + 1, FrontLine.Trim, R, Extra]));
        end;

        // insert = 'metodo'
        if A.ClassName_.Trim = '' then
          Exit('RECHAZADO: insert:"metodo" necesita "inclass" con el nombre exacto de la clase.');
        var ClsRe := TRegEx.Create('\b' + TRegEx.Escape(A.ClassName_) + '\s*=\s*class\b', [roIgnoreCase]);
        var IClase := -1;
        for I := 0 to High(Lines) do
          if ClsRe.IsMatch(Lines[I]) then
          begin
            IClase := I;
            Break;
          end;
        if IClase = -1 then
          Exit(Format('RECHAZADO: no encuentro ''%s = class'' en %s.', [A.ClassName_, TPath.GetFileName(A.Path)]));
        // Un tipo ANIDADO (private type TPendingCall = class ... end;) cierra
        // con su propio 'end;' antes que la clase, asi que el primer 'end;'
        // no es el de la clase: la declaracion caia DENTRO del tipo anidado y
        // la seccion pedida "no existia" (medido 2026-09-22 en Lsp.Client).
        // Se lleva la profundidad: un tipo anidado abre en la linea que lo
        // declara sin cerrarlo (sin ';' al final) y cierra con su 'end;'.
        var IFin := -1;
        var TipoAnidadoRe := TRegEx.Create('[=:]\s*(packed\s+)?(class|record|interface|dispinterface|object)\b', [roIgnoreCase]);
        var Prof := 0;
        for I := IClase + 1 to High(Lines) do
        begin
          var L := Lines[I].Trim;
          if L.ToLower = 'end;' then
          begin
            if Prof = 0 then
            begin
              IFin := I;
              Break;
            end;
            Dec(Prof);
          end
          else if TipoAnidadoRe.IsMatch(L) and not L.EndsWith(';') and
                  not L.ToLower.Contains(' end;') then
            Inc(Prof);
        end;
        if IFin = -1 then
          Exit(Format('RECHAZADO: no encuentro el ''end;'' de cierre de la clase %s.', [A.ClassName_]));

        // COLISION (campo, hermes 17-sep): la firma de un metodo vive DOS
        // veces (interface + implementation) y la tool escribia las dos a
        // ciegas - si la clase YA declaraba el metodo, la segunda declaracion
        // es E2254/E2537 seguro. Se mira cada mitad por separado y solo se
        // escribe la que falta; entero = rechazo con el camino.
        var Nombre := MF.Groups[2].Value;
        var DeclRe := TRegEx.Create('^\s*(class\s+)?(procedure|function|constructor|destructor)\s+' +
          TRegEx.Escape(Nombre) + '\s*[(;:]', [roIgnoreCase]);
        var IDeclExiste := -1;
        for I := IClase + 1 to IFin - 1 do
          if DeclRe.IsMatch(Lines[I]) then
          begin
            IDeclExiste := I;
            Break;
          end;
        var ImplRe := TRegEx.Create('^\s*(class\s+)?(procedure|function|constructor|destructor)\s+' +
          TRegEx.Escape(A.ClassName_) + '\.' + TRegEx.Escape(Nombre) + '\s*[(;:]', [roIgnoreCase]);
        var IImplExiste := -1;
        for I := 0 to High(Lines) do
          if ImplRe.IsMatch(Lines[I]) then
          begin
            IImplExiste := I;
            Break;
          end;
        if (IDeclExiste >= 0) and (IImplExiste >= 0) then
          Exit(Format('RECHAZADO: %s.%s ya existe ENTERO (declaracion en linea %d, ' +
            'implementacion en linea %d). insert:"metodo" no duplica: para cambiar ' +
            'su cuerpo usa old/new anclando en una linea del metodo; si querias un ' +
            'OVERLOAD, anade sus dos mitades con old/new.',
            [A.ClassName_, Nombre, IDeclExiste + 1, IImplExiste + 1]));
        if IImplExiste >= 0 then
          Exit(Format('RECHAZADO: existe la implementacion %s.%s (linea %d) pero la ' +
            'clase no la declara - fichero incoherente. Revisalo y anade la ' +
            'declaracion con old/new.',
            [A.ClassName_, Nombre, IImplExiste + 1]));

        var R1 := '';
        var DeclLinea := '';
        var DeclNota := '';
        var NotaPublished := '';
        if IDeclExiste >= 0 then
          DeclNota := Format('la clase YA declaraba ''%s'' (linea %d) y NO se anade ' +
            'segunda declaracion (si querias un OVERLOAD, su declaracion va con old/new)',
            [Nombre, IDeclExiste + 1])
        else
        begin
        var Secs := TArray<string>.Create('private', 'protected', 'public', 'published',
          'strict private', 'strict protected');
        var IDecl := IFin;
        var Vis := A.Visibility.Trim.ToLower;
        if Vis = 'default' then
          Vis := 'published';
        // Sin visibility, un metodo que el designer pareja YA cablea como
        // evento (OnClick = Nombre) va a published: es lo unico que resuelve
        // el streaming (hermes, 25-sep-2026: cayo en public, build verde,
        // "Invalid property value" al cargar el form en Zorin).
        if Vis = '' then
          for var ExtD in ['.dfm', '.fmx'] do
            if DesignerWiresMethodFile(ChangeFileExt(A.Path, ExtD), Nombre) then
            begin
              Vis := 'published';
              NotaPublished := Format(SN_PATCH_INSERT_PUBLISHED_BY_EVENT_FMT,
                [TPath.GetFileName(ChangeFileExt(A.Path, ExtD)), Nombre]);
              Break;
            end;
        if Vis <> '' then
        begin
          var IVis := -1;
          for I := IClase + 1 to IFin - 1 do
            if Lines[I].Trim.ToLower = Vis then
            begin
              IVis := I;
              Break;
            end;
          if IVis = -1 then
          begin
            // A form class keeps components and event handlers in the
            // IMPLICIT published section right after the class header, with
            // no keyword line. 'published' must land there - the most common
            // VCL case (round 2, C1). But it must go AFTER the last member of
            // that section (after the component fields), never right after the
            // header: a method before a field is E2169 (round 3, C1-bis).
            if Vis = 'published' then
            begin
              IDecl := IFin;
              for I := IClase + 1 to IFin - 1 do
              begin
                var TrimL := Lines[I].Trim.ToLower;
                var IsSec := False;
                for var S2 in Secs do
                  if (S2 = TrimL) or TrimL.StartsWith(S2 + ' ') then IsSec := True; // 'private type', 'public const'...
                if IsSec then // first explicit visibility specifier = end of
                begin         // the implicit published section
                  IDecl := I;
                  Break;
                end;
              end;
            end
            else
              Exit(Format('RECHAZADO: la clase %s no tiene seccion ''%s''. Omite visibility o usa una que exista.',
                [A.ClassName_, Vis]));
          end
          else
          begin
            IDecl := IFin;
            for I := IVis + 1 to IFin - 1 do
            begin
              var TrimL := Lines[I].Trim.ToLower;
              var IsSec := False;
              for var S2 in Secs do
                if (S2 = TrimL) or TrimL.StartsWith(S2 + ' ') then IsSec := True;
              if IsSec then
              begin
                IDecl := I;
                Break;
              end;
            end;
          end;
        end;
        var Sangria := '    ';
        for I := IClase + 1 to IFin - 1 do
        begin
          var TrimL := Lines[I].Trim;
          var IsSec := False;
          for var S2 in Secs do
            if (S2 = TrimL.ToLower) or TrimL.ToLower.StartsWith(S2 + ' ') then IsSec := True;
          if (TrimL <> '') and not IsSec then
          begin
            Sangria := Copy(Lines[I], 1, Length(Lines[I]) - Length(Lines[I].TrimLeft));
            Break;
          end;
        end;
        DeclLinea := Sangria + FirmaLineas[0];
        for I := 1 to High(FirmaLineas) do
          DeclLinea := DeclLinea + #10 + Sangria + '  ' + FirmaLineas[I];
        if not DeclLinea.EndsWith(';') then DeclLinea := DeclLinea + ';';
        var AnclaDecl := Lines[IDecl - 1];
        R1 := DoEdit(A.Path, AnclaDecl, AnclaDecl + #10 + DeclLinea, IDecl, False);
        if not R1.StartsWith('ESCRITO') then
          Exit(Format('INSERT metodo - FALLO en la mitad 1 (declaracion en la clase %s):'#10'%s', [A.ClassName_, R1]));
        end;
        var FirmaCual := TRegEx.Replace(Firma,
          '^(procedure|function|constructor|destructor)(\s+)', '$1$2' + A.ClassName_ + '.', [roIgnoreCase]);
        CodeLines[IFirmaIni] := FirmaCual;
        var R2 := DoEdit(A.Path, FrontLine, string.Join(#10, CodeLines) + #10#10 + FrontLine, 0, False);
        if not R2.StartsWith('ESCRITO') then
        begin
          if DeclNota <> '' then
            Exit('INSERT metodo - FALLO en la implementacion (la declaracion ya ' +
              'existia y no se toco; el fichero NO ha cambiado).'#10 + R2);
          Exit('INSERT metodo - mitad 1 (declaracion) ESCRITA pero FALLO en la mitad 2 (implementacion). ' +
            'El fichero ha quedado A MEDIAS: restaura con restore:true y reintenta.'#10 + R2);
        end;
        if DeclNota <> '' then
          Exit(Format('INSERT metodo en %s: %s. Solo se ha escrito la implementacion.'#10 +
            '--- Implementacion ''%s'' en la frontera legal ---'#10'%s',
            [A.ClassName_, DeclNota, Copy(FirmaCual, 1, 70), R2]));
        Exit(Format('INSERT metodo en %s: la tool ha hecho las DOS mitades.%s'#10 +
          '--- Mitad 1: declaracion ''%s'' dentro de la clase ---'#10'%s'#10 +
          '--- Mitad 2: implementacion ''%s'' en la frontera legal ---'#10'%s',
          [A.ClassName_, IfThen(NotaPublished <> '', #10'  ' + NotaPublished, ''),
           DeclLinea.Trim, R1, Copy(FirmaCual, 1, 70), R2]));
      end;

      // ---------- DELETE LINE ----------
      if A.DeleteLine then
      begin
        if not A.HasOld or (A.OldLine = '') then
          Exit('RECHAZADO: delete:true necesita "old" con la linea exacta a borrar (copiada de delphi_read).');
        if A.NewText <> '' then
          Exit('RECHAZADO: delete:true no lleva "new": elimina la linea del ancla entera. Para sustituirla usa old+new sin delete.');
        Exit(DoEdit(A.Path, A.OldLine, '', A.AtLine, IsDesigner, True, A.ToLine));
      end;

      // new without anchor: measured pattern where generic edit tools rewrite
      // the whole file. Explicit rejection, never creative interpretation.
      if (not A.HasOld or (A.OldLine = '')) and A.HasNew then
        Exit('RECHAZADO: has pasado "new" sin ancla ("old" vacio). Esta tool NUNCA reescribe un fichero entero.'#10 +
          '- Para editar: old = la linea COMPLETA a sustituir, copiada de delphi_read.'#10 +
          '- Para leer: usa delphi_read.');
      if not A.HasOld then
        Exit('RECHAZADO: faltan parametros. Modos: old+new (editar) | insert+code (insertar) | createunit | restore. Para leer usa delphi_read.');
      if not A.HasNew then
        Exit('RECHAZADO: has pasado "old" pero no "new".');

      Result := DoEdit(A.Path, A.OldLine, A.NewText, A.AtLine, IsDesigner,
        False, A.ToLine);
    except
      on E: Exception do
        Result := 'ERROR: ' + E.ClassName + ': ' + E.Message;
    end;
  finally
    GLock.Leave;
  end;
end;

{ Designer lint: every property line of the RESULTING file resolved against
  the GENERATED framework tables (Lsp.DesignerMeta - classes, published
  properties, enum/set members and instance aliases dumped from the
  framework's own metadata by src\DesignerMetaDump). The framework
  describes itself; no hand-written error rules. Field origin (Fase 3): a
  hand-edited .fmx crashed at form-load on the device with no trace - the
  build only checks a form resource's text grammar. Warnings, not
  refusals. }
function DesignerLint(const APath: string;
  const ALines: TArray<string>): TArray<string>;
var
  Raw: TArray<string>;
  Res: TStringList;
  I: Integer;
  ExtName: string;
begin
  Result := [];
  Raw := DesignerMetaLint(APath.ToLower.EndsWith('.fmx'), ALines);
  // El form contra su clase (Lsp.DesignerBinding): un OnClick a un metodo
  // en public compila y revienta al cargar el form. Se avisa AL ESCRIBIR.
  var Bind := DesignerBindingWarnings(APath, ALines);
  if (Length(Raw) = 0) and (Length(Bind) = 0) then
    Exit;
  Res := TStringList.Create;
  try
    if Length(Raw) > 0 then
    begin
    for I := 0 to High(Raw) do
    begin
      if I >= 8 then
      begin
        Res.Add(Format('  ... y %d mas', [Length(Raw) - 8]));
        Break;
      end;
      Res.Add(Raw[I]);
    end;
    if APath.ToLower.EndsWith('.fmx') then
      ExtName := '.fmx'
    else
      ExtName := '.dfm';
    Res.Insert(0, '*** AVISO DESIGNER: propiedades que el streaming del ' +
      ExtName + ' NO conoce (contrastado con las tablas generadas del ' +
      'propio framework). El build las empaqueta igual (solo valida ' +
      'gramatica) y la app CRASHEA al cargar el form en runtime - en ' +
      'Android muere sin mensaje. Corrigelas antes de desplegar: ***');
    end;
    if Length(Bind) > 0 then
    begin
      Res.Add(SN_DESIGNER_BINDING_LINT_HEADER);
      Res.AddStrings(Bind);
    end;
    Result := Res.ToStringArray;
  finally
    Res.Free;
  end;
end;

function DoEdit(const APath, AOld, ANew: string; AAtLine: Integer;
  AIsDesigner: Boolean; ADelete: Boolean = False;
  AToLine: Integer = 0): string;
var
  B, NewBytes, After: TBytes;
  K: TEncKind;
  Text, Eol: string;
  M, D: TMetrics;
  Lines: TArray<string>;
  Hits: TList<Integer>;
  I, HitIdx: Integer;
  Prefix, Replacement: string;
  Warnings: TStringList;

  function HighCount(const S: string): Integer;
  var
    X: Byte;
    KH: TEncKind;
  begin
    Result := 0;
    // The BOM belongs to the FILE, not to any line of text: encoding a text
    // fragment as utf8-bom would smuggle 3 phantom high bytes into the
    // accounting (measured false positive: "expected 0, got 3").
    KH := K;
    if KH in [ekUtf8Bom, ekUtf16LE, ekUtf16BE] then
      KH := ekUtf8; // sin BOM, y UTF-16 en el mismo cuerpo UTF-8 que mide Measure
    try
      for X in EncodeText(S, KH) do
        if X > 127 then
          Inc(Result);
    except
      Result := -1;
    end;
  end;

  function CountEndDot(const T: string): Integer;
  begin
    Result := TRegEx.Matches(T, '^[ \t]*end\.[ \t]*$', [roMultiLine]).Count;
  end;

begin
  B := TFile.ReadAllBytes(APath);
  K := DetectEnc(B);
  Text := DecodeBytes(B, K);
  M := Measure(B);
  if M.CRLF > M.Loose then Eol := 'CRLF' else Eol := 'LF';

  if (Pos(#13, AOld) > 0) or (Pos(#10, AOld) > 0) then
    Exit(SR_PATCH_ANCHOR_MULTILINE);
  if AOld.Trim = '' then
    Exit('RECHAZADO: el ancla esta vacia o es solo espacios.');
  if Pos(#$FFFD, AOld) > 0 then
    Exit('RECHAZADO: tu ancla lleva el caracter de corrupcion U+FFFD. Leiste el fichero con una tool generica ' +
      'que destruyo los acentos. Vuelve a leerlo con delphi_read y copia el ancla de ahi.');

  Lines := SplitToLines(Text);
  Hits := TList<Integer>.Create;
  Warnings := TStringList.Create;
  try
    for I := 0 to High(Lines) do
      if (Lines[I] = AOld) or
         (Lines[I].EndsWith(AOld) and
          IsAllWhitespace(Copy(Lines[I], 1, Length(Lines[I]) - Length(AOld)))) then
        Hits.Add(I);

    if Hits.Count = 0 then
    begin
      var Pista := '';
      var Objetivo := AOld.Trim;
      for I := 0 to High(Lines) do
        if Lines[I].Trim = Objetivo then
        begin
          Pista := Format(#10'OJO: la linea %d tiene ese MISMO texto con OTRA indentacion. Copiala tal cual:'#10'  %d|%s',
            [I + 1, I + 1, Lines[I]]);
          Break;
        end;
      if Pista = '' then
      begin
        var Mejor := -1;
        var MejorLen := 0;
        for I := 0 to High(Lines) do
        begin
          var Lt := Lines[I].Trim;
          if Lt = '' then Continue;
          var Tope := Length(Lt);
          if Length(Objetivo) < Tope then Tope := Length(Objetivo);
          var KK := 0;
          while (KK < Tope) and (Lt[KK + 1] = Objetivo[KK + 1]) do
            Inc(KK);
          if KK > MejorLen then
          begin
            MejorLen := KK;
            Mejor := I;
          end;
        end;
        if (Mejor >= 0) and (MejorLen >= 12) then
          Pista := Format(#10'La linea REAL mas parecida es la %d - comparala caracter a caracter:'#10'  %d|%s',
            [Mejor + 1, Mejor + 1, Lines[Mejor]]);
      end;
      Exit(Format('RECHAZADO: el ancla no aparece en el fichero. No he escrito nada.'#10 +
        'Ancla buscada: |%s|%s'#10'Copia la linea literal de delphi_read (no la reconstruyas de memoria).',
        [AOld, Pista]));
    end;

    if (Hits.Count > 1) and (AAtLine <= 0) then
    begin
      var Nums := '';
      for I in Hits do
        Nums := Nums + IntToStr(I + 1) + ', ';
      Exit(Format('RECHAZADO: el ancla aparece %d veces (lineas %s), no es unica. No he escrito nada.'#10 +
        'Elige otra linea unica si existe; solo si NO existe (firma repetida interface/implementation) repite con atline: <numero>.',
        [Hits.Count, Nums.TrimRight([',', ' '])]));
    end;

    HitIdx := Hits[0];
    if AAtLine > 0 then
    begin
      HitIdx := -1;
      for I in Hits do
        if I + 1 = AAtLine then
          HitIdx := I;
      if HitIdx = -1 then
      begin
        var Nums := '';
        for I in Hits do
          Nums := Nums + IntToStr(I + 1) + ', ';
        Exit(Format('RECHAZADO: en la linea %d no esta ese ancla. Apariciones reales: %s. Relee con delphi_read.',
          [AAtLine, Nums.TrimRight([',', ' '])]));
      end;
    end;

    // EL RANGO. Con AToLine el ancla deja de ser una linea y pasa a ser la
    // PRIMERA de un tramo que acaba en AToLine, incluida. Las reglas de un
    // rango no tienen nada de Pascal, asi que viven en RangoHasta y de ahi
    // tira tambien el motor de texto plano: una sola puerta.
    var Reales := Length(Lines);
    if (Reales > 0) and (Lines[Reales - 1] = '') then
      Dec(Reales); // la linea fantasma que deja el salto final del fichero
    var Fin: Integer;
    var MalRango := RangoHasta(APath, HitIdx, AToLine, Reales, Fin);
    if MalRango <> '' then
      Exit(MalRango);
    var Cuantas := Fin - HitIdx + 1;
    // Lo que SALE, para el recuento de bytes altos de mas abajo. Con un rango
    // no es el ancla: son TODAS las lineas que se van. Contar solo el ancla
    // dispararia el aviso de "acentos fuera de cuadro" -que manda PARAR- en
    // cualquier rango que incluyese una linea con acentos.
    var Salido := AOld;
    if Cuantas > 1 then
      Salido := string.Join(#10, Copy(Lines, HitIdx, Cuantas));

    // The anchor may omit leading indentation: whatever prefix the real line
    // has beyond the anchor is preserved in front of the new text.
    Prefix := Copy(Lines[HitIdx], 1, Length(Lines[HitIdx]) - Length(AOld));
    Replacement := ANew.Replace(#13#10, #10).Replace(#13, #10);
    // ONE trailing line break is dropped. "new" replaces a LINE, so the break
    // that ends it is the file's business, not the caller's: a block read from
    // a file (the recommended way to send code without the console eating
    // backslashes) always carries one, and it was landing as a blank line in
    // the middle of the code (measured 2026-08-25). Two or more are kept:
    // asking for a blank line after the replacement is a legitimate thing.
    if Replacement.EndsWith(#10) and not Replacement.EndsWith(#10#10) then
      Replacement := Replacement.Substring(0, Replacement.Length - 1);
    // Empty replacement (old given + new='') blanks the line - a legitimate
    // edit. Never index Split()[0] on it: '' yields an empty array (measured
    // Access Violation in the field test). Line DELETION is delete:true.
    var NewFirst := '';
    if Replacement <> '' then
      NewFirst := Replacement.Split([#10])[0];
    var Quita := 0;      // cuantas lineas desaparecen del array
    var Desde := HitIdx; // desde donde se cierra el hueco
    if ADelete then
      Quita := Cuantas   // el tramo entero se va (sin rango, Cuantas = 1)
    else
    begin
      // An insert that repeats the line above or below is almost always the
      // anchor line sent twice by mistake: it compiles, it is invisible, and
      // it cost an agent eight calls to find and undo (field round 10).
      if not ADelete and (Replacement <> '') then
      begin
        var LastNew := Replacement;
        if Replacement.Contains(#10) then
        begin
          var Parts := Replacement.Split([#10]);
          LastNew := Parts[High(Parts)];
        end;
        if (HitIdx > 0) and (Lines[HitIdx - 1].Trim <> '') and
           (Lines[HitIdx - 1].Trim = NewFirst.Trim) then
          Warnings.Add(Format(SN_EDIT_DUP_ABOVE_FMT, [HitIdx, NewFirst.Trim]));
        // Con un rango, la linea de debajo esta DENTRO de lo que se va: no
        // es una duplicacion, es material a punto de desaparecer.
        if (Cuantas = 1) and (HitIdx < High(Lines)) and (Lines[HitIdx + 1].Trim <> '') and
           (Lines[HitIdx + 1].Trim = LastNew.Trim) then
          Warnings.Add(Format(SN_EDIT_DUP_BELOW_FMT, [HitIdx + 2, LastNew.Trim]));
      end;
      Lines[HitIdx] := Prefix + Replacement;
      Quita := Cuantas - 1; // la del ancla se queda, con el texto nuevo
      Desde := HitIdx + 1;
    end;
    if Quita > 0 then
    begin
      for I := Desde to High(Lines) - Quita do
        Lines[I] := Lines[I + Quita];
      SetLength(Lines, Length(Lines) - Quita);
    end;

    var Joined: string;
    var EolSep: string;
    if Eol = 'CRLF' then EolSep := #13#10 else EolSep := #10;
    Joined := string.Join(#10, Lines).Replace(#10, EolSep);

    try
      NewBytes := EncodeText(Joined, K);
    except
      on E: Exception do
      begin
        var Hex := 'XXXX';
        var MU := TRegEx.Match(E.Message, 'U\+([0-9A-F]+)');
        if MU.Success then Hex := MU.Groups[1].Value;
        Exit(Format('RECHAZADO: %s. El fichero esta en %s y el texto nuevo lleva caracteres que no caben. No he escrito nada.'#10 +
          'SALIDA LEGITIMA SIN CONVERTIR: literal nativo Pascal - #$%s concatenado (''antes '' + #$%s + '' despues'') ' +
          'o ChrW($%s) / WideChar($%s) - el fuente queda ASCII y conserva su encoding. Declaralo en el informe.',
          [E.Message, EncName(K), Hex, Hex, Hex, Hex]));
      end;
    end;

    var CopyNote := BackupFile(APath);
    AtomicWrite(APath, NewBytes);

    After := TFile.ReadAllBytes(APath);
    D := Measure(After);
    var AfterText := DecodeBytes(After, K);
    var AfterLines := SplitToLines(AfterText);

    var Ctx := '(no he sabido localizar la linea nueva)';
    // El sitio se SABE: la sustitucion empieza justo donde estaba el ancla.
    // Buscar la primera linea del texto nuevo DESDE ARRIBA sacaba otra
    // region entera cuando esa linea es de las que se repiten - un "begin",
    // un "var", un "end;" - y entonces el agente comprobaba su edicion
    // mirando un trozo de fichero que no era el suyo (medido el 2026-09-20:
    // edicion en la linea 19, eco de la 7).
    var Idx := HitIdx;
    if Idx > High(AfterLines) then
      Idx := High(AfterLines);
    // Salvavidas por si algun dia el sitio no cuadra: se busca DESDE ahi
    // hacia abajo, nunca desde el principio.
    if (NewFirst <> '') and (Idx >= 0) and (Idx <= High(AfterLines)) and
       not AfterLines[Idx].Contains(NewFirst) then
      for I := Idx to High(AfterLines) do
        if AfterLines[I].Contains(NewFirst) then
        begin
          Idx := I;
          Break;
        end;
    if Idx >= 0 then
    begin
      var IniC := Idx - 1;
      if IniC < 0 then IniC := 0;
      // La ventana cubre TODO lo escrito, no las dos primeras lineas: una
      // insercion de diez lineas se verificaba viendo tres.
      var FinC := Idx + 2;
      if Replacement <> '' then
        FinC := Idx + Length(Replacement.Split([#10])) + 1;
      if FinC > High(AfterLines) then FinC := High(AfterLines);
      var SbC := TStringBuilder.Create;
      try
        for I := IniC to FinC do
          SbC.Append('  ').Append(I + 1).Append('|').Append(AfterLines[I]).Append(#10);
        Ctx := SbC.ToString.TrimRight([#10]);
      finally
        SbC.Free;
      end;
    end;

    if D.Corruption > M.Corruption then
      Warnings.Add('*** HAN APARECIDO CARACTERES DE CORRUPCION. Restaura con restore:true y PARA. ***');
    if (M.High = 0) and (D.High > 0) then
      Warnings.Add(Format('(el fichero era ASCII puro y he escrito los caracteres ' +
        'nuevos en %s, el encoding que el IDE tiene configurado para ficheros ' +
        'sin BOM. Si este proyecto usa otro, dilo en tu informe.)', [EncName(K)]));
    var Salen := HighCount(Salido);
    var Entran := HighCount(Prefix + Replacement) - HighCount(Prefix);
    if (Salen >= 0) and (Entran >= 0) and (D.High <> M.High - Salen + Entran) then
      Warnings.Add(Format('*** ACENTOS FUERA DE CUADRO: esperaba %d bytes altos y hay %d. Restaura con restore:true y PARA. ***',
        [M.High - Salen + Entran, D.High]));
    var Ajenos: Boolean;
    if Eol = 'CRLF' then Ajenos := D.Loose > M.Loose else Ajenos := D.CRLF > M.CRLF;
    if Ajenos then
      Warnings.Add(Format('*** FINALES DE LINEA AJENOS: el fichero es %s y han entrado del otro estilo. Restaura con restore:true y PARA. ***', [Eol]));
    var FmNew := MojibakeLines(Replacement);
    if (Length(FmNew) > 0) and (Length(MojibakeLines(AOld)) = 0) then
      Warnings.Add('*** FIRMA DE MOJIBAKE EN TU TEXTO NUEVO. Si querias escribir un acento, pon el caracter LIMPIO; si copias adrede una corrupcion existente, declaralo. ***');
    if AIsDesigner then
    begin
      Warnings.Add('(fichero del designer en formato texto: editado, pero lo gobierna el IDE. MENCIONALO en tu informe.)');
      for var LintW in DesignerLint(APath, AfterLines) do
        Warnings.Add(LintW);
    end;

    if not AIsDesigner then
    begin
      var EA := CountEndDot(Text);
      var ED := CountEndDot(AfterText);
      if (EA = 1) and (ED <> 1) then
        Warnings.Add(Format('*** ESTRUCTURA ROTA: el fichero tenia UN ''end.'' y ahora tiene %d. Restaura con restore:true y PARA. ***', [ED]))
      else if EA = 1 then
      begin
        var Ult := High(AfterLines);
        while (Ult >= 0) and (AfterLines[Ult].Trim = '') do
          Dec(Ult);
        if (Ult >= 0) and not TRegEx.IsMatch(AfterLines[Ult], '^[ \t]*end\.[ \t]*$') then
          Warnings.Add('*** ESTRUCTURA ROTA: el ''end.'' ya no es la ultima linea - lo que quede detras desaparece de la compilacion. Restaura con restore:true y PARA. ***');
      end;
      var NewLines := Replacement.Split([#10]);
      for var J := 0 to High(NewLines) do
      begin
        if not TRegEx.IsMatch(NewLines[J], '^(procedure|function|constructor|destructor)\b', [roIgnoreCase]) then
          Continue;
        var Encima: string;
        if J = 0 then
        begin
          if Idx > 0 then Encima := AfterLines[Idx - 1].Trim else Encima := '';
        end
        else
          Encima := NewLines[J - 1].Trim;
        var EsStmt := Encima.Contains(':=') or TRegEx.IsMatch(Encima, '\);?$') or
          TRegEx.IsMatch(Encima, '^[A-Za-z_][\w.]*\.[A-Za-z_]\w*\s*;$') or
          TRegEx.IsMatch(Encima, '^(if|while|for|case|repeat|until|raise|exit|inc|dec|with|begin|try)\b', [roIgnoreCase]);
        if EsStmt then
        begin
          Warnings.Add(Format('*** POSIBLE INSERCION DENTRO DE UN METODO: la firma ''%s'' ha quedado con ''%s'' encima, que parece un statement. Comprueba el balance begin/end; si el metodo quedo partido, restaura con restore:true. ***',
            [Copy(NewLines[J], 1, 60), Copy(Encima, 1, 60)]));
          Break;
        end;
      end;
    end;

    var Accion := 'ESCRITO en ' + TPath.GetFileName(APath);
    if Cuantas > 1 then
    begin
      if ADelete then
        Accion := Format(SN_RANGE_DELETED_FMT,
          [Cuantas, HitIdx + 1, HitIdx + Cuantas, TPath.GetFileName(APath)])
      else
        Accion := Format(SN_RANGE_REPLACED_FMT,
          [Cuantas, HitIdx + 1, HitIdx + Cuantas, TPath.GetFileName(APath)]);
    end
    else if ADelete then
      Accion := Format('BORRADA la linea %d de %s (la linea ya no existe)',
        [HitIdx + 1, TPath.GetFileName(APath)])
    else if Replacement = '' then
      Accion := Format('BLANQUEADA la linea %d de %s (sigue existiendo, vacia; ' +
        'para eliminarla del todo usa delete:true)',
        [HitIdx + 1, TPath.GetFileName(APath)]);
    Result := Format('%s'#10'  encoding=%s  finales=%s  copia=%s'#10 +
      '  antes:   %s'#10'  despues: %s'#10'  lineas resultantes leidas del disco:'#10'%s',
      [Accion, EncName(K), Eol, CopyNote, Summary(M), Summary(D), Ctx]);
    if Warnings.Count > 0 then
      Result := Result + #10 + Warnings.Text.TrimRight;
  finally
    Hits.Free;
    Warnings.Free;
  end;
end;

procedure InitHighMap;
var
  B: Byte;
  S: string;
begin
  GHighMap := TDictionary<Char, Byte>.Create;
  for B := $80 to $9F do
  begin
    S := GCp1252.GetString(TBytes.Create(B));
    if (Length(S) = 1) and (S[1] <> #$FFFD) and (Ord(S[1]) <> B) then
      GHighMap.AddOrSetValue(S[1], B);
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GCp1252 := TEncoding.GetEncoding(1252);
  InitHighMap;

finalization
  GHighMap.Free;
  GCp1252.Free;
  GLock.Free;

end.
