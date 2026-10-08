unit Lsp.Mascara;

{ LA MASCARA DE UNIDADES: las letras de este servidor viajan al cliente como
  unidades virtuales (srvd:, srvc:, ...) y vuelven como letras. De ida, a la
  entrada de cada llamada, ExpandVirtualDrives (la llama la puerta de entrada
  de Lsp.Guard) y ExpandDriveValue (un valor suelto: la ruta de descarga
  /files); de vuelta, MaskDriveText, EL filtro de salida, y las tres formas
  de enmascarar una respuesta que lleva CONTENIDO del disco
  (EnmascaraSalvoContenido, EnmascaraJsonSalvo, EnmascaraSalvoCodigo), con lo
  que cada llamada deja anotado (lo ya enmascarado y las citas de
  CitaDeLinea). La forma 'srvX:' tiene UN escritor (VirtualUnitOf) y UNA
  prueba (EmpiezaPorUnidadVirtual); las letras que se sirven, por workspace,
  las dice ServedDriveLetters.

  Sale de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movida sin cambiar una linea: la ultima de las cuatro mudanzas que la
  sacan de Guard. Va encima del mapa de los lugares (Lsp.Lugares: los sitios
  declarados, sus letras de red y su forma declarada) y debajo de la jaula,
  que la llama a la entrada y en sus anomalias de ruta (PathAnomaly niega
  por su nombre una unidad virtual que no se sirve). Su candado (GDrvLock)
  nace en su initialization, como nacia en la de Guard; lo anotado en cada
  llamada es del hilo (threadvar). }

interface

uses
  System.JSON; // TJSONObject: los argumentos de una llamada

{ Virtual drive units. The drive letters of this SERVER travel to the client
  as srvd:, srvc:, ... so a model never mistakes server paths for its own
  local disks (measured confusion in the field test). Round trip:
  - inbound: the entry gate expands srvX: in tool arguments (whole-value
    prefix match only, and never inside content-carrying parameters);
  - outbound: MaskDriveText rewrites every served drive prefix in a tool's
    textual result - one generic rule, so compiler/git/LSP output and even
    8.3 short forms (D:\PROYEC~1) are covered - EXCEPT the ECHO of the tools
    whose text is content (TOOLS_ECO: delphi_read, the hits of
    delphi_search, vault_read / vault_search, the read-back of delphi_edit /
    delphi_textedit, the help pages of delphi_docs), which must reach the
    client verbatim (an edit anchor built from masked text would not match
    the disk). What those tools compose themselves still goes through
    MaskDriveText('', ...). delphi_fetch is NOT exempt: its payload is
    base64, which the mask cannot corrupt.
  With a tool name it is THE outbound filter (Lsp.Host's ResultFilter, once
  per answer): it spends what the call left noted (TSalidaHecha, the disk
  citations of CitaDeLinea). A tool masking a piece of its own uses ''; four
  tools masked their whole answer again with their own name, and the real
  line of a delphi_changeset refusal left masked (4-oct-2026). }
function MaskDriveText(const AToolName, AText: string): string;
{ Para la tool cuya respuesta mezcla lineas SUYAS con lineas de CONTENIDO del
  disco (delphi_git diff / show / log: las de un fichero o de un mensaje de
  commit empiezan por +, - o espacio): enmascara las demas, una a una, y
  deja el contenido como esta. El filtro de salida de ESTA llamada deja pasar
  ese texto, y solo ese, tal cual (lo recuerda el hilo; OlvidaSalidaHecha lo
  borra al empezar cada llamada). El barrido entero reescribia las lineas de
  un diff como si fueran rutas del servidor: un '\\equipo' de un literal
  salia '\\srvhost' y un 'Z:\x', 'srv0:\x' (medido el 1-oct-2026). }
function EnmascaraSalvoContenido(const ATexto, AEmpiezaPor: string): string;
procedure OlvidaSalidaHecha;
{ LA cita de una linea de un fichero, 'N|texto' (N 1-based, el texto tal
  cual; la sangria de delante la pone quien la escribe): lo que un agente
  copia para construir un ancla. La componen delphi_read, vault_read y las
  pistas y los ecos de delphi_edit y delphi_changeset, y nadie mas a mano:
  habia siete escritores con cuatro formas ('N|', '  N|', 'N| ' con el texto
  recortado). Y el filtro de salida deja tal cual, en la respuesta de
  CUALQUIER tool, las lineas que esta funcion compuso en ESTA llamada, y solo
  esas: adivinaba por la forma ('^\s*\d+\|'), y en las negativas de las tools
  de eco pasaba sin mascara toda linea que lo pareciera, la escribiera quien
  la escribiera; las de las demas tools se enmascaraban, y una pista de
  delphi_changeset no servia de ancla (revision del 4-oct-2026). }
