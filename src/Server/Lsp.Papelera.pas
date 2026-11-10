unit Lsp.Papelera;

{ LA PAPELERA de la jaula (__delphi-patch): la copia diaria antes de editar
  (BackupFile), el nombrador de las copias selladas y su inversa, sus cajones,
  la copia de lo que se pisa o se borra entero (GuardaContenidoActual) y la
  marca de su dueno. Vivia en Lsp.Patch (V94 de la depuracion de la 1.23, B6
  de la 1.28): se mudo sin cambiar una linea. }

interface

{ Makes a recoverable copy of a file into __delphi-patch\<date>\ before it is
  overwritten (once per file per day). Returns a note / the backup path.
  Exposed so binary writers (delphi_upload) can be non-destructive too. }
function BackupFile(const APath: string): string;
{ La copia DIARIA que BackupFile hace de un fichero (__delphi-patch\<dia>\
  <nombre>, sin sello): el nombrador, para quien tenga que quitarla porque la
  escritura que la dejo se deshizo (el move de una unit que no acaba). }
function CopiaDiariaDe(const APath: string): string;
{ Su lector: la copia diaria MAS RECIENTE de APath, la de la ultima carpeta de
  dia que la tenga, por el mismo nombre; '' si no hay ninguna. La busca
  restore, que componia el nombre a mano (B6 del revisor del paisaje de la
  1.28). }
function UltimaCopiaDiariaDe(const APath: string): string;
{ El nombre ORIGINAL de una copia de la papelera, o '' si ese nombre no lleva
  sello. Solo tiene sentido DENTRO de __delphi-patch.

  delphi_delete aparca los ficheros como "UFicha.pas-215825250": el sello de
  hora va DETRAS de la extension, que es lo que impide que dos borrados del
  mismo fichero se pisen... y lo que rompe a todo el que mire la extension.
  Quita UN sello, el que pone el nombrador: "x-215825250-215841305" vuelve
  como "x-215825250", el nombre que tenia al entrar (quitarlos todos
  devolvia "lote-123456789" como "lote": J13 de la 1.28).

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

{ El nombre de una copia: el nombre real + el sello. La unica forma. }
function TrashStampedName(const AName: string): string;
{ ...y el COMODIN que casa con las copias de AMascara (*.pas -> *.pas-*): el
  sello va detras del nombre, asi que la mascara sola no las ve. Lo usan quien
  recorre la papelera (WalkFiles) y la llamada que recupera un lote
  (Mcp.Tools.FileOps); lo escribian los dos a mano (V106 de la 1.23.1). }
function MascaraDeCopias(const AMascara: string): string;

const
  { Los CAJONES de la papelera de un dia (TrashDayDir): en que carpeta cae una
    copia sellada. El nombre lo pone TrashStampedName; lo que distingue una
    copia de otra es su cajon, no su nombre. Estaban escritos a mano
    ('deleted' en Mcp.Tools.FileOps, 'before-restore' en el restore). }
  CAJON_BORRADOS = 'deleted';                  // delete, changeset delete, la copia previa de move
  CAJON_ANTES_DE_RESTAURAR = 'before-restore'; // lo que habia antes de un restore
  CAJON_SUSTITUIDOS = 'replaced';              // lo que habia antes de pisar un fichero ENTERO
  CAJON_CORRUPTOS = 'corrupt';                 // la subida que no casa con su sha256 (UPLOAD-011)

{ La ruta de una copia SELLADA de APath en el cajon ACajon de su papelera,
  por la puerta de escribir sobre la ruta REAL (lanza la negativa): un
  __delphi-patch que fuera un enlace se llevaba la copia FUERA de la jaula
  (quinta revision). Vivia en Mcp.Tools.FileOps, donde Lsp.Changeset no la
  alcanzaba, y el restore la escribia aparte, a mano. }
function TrashPathFor(const APath, ACajon: string): string;

{ Guarda el contenido ACTUAL de APath (un fichero) sellado en ACajon, con su
  marca de dueno, y devuelve la ruta de la copia ('' si no habia fichero).
  Para todo lo que PISA o BORRA un fichero entero: la copia de BackupFile es
  UNA por fichero y dia -la version previa al primer cambio-, asi que lo
  escrito despues se perdia al sustituirlo o borrarlo (sexta revision, medido:
  changeset delete tras dos ediciones dejo solo la de la manana). Lanza si no
  se puede: pisar sin copia no se hace. }
function GuardaContenidoActual(const APath: string;
  const ACajon: string = CAJON_SUSTITUIDOS): string;

{ Las COPIAS que la llamada en curso HIZO (la diaria de BackupFile, la
  sellada de GuardaContenidoActual), para que su respuesta las NOMBRE: UNA
  nota para todas las tools que escriben, que pone el filtro de salida
  (Lsp.Host). Unas 30 respuestas decian "Backup in __delphi-patch." sin el
  fichero, solo delphi_edit y delphi_textedit daban su ruta, y Hermes fue a
  la papelera unas 520 veces en tres semanas (R6 del revisor del paisaje del
  10-nov-2026). Por hilo, como los origenes de Lsp.Puertas: OlvidaOrigenes las
  vacia al empezar y al acabar la llamada. }
procedure OlvidaCopiasDeLaLlamada(AEnLlamada: Boolean);
{ ...y la nota: las copias que siguen en el disco y que ATexto no nombra ya
  (el backup= de delphi_edit), enmascaradas como toda ruta que se ensena; ''
  si no queda ninguna. }
function NotaDeLasCopias(const ATexto: string): string;

{ Deja "<copia>.by" con el agente que la tiro; sin identidad, nada. }
procedure WriteOwnerMarker(const ATrash: string);
{ El agente dueno de una copia, '' si no consta. }
function TrashOwner(const APath: string): string;
{ El agente dueno de lo que hay en APath dentro de la papelera: su marca, o
  la de la copia que lo CONTIENE - MoveToTrash marca la carpeta entera, no
  cada fichero de dentro, y otro agente purgaba lo de dentro de una copia
  ajena (V193 de la 1.23.1, medido). '' si nadie la marco. }
function DuenoEnLaPapelera(const APath: string): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Lsp.Puertas,      // EscribeTexto, LeeTexto: la marca de dueno por las puertas
  Lsp.Codificacion, // ekUtf8
  Lsp.Guard,        // las puertas de escribir, CrearCarpeta, EnPapelera, PurgeOldBackups
  Lsp.Casa,         // TrashDayDir, CarpetaDePapelera, MarcaDeDueno: las carpetas de la casa
  Lsp.Mascara,      // MaskDriveText: la copia que se ensena
  Lsp.Identidad,    // CurrentAgent: el dueno de una copia
  Lsp.NetDrives,    // SinBarraFinal
  Lsp.Texts;

threadvar
  // por hilo, como los origenes de Lsp.Puertas: el servidor HTTP atiende
  // varias llamadas a la vez, y fuera de una llamada no se apunta nada
  GCopias: TArray<string>;
  GCopiasEnLlamada: Boolean;

procedure OlvidaCopiasDeLaLlamada(AEnLlamada: Boolean);
begin
  GCopias := nil;
  GCopiasEnLlamada := AEnLlamada;
end;

procedure ApuntaCopia(const ACopia: string);
begin
  if not GCopiasEnLlamada or (ACopia = '') then
    Exit;
  for var C in GCopias do
    if SameFileName(C, ACopia) then
      Exit;
  GCopias := GCopias + [ACopia];
end;

function NotaDeLasCopias(const ATexto: string): string;
var
  Nombradas: string;
begin
  Result := '';
  Nombradas := '';
  for var C in GCopias do
  begin
    var Vista := MaskDriveText('', C);
    // la que ya nombra la respuesta (el backup= de delphi_edit y textedit) no
    // se repite; la que una escritura que no acabo quito (Coloca) no se nombra
    if ATexto.Contains(Vista) or ATexto.Contains(C) or not TFile.Exists(C) then
      Continue;
    if Nombradas <> '' then
      Nombradas := Nombradas + ', ';
    Nombradas := Nombradas + Vista;
  end;
  if Nombradas <> '' then
    Result := MsgFmt(SN_COPIAS_DE_LA_LLAMADA_FMT, [Nombradas]);
end;

{ La copia diaria de APath en la carpeta de un dia: EL nombre, el que escribe
  CopiaDiariaDe (hoy) y lee UltimaCopiaDiariaDe (el dia mas reciente). }
function CopiaDiariaEn(const ACarpetaDelDia, APath: string): string;
begin
  Result := TPath.Combine(ACarpetaDelDia, TPath.GetFileName(APath));
end;

function CopiaDiariaDe(const APath: string): string;
begin
  // Esta copia NO lleva sello a proposito: es una por fichero y dia, la
  // version previa al primer cambio del dia. Pero la CARPETA la pone el
  // nombrador, como todas.
  Result := CopiaDiariaEn(TrashDayDir(APath, ''), APath);
end;

function UltimaCopiaDiariaDe(const APath: string): string;
var
  Dir: string;
  Dias: TArray<string>;
begin
  Result := '';
  Dir := CarpetaDePapelera(APath);
  if not TDirectory.Exists(Dir) then
    Exit;
  // los nombres de dia (yyyymmdd) ordenan como las fechas; por EL lister de la
  // puerta, que dice una papelera que Windows no deja listar en vez de darla
  // por vacia (GetDirectories, B2 del cierre de la 1.19.0)
  Dias := EntradasDeCarpeta(Dir);
  TArray.Sort<string>(Dias);
  for var I := High(Dias) downto 0 do
    if EsCarpetaDeDia(TPath.GetFileName(Dias[I])) and TFile.Exists(CopiaDiariaEn(Dias[I], APath)) then
      Exit(CopiaDiariaEn(Dias[I], APath));
end;

{ Makes the pre-edit copy (once per file per day). Returns a note. }
function BackupFile(const APath: string): string;
var
  Dir, DayDir, Dest, Motivo: string;
begin
  Dir := CarpetaDePapelera(APath);
  Dest := CopiaDiariaDe(APath);
  DayDir := TPath.GetDirectoryName(Dest);
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
  // La copia se escribe JUNTO al fichero: el fichero y su carpeta de copias
  // pasan la puerta, esta por la ruta REAL (un __delphi-patch que fuera un
  // junction llevaria la copia a donde apunte).
  // la MISMA pregunta que hara el escritor, con el +R incluido: si se va a
  // negar, que se niegue antes de dejar la copia diaria (decima revision)
  Motivo := SustitucionDenegada(APath);
  if Motivo = '' then
    Motivo := EscrituraDenegada(DayDir);
  // la copia es LEER el fichero (un enlace duro: GUARD-041). La segunda
  // barrera: quien edita ya lo leyo por la puerta de leer
  if Motivo = '' then
    Motivo := EnlaceDuroIlegible(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // la que ya existia la nombro la primera llamada del dia: no se repite
  // (test_docs_tokens T6: la segunda dice "ya existia" sin la ruta)
  if TFile.Exists(Dest) then
    Exit(MsgText(SF_EDIT_COPIA_YA_EXISTIA));
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
        Exit(MsgText(SF_EDIT_COPIA_YA_EXISTIA))
      else
        raise;
  end;
  ApuntaCopia(Dest);
  PurgeOldBackups(Dir);
  Result := MaskDriveText('', Dest);
end;

function TrashStampedName(const AName: string): string;
begin
  Result := AName + '-' + FormatDateTime('hhnnsszzz', Now);
end;

function MascaraDeCopias(const AMascara: string): string;
begin
  Result := AMascara + '-*';
end;

function TrashPathFor(const APath, ACajon: string): string;
var
  Veto: string;
begin
  Result := TPath.Combine(TrashDayDir(APath, ACajon),
    TrashStampedName(TPath.GetFileName(SinBarraFinal(APath))));
  // Un nombre NUEVO siempre: el sello sale de Now, que avanza a golpes de
  // ~15 ms, y dos sustituciones del mismo fichero en el mismo golpe (to-binary
  // y enseguida to-text) tenian el mismo nombre: la copia no pisa y la segunda
  // operacion fallaba (la puerta 18 lo cazo; septima revision). Se espera al
  // sello siguiente: el formato no cambia y su lector (TrashOriginalName)
  // tampoco.
  var Espera := 0;
  while (TFile.Exists(Result) or TDirectory.Exists(Result)) and (Espera < 100) do
  begin
    Sleep(5);
    Inc(Espera);
    Result := TPath.Combine(TrashDayDir(APath, ACajon),
      TrashStampedName(TPath.GetFileName(SinBarraFinal(APath))));
  end;
  // La papelera es un DESTINO: por la puerta de escribir, sobre la ruta REAL.
  Veto := EscrituraDenegada(TPath.GetDirectoryName(Result));
  if Veto = '' then
    Veto := EscrituraDenegada(Result);
  if Veto <> '' then
    raise Exception.Create(Veto);
end;

procedure WriteOwnerMarker(const ATrash: string);
var
  Who: string;
begin
  Who := CurrentAgent;
  if Who = '' then
    Exit;
  try
    // por LA puerta de escribir, en UTF-8 (un agente ASCII da los mismos
    // bytes de siempre): en ASCII un nombre no ASCII salia con '?' y no
    // casaba con su dueno al purgar (P3-L1 de la 1.18.0); TrashOwner lo lee
    // con el detector
    EscribeTexto(MarcaDeDueno(ATrash), Who, ltJaula, ekUtf8);
  except
    // a missing marker just means "nobody's": never fatal
  end;
end;

function TrashOwner(const APath: string): string;
begin
  Result := '';
  try
    if TFile.Exists(MarcaDeDueno(APath)) then
      Result := LeeTexto(MarcaDeDueno(APath), [ltJaula]).Trim([' ', #9, #13, #10, #$FEFF]);
  except
    Result := '';
  end;
end;

function DuenoEnLaPapelera(const APath: string): string;
var
  A, Padre: string;
  EsLaCarpeta: Boolean;
begin
  Result := TrashOwner(APath);
  A := TPath.GetDirectoryName(SinBarraFinal(APath));
  // hacia arriba mientras se siga DENTRO de la papelera (la carpeta
  // __delphi-patch misma no es una copia de nadie)
  while (Result = '') and (A <> '') and EnPapelera(A, EsLaCarpeta) and not EsLaCarpeta do
  begin
    Result := TrashOwner(A);
    Padre := TPath.GetDirectoryName(A);
    if (Padre = '') or SameFileName(Padre, A) then
      Break;
    A := Padre;
  end;
end;

function GuardaContenidoActual(const APath, ACajon: string): string;
begin
  Result := '';
  if not TFile.Exists(APath) then
    Exit;
  // Quien guarda la copia va a PISAR o BORRAR el fichero entero: si tiene
  // el atributo de solo lectura, se dice aqui, antes de copiar nada. Es el
  // sitio de todos (upload, cuarentena, disenador, adb, escritorio,
  // package, changeset delete, restore): package decia "alguien lo tiene
  // abierto, reintenta" y dejaba copia (septima revision, medido)
  var Motivo := SoloLecturaDenegado(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  // de un temporal no se restaura nada (la regla del borrado): su copia
  // dejaba una papelera DENTRO de la temporal (septima revision)
  if EnTemporal(APath) then
    Exit;
  // ...y la copia es LEER el fichero: un enlace duro con un nombre que la
  // sesion no lee no se copia, y sin copia no se pisa (medido el
  // 20-oct-2026: upload y el .res de styles build metian en la papelera los
  // bytes del fichero de fuera de las raices)
  Motivo := EnlaceDuroIlegible(APath);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  Result := TrashPathFor(APath, ACajon); // la puerta, o la negativa
  CrearCarpeta(TPath.GetDirectoryName(Result));
  TFile.Copy(APath, Result);
  WriteOwnerMarker(Result);
  ApuntaCopia(Result); // la respuesta la nombra (R6)
end;

function TrashOriginalName(const AName: string): string;
var
  M: TMatch;
begin
  // hhnnsszzz = 9 digitos, y UNO: el que pone el nombrador. Se quitaban en
  // bucle (por las cadenas que dejaba restaurar DENTRO de la papelera) y un
  // fichero llamado lote-123456789 volvia como "lote" (J13 del revisor de la
  // 1.28, medido). Una cadena vuelve con el nombre que tenia al entrar.
  M := TRegEx.Match(AName, '^(.+)-\d{9}$');
  if M.Success then
    Result := M.Groups[1].Value
  else
    Result := '';
end;

end.
