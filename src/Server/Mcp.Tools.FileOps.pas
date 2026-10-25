unit Mcp.Tools.FileOps;

{ delphi_delete and delphi_move: remove or relocate files/folders inside the
  workspace, safely. delete is NOT a hard delete - the target is moved to a
  recoverable trash (__delphi-patch\<date>\deleted\...) next to it, the same
  place delphi_edit keeps its backups. move copies the source to trash first,
  then relocates it. Both are jailed and refused in read-only mode. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,   // SchemaDescription texts: attributes are interface-level
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiDeleteParams = class
  private
    FPath: string;
    FPurge: Boolean;
  public
    [SchemaDescription(SP_FILE_PATH)]
    [Required]
    [RutaDelServidor]
    [ComodinEnNombre]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_DELETE_PURGE)]
    property Purge: Boolean read FPurge write FPurge;
  end;

  TDelphiMoveParams = class
  private
    FPath: string;
    FDest: string;
    FCopy: Boolean;
  public
    [SchemaDescription(SP_FILE_PATH_2)]
    [Required]
    [RutaDelServidor]
    [ComodinEnNombre]
    property Path: string read FPath write FPath;
    [SchemaDescription(SP_FILE_DEST)]
    [Required]
    [RutaDelServidor]
    property Dest: string read FDest write FDest;
    [SchemaDescription(SP_MOVE_COPY)]
    property Copy: Boolean read FCopy write FCopy;
  end;

  TDelphiDeleteTool = class(TMCPToolBase<TDelphiDeleteParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiDeleteParams): string; override;
  public
    constructor Create; override;
  end;

  TDelphiMoveTool = class(TMCPToolBase<TDelphiMoveParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiMoveParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.ProjectUnits,
  Lsp.NetDrives,
  Lsp.Rutas,
  Lsp.Casa,
  Lsp.Identidad;

function IsBackupPath(const APath: string): Boolean;
begin
  // inside the trash, OR the trash folder itself: EL lector de Lsp.Guard,
  // sobre la ruta larga (aqui se miraba el texto y __DELP~1 no era papelera)
  Result := EnPapelera(APath);
end;

{ The trash/backup folder ITSELF (…\__delphi-patch), not something inside it.
  Moving/deleting the trash itself is refused; moving an item OUT of it (a
  restore) is allowed. }
function IsBackupRoot(const APath: string): Boolean;
var
  EsLaCarpeta: Boolean;
begin
  Result := EnPapelera(APath, EsLaCarpeta) and EsLaCarpeta;
end;

type
  { Un paso de una operacion como la del operador (V19 de la 1.23): lo que se
    toca (Origen) y adonde va (Destino). }
  TPaso = record
    Origen, Destino: string;
  end;

function Paso(const AOrigen, ADestino: string): TPaso;
begin
  Result.Origen := AOrigen;
  Result.Destino := ADestino;
end;

{ Las entradas de la carpeta de APath que casan con su nombre, por EL juez del
  pattern de delphi_list y delphi_search (TDirectory, sobre el nombre LARGO:
  medido el 25-oct-2026, *.pas no casa b.pas2 aunque su nombre 8.3 si), sin
  la papelera ni las marcas de dueno. '' con AEntradas, o la negativa. }
function EntradasDelComodin(const APath: string; out AEntradas: TArray<string>): string;
var
  Carpeta, Mascara: string;
  Todas: TArray<string>;
begin
  Result := '';
  AEntradas := [];
  Carpeta := CarpetaDelComodin(APath);
  Mascara := ExtractFileName(SinBarraFinal(APath));
  // el comodin va en el NOMBRE, en su carpeta: nunca recorre carpetas
  if Carpeta.IndexOfAny(['*', '?']) >= 0 then
    Exit(MsgFmt(SR_FILE_COMODIN_SOLO_EN_NOMBRE_FMT, [APath]));
  if not TDirectory.Exists(Carpeta) then
    Exit(MsgFmt(SR_FILE_NO_EXISTE_ORIGEN_FMT, [Carpeta]));
  // lo que no se deja listar se dice (GUARD-040): TDirectory lo daria vacio
  try
    Todas := EntradasDeCarpeta(Carpeta);
  except
    on E: Exception do
      Exit(E.Message);
  end;
  // la mascara, con LA pregunta que TDirectory le hace a cada nombre
  // (System.IOUtils, WalkThroughDirectory: DoMatchesPattern sobre el nombre
  // de FindFirst, con las mayusculas de la plataforma), medido en su fuente
  for var E in Todas do
    if TPath.MatchesPattern(TPath.GetFileName(E), Mascara) and
       not SameText(TPath.GetFileName(E), TrashFolderName) and not EsMarcaDeDueno(E) then
      AEntradas := AEntradas + [E];
  if Length(AEntradas) = 0 then
    Result := MsgFmt(SR_FILE_COMODIN_NADA_FMT, [Carpeta, Mascara]);
end;

{ El nombre con el que una entrada de un comodin llega a su carpeta: el suyo,
  o el ORIGINAL si viene de la papelera (sus copias llevan el sello detras:
  "UFicha.pas-215825250"; restaurar es volver al nombre de antes). }
function NombreDeDestino(const AEntrada: string; ADesdePapelera: Boolean): string;
begin
  Result := TPath.GetFileName(SinBarraFinal(AEntrada));
  if ADesdePapelera then
  begin
    var Original := TrashOriginalName(Result);
    if Original <> '' then
      Result := Original;
  end;
end;

{ LA MIRADA PREVIA de un move o una copia (V19), antes del primer byte: que
  ningun FICHERO del destino se pise (David, 25-oct-2026: "carpeta vacia o no
  da igual; lo que no queremos es sobrescribir ficheros": una carpeta que existe
  se mezcla; el mismo fichero con otras mayusculas es un renombrado), que la
  ruta mas larga quepa (GUARD-028: fallaba a mitad, con N ficheros ya copiados;
  Fable 5) y que haya sitio (David, 17-oct: "espacio suficiente y con margen":
  la copia en su destino, la copia de seguridad de un move en su papelera).
  Lo que se mira es lo que se va a escribir: la copia, por EL copiador sin
  escribir (AAlListar); el move, renombrando, tal cual (los enlaces como
  enlaces). '' o la negativa (con la lista de lo que choca). }
function MiradaPrevia(const APasos: TArray<TPaso>; ACopia, ADesdePapelera: Boolean): string;
const
  TOPE = 20;
var
  Choques, Vistos, NoSeg: TArray<string>;
  Larga: string;
  Bytes: Int64;
  Mide: TProc<string, Int64>;
  Choca: TProc<string>;
begin
  Result := '';
  Choques := [];
  Vistos := [];
  Larga := '';
  Bytes := 0;
  Mide :=
    procedure(D: string; ATamano: Int64)
    begin
      if Length(D) > Length(Larga) then
        Larga := D;
      Inc(Bytes, ATamano);
    end;
  Choca :=
    procedure(D: string)
    begin
      if not MatchText(D, Choques) then
        Choques := Choques + [D];
    end;
  for var P in APasos do
  begin
    var Origen := SinBarraFinal(TPath.GetFullPath(P.Origen));
    var Destino := SinBarraFinal(TPath.GetFullPath(P.Destino));
    // dos al MISMO destino (dos copias de la papelera del mismo original, con
    // un comodin) chocan entre si
    if MatchText(Destino, Vistos) then
      Choca(Destino);
    Vistos := Vistos + [Destino];
    if not TDirectory.Exists(Origen) or EsEnlace(Origen) then
    begin
      // un fichero o un enlace (viaja como enlace): no se pisa nada; el mismo
      // con otras mayusculas es un renombrado (MismaEntrada, punto 4 de Fable)
      // al MOVER; copiarse encima, no (lo niega antes CopiaDenegada: MOVE-009)
      if (TDirectory.Exists(Destino) or TFile.Exists(Destino)) and
         (ACopia or not MismaEntrada(Origen, Destino)) then
        Choca(Destino);
      if TFile.Exists(Origen) and not EsEnlace(Origen) then
        Mide(Destino, TFile.GetSize(Origen))
      else
        Mide(Destino, 0);
      Continue;
    end;
    if TFile.Exists(Destino) then
    begin
      Choca(Destino);
      Continue;
    end;
    // la carpeta misma con otras mayusculas no se mezcla consigo: se renombra
    var Mezcla := TDirectory.Exists(Destino) and (ACopia or not MismaEntrada(Origen, Destino));
    if ACopia then
      CopiaArbol(Origen, Destino, False, NoSeg, True, nil,
        function(const O, D: string; AEsCarpeta, ADetras: Boolean): Boolean
        begin
          Result := True;
          if AEsCarpeta then
          begin
            if Mezcla and TFile.Exists(D) then
            begin
              Choca(D);
              Result := False;
            end;
            Mide(D, 0);
          end
          else
          begin
            if Mezcla and (TFile.Exists(D) or TDirectory.Exists(D)) then
              Choca(D);
            Mide(D, TFile.GetSize(O));
          end;
        end)
    else
      RecorreSinEnlaces(Origen,
        procedure(const E: string)
        begin
          var D := Destino + E.Substring(Length(Origen));
          if TDirectory.Exists(E) then
          begin
            if Mezcla and TFile.Exists(D) then
              Choca(D);
            Mide(D, 0);
          end
          else
          begin
            if Mezcla and (TFile.Exists(D) or TDirectory.Exists(D)) then
              Choca(D);
            Mide(D, TFile.GetSize(E)); // lo que ocupara su copia de seguridad
          end;
        end,
        procedure(const E: string)
        begin
          var D := Destino + E.Substring(Length(Origen));
          if Mezcla and (TFile.Exists(D) or TDirectory.Exists(D)) then
            Choca(D);
          Mide(D, 0);
        end);
  end;
  if Length(Choques) > 0 then
  begin
    var Lista := string.Join(', ', Copy(Choques, 0, TOPE));
    if Length(Choques) > TOPE then
      Lista := Lista + MsgFmt(SF_FILE_Y_MAS_FMT, [Length(Choques) - TOPE]);
    Exit(MsgFmt(SR_FILE_DESTINO_YA_EXISTE_FMT, [Lista]));
  end;
  Result := RutaLargaDenegada(Larga);
  if Result <> '' then
    Exit(Result + MsgFmt(SF_FILE_RUTA_MAS_LARGA_FMT, [Larga]));
  if Length(APasos) = 0 then
    Exit;
  if ACopia then
    Result := EspacioDenegado(TPath.GetDirectoryName(SinBarraFinal(TPath.GetFullPath(APasos[0].Destino))), Bytes)
  else if not ADesdePapelera then
    Result := EspacioDenegado(TPath.GetDirectoryName(SinBarraFinal(TPath.GetFullPath(APasos[0].Origen))), Bytes);
end;

{ LA PUERTA de un movimiento: la que pasa la unit y la que pasa cada designer
  que viaja con ella (se movia y se copiaba sin preguntar nada: 1.18.2, 2c).
  El ORIGEN, por la de escribir si se mueve (se quita de su sitio) o por la de
  leer si se copia; el DESTINO, por la de un destino que elige quien llama; y
  las carpetas REALES de lo que se quita y de lo que se pone (EntradaDenegada,
  revisor 4.8 de la 1.18.0, M2; copiar solo pone). '' si pasa. }
function PuertaDelMovimiento(const AOrigen, ADestino: string; ACopia: Boolean): string;
begin
  if ACopia then
    Result := ReadPathDenied(AOrigen)
  else
    Result := PathDenied(AOrigen);
  if Result = '' then
    Result := WriteTargetDenied(ADestino);
  if (Result = '') and not ACopia then
    Result := EntradaDenegada(AOrigen);
  if Result = '' then
    Result := EntradaDenegada(ADestino);
end;

{ ...y LA PUERTA de un borrado, la de la unit y la de su designer: la de
  escribir y la carpeta REAL de la que se quita (EntradaDenegada). La
  pregunta tambien el escritor de la papelera (MoveToTrash). '' si pasa. }
function PuertaDelBorrado(const APath: string): string;
begin
  Result := PathDenied(APath);
  if Result = '' then
    Result := EntradaDenegada(APath);
end;

{ La copia en la papelera de algo que al final no se hizo (un move que
  fallo, el form de un borrado de unit que se deshizo), fuera: es nuestra y
  recien hecha, y dejarla sumaba una copia por reintento; con su marca de
  dueno y las carpetas que se crearon para ella (octava revision). Nunca
  lanza. }
{ Quita la marca de dueno (.by) de una copia de la papelera, si la tiene.
  Nunca lanza: una marca que se queda es inofensiva. UNO: estaba a mano en
  cuatro sitios (novena revision). }
procedure QuitaMarcaDeDueno(const ACopia: string);
begin
  try
    if TFile.Exists(MarcaDeDueno(ACopia)) then
      TFile.Delete(MarcaDeDueno(ACopia));
  except
  end;
end;

procedure QuitaCopiaDeSeguridad(const ACopia, AAncestro: string);
begin
  if ACopia = '' then
    Exit;
  try
    if TDirectory.Exists(ACopia) then
      BorraArbol(ACopia)
    else if TFile.Exists(ACopia) then
      BorraLoNuestro(ACopia); // la copia de un +R es +R (decima revision)
  except
    // se queda: es una copia en la papelera, no hace dano
  end;
  QuitaMarcaDeDueno(ACopia);
  QuitaCarpetasCreadas(ExtractFileDir(ACopia), AAncestro);
end;

procedure MoveToTrash(const APath: string; out ATrash, AAncestro: string); overload;
var
  Ancestro: string;
begin
  // un FICHERO de solo lectura no se borra, como no se edita ni se pisa
  // (SYS-029: puede ser deliberado); el changeset delete ya lo decia y
  // delphi_delete lo borraba: UNA regla (septima revision). Y la puerta,
  // preguntada por el escritor mismo, como AtomicWrite: quien llama la
  // pregunta antes, y un llamador que se olvide no quita nada (1.18.2, 2c)
  var Denegado := PuertaDelBorrado(APath);
  if Denegado <> '' then
    raise Exception.Create(Denegado);
  if TFile.Exists(APath) then
  begin
    var Motivo := SoloLecturaDenegado(APath);
    if Motivo <> '' then
      raise Exception.Create(Motivo);
  end;
  ATrash := TrashPathFor(APath, CAJON_BORRADOS);
  Ancestro := PrimerAncestroQueExiste(TPath.GetDirectoryName(ATrash));
  CrearCarpeta(TPath.GetDirectoryName(ATrash));
  try
    if TDirectory.Exists(APath) then
      // EL mudador (Lsp.Guard): renombrar o nada, con su guard. Nacio AQUI el
      // 2026-08-25 (TDirectory.Move, al no poder renombrar, copiaba y borraba
      // por su cuenta y vacio en la papelera una carpeta bloqueada) y se quedo
      // aqui solo: delphi_move siguio un mes con TDirectory.Move y se trajo a
      // la jaula y BORRO lo de detras de un junction (2026-09-25).
      MueveArbol(APath, ATrash)
    else
      TFile.Move(APath, ATrash);
  except
    // un borrado que no se hizo no deja su cajon del dia vacio (FILE-036
    // decia "no he tocado NADA" con deleted\ recien creado; septima)
    QuitaCarpetasCreadas(TPath.GetDirectoryName(ATrash), Ancestro);
    raise;
  end;
  // Who trashed it, so a later purge can be told "yours only". A file with no
  // marker (or an unknown agent) is nobody's in particular and any caller may
  // purge it - which keeps the operator's own cleanup, and stdio, working.
  WriteOwnerMarker(ATrash);
  AAncestro := Ancestro; // para quien tenga que deshacerlo (QuitaCopiaDeSeguridad)
end;

procedure MoveToTrash(const APath: string; out ATrash: string); overload;
var
  Ancestro: string;
begin
  MoveToTrash(APath, ATrash, Ancestro);
end;

{ Who else's work is inside this purge, '' when none.

  Measured 2026-08-25 by a probe agent: the per-FILE check below worked, so it
  purged the DATE FOLDER instead and took every agent's copies inside with it -
  the check asked for "<folder>.by", which never exists, read that as "nobody's"
  and deleted the tree. A guard that only looks at the path it was handed is no
  guard on a recursive delete. Now a folder is refused if it holds a single
  marker belonging to somebody else, and it names them. }
function PurgeOwnershipDenied(const APathIn: string): string;
var
  Me, Owner, F, Sib, APath: string;
  Others: TStringList;
begin
  Result := '';
  APath := LongCanonical(APathIn);
  Me := CurrentAgent;
  // No identity (stdio, the operator's own console) is trusted with everything.
  if Me = '' then
    Exit;
  if TFile.Exists(APath) then
  begin
    Owner := TrashOwner(APath);
    if (Owner <> '') and not SameText(Owner, Me) then
      Result := MsgFmt(SR_FILE_PURGE_NOT_YOURS_FMT, [Owner]);
    Exit;
  end;
  if not TDirectory.Exists(APath) then
    Exit;
  Others := TStringList.Create;
  try
    Others.Duplicates := dupIgnore;
    Others.Sorted := True;
    for F in WalkFiles(APath, MascaraDeMarcas) do
    begin
      // A marker only OWNS the copy sitting next to it. An orphan .by (its copy
      // already restored or purged) or a file someone just renamed to .by marks
      // nothing - counting its content as an owner let a planted .by make a
      // whole folder unpurgeable by anyone (measured 2026-08-25).
      Sib := CopiaDeLaMarca(F);
      if not (TFile.Exists(Sib) or TDirectory.Exists(Sib)) then
        Continue;
      Owner := TrashOwner(Sib);
      if (Owner <> '') and not SameText(Owner, Me) then
        Others.Add(Owner);
    end;
    if Others.Count > 0 then
      Result := MsgFmt(SR_FILE_PURGE_FOLDER_NOT_YOURS_FMT,
        [Others.Count, Others.CommaText]);
  finally
    Others.Free;
  end;
end;

{ Whether anything is still standing where the caller asked us to delete. }
function StillThere(const APath: string): Boolean;
begin
  Result := TFile.Exists(APath) or TDirectory.Exists(APath);
end;

{ Lo que queda dentro de una carpeta que no se dejo borrar, para decirlo:
  sus primeras entradas, y cual de ellas Windows lista pero no deja abrir -
  un borrado PENDIENTE, retenido por el handle de algun proceso (medido el
  19-oct-2026 en el NAS: un motor con una unidad abierta; FILE-011 decia
  "not empty" y nada mas). '' si no es una carpeta, no se deja listar o no
  queda nada. }
function LoQueQueda(const ADir: string): string;
const
  TOPE = 5;
var
  Entradas, Partes: TArray<string>;
  Nombre: string;
  I: Integer;
begin
  Result := '';
  if not TDirectory.Exists(ADir) then
    Exit;
  try
    Entradas := EntradasDeCarpeta(ADir);
  except
    Exit; // lo que no se deja listar no se describe
  end;
  Partes := nil;
  for I := 0 to High(Entradas) do
  begin
    if I >= TOPE then
      Break;
    Nombre := TPath.GetFileName(Entradas[I]);
    // listada pero sin abrir (ERROR_ACCESS_DENIED): un borrado pendiente
    if (GetFileAttributes(PChar(Entradas[I])) = INVALID_FILE_ATTRIBUTES) and
       (GetLastError = ERROR_ACCESS_DENIED) then
      Nombre := MsgFmt(SF_FILE_ENTRADA_RETENIDA_FMT, [Nombre]);
    Partes := Partes + [Nombre];
  end;
  if Length(Partes) = 0 then
    Exit;
  Result := MsgFmt(SF_FILE_LO_QUE_QUEDA_FMT, [string.Join(', ', Partes),
    IfThen(Length(Entradas) > TOPE, MsgFmt(SF_FILE_Y_MAS_FMT, [Length(Entradas) - TOPE]), '')]);
end;

{ Borrar DE VERDAD, sin papelera: una carpeta por el borrador con guard
  (no cruza enlaces: el junction cae como entrada y su destino ni se
  mira), un fichero quitandole antes el solo-lectura. '' si ya no esta;
  si no, la negativa. Los dos unicos sitios de donde algo se va para
  siempre lo comparten: la purga de la papelera y el borrado dentro de una
  temporal del servidor. }
function BorraDeVerdad(const APath: string): string;
begin
  Result := '';
  try
    if TDirectory.Exists(APath) then
      // La RTL recursiva entraba y borraba AL OTRO LADO de un junction
      // (2026-09-21): BorraArbol no.
      BorraArbol(APath)
    else
      BorraLoNuestro(APath);
  except
    on E: Exception do
      Exit(MsgFmt(SR_FILE_PURGE_FAILED_FMT,
        [TPath.GetFileName(SinBarraFinal(APath)), E.Message + LoQueQueda(APath)]));
  end;
  if StillThere(APath) then
    Result := MsgFmt(SR_FILE_PURGE_FAILED_FMT,
      [TPath.GetFileName(SinBarraFinal(APath)),
       MsgText(SF_FILE_SIGUE_AHI_DESPUES_BORRARLO) + LoQueQueda(APath)]);
end;

{ Las carpetas de la papelera que una purga deja VACIAS, de abajo arriba y
  hasta la propia papelera: purgar la ultima copia dejaba "deleted", la del
  dia y __delphi-patch en la raiz para siempre (vistas en la raiz de un NAS,
  1-oct-2026). RemoveDir solo quita una carpeta vacia (y de un enlace, el
  enlace): se para en la primera que no lo esta, y nunca sube de la papelera. }
procedure RecogeVacias(const ADesde: string);
var
  EsLaPapelera: Boolean;
begin
  for var P in Ancestros(SinBarraFinal(ADesde)) do
  begin
    if not IsBackupPath(P) then
      Break;
    EsLaPapelera := IsBackupRoot(P);
    // un ENLACE no es una carpeta vacia: RemoveDir lo quitaria tenga lo que
    // tenga detras (revision de la 1.9.0). Ahi se para
    if EsEnlace(P) or not RemoveDir(P) then
      Break;
    if EsLaPapelera then
      Break;
  end;
end;

{ TDelphiDeleteTool }

constructor TDelphiDeleteTool.Create;
begin
  inherited;
  FName := 'delphi_delete';
  FDescription := SD_FILE_DELETE;
end;

function BorrarNucleo(const Params: TDelphiDeleteParams): string; forward;

function TDelphiDeleteTool.ExecuteWithParams(const Params: TDelphiDeleteParams): string;
begin
  // El cerrojo de escritura, como toda tool que escribe: un commit de
  // changeset que fallaba a mitad deshacia lo que esta tool escribia
  // entre medias, contestando OK a los dos (verificacion de la tercera
  // revision, 27-sep-2026, medido). Perder una edicion con OK es peor que
  // esperar (David).
  EnterFileEdit;
  try
    Result := BorrarNucleo(Params);
  finally
    LeaveFileEdit;
  end;
end;

function BorrarNucleo(const Params: TDelphiDeleteParams): string;
var
  Denied, Trash, Ancestro, Puerta: string;
  Rutas, Copias, Ancestros: TArray<string>;
  Comodin: Boolean;

  { Lo ya mandado a la papelera vuelve a su sitio (todo o nada con un
    comodin), sin sus marcas ni los cajones que se crearon. '' si todo volvio;
    si no, lo que no, una linea por entrada (SYS-018). }
  function Devuelve: string;
  begin
    Result := '';
    for var I := High(Copias) downto 0 do
      try
        if TDirectory.Exists(Copias[I]) and not EsEnlace(Copias[I]) then
          MueveArbol(Copias[I], Rutas[I])
        else if not MoveFile(PChar(Copias[I]), PChar(SinBarraFinal(Rutas[I]))) then
          RaiseLastOSError;
        QuitaMarcaDeDueno(Copias[I]);
        QuitaCarpetasCreadas(TPath.GetDirectoryName(Copias[I]), Ancestros[I]);
      except
        on E: Exception do
          Result := Result + IfThen(Result <> '', #10) + '  ' + Rutas[I] + ': ' + E.Message.Trim;
      end;
  end;

begin
  Rutas := [];
  Copias := [];
  Ancestros := [];
  // con un comodin en el nombre (V19), la puerta es la de su carpeta y cada
  // entrada que case pasa despues la suya
  Comodin := TieneComodin(Params.Path);
  Puerta := IfThen(Comodin, CarpetaDelComodin(Params.Path), Params.Path);
  Denied := PathDenied(Puerta);
  if Denied <> '' then
    Exit(Denied);
  // un comodin manda a la PAPELERA, y desde fuera de ella y de las temporales:
  // dentro, cada cosa se purga o se borra por su nombre
  if Comodin and (Params.Purge or IsBackupPath(Puerta) or EnTemporal(Puerta)) then
    Exit(MsgFmt(SR_FILE_COMODIN_PAPELERA_FMT, [Params.Path]));
  // PURGE: the one way anything leaves for good, and it only reaches INSIDE
  // the trash. The rule that a live file always goes to the recoverable copy
  // first is what makes every other write safe, so it does not bend; but an
  // agent that made a mess had no way to clean it up, and five of them in one
  // day left 112 MB of copies nobody could remove through MCP (measured
  // 2026-08-25). Worse, a file that should never have existed survived its
  // own delete, still inside the jail and still downloadable.
  if Params.Purge then
  begin
    if not IsBackupPath(Params.Path) then
      Exit(MsgText(SR_FILE_PURGE_ONLY_TRASH));
    // ...y que este en la papelera DE VERDAD, no solo por su texto: un enlace
    // que se borra va a la papelera como enlace, y un fichero nombrado a
    // traves de el es el VIVO de detras. Se purgaba - borrado para siempre,
    // sin copia, con un "it was a copy in the trash" (medido en la revision
    // de la 1.9.0). El enlace mismo si esta alli: se juzga por donde esta.
    try
      if not IsBackupPath(RutaDelEnlace(SinBarraFinal(TPath.GetFullPath(Params.Path)))) then
        Exit(MsgText(SR_FILE_PURGE_ONLY_TRASH));
    except
      Exit(MsgText(SR_FILE_PURGE_ONLY_TRASH)); // lo que no se puede resolver no se purga
    end;
    if IsBackupRoot(Params.Path) then
      Exit(MsgText(SR_FILE_PURGE_NOT_ROOT));
    // un enlace COLGANTE (su destino se borro) existe como NOMBRE: la
    // existencia se preguntaba siguiendo el enlace, contestaba SYS-012 y el
    // enlace se quedaba en la papelera para siempre (2y de la 1.18.2, medido
    // en produccion). El juez es el atributo del propio nombre (EsEnlace)
    if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path) or
            EsEnlace(SinBarraFinal(TPath.GetFullPath(Params.Path)))) then
      Exit(MsgFmt(SR_NO_EXISTE_FMT, [Params.Path]));
    var CanonPurge := LongCanonical(Params.Path);
    if EsMarcaDeDueno(CanonPurge) then
    begin
      // A live marker for someone else's copy is off limits - removing it would
      // orphan their copy for the taking. But an orphan marker (copy already
      // restored/purged) or your own is yours to sweep: otherwise the trash
      // could never be left clean by the agent that made it.
      var SibMk := CopiaDeLaMarca(CanonPurge);
      var Mk := TrashOwner(SibMk); // owner is THIS marker's content
      if (TFile.Exists(SibMk) or TDirectory.Exists(SibMk)) and
         (CurrentAgent <> '') and (Mk <> '') and not SameText(Mk, CurrentAgent) then
        Exit(MsgFmt(SR_FILE_PURGE_NOT_YOURS_FMT, [Mk]));
    end
    else
    begin
      // Yours only - and on a folder, that means everything inside it too.
      Denied := PurgeOwnershipDenied(Params.Path);
      if Denied <> '' then
        Exit(Denied);
    end;
    Denied := BorraDeVerdad(Params.Path);
    if Denied <> '' then
      Exit(Denied);
    QuitaMarcaDeDueno(Params.Path);
    RecogeVacias(TPath.GetDirectoryName(SinBarraFinal(CanonPurge)));
    Exit(MsgFmt(SN_FILE_PURGED_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path))]));
  end;
  // De un temporal no se restaura nada (lo dicen la purga del arranque y
  // los listados): la copia a la papelera era un temporal mas, guardado
  // DENTRO de la propia temporal y escondido de todo listado hasta la
  // siguiente purga (visto el 26-sep-2026 al limpiar dos capturas de 6 MB).
  // Se borra de verdad, y ANTES de la regla de la papelera: una papelera
  // que ya este dentro de una temporal es un temporal mas. La carpeta de
  // temporales misma no: es de todos los agentes del servidor y se vacia
  // sola al arrancar.
  var EsLaTemporal: Boolean;
  if not Comodin and EnTemporal(Params.Path, EsLaTemporal) then
  begin
    if EsLaTemporal then
      Exit(MsgFmt(SR_FILE_DELETE_TEMP_ROOT_FMT, [Params.Path]));
    if not StillThere(Params.Path) then
      Exit(MsgFmt(SR_NO_EXISTE_FMT, [Params.Path]));
    Denied := BorraDeVerdad(Params.Path);
    if Denied <> '' then
      Exit(Denied);
    Exit(MsgFmt(SN_FILE_DELETE_TEMP_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path))]));
  end;
  if Comodin then
  begin
    Denied := EntradasDelComodin(Params.Path, Rutas);
    if Denied <> '' then
      Exit(Denied);
  end
  else
  begin
    if IsBackupPath(Params.Path) then
      Exit(MsgFmt(SR_FILE_PAPELERA_NO_SE_BORRA_FMT, [TrashFolderName]));
    if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
      Exit(MsgFmt(SR_NO_EXISTE_FMT, [Params.Path]));
    Rutas := [Params.Path];
  end;
  for var P in Rutas do
  begin
    // Una carpeta a la papelera se lleva TODO lo de dentro: ni ser ni contener
    // una raiz, una referencia o una carpeta de solo lectura. La puerta solo
    // mira la ruta que le pasan (2026-09-25). Tambien la vacia: una raiz de
    // otro workspace sin nada dentro sigue siendo suya.
    if TDirectory.Exists(P) then
    begin
      Denied := ProtegidoDenegado(P);
      if Denied <> '' then
        Exit(Denied);
    end;
    // borrar QUITA una entrada de su carpeta: la carpeta REAL que la contiene
    // tambien (EntradaDenegada; revisor 4.8 de la 1.18.0, M2)
    Denied := PuertaDelBorrado(P);
    if Denied <> '' then
      Exit(Denied);
  end;
  // An empty folder needs no copy: retrying a half-finished delete used to
  // dump the (empty) tree into the trash again on every attempt.
  // (vacia DE VERDAD: una que no se deja listar no lo es; 2g de la 1.18.x)
  if not Comodin and CarpetaVacia(Params.Path) then
  begin
    // la carpeta VACIA no pasa por el mudador: lo NUESTRO se suelta aqui. Una
    // carpeta que algo de fuera vacio (git, al cambiar de rama) con el motor
    // dentro era un cascaron que no se dejaba quitar (29-sep-2026)
    SueltaLoNuestroBajo(Params.Path);
    try
      // la carpeta esta VACIA (se comprobo arriba): no hay +R de ficheros que
      // quitar, y un recorrido soAllDirectories aqui solo cruzaba junctions sin
      // nada que hacer (2e de la 1.18.2). El +R de una carpeta no impide borrarla.
      try
        TDirectory.Delete(Params.Path, False);
      except
        // fall through to the honest report below
      end;
    finally
      YaNoSeQuita(Params.Path);
    end;
    if not TDirectory.Exists(Params.Path) then
      Exit(MsgFmt(SN_FILE_DELETE_EMPTY_OK_FMT,
        [TPath.GetFileName(SinBarraFinal(Params.Path))]));
    Exit(MsgFmt(SR_FILE_DELETE_STUCK_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path))]));
  end;
  // A la papelera, todo o nada: con un comodin, lo que ya fue vuelve si uno no
  // puede ir. Como un operador (V19): una unit no sale de sus proyectos ni se
  // lleva su form; se AVISA de los dos
  for var P in Rutas do
    try
      MoveToTrash(P, Trash, Ancestro);
      Copias := Copias + [Trash];
      Ancestros := Ancestros + [Ancestro];
    except
      on E: Exception do
      begin
        var NoVolvio := Devuelve;
        if NoVolvio <> '' then
          Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, E.Message]));
        // A locked FOLDER move fails as a whole and leaves the tree intact: say
        // so plainly. La CAUSA manda: una negativa con etiqueta sale tal cual;
        // "algo la tiene abierta" solo si Windows dijo eso (septima revision)
        if TDirectory.Exists(P) then
        begin
          if EsFallo(E.Message) then
            Exit(E.Message);
          if MotivoDelSistema(E.Message) <> '' then
            Exit(MsgFmt(SR_FILE_DELETE_LOCKED_FMT,
              [TPath.GetFileName(SinBarraFinal(P)), E.Message]));
          Exit(MsgFmt(SR_FILE_CARPETA_NO_MOVIDA_FMT,
            [TPath.GetFileName(SinBarraFinal(P)), E.Message]));
        end;
        Exit(MsgEnvuelve(SR_FILE_ERROR_MOVER_PAPELERA_FMT, E.Message));
      end;
    end;
  // Say BORRADO only if it is gone (an auditor found a folder still standing
  // after a cheerful "BORRADO", 2026-08-25): a delete that half-happened must
  // read as one, and say which of the two it is (the empty shell, or more)
  if not Comodin and StillThere(Params.Path) then
  begin
    if CarpetaVacia(Params.Path) then
      Exit(MsgFmt(SN_FILE_DELETE_EMPTY_SHELL_FMT,
        [TPath.GetFileName(SinBarraFinal(Params.Path)), Copias[0]]));
    Exit(MsgFmt(SR_FILE_DELETE_PARTIAL_FMT,
      [TPath.GetFileName(SinBarraFinal(Params.Path)), Copias[0]]));
  end;
  Result := '';
  for var I := 0 to High(Rutas) do
    Result := Result + IfThen(Result <> '', #10) + MsgFmt(SK_FILE_BORRADO_PAPELERA_FMT,
      [TPath.GetFileName(SinBarraFinal(Rutas[I])), Copias[I]]);
  // el par partido y lo que aun apunta a lo borrado, como informacion (V19)
  Result := Result + NotaDeMudanza(Rutas, Copias, mzBorra);
end;

{ TDelphiMoveTool }

constructor TDelphiMoveTool.Create;
begin
  inherited;
  FName := 'delphi_move';
  FDescription := SD_FILE_MOVE;
end;

function MoverNucleo(const Params: TDelphiMoveParams): string; forward;

function TDelphiMoveTool.ExecuteWithParams(const Params: TDelphiMoveParams): string;
begin
  // El cerrojo de escritura, como toda tool que escribe: un commit de
  // changeset que fallaba a mitad deshacia lo que esta tool escribia
  // entre medias, contestando OK a los dos (verificacion de la tercera
  // revision, 27-sep-2026, medido). Perder una edicion con OK es peor que
  // esperar (David).
  if Params.Copy then // una copia no toca lo de nadie y puede ser grande
    Exit(MoverNucleo(Params));
  EnterFileEdit;
  try
    Result := MoverNucleo(Params);
  finally
    LeaveFileEdit;
  end;
end;

function MoverNucleo(const Params: TDelphiMoveParams): string;
const
  // la forma de un paso hecho, para deshacerlo
  FM_FICHERO = 0;        // un fichero (o un enlace) renombrado
  FM_CARPETA = 1;        // una carpeta renombrada entera
  FM_MEZCLA = 2;         // una carpeta mezclada en otra que ya estaba
  FM_COPIA_FICHERO = 3;
  FM_COPIA_CARPETA = 4;  // una carpeta copiada a un sitio nuevo
  FM_COPIA_MEZCLA = 5;   // ...o mezclada, desde su bajada, en una que estaba
var
  Denied, Puerta: string;
  Comodin, DesdePapelera: Boolean;
  Pasos: TArray<TPaso>;
  NoSeguidos, NoSegCopia: TArray<string>;
  // lo hecho, en su orden, para deshacerlo todo o nada: cada paso con su
  // forma, su mezcla y su bajada; las copias de seguridad y las carpetas de
  // destino que se crearon
  Hechos: TArray<TPaso>;
  Formas: TArray<Integer>;
  Mezclas: TArray<TArray<TPasoDeMezcla>>;
  Bajadas, Copias, AncestrosCopia, CarpetasCreadas, AncestrosCreadas: TArray<string>;

  procedure Anota(const AOrigen, ADestino: string; AForma: Integer;
    const AMezcla: TArray<TPasoDeMezcla>; const ABajada: string);
  begin
    Hechos := Hechos + [Paso(AOrigen, ADestino)];
    Formas := Formas + [AForma];
    Mezclas := Mezclas + [AMezcla];
    Bajadas := Bajadas + [ABajada];
  end;

  { Lo hecho, al reves: cada fichero y carpeta a su sitio, lo copiado fuera
    (es nuestro: la mirada previa dijo que no habia nada alli), y las copias
    de seguridad y las carpetas que se crearon, tambien fuera (un move que no
    se hizo no deja copias por reintento; octava revision). '' si todo volvio;
    si no, lo que no (SYS-018). }
  function DeshazTodo: string;
  begin
    Result := '';
    for var I := High(Hechos) downto 0 do
      try
        case Formas[I] of
          FM_FICHERO:
            if not MoveFile(PChar(Hechos[I].Destino), PChar(Hechos[I].Origen)) then
              RaiseLastOSError;
          FM_CARPETA:
            MueveArbol(Hechos[I].Destino, Hechos[I].Origen);
          FM_MEZCLA, FM_COPIA_MEZCLA:
            begin
              var Queda := DeshazMezcla(Mezclas[I]);
              if Queda <> '' then
                raise Exception.Create(Queda);
              // lo de la copia vuelve a su bajada (la volvio a crear), y fuera
              if Formas[I] = FM_COPIA_MEZCLA then
                BorraArbol(Bajadas[I]);
            end;
          FM_COPIA_FICHERO:
            BorraLoNuestro(Hechos[I].Destino); // la copia de un +R es +R
          FM_COPIA_CARPETA:
            begin
              // a una bajada nueva y de alli fuera: el borrador solo quita
              // dentro de una carpeta desechable
              var Bajada := NuevaCarpetaDescarga(TPath.GetDirectoryName(SinBarraFinal(Hechos[I].Destino)));
              MueveArbol(Hechos[I].Destino, Bajada);
              BorraArbol(Bajada);
            end;
        end;
      except
        on E: Exception do
          Result := Result + IfThen(Result <> '', #10) + '  ' + Hechos[I].Destino + ': ' + E.Message.Trim;
      end;
    for var I := 0 to High(Copias) do
      QuitaCopiaDeSeguridad(Copias[I], AncestrosCopia[I]);
    for var I := High(CarpetasCreadas) downto 0 do
      QuitaCarpetasCreadas(CarpetasCreadas[I], AncestrosCreadas[I]);
  end;

  { Lo que se movio o se copio DE VERDAD, para la nota: un paso entero o, en
    una mezcla, cada entrada que entro. Lo que ya estaba en el destino no se
    movio, y la nota lo contaba como movido (medido el 25-oct-2026: el .dproj
    que ya estaba en la carpeta de destino salia en MOVE-023). De una copia
    mezclada, cada entrada por su ORIGEN, no por su bajada. }
  procedure LoMovido(out AViejos, ANuevos: TArray<string>);
  begin
    AViejos := [];
    ANuevos := [];
    for var I := 0 to High(Hechos) do
      if (Formas[I] = FM_MEZCLA) or (Formas[I] = FM_COPIA_MEZCLA) then
      begin
        for var M in Mezclas[I] do
          if M.A <> '' then // '' es una carpeta que la mezcla vacio y quito
          begin
            if Formas[I] = FM_COPIA_MEZCLA then
              AViejos := AViejos + [SinBarraFinal(Hechos[I].Origen) +
                M.De.Substring(Length(SinBarraFinal(Bajadas[I])))]
            else
              AViejos := AViejos + [M.De];
            ANuevos := ANuevos + [M.A];
          end;
      end
      else
      begin
        AViejos := AViejos + [Hechos[I].Origen];
        ANuevos := ANuevos + [Hechos[I].Destino];
      end;
  end;

  { Una carpeta del origen copiada por EL copiador a una bajada (__tmp-) de
    ACarpeta: una copia que falla a mitad se quita ENTERA y no se queda a
    medias en el destino (novena revision); lo que no se deja quitar, se dice
    (decima revision). }
  function CopiaABajada(const AOrigen, ACarpeta: string): string;
  var
    NoSeg: TArray<string>;
  begin
    Result := NuevaCarpetaDescarga(ACarpeta);
    try
      CopiaArbol(AOrigen, Result, False, NoSeg);
      NoSeguidos := NoSeguidos + NoSeg;
    except
      on E: Exception do
      begin
        var Queda := '';
        try
          BorraArbol(Result);
        except
          Queda := Result;
        end;
        if TDirectory.Exists(Result) then
          Queda := Result;
        if Queda <> '' then
          raise Exception.Create(E.Message.TrimRight + #10 + MsgFmt(SF_MOVE_BAJADA_QUEDA_FMT, [Queda]));
        raise;
      end;
    end;
  end;

begin
  Hechos := [];
  Formas := [];
  Mezclas := [];
  Bajadas := [];
  Copias := [];
  AncestrosCopia := [];
  CarpetasCreadas := [];
  AncestrosCreadas := [];
  NoSeguidos := [];
  NoSegCopia := [];
  Pasos := [];
  if Params.Dest.Trim = '' then
    Exit(MsgText(SR_FILE_DELPHI_MOVE_NECESITA_DEST));
  // Con un comodin en el nombre (V19; David: "permitir form1.*") la puerta del
  // origen es la de su carpeta, y cada entrada que case pasa despues la suya
  Comodin := TieneComodin(Params.Path);
  Puerta := IfThen(Comodin, CarpetaDelComodin(Params.Path), Params.Path);
  // El ORIGEN: mover lo quita de su sitio, asi que pasa la puerta de
  // ESCRITURA; copiar solo lo LEE, asi que pasa la de LECTURA: tus raices,
  // tus ReadOnlyRoots, la zona de biblioteca (David, 25-sep-2026)
  if Params.Copy then
    Denied := ReadPathDenied(Puerta)
  else
    Denied := PathDenied(Puerta);
  if Denied <> '' then
    Exit(Denied);
  // El destino no cae en temporales, __history ni papelera (aprobado por
  // David, 25-sep-2026). Sacar algo de ahi es el ORIGEN, libre en la jaula.
  Denied := WriteTargetDenied(Params.Dest);
  if Denied <> '' then
    Exit(Denied);
  // Sacar algo de la papelera es RESTAURAR (lo que dice delphi_delete); lo que
  // no: mover la papelera misma, o meter algo en ella a mano
  if not Comodin and IsBackupRoot(Params.Path) then
    Exit(MsgFmt(SR_FILE_PAPELERA_NO_SE_MUEVE_FMT, [TrashFolderName]));
  if IsBackupPath(Params.Dest) then
    Exit(MsgFmt(SR_FILE_NO_MUEVAS_DENTRO_PAPELERA_FMT, [TrashFolderName]));
  DesdePapelera := IsBackupPath(Puerta);
  // desde la papelera se RESTAURA (move), no se copia
  if Params.Copy and DesdePapelera then
    Exit(MsgText(SR_MOVE_COPY_FROM_TRASH));
  if Comodin then
  begin
    var Entradas: TArray<string>;
    Denied := EntradasDelComodin(Params.Path, Entradas);
    if Denied <> '' then
      Exit(Denied);
    // con un comodin, dest es la CARPETA adonde van
    if TFile.Exists(Params.Dest) then
      Exit(MsgFmt(SR_FILE_COMODIN_DEST_FICHERO_FMT, [Params.Dest]));
    for var E in Entradas do
      Pasos := Pasos + [Paso(E, TPath.Combine(Params.Dest, NombreDeDestino(E, DesdePapelera)))];
  end
  else
  begin
    if not (TFile.Exists(Params.Path) or TDirectory.Exists(Params.Path)) then
      Exit(MsgFmt(SR_FILE_NO_EXISTE_ORIGEN_FMT, [Params.Path]));
    // un FICHERO que va a una ruta con separador final: esa ruta nombra una
    // CARPETA, y dest es el NUEVO nombre (GUARD-025; octava revision)
    if TFile.Exists(Params.Path) and (CarpetaEnVezDeFichero(Params.Dest) <> '') then
      Exit(CarpetaEnVezDeFichero(Params.Dest));
    Pasos := [Paso(Params.Path, Params.Dest)];
  end;
  // Cada paso por SU puerta. Un move renombra en su unidad, fichero o carpeta
  // (una carpeta tambien mezclandola), nunca copiando por debajo
  // (MovidoDenegado: ni ser ni contener un lugar protegido, ni otra unidad; un
  // fichero cruzaba de unidad copiando y borrando, TFile.Move, hasta V19); una
  // copia, por su decision (Lsp.Guard: un destino dentro del origen o
  // protegido, el git de dentro); y la puerta entera de lo que se quita y se
  // pone (PuertaDelMovimiento)
  for var P in Pasos do
  begin
    if not Params.Copy then
    begin
      Denied := MovidoDenegado(P.Origen, P.Destino);
      if Denied <> '' then
        Exit(Denied);
    end;
    if Params.Copy then
    begin
      Denied := CopiaDenegada(P.Origen, P.Destino);
      if Denied <> '' then
        Exit(Denied);
    end;
    Denied := PuertaDelMovimiento(P.Origen, P.Destino, Params.Copy);
    if Denied <> '' then
      Exit(Denied);
  end;
  // LA MIRADA PREVIA, antes del primer byte: ningun fichero se pisa, la ruta
  // mas larga cabe y hay sitio. Lo que no se deja mirar (GUARD-040) no se toca
  try
    Denied := MiradaPrevia(Pasos, Params.Copy, DesdePapelera);
  except
    on E: Exception do
      Denied := IfThen(EsFallo(E.Message), E.Message, MsgEnvuelve(SR_MOVE_ERROR_AL_MOVER_FMT, E.Message));
  end;
  if Denied <> '' then
    Exit(Denied);
  try
    for var P in Pasos do
    begin
      // la carpeta de destino PRIMERO: si no se puede (GUARD-019, un fichero
      // en el camino) no se ha movido nada ni hay copia que quitar (quinta)
      var Carpeta := TPath.GetDirectoryName(TPath.GetFullPath(SinBarraFinal(P.Destino)));
      if not MatchText(Carpeta, CarpetasCreadas) then
      begin
        CarpetasCreadas := CarpetasCreadas + [Carpeta];
        AncestrosCreadas := AncestrosCreadas + [PrimerAncestroQueExiste(Carpeta)];
        CrearCarpeta(Carpeta);
      end;
      // un ENLACE de carpeta se mueve como enlace (un fichero mas); en una
      // copia se lee a traves de el, como siempre
      var EsCarpeta := TDirectory.Exists(P.Origen) and not EsEnlace(SinBarraFinal(P.Origen));
      var Mezcla := TDirectory.Exists(P.Origen) and TDirectory.Exists(P.Destino) and
        not MismaEntrada(P.Origen, P.Destino);
      if Params.Copy then
      begin
        if not TDirectory.Exists(P.Origen) then
        begin
          CopiaNuestra(P.Origen, P.Destino); // la copia es del agente: sin el +R del original
          Anota(P.Origen, P.Destino, FM_COPIA_FICHERO, nil, '');
        end
        else
        begin
          var Bajada := CopiaABajada(P.Origen, Carpeta);
          if Mezcla then
          begin
            var Pasados: TArray<TPasoDeMezcla> := [];
            try
              MezclaArbol(Bajada, P.Destino, Pasados);
            finally
              Anota(P.Origen, P.Destino, FM_COPIA_MEZCLA, Pasados, Bajada);
            end;
          end
          else
          begin
            try
              MueveArbol(Bajada, P.Destino); // renombrar o nada
            except
              BorraArbol(Bajada);
              raise;
            end;
            Anota(P.Origen, P.Destino, FM_COPIA_CARPETA, nil, '');
          end;
        end;
        Continue;
      end;
      // La copia de seguridad en la papelera ANTES de mover, salvo que el
      // origen YA sea una copia de la papelera (la red es el: una copia de una
      // copia doblaba el sello; 20-sep-2026), un ENLACE (viaja como enlace y lo
      // de detras no se toca; octava revision) o un enlace duro con un nombre
      // que la sesion no lee (copiarlo era leer el de fuera; 20-oct-2026)
      if not DesdePapelera and not EsEnlace(SinBarraFinal(P.Origen)) and
         (EnlaceDuroIlegible(P.Origen) = '') then
      begin
        var Copia := TrashPathFor(P.Origen, CAJON_BORRADOS);
        Copias := Copias + [Copia];
        AncestrosCopia := AncestrosCopia + [PrimerAncestroQueExiste(TPath.GetDirectoryName(Copia))];
        CrearCarpeta(TPath.GetDirectoryName(Copia));
        if TDirectory.Exists(P.Origen) then
          // EL copiador, SIN seguir enlaces: el move los lleva como enlaces
          // (MOVE-012), y sin las papeleras de dentro (V21)
          CopiaArbol(P.Origen, Copia, True, NoSegCopia, False)
        else
          TFile.Copy(P.Origen, Copia);
      end;
      if not EsCarpeta then
      begin
        // renombrar: con otras mayusculas, el mismo fichero (punto 4 de Fable)
        if not MoveFile(PChar(SinBarraFinal(P.Origen)), PChar(SinBarraFinal(P.Destino))) then
          raise Exception.Create(MotivoDeRenombre(P.Origen, GetLastError));
        Anota(P.Origen, P.Destino, FM_FICHERO, nil, '');
      end
      else if Mezcla then
      begin
        var Pasados: TArray<TPasoDeMezcla> := [];
        try
          MezclaArbol(P.Origen, P.Destino, Pasados);
        finally
          Anota(P.Origen, P.Destino, FM_MEZCLA, Pasados, '');
        end;
      end
      else
      begin
        MueveArbol(P.Origen, P.Destino); // renombrar o nada
        Anota(P.Origen, P.Destino, FM_CARPETA, nil, '');
      end;
    end;
  except
    on E: Exception do
    begin
      // TODO O NADA: lo hecho vuelve; lo que no, se dice con la causa
      var NoVolvio := DeshazTodo;
      if NoVolvio <> '' then
        Exit(MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, E.Message]));
      if Params.Copy then
        Exit(MsgEnvuelve(SR_MOVE_ERROR_AL_COPIAR_FMT, E.Message));
      Exit(MsgEnvuelve(SR_MOVE_ERROR_AL_MOVER_FMT, E.Message));
    end;
  end;
  // Lo que sale de la papelera deja su marca de dueno sin nada que marcar:
  // fuera, y la papelera queda limpia sin el operador
  if DesdePapelera then
    for var P in Pasos do
      QuitaMarcaDeDueno(P.Origen);
  Result := '';
  for var P in Pasos do
    if Params.Copy then
      Result := Result + IfThen(Result <> '', #10) + MsgFmt(SK_MOVE_COPIADO_FMT, [P.Origen, P.Destino])
    else
      Result := Result + IfThen(Result <> '', #10) + MsgFmt(SK_MOVE_MOVIDO_FMT, [P.Origen, P.Destino]);
  if Length(NoSeguidos) > 0 then
    Result := Result + #10 + MsgFmt(SN_COPY_LINKS_NOT_FOLLOWED_FMT,
      [Length(NoSeguidos), string.Join(', ', NoSeguidos)]);
  // una copia no necesita red: el origen sigue ahi; y lo que sale de la
  // papelera tampoco
  if not Params.Copy then
    if DesdePapelera then
      Result := Result + #10 + MsgText(SN_FILE_SIN_COPIA_DESDE_PAPELERA)
    else
      for var C in Copias do
        Result := Result + #10 + MsgFmt(SN_FILE_COPIA_SEGURIDAD_EN_FMT, [C]);
  // como un operador (V19): ni la cabecera, ni el par, ni los proyectos; se
  // AVISA del par partido y de lo que cruza el borde, de lo que se movio
  var Viejos, Nuevos: TArray<string>;
  LoMovido(Viejos, Nuevos);
  if Params.Copy then
    Result := Result + NotaDeMudanza(Viejos, Nuevos, mzCopia)
  else
    Result := Result + NotaDeMudanza(Viejos, Nuevos, mzMueve);
end;

initialization
  TMCPRegistry.RegisterTool('delphi_delete',
    function: IMCPTool begin Result := TDelphiDeleteTool.Create; end);
  TMCPRegistry.RegisterTool('delphi_move',
    function: IMCPTool begin Result := TDelphiMoveTool.Create; end);

end.