function CitaDeLinea(N: Integer; const ATexto: string): string;
{ Para la tool que devuelve JSON con CONTENIDO de un fichero en algunos
  campos (references y rename_symbol: "text" y "anchor", la linea tal cual;
  symbols: las declaraciones; signature y completion: la documentacion; NO
  delphi_designer: su get devuelve las lineas del .dfm como texto, por el
  filtro general):
  enmascara todas las demas cadenas y deja esos campos, con todo lo que cuelga
  de ellos, como estan; el filtro de salida de ESTA llamada deja pasar el
  resultado. Lo que no se nombra se enmascara: un campo nuevo no se escapa.
  Si AJson no es JSON, sale entero enmascarado. ADetras: lo que la tool pega
  detras del JSON (una nota), enmascarado entero. }
function EnmascaraJsonSalvo(const AJson: string; const AClaves: array of string;
  const ADetras: string = ''): string;
{ Para un texto markdown con bloques de codigo (delphi_hover: la declaracion
  que da el motor, entre ```): enmascara lo de fuera de los bloques y deja el
  codigo como esta; el filtro de salida de ESTA llamada deja pasar el
  resultado. Una constante con una ruta salia con la letra virtual. }
function EnmascaraSalvoCodigo(const ATexto: string): string;

{ Inbound expansion of ONE value ('srvd:\x' -> 'D:\x'; anything else
  untouched, an unserved unit stays literal). Exposed for the /files download
  route, which receives its path as a query parameter, not as a tools/call
  argument - the same door, entered from HTTP. }
function ExpandDriveValue(const AValue: string): string;

{ The letter of a value shaped like a virtual unit ('srvd:', 'srvd:\x'),
  #0 otherwise. After ExpandDriveValue a non-#0 answer means an UNSERVED
  unit: refuse it by name, never let it near GetFullPath. }
function VirtualUnitLetter(const AValue: string): Char;

{ True si AValue EMPIEZA con la forma de una unidad virtual ('srvd:', o el
  centinela 'srv0:'), sea lo que sea lo que venga detras. La unica prueba de
  esa forma: VirtualUnitLetter la usa (y exige ademas la barra o el final) y
  la puerta rechaza con ella 'srvd:x', una unidad sin su barra. Hasta la
  1.16.0 la puerta la probaba a mano (lo encontro test_paisaje en su primera
  pasada). }
function EmpiezaPorUnidadVirtual(const AValue: string): Boolean;

{ Las letras que este servidor sirve, en mayusculas ('DC'), por workspace:
  las de sus raices, la zona de biblioteca, sus referencias y el vault. La
  jaula niega por su nombre una unidad virtual que no esta entre ellas
  (PathAnomaly, Lsp.Guard). }
function ServedDriveLetters: string;
{ EL nombrador de la unidad virtual de una letra ('srvd'; 'srv0' si no se
  sirve), sin los dos puntos: lo usan el enmascarador y la lista de unidades
  validas de PathAnomaly (Lsp.Guard). }
function VirtualUnitOf(ALetter: Char; const AServed: string): string;
{ La expansion de ida de una llamada, en su sitio: cada argumento de texto
  que no lleva contenido (PARAMS_CON_CONTENIDO) pasa por ExpandDriveValue. La
  llama la puerta de entrada (ReglasDeLaLlamadaDenegadas, Lsp.Guard). }
procedure ExpandVirtualDrives(const AArguments: TJSONObject);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.SyncObjs,
  Lsp.Texts,
  Lsp.Json,
  Lsp.Settings,
  Lsp.Lugares;

threadvar
  TSalidaHecha: string; // lo que la tool de ESTA llamada ya enmascaro (EnmascaraSalvoContenido)
  TCitasHechas: string; // las citas (CitaDeLinea) de ESTA llamada, cada una seguida de #0

{ Los parametros que llevan CONTENIDO, no rutas: su texto es de un fichero o
  de un mensaje y no pertenece al espacio de nombres de rutas. Lo lee solo la
  expansion de ida (ExpandVirtualDrives): la pasada de la jaula ya no elige
  por una lista de nombres sino por las marcas [RutaDelServidor] de cada tool
  (RutasNuestras, Lsp.Guard). }
const
  PARAMS_CON_CONTENIDO: array [0 .. 6] of string = (
    'new', 'old', 'content', 'data', 'message', 'code', 'args');
  { El host con el que sale enmascarado el de una ruta de red (\\srvhost\...):
    lo escribe MaskDriveText y lo lee de vuelta ExpandDriveValue. UNA
    constante para los dos lados (estaba escrito a mano en los dos). }
  HOST_VIRTUAL = 'srvhost';

// ---------------------------------------------------------------------------
// Virtual drive units (srvd:, srvc:, ...)
// ---------------------------------------------------------------------------

var
  GDrvLock: TCriticalSection;
  // uppercase letters of every served drive, e.g. 'DC': [0] el modo local,
  // [i] el workspace i
  GDrvLetters: TArray<string>;
  GDrvLoaded: TArray<Boolean>;

{ The drives that can legitimately appear in tool output: those hosting the
  workspace roots, the library zone (RAD Studio + components) and the
  knowledge vault. Cached, POR WORKSPACE: se calculaban una vez por proceso,
  con el workspace de la PRIMERA llamada, y a otro con su raiz en otra unidad
  le salia esa raiz como srv0:\ y su srvn:\ como "not a drive of this
  server" hasta reiniciar (apuntado en la 1.8.2; medido el 1-oct-2026 con
  dos workspaces en dos unidades: dependia de quien llamase primero). }
function ServedDriveLetters: string;
var
  Letras: string;

  procedure AddDriveOf(const APath: string);
  begin
    if (Length(APath) >= 2) and (APath[2] = ':') and
       CharInSet(APath[1], ['A'..'Z', 'a'..'z']) and
       (Pos(UpCase(APath[1]), Letras) = 0) then
      Letras := Letras + UpCase(APath[1]);
  end;

var
  R: string;
  Ix: Integer;
begin
  Ix := 0;
  if HasActiveWS then
    Ix := TWorkspaceIx1; // las letras de ESTE workspace
  GDrvLock.Enter;
  try
    if (Ix <= High(GDrvLoaded)) and GDrvLoaded[Ix] then
      Exit(GDrvLetters[Ix]);
  finally
    GDrvLock.Leave;
  end;
  Letras := '';
  for R in WorkspaceRoots do
    AddDriveOf(R);
  for R in LibraryRoots do
    AddDriveOf(R);
  for R in WorkspaceReadOnlyRoots do
    AddDriveOf(R);
  // The vault is a served root of its OWN: it sits deliberately outside the
  // code jail and outside the library zone, so neither list carries it. A
  // vault on another letter used to leak that letter unmasked, and its
  // srvX: form did not resolve on the way in - it goes through the same
  // door as everybody else.
  AddDriveOf(VaultPath);
  GDrvLock.Enter;
  try
    if Ix > High(GDrvLoaded) then
    begin
      SetLength(GDrvLoaded, Ix + 1);
      SetLength(GDrvLetters, Ix + 1);
    end;
    GDrvLetters[Ix] := Letras;
    GDrvLoaded[Ix] := True;
  finally
    GDrvLock.Leave;
  end;
  Result := Letras;
end;

{ EL NOMBRADOR de la unidad virtual, y la inversa exacta de la funcion que
  viene justo debajo: esa LEE la forma, esta la ESCRIBE. Nadie la compone a
  mano en ningun sitio.

  Estaba escrita a mano en CUATRO: las tres formas de MaskDriveText (la ruta
  normal, el %3A de las URIs del motor, y la unidad a secas) y la lista de
  unidades validas de PathAnomaly. Las cuatro decian
  'srv' + Char(Ord(...) + 32), pero no igual: tres hacian UpCase antes y la
  cuarta no, apoyandose en que ServedDriveLetters promete mayusculas
  cuatrocientas lineas mas arriba. Ninguna estaba mal; era la forma de que
  una se desviase. Lo pregunto David el 2026-09-21 -"lo de enmascarar y
  desenmascarar las unidades esta centralizado, no?"- el dia despues de
  encontrar exactamente esta misma forma en los nombres de la papelera:
  alli el lector estaba unificado y habia TRES escritores.

  Una letra que este servidor no sirve sale como 'srv0': dice que hay una
  ruta y no dice donde. Era 'srvx', que es EXACTAMENTE lo que produce una
  unidad X: servida de verdad (una red mapeada como X: es lo normal): el
  nombrador dejaba de ser inyectivo y su inversa expandia el centinela a
  X:\ (auditoria 2026-09-21). El '0' no es letra: no puede chocar con
  nada servido, y VirtualUnitLetter lo reconoce para que PathAnomaly lo
  rechace POR NOMBRE con la lista de unidades validas, como a cualquier
  otra unidad no servida. }
function VirtualUnitOf(ALetter: Char; const AServed: string): string;
begin
  if (ALetter <> #0) and (Pos(UpCase(ALetter), AServed) > 0) then
    Result := 'srv' + Char(Ord(UpCase(ALetter)) + 32)
  else
    Result := 'srv0';
end;

function EmpiezaPorUnidadVirtual(const AValue: string): Boolean;
begin
  Result := (Length(AValue) >= 5) and StartsText('srv', AValue) and
    CharInSet(AValue[4], ['A'..'Z', 'a'..'z', '0']) and (AValue[5] = ':');
end;

{ The ONE place that recognizes the virtual-unit shape: 'srvd:', 'srvd:\x',
  'srvd:/x' - y el centinela 'srv0:', para que su rechazo sea el de una
  unidad no servida. Returns the upper-case letter, or #0 when the value is not a
  virtual unit at all. Both the inbound expansion and the rejection of an
  unserved unit ask this - the shape is never re-tested by hand. }
function VirtualUnitLetter(const AValue: string): Char;
begin
  Result := #0;
  if EmpiezaPorUnidadVirtual(AValue) then
    if (Length(AValue) = 5) or CharInSet(AValue[6], ['\', '/']) then
      Result := UpCase(AValue[4]);
end;

{ 'srvd:\x' / 'srvd:/x' / bare 'srvd:' -> 'D:\x' ... Whole-value prefix match
  only; anything else comes back untouched (real paths keep working).
  Only a SERVED letter expands. Mapping an unserved 'srvz:' to the real 'Z:\'
  put a drive of the host into the rejection echo, and the outbound mask
  covers served letters only, so it travelled back raw: probing srva: .. srvz:
  enumerated the machine's drives (field round 10). An unserved unit now stays
  literal and PathAnomaly refuses it by name, without ever reaching disk. }
function ExpandDriveValue(const AValue: string): string;
var
  Letter: Char;
  Host, V: string;
begin
  Result := AValue;
  Letter := VirtualUnitLetter(AValue);
  if (Letter <> #0) and (Pos(Letter, ServedDriveLetters) > 0) then
    Exit(Letter + Copy(AValue, 5, MaxInt));
  // el HOST de un UNC sale enmascarado como srvhost (MaskDriveText) y nadie
  // lo leia de vuelta: el agente no podia repetir lo que el servidor le
  // ensenaba (GUARD-002). Vuelve solo si el operador declaro UN unico host
  // UNC entre sus lugares (novena revision, M5b)
  V := AValue.Replace('/', '\');
  if StartsText('\\' + HOST_VIRTUAL + '\', V) then
  begin
    Host := HostUncDeclarado;
    if Host <> '' then
      Result := '\\' + Host + Copy(V, Length('\\' + HOST_VIRTUAL) + 1, MaxInt);
  end;
end;

{ Rewrites the string arguments of a tools/call in place. Content-carrying
  parameters are never touched: their text belongs to files/messages, not to
  the path namespace. }
procedure ExpandVirtualDrives(const AArguments: TJSONObject);
begin
  ReescribeCadenas(AArguments,
    function(const ANombre, AValor: string): string
    begin
      Result := AValor;
      if not MatchText(ANombre, PARAMS_CON_CONTENIDO) then
        Result := ExpandDriveValue(AValor);
    end);
end;

type
  // de una linea de una respuesta: es contenido (va tal cual) o no
  TEsContenido = reference to function(const ALinea: string): Boolean;

// ATexto linea a linea: lo que no es contenido, enmascarado. El nucleo de
// EnmascaraSalvoContenido (git), EnmascaraSalvoCodigo (hover) y las citas
function EnmascaraLineas(const ATexto: string; const AEsContenido: TEsContenido): string;
var
  Lineas: TArray<string>;
begin
  Lineas := ATexto.Split([#10]);
  for var K := 0 to High(Lineas) do
    if not AEsContenido(Lineas[K]) then
      Lineas[K] := MaskDriveText('', Lineas[K]);
  Result := string.Join(#10, Lineas);
end;

// la linea es una cita que CitaDeLinea compuso en esta llamada (con su
// sangria delante y, si va en un texto CRLF, su CR detras)
function EsCitaHecha(const ALinea: string): Boolean;
var
  L: string;
begin
  Result := False;
  if TCitasHechas = '' then
    Exit;
  L := ALinea.TrimLeft;
  if L.EndsWith(#13) then
    L := L.Substring(0, L.Length - 1);
  Result := (L <> '') and (Pos(#0 + L + #0, #0 + TCitasHechas) > 0);
end;

function CitaDeLinea(N: Integer; const ATexto: string): string;
begin
  Result := IntToStr(N) + '|' + ATexto;
  TCitasHechas := TCitasHechas + Result + #0;
end;

function MaskDriveText(const AToolName, AText: string): string;
const
  // las tools cuyo ECO es contenido del disco (la nota de abajo dice por que)
  TOOLS_ECO: array [0 .. 6] of string = ('delphi_read', 'vault_read', 'vault_search',
    'delphi_search', 'delphi_edit', 'delphi_textedit', 'delphi_docs');
var
  Sb: TStringBuilder;
  Letters: string;
  I, L: Integer;
  C, PrevC: Char;
  EnJson: Boolean;
begin
  // delphi_read was the FIRST exemption: its payload is the file's TEXT, which
  // may legitimately contain "D:\..." that an edit anchor must match
  // byte-for-byte. delphi_fetch is NOT exempt (fixed after field round 4):
  // its payload is base64, whose alphabet has neither ':' nor '%', so
  // masking can never corrupt it - while its "path" field must be
  // virtualized like every other path the client sees.
  // The vault tools are exempt on the same grounds: their payload is the
  // TEXT of a note, and an agent copies fragments of it verbatim to build the
  // "anchor" / "old_text" of a later vault_append / vault_patch. Masking it
  // would silently break every anchored write (the fragment would no longer
  // match the file on disk). Vault paths are relative and carry no drive
  // letter, and the vault is knowledge the operator chose to expose.
  // ...and an exception that ESCAPED a tool is not content either. The
  // dispatcher wraps ANY exception as "Error executing tool: <E.Message>", and
  // a Delphi I/O exception embeds the REAL absolute path (EFOpenError: 'Cannot
  // open file "D:\..."'), reachable on a locked or ACL-denied file - the read
  // paths have no try/except of their own. Case-SENSITIVE and the exact
  // wrapper token on purpose: a delphi_read result starts with the FILE NAME
  // and a note may start with "Error", so a loose case-insensitive 'error'
  // test would silently mask real content and break every anchored write built
  // on it.
  // delphi_search joined them 2026-09-20, and it was the loudest of all:
  // its "text" field is a VERBATIM line of the file, published precisely so
  // an agent can copy it as an edit anchor - and the blanket mask rewrote
  // the drive letter INSIDE it. README.md:358 reads "Roots=D:\Projects\..."
  // and the search answered "Roots=srvd:\Projects\...": an anchor copied
  // from a hit could never match the disk, and a documentation file was
  // quoted wrong. It masks its own "path" fields instead (see there).
  // delphi_edit y delphi_textedit, por lo mismo y con una vuelta de tuerca:
  // su eco de verificacion son las lineas RELEIDAS DEL DISCO, que es la
  // prueba con la que el agente comprueba que escribio lo que queria. Si esa
  // prueba va enmascarada, no prueba nada. Encontrado escribiendo este mismo
  // CHANGELOG el 2026-09-20: se escribio "D:\Projects\Galatea", el disco lo
  // tenia bien, y el eco devolvia "srvd:\Projects\Galatea". Sus negativas
  // empiezan por su etiqueta con resultado y siguen enmascarandose por el test de
  // abajo.
  // delphi_docs (1.10.0): su texto es la AYUDA instalada, y sus ejemplos citan
  // rutas que no son de este servidor. Medido el 2-oct-2026 en la pagina de
  // TPath.Combine: 'E:\somewhere\' salia 'srv0:\somewhere\' y la ruta que
  // empieza por una barra, '\srvhost\file.txt': la documentacion de lo que
  // hace Combine con cada ruta quedaba en un sinsentido. Lo que compone ella
  // misma no lleva rutas: el id es <ayuda>:<pagina> y la nota da el nombre del
  // fichero de ayuda, sin carpeta.
  //
  // LA OBLIGACION QUE VIENE CON ESTAR EN ESTA LISTA, y es facil de olvidar:
  // la exencion es por TOOL, pero solo el ECO merece exencion. Todo lo que
  // una de estas tools COMPONGA ella misma -una ruta en un mensaje, un campo
  // "path" de un JSON- tiene que pasar a mano por MaskDriveText('', ruta),
  // que es esta misma funcion con el nombre de tool vacio. delphi_search lo
  // hace asi con sus campos "path" (ver Mcp.Tools.Workspace). delphi_textedit
  // NO lo hacia con la ruta de su "CREADO %s" y sacaba la letra real del
  // servidor; aqui ponia escrito que "sus ecos de exito no llevan rutas
  // absolutas", que era FALSO y es justo lo que hizo que nadie mirara. Lo
  // caza ya la bateria test_round40, en las dos direcciones: que no salga la
  // letra real, y que el contenido del disco NO venga enmascarado.
  // Lo que la propia tool ya enmascaro linea a linea (EnmascaraSalvoContenido):
  // ESE texto, y solo ese, pasa como esta. Se gasta al mirarlo.
  if (AToolName <> '') and (TSalidaHecha <> '') then
  begin
    var Hecha := TSalidaHecha;
    TSalidaHecha := '';
    if AText = Hecha then
    begin
      TCitasHechas := '';
      Exit(AText);
    end;
  end;
  if MatchText(AToolName, TOOLS_ECO) and
     // la RESPUESTA no es una negativa: se mira como EMPIEZA (MsgOutcome +
     // la regla de la marca), nunca una etiqueta de DENTRO: un delphi_read de
     // Lsp.Texts trae [X DENIED] en sus lineas, se tomaba por negativa y se
     // enmascaraba el CONTENIDO ('%s:' salia '%srv0:', medido 27-sep)
     (MsgOutcome(AText) = '') then
    Exit(AText);
  // ...y en lo demas (la NEGATIVA de una de esas tools, la respuesta de
  // cualquier otra), las lineas que CITAN el disco y que la tool compuso en
  // ESTA llamada (CitaDeLinea) son contenido y se dejan tal cual; el resto
  // (rutas del guard, mensajes) se enmascara linea a linea. Una pista
  // enmascarada no servia de ancla (novena revision, M5a). Solo las
  // compuestas: se adivinaba por la forma ('^\s*\d+\|') y pasaba cualquier
  // linea que lo pareciera (revision del 4-oct-2026)
  if (AToolName <> '') and (TCitasHechas <> '') then
  begin
    Result := EnmascaraLineas(AText, EsCitaHecha);
    TCitasHechas := '';
    Exit;
  end;
  Letters := ServedDriveLetters;
  if (Letters = '') or (AText = '') then
    Exit(AText);
  // ANTES del barrido: la ruta real de un sitio declarado en una letra de
  // red vuelve a su forma declarada, y el barrido le pone su unidad virtual.
  // git escribe //host/recurso/..., que este barrido no reconoce por su
  // forma (se llevaria los comentarios de un diff): salia el nombre de la
  // maquina, y worktree list daba rutas que el agente no podia devolver
  // (medido el 30-sep-2026). Lo traducido vuelve a entrar, ya sin nada que
  // traducir, para el barrido de siempre.
  var RedDecl, RedReal: TArray<string>;
  SitiosEnLetraDeRed(RedDecl, RedReal);
  if Length(RedDecl) > 0 then
  begin
    var Traducido := FormaDeclaradaEnTexto(AText, RedDecl, RedReal);
    if Traducido <> AText then
      Exit(MaskDriveText('', Traducido));
  end;
  Sb := TStringBuilder.Create(Length(AText) + 64);
  try
    I := 1;
    L := Length(AText);
    // un JSON escribe cada barra doble: alli \\x es UNA barra (una ruta que
    // cuelga de la raiz de la unidad) y la ruta de red es la de cuatro. La
    // forma de dos barras, la del texto plano, convertia \Shared\Lib de un
    // .dproj en \srvhost\Lib (delphi_config view, medido el 2-oct-2026), y
    // los ejemplos de la ayuda igual. Lo que llega aqui como JSON es el
    // resultado entero de una tool: los demas llamadores pasan una ruta o una
    // linea de texto, y para ellos nada cambia. Un JSON de una tool es un
    // objeto; una lista empezaria por [{, [" o []. Un [ a secas NO: es la
    // etiqueta de una negativa ([GUARD-002 DENIED] ...), que es texto plano
    // y lleva su ruta de red con dos barras (lo cazo test_round22, M2)
    while (I <= L) and CharInSet(AText[I], [' ', #9, #10, #13]) do
      Inc(I);
    EnJson := (I <= L) and ((AText[I] = '{') or ((AText[I] = '[') and
      (I + 1 <= L) and CharInSet(AText[I + 1], ['{', '"', ']'])));
    I := 1;
    while I <= L do
    begin
      C := AText[I];
      // Any drive letter, not only the served ones. The mask was a C/D
      // allowlist, so E:\secret\x.inc or z:\... walked out untouched
      // (found 2026-08-25 by an auditor). Nothing real leaks on THIS machine
      // today - only C: and D: exist and both are mapped - but a root on
      // another drive, or a file referenced from one, would have. An
      // unmapped letter travels as srv0: : the reader learns there is a path
      // and learns nothing about where.
      if CharInSet(UpCase(C), ['A' .. 'Z']) then
      begin
        // ...but by the time this runs the text is already JSON, where a line
        // break is the two characters \ and n. That made the LETTER 'n' the
        // previous char for every path that starts a line, and the guard below
        // let it through unmasked: the real C:\Program Files... leaked in
        // multi-line fields (build outputTail) while the same path masked fine
        // inside single-line ones (errors[]). Measured, field round 8.
        PrevC := CaracterPrevio(AText, I);
        // A drive prefix only starts where the previous char is not a
        // letter/digit (keeps git's "HEAD:" and words intact).
        if not CharInSet(PrevC, ['A'..'Z', 'a'..'z', '0'..'9']) then
        begin
          // form A - plain path: <letter>:<separator> (D:\ or D:/)
          if (I + 2 <= L) and (AText[I + 1] = ':') and
             CharInSet(AText[I + 2], ['\', '/']) then
          begin
            Sb.Append(VirtualUnitOf(C, Letters)).Append(':');
            Inc(I, 2);
            Continue;
          end;
          // form B - percent-encoded colon in a file URI: <letter>%3A/ ...
          // (DelphiLSP answers with file:///D%3A/... - measured, R3-1).
          if (I + 4 <= L) and (AText[I + 1] = '%') and (AText[I + 2] = '3') and
             ((AText[I + 3] = 'A') or (AText[I + 3] = 'a')) and (AText[I + 4] = '/') then
          begin
            // Aqui los dos puntos van codificados (%3A), asi que el nombrador
            // pone la unidad y el separador se copia tal cual viene.
            Sb.Append(VirtualUnitOf(C, Letters));
            Sb.Append(AText[I + 1]).Append(AText[I + 2]).Append(AText[I + 3]);
            Inc(I, 4);
            Continue;
          end;
          // forma B2 - la unidad SIN separador detras: "D:" a secas, o una
          // ruta relativa a la unidad como "D:foo\bar". La forma A pide
          // <letra>:<separador>, asi que estas salian con la LETRA REAL en
          // cada negativa que echoa el parametro del que llama:
          //   delphi_list root="D:"       -> RECHAZADO: "D:" esta FUERA...
          //   delphi_git  repo="C:"       -> idem, en todas las tools
          // Y eso no es solo incumplir el contrato: como C:\Windows si sale
          // como srvc:, el lector deduce el mapeo entero. Medido 2026-09-20
          // por un agente auditor; es la misma forma del roots:["D:"] de esa
          // misma manana.
          //
          // Donde NO se toca, para no estropear texto que no es una ruta:
          // si tras los dos puntos viene un ESPACIO ("opcion C: haz esto") o
          // un DIGITO (una clave JSON de una letra, "a":1), se deja como
          // esta. Una ruta nunca empieza por espacio, y "D:1" no es un caso
          // que se de aqui.
          if (I + 1 <= L) and (AText[I + 1] = ':') and
             ((I + 2 > L) or
              not CharInSet(AText[I + 2],
                            [' ', #9, #10, #13, '0' .. '9'])) then
          begin
            Sb.Append(VirtualUnitOf(C, Letters)).Append(':');
            Inc(I, 2);
            Continue;
          end;
        end;
      end;
      // form C - a UNC path, whose HOST names the machine and what it can
      // see. Two shapes, and both have to be told apart from an ordinary
      // separator: by the time this runs the text is usually JSON, where a
      // single \ is written \\ - so "C:\\Users" is NOT a UNC, and a first
      // attempt at this rule happily turned it into "srvc:\srvhost" and ate
      // the rest of the path (caught by the battery, same day).
      //   raw text: \\host\share   - two, after a delimiter, then a letter
      //   inside JSON: \\\\host   - four, then a letter
      // The JSON form fires ONLY after a delimiter, like the raw form: the
      // Linux64 linker echoes its command line with backslashes ALREADY
      // doubled, which the JSON encoding doubles again - so mid-path every
      // re-doubled separator looked like a UNC opener and the whole tail
      // collapsed into srvhost after srvhost (sweep10's report, reproduced
      // 2026-08-26: 227 masks in one outputTail). A genuine UNC never starts
      // glued to a letter; a re-doubled path separator always does.
      // (el delimitador de antes, por CaracterPrevio: un UNC que ABRE LINEA
      // dentro de un JSON va detras de los caracteres \ y n, y salia con el
      // nombre de la maquina; apuntado en la 1.8.2, medido en la 1.9.0)
      // UNA regla para las dos formas, por la tira de barras (revision de la
      // 1.10.0: medido con LspTests.Rutas, el nombre de la maquina salia
      // detras de un ';' -una lista de rutas-, pegado a una opcion del
      // compilador -dcc64 -U\\nas\lib-, en el eco del enlazador doblado otra
      // vez dentro de un JSON -ocho barras-, en \\?\UNC\host y con un host
      // que empieza por _). En texto plano un UNC son 2 barras (o 4, el eco
      // doblado del enlazador); en JSON, 4 (u 8). Detras puede ir el prefijo
      // largo de Windows, ?\UNC\, con su separador.
      if (C = '\') and DelimitadorDeRed(AText, I) then
      begin
        var N := 0;
        while (I + N <= L) and (AText[I + N] = '\') do
          Inc(N);
        if (EnJson and ((N = 4) or (N = 8))) or (not EnJson and ((N = 2) or (N = 4))) then
        begin
          var J := I + N;
          var Sep := StringOfChar('\', N div 2);
          var Largo := '';
          if SameText(Copy(AText, J, 4 + 2 * Length(Sep)), '?' + Sep + 'UNC' + Sep) then
          begin
            Largo := Copy(AText, J, 4 + 2 * Length(Sep));
            Inc(J, Length(Largo));
          end;
          if (J <= L) and (CharInSet(AText[J], ['A'..'Z', 'a'..'z', '0'..'9', '_', '[']) or
             (Ord(AText[J]) >= $80)) then
          begin
            Sb.Append(StringOfChar('\', N)).Append(Largo).Append(HOST_VIRTUAL);
            I := J;
            while (I <= L) and not CharInSet(AText[I], ['\', '/', '"', ' ', #9]) do
              Inc(I);
            Continue;
          end;
        end;
      end;
      Sb.Append(C);
      Inc(I);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;


function EnmascaraSalvoContenido(const ATexto, AEmpiezaPor: string): string;
var
  Empieza: string;
begin
  Empieza := AEmpiezaPor;
  Result := EnmascaraLineas(ATexto,
    function(const L: string): Boolean
    begin
      // (la linea vacia y la que no empieza como el contenido son de la tool)
      Result := (L <> '') and (Pos(L[1], Empieza) > 0);
    end);
  TSalidaHecha := Result;
end;

function EnmascaraSalvoCodigo(const ATexto: string): string;
var
  EnBloque: Boolean;
begin
  EnBloque := False;
  Result := EnmascaraLineas(ATexto,
    function(const L: string): Boolean
    begin
      if L.TrimLeft.StartsWith('```') then
      begin
        EnBloque := not EnBloque;
        Exit(False); // la valla es de la tool
      end;
      Result := EnBloque;
    end);
  TSalidaHecha := Result;
end;

function EnmascaraJsonSalvo(const AJson: string; const AClaves: array of string;
  const ADetras: string): string;
var
  Claves: TArray<string>;

  // una copia de AValor con sus cadenas enmascaradas, salvo lo que cuelga de
  // un campo de Claves (que se copia tal cual). Las CLAVES tambien: antes de
  // esto el texto entero pasaba por la mascara y las cubria, y un objeto con
  // rutas por clave (los changes de un WorkspaceEdit) saldria con la letra
  // real (revision de la 1.13.0)
  function Transforma(AValor: TJSONValue): TJSONValue;
  begin
    if AValor is TJSONObject then
    begin
      var O := TJSONObject.Create;
      for var P in TJSONObject(AValor) do
        if MatchText(P.JsonString.Value, Claves) then
          O.AddPair(P.JsonString.Value, TJSONValue(P.JsonValue.Clone))
        else
          O.AddPair(MaskDriveText('', P.JsonString.Value), Transforma(P.JsonValue));
      Result := O;
    end
    else if AValor is TJSONArray then
    begin
      var A := TJSONArray.Create;
      for var E in TJSONArray(AValor) do
        A.AddElement(Transforma(E));
      Result := A;
    end
    // (un TJSONNumber ES un TJSONString en el RTL)
    else if (AValor is TJSONString) and not (AValor is TJSONNumber) then
      Result := TJSONString.Create(MaskDriveText('', TJSONString(AValor).Value))
    else
      Result := TJSONValue(AValor.Clone);
  end;

var
  V, T: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(AJson);
  if V = nil then
    Exit(MaskDriveText('', AJson + ADetras));
  try
    Claves := [];
    for var C in AClaves do
      Claves := Claves + [C];
    T := Transforma(V);
    try
      Result := T.ToJSON;
    finally
      T.Free;
    end;
  finally
    V.Free;
  end;
  Result := Result + MaskDriveText('', ADetras);
  TSalidaHecha := Result;
end;

procedure OlvidaSalidaHecha;
begin
  TSalidaHecha := '';
  TCitasHechas := '';
end;

initialization
  GDrvLock := TCriticalSection.Create;

finalization

  // (GDrvLock no se libera: el enmascarador lo usa desde cualquier hilo que
  // aun este contestando, y se va con el proceso)

end.