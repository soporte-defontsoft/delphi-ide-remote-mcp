unit Lsp.Changeset;

{ Multi-file TRANSACTIONS over the safe-editing engine - the piece the
  single-file engine could not give: when one operation touches five files
  and the fifth fails, files one to four must not stay changed (today the
  project tools can only REPORT a partial change; measured origin:
  SR_FILE_PARTIAL_FMT). A changeset makes the whole batch land or none of it.

  Life cycle (delphi_changeset):

    begin                     -> id
    stage (edit/create/delete/move)   accumulates, touches NOTHING
    preview                   -> per-op resolution + a fingerprint (SHA-256)
                                 of every file the batch will touch
    commit                    -> fingerprints re-checked (a file changed since
                                 preview = the whole batch refused), byte
                                 snapshots taken of EVERY file, ops applied in
                                 order; ANY failure restores every snapshot
    rollback                  -> discard the staged batch (before commit)

  Invariants, enforced here and not by prompt:
    - every path vetted against the jail AT STAGE TIME (and again at commit);
    - nothing is written before preview has resolved every anchor;
    - snapshots of all touched files exist before the first byte changes;
    - commit refuses when a file moved under it (FILE_CHANGED, per file);
    - a failed apply restores byte-exact and says which op failed.

  State is in-memory: a changeset lives in THIS server process, expires after
  30 minutes without use, and at most 8 exist at once. Edits use the same
  contract as delphi_edit (old = ONE full line, unique; new = replacement). }

interface

uses
  System.JSON;

function ChangesetExecute(const ACommand, AId, AKind, APath, ADest,
  AOldLine, ANewText, AContent: string; AAtLine: Integer; AN: Integer = 0;
  const AFragment: string = ''): string;

{ Abre un changeset y devuelve su id ('' = ya hay demasiados abiertos). Es lo
  que hace command=begin, expuesto para que otro motor del servidor (el
  rename, desde 1.0.17) apile y confirme por AQUI, con las mismas huellas,
  copias y todo-o-nada, en vez de escribir ficheros por su cuenta. }
function ChangesetBegin: string;

{ "Hay demasiados changesets abiertos", con los numeros de verdad: lo dicen
  dos sitios (begin y el rename) y los numeros viven aqui. }
function MsgChangesetsLlenos: string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Hash,
  System.DateUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Lsp.Guard,
  Lsp.Patch,
  Lsp.TextEdit,
  Lsp.Texts;

type
  TOpKind = (opEdit, opCreate, opDelete, opDeleteLine, opMove);

  TStagedOp = record
    Kind: TOpKind;
    Path: string;      // absolute, jail-vetted
    Dest: string;      // move
    OldLine: string;   // edit: the anchor line
    NewText: string;   // edit: replacement
    AtLine: Integer;   // edit: 1-based disambiguation, 0 = unset
    Content: string;   // create
  end;

  TChangeset = class
    Id: string;
    Ops: TList<TStagedOp>;
    Fingerprints: TDictionary<string, string>; // path -> sha256('' = absent)
    Previewed: Boolean;
    LastUsed: TDateTime;
    constructor Create(const AId: string);
    destructor Destroy; override;
  end;

var
  GLock: TCriticalSection;
  GSets: TObjectDictionary<string, TChangeset>;
  GSeq: Integer = 0;

const
  MAX_SETS = 8;
  TTL_MIN = 30;

function MsgChangesetsLlenos: string;
begin
  Result := MsgFmt(SR_CHANGESET_TOO_MANY_FMT, [MAX_SETS, TTL_MIN]);
end;

constructor TChangeset.Create(const AId: string);
begin
  inherited Create;
  Id := AId;
  Ops := TList<TStagedOp>.Create;
  Fingerprints := TDictionary<string, string>.Create;
  LastUsed := Now;
end;

destructor TChangeset.Destroy;
begin
  Ops.Free;
  Fingerprints.Free;
  inherited;
end;

function FingerprintBytes(const APath: string): string;
var
  S: TBytesStream;
begin
  if not TFile.Exists(APath) then
    Exit('');
  S := TBytesStream.Create(TFile.ReadAllBytes(APath));
  try
    Result := THashSHA2.GetHashString(S, SHA256);
  finally
    S.Free;
  end;
end;

procedure Prune;
var
  K: string;
  Dead: TList<string>;
begin
  Dead := TList<string>.Create;
  try
    for K in GSets.Keys do
      if MinutesBetween(Now, GSets[K].LastUsed) > TTL_MIN then
        Dead.Add(K);
    for K in Dead do
      GSets.Remove(K);
  finally
    Dead.Free;
  end;
end;

{ Paths every op will read or write (dest included). }
function TouchedPaths(const C: TChangeset): TArray<string>;
var
  L: TList<string>;
  Op: TStagedOp;
begin
  L := TList<string>.Create;
  try
    for Op in C.Ops do
    begin
      if not L.Contains(Op.Path) then
        L.Add(Op.Path);
      if (Op.Kind = opMove) and not L.Contains(Op.Dest) then
        L.Add(Op.Dest);
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Physical line count, '' when the file is gone (a delete op). }
{ The half of a changeset id that may be shown to anyone: everything before
  the random tail. Seeing it tells you a batch exists; it does not let you
  operate on it. }
function PublicId(const AId: string): string;
var
  P: Integer;
begin
  Result := AId;
  P := AId.LastIndexOf('-');
  if (P > 0) and (Length(AId) - P - 1 = 8) then
    Result := Copy(AId, 1, P) + '...';
end;

{ Las lineas de un fichero como las cuenta delphi_read; ninguna si no esta. }
function LineasDeFichero(const APath: string): TArray<string>;
var
  Enc: string;
begin
  if not TFile.Exists(APath) then
    Exit(nil);
  Result := LineasDelTexto(PatchLoadText(APath, Enc));
end;

function LineCountOf(const APath: string): Integer;
begin
  Result := Length(LineasDeFichero(APath)); // como delphi_read
end;

function KindName(K: TOpKind): string;
begin
  case K of
    opEdit: Result := 'edit';
    opCreate: Result := 'create';
    opDelete: Result := 'delete';
    opDeleteLine: Result := 'delete-line';
  else
    Result := 'move';
  end;
end;


{ Como resuelve un ancla el motor que la va a aplicar (la misma pregunta,
  Lsp.Patch.LineasDondeCasaElAncla): cuantas lineas casan (1 = unica, 0 =
  no esta, >1 = ambigua) y cual (1-based, 0 si no hay una). Con atline, la
  de atline si es de las que casan, como en los motores. El preview
  preguntaba con OTRA regla (exacta en una funcion, recortada en la otra) y
  decia limpio lo que el commit deshacia (octava revision). }
{ La linea de un delete-line es la de old, con la regla del motor del
  fichero (sin la sangria en Pascal, recortadas en texto): se comparaba
  exacta (octava revision). }
function LineaEsLaDeOld(const ALinea, AOld, APath: string): Boolean;
begin
  Result := Length(LineasDondeCasaElAncla([ALinea], AOld, EsDelMotorPascal(APath))) > 0;
end;

function ResuelveAncla(const AText, APath, ALine: string; AAtLine: Integer;
  out ALinea: Integer): Integer;
var
  Hits: TArray<Integer>;
  H: Integer;
begin
  ALinea := 0;
  Hits := LineasDondeCasaElAncla(LineasDelTexto(AText), ALine, EsDelMotorPascal(APath));
  if AAtLine > 0 then
  begin
    Result := 0;
    for H in Hits do
      if H + 1 = AAtLine then
      begin
        Result := 1;
        ALinea := AAtLine;
      end;
    Exit;
  end;
  Result := Length(Hits);
  if Result = 1 then
    ALinea := Hits[0] + 1;
end;

{ Whether APath will be there when its turn comes, GIVEN the ops already
  staged. `stage` used to ask the disk, which made the most natural sequence
  of all impossible: delete a unit and create it again in the same batch was
  refused ("ya existe") because the delete had not run yet. A changeset is a
  PLAN, so the plan is what decides; the disk is only its starting point. }
function WillExist(C: TChangeset; const APath: string): Boolean;
var
  Op: TStagedOp;
begin
  Result := TFile.Exists(APath);
  for Op in C.Ops do
  begin
    if SameText(Op.Path, APath) then
      case Op.Kind of
        opCreate: Result := True;
        opDelete, opMove: Result := False;
      end;
    if (Op.Kind = opMove) and SameText(Op.Dest, APath) then
      Result := True;
  end;
end;

{ Donde esta HOY en el disco el fichero que la operacion AIndice va a tocar en
  APath: si un move anterior del lote lo trae de otro sitio, su origen (y el
  origen del origen); '' si nada en el disco lo tiene todavia (lo estrena un
  create del lote). El inverso de WillExist, para ENSAYAR contra el contenido
  real - y su +R, que viaja con el (decima revision). }
function RutaHoy(C: TChangeset; AIndice: Integer; const APath: string): string;
var
  J: Integer;
begin
  Result := APath;
  for J := AIndice - 1 downto 0 do
  begin
    if (C.Ops[J].Kind = opMove) and SameText(C.Ops[J].Dest, Result) then
      Result := C.Ops[J].Path
    else if (C.Ops[J].Kind = opCreate) and SameText(C.Ops[J].Path, Result) then
      Exit('');
  end;
  if not TFile.Exists(Result) then
    Result := '';
end;

function ApplyOne(const Op: TStagedOp; out AError: string; AEnsayo: Boolean = False): Boolean;
var
  A: TPatchArgs;
  T: TTextEditArgs;
  R, Enc: string;
begin
  AError := '';
  Result := False;
  // La puerta OTRA VEZ al aplicar, para cada operacion: entre stage y
  // commit pasan hasta 30 minutos, y un camino puede haber cambiado (un
  // junction nuevo, las raices). Solo las ediciones lo volvian a mirar
  // (auditoria 25-sep-2026). La misma pregunta que los escritores.
  AError := EscrituraDenegada(Op.Path);
  if (AError = '') and (Op.Kind = opMove) then
    AError := EscrituraDenegada(Op.Dest);
  if AError <> '' then
    Exit;
  // ENSAYO (el preview): solo edit y create tienen un motor que ensayar
  if AEnsayo and not (Op.Kind in [opEdit, opCreate]) then
    Exit(True);
  case Op.Kind of
    opEdit:
      begin
        // Delphi sources go through the pascal engine; anything else through
        // the plain-text one - a transaction that could not touch a .md or a
        // .json next to the code would be half a transaction (field
        // 2026-08-24).
        if EsDelMotorPascal(Op.Path) then
        begin
          FillChar(A, SizeOf(A), 0);
          A.Path := Op.Path;
          A.OldLine := Op.OldLine;
          A.NewText := Op.NewText;
          A.HasOld := True;
          A.HasNew := True;
          A.AtLine := Op.AtLine;
          A.Ensayo := AEnsayo;
          R := ExecutePatch(A);
        end
        else
        begin
          FillChar(T, SizeOf(T), 0);
          T.Path := Op.Path;
          T.OldLine := Op.OldLine;
          T.NewText := Op.NewText;
          T.HasOld := True;
          T.HasNew := True;
          T.AtLine := Op.AtLine;
          T.Ensayo := AEnsayo;
          R := ExecuteTextEdit(T);
        end;
        Result := not EsFallo(R);
        if not Result then
          AError := R;
      end;
    opCreate:
      begin
        if EsDelMotorPascal(Op.Path) then
          Enc := NewFileEncName
        else
          Enc := 'utf8';
        // el ENSAYO codifica el contenido y pregunta la puerta sin escribir ni
        // crear carpetas (decima revision). Si el fichero existe lo decide el
        // PLAN (PlanConflict): en el disco puede seguir hasta que corra el
        // delete anterior del mismo lote
        if AEnsayo then
        begin
          try
            PatchSaveText(Op.Path, Op.Content, Enc, True);
          except
            on E: Exception do
            begin
              AError := E.Message;
              Exit;
            end;
          end;
          Exit(True);
        end;
        if TFile.Exists(Op.Path) then
        begin
          AError := MsgFmt(SF_CHSET_YA_EXISTE_FMT, [Op.Path]);
          Exit;
        end;
        CrearCarpeta(TPath.GetDirectoryName(Op.Path));
        PatchSaveText(Op.Path, Op.Content, Enc);
        Result := True;
      end;
    opDelete:
      begin
        if not TFile.Exists(Op.Path) then
        begin
          AError := MsgFmt(SF_CHSET_NO_EXISTE_FMT, [Op.Path]);
          Exit;
        end;
        // La foto deshace si el commit falla; si SALE BIEN, el fichero se iba
        // sin copia mientras la respuesta decia que las copias de siempre en
        // __delphi-patch seguian ahi (quinta revision, medido): la copia de
        // antes de tocarlo, como toda tool que escribe
        // la copia del contenido ACTUAL, sellada: la diaria (BackupFile) es
        // la de la primera version del dia y lo de despues se perdia (sexta revision)
        // el atributo de solo lectura se dice antes, como en toda escritura
        // (salia SYS-028 del TFile.Delete; septima revision)
        AError := SoloLecturaDenegado(Op.Path);
        if AError <> '' then
          Exit;
        GuardaContenidoActual(Op.Path, CAJON_BORRADOS);
        TFile.Delete(Op.Path);
        Result := True;
      end;
    opDeleteLine:
      begin
        if not TFile.Exists(Op.Path) then
        begin
          AError := MsgFmt(SF_CHSET_NO_EXISTE_FMT, [Op.Path]);
          Exit;
        end;
        // las lineas como delphi_read (sin la fantasma del salto final, y un CR
        // suelto es salto): atline=4 en un fichero de 3 se aceptaba y solo
        // quitaba el salto final, con COMMIT COMPLETE (septima revision)
        var Txt := PatchLoadText(Op.Path, Enc);
        var Eol := SaltoDominante(Txt);
        var Ls := LineasDelTexto(Txt);
        var SaltoFinal := TieneSaltoFinal(Txt);
        if (Op.AtLine < 1) or (Op.AtLine > Length(Ls)) then
        begin
          AError := MsgFmt(SF_CHSET_LINEA_NO_EXISTE_FMT,
            [Op.AtLine, TPath.GetFileName(Op.Path), Length(Ls)]);
          Exit;
        end;
        if (Op.OldLine <> '') and not LineaEsLaDeOld(Ls[Op.AtLine - 1], Op.OldLine, Op.Path) then
        begin
          AError := MsgFmt(SF_CHSET_LINEA_NO_ESPERADA_FMT,
            [Op.AtLine, Ls[Op.AtLine - 1]]);
          Exit;
        end;
        Delete(Ls, Op.AtLine - 1, 1);
        var Nuevo := string.Join(Eol, Ls);
        if SaltoFinal and (Length(Ls) > 0) then
          Nuevo := Nuevo + Eol;
        PatchSaveText(Op.Path, Nuevo, Enc);
        Result := True;
      end;
    opMove:
      begin
        if not TFile.Exists(Op.Path) then
        begin
          AError := MsgFmt(SF_CHSET_NO_EXISTE_FMT, [Op.Path]);
          Exit;
        end;
        if TFile.Exists(Op.Dest) then
        begin
          AError := MsgFmt(SF_CHSET_DESTINO_YA_EXISTE_FMT, [Op.Dest]);
          Exit;
        end;
        CrearCarpeta(TPath.GetDirectoryName(Op.Dest));
        TFile.Move(Op.Path, Op.Dest);
        Result := True;
      end;
  end;
end;

{ Walks the staged operations in order, keeping the virtual state in mind,
  and returns the first contradiction ('' when the plan still holds). }
function PlanConflict(C: TChangeset): string;
var
  I, J: Integer;
  Op: TStagedOp;
  Sub: TChangeset;

  { La carpeta de un fichero nuevo no puede ser un FICHERO (existente o
    creado antes en la tanda): el preview lo daba por bueno y el commit
    reventaba con el texto del sistema (segunda revision, 27-sep-2026).
    Devuelve la ruta que estorba, o ''. }
  function PadreFichero(const APath: string): string;
  var
    D: string;
  begin
    Result := '';
    D := TPath.GetDirectoryName(APath);
    while (D <> '') and (D <> TPath.GetDirectoryName(D)) do
    begin
      if WillExist(Sub, D) then
        Exit(D);
      D := TPath.GetDirectoryName(D);
    end;
  end;
begin
  Result := '';
  Sub := TChangeset.Create('probe');
  try
    for I := 0 to C.Ops.Count - 1 do
    begin
      Op := C.Ops[I];
      // Una CARPETA donde la operacion pide un fichero: el preview la daba por
      // buena y el commit reventaba con otro motivo (tercera revision)
      Result := CarpetaEnVezDeFichero(Op.Path);
      if (Result = '') and (Op.Kind = opMove) then
        Result := CarpetaEnVezDeFichero(Op.Dest);
      if Result <> '' then
        Exit;
      case Op.Kind of
        opCreate:
          begin
            if WillExist(Sub, Op.Path) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_EXISTS_FMT, [Op.Path]));
            if PadreFichero(Op.Path) <> '' then
              Exit(MsgFmt(SR_CHANGESET_PADRE_FICHERO_FMT, [Op.Path, PadreFichero(Op.Path)]));
          end;
        opEdit, opDeleteLine, opDelete:
          if not WillExist(Sub, Op.Path) then
            Exit(MsgFmt(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
        opMove:
          begin
            if not WillExist(Sub, Op.Path) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
            if WillExist(Sub, Op.Dest) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_DEST_FMT, [Op.Dest]));
            if PadreFichero(Op.Dest) <> '' then
              Exit(MsgFmt(SR_CHANGESET_PADRE_FICHERO_FMT, [Op.Dest, PadreFichero(Op.Dest)]));
          end;
      end;
      Sub.Ops.Add(Op);
    end;
    J := 0; // keeps the compiler quiet about an unused counter
    Inc(J);
  finally
    Sub.Free;
  end;
end;

function ChangesetBegin: string;
begin
  GLock.Enter;
  try
    Prune;
    if GSets.Count >= MAX_SETS then
      Exit('');
    Inc(GSeq); // Now has ~16 ms granularity: two begins can share it
    // The id is also the CAPABILITY. Nothing bound a changeset to whoever
    // opened it, and `status` printed every open id: anybody holding the
    // token could commit or roll back somebody else's half-built batch
    // (found 2026-08-25 while auditing through MCP). So the id gets a
    // random tail, and status shows only the part before it - enough to
    // see that a batch exists and how big it is, not enough to touch it.
    Result := FormatDateTime('hhnnss', Now) + '-' + IntToStr(GSeq) + '-' +
      IntToHex(Random($10000), 4) + IntToHex(Random($10000), 4);
    GSets.Add(Result, TChangeset.Create(Result));
  finally
    GLock.Leave;
  end;
end;

function ChangesetExecute(const ACommand, AId, AKind, APath, ADest,
  AOldLine, ANewText, AContent: string; AAtLine: Integer; AN: Integer;
  const AFragment: string): string;
var
  Cmd, Id, Denied, EncName, Text, Err: string;
  C: TChangeset;
  Op: TStagedOp;
  Ret, Obj: TJSONObject;
  Arr: TJSONArray;
  P: string;
  N, I: Integer;
  Foto: TFotoDeFicheros;
  Changed: TList<string>;
  Applied: Boolean;
  OpCount, FileCount, Before, After: Integer;
  Deltas2: TDictionary<string, Integer>;  // el cambio de lineas de cada fichero, para el informe
  Audit: TStringBuilder;
  Seen: TStringList;
  AuditText: string;
begin
  Cmd := ACommand.Trim.ToLower;
  GLock.Enter;
  try
    Prune;

    if Cmd = 'begin' then
    begin
      Id := ChangesetBegin;
      if Id = '' then
        Exit(MsgChangesetsLlenos);
      Exit(MsgFmt(SN_CHANGESET_BEGUN_FMT, [Id]));
    end;

    if Cmd = 'status' then
    begin
      Ret := TJSONObject.Create;
      try
        Arr := TJSONArray.Create;
        Ret.AddPair('changesets', Arr);
        for Id in GSets.Keys do
        begin
          Obj := TJSONObject.Create;
          Arr.AddElement(Obj);
          Obj.AddPair('id', PublicId(Id));
          Obj.AddPair('ops', TJSONNumber.Create(GSets[Id].Ops.Count));
          Obj.AddPair('previewed', TJSONBool.Create(GSets[Id].Previewed));
        end;
        Ret.AddPair('note', MsgText(SN_CHANGESET_STATUS_NOTE));
        Exit(Ret.ToJSON);
      finally
        Ret.Free;
      end;
    end;

    // el COMANDO antes que el id: {} o un comando mal escrito contestaban
    // "ese changeset no existe" (segunda revision, 27-sep-2026)
    if not MatchStr(Cmd, ['stage', 'unstage', 'undo', 'preview', 'commit', 'rollback']) then
      Exit(MsgText(SR_CHANGESET_CMD));
    Id := AId.Trim;
    if Id = '' then
      Exit(MsgText(SR_CHANGESET_NEED_ID));
    if not GSets.TryGetValue(Id, C) then
      Exit(MsgFmt(SR_CHANGESET_UNKNOWN_FMT, [TTL_MIN]));
    C.LastUsed := Now;

    if Cmd = 'rollback' then
    begin
      GSets.Remove(Id);
      Exit(MsgText(SN_CHANGESET_DISCARDED));
    end;

    if Cmd = 'stage' then
    begin
      C.Previewed := False; // a new op invalidates any previous preview
      FillChar(Op, SizeOf(Op), 0);
      Op := Default(TStagedOp);
      if AKind = 'edit' then Op.Kind := opEdit
      else if AKind = 'create' then Op.Kind := opCreate
      else if AKind = 'delete' then Op.Kind := opDelete
      else if (AKind = 'delete-line') or (AKind = 'deleteline') then Op.Kind := opDeleteLine
      else if AKind = 'move' then Op.Kind := opMove
      else
        Exit(MsgText(SR_CHANGESET_KIND));
      // lo que no es de este kind se dice, no se ignora - por la regla de
      // todas las tools de varios modos (Lsp.Guard.ParametroQueNoVa): era
      // una copia propia que no decia lo que el kind toma (octava revision).
      // delete-line toma old: lo compara con su linea
      var SuyosK: string;
      var SobraK := ParametroQueNoVa(KindName(Op.Kind), [
          'edit', 'old new fragment atline',
          'create', 'content',
          'delete', '',
          'delete-line', 'atline old',
          'move', 'dest'],
        ['content', AContent, '', 'old', AOldLine, '', 'new', ANewText, '',
         'fragment', AFragment, '', 'dest', ADest, '',
         'atline', IfThen(AAtLine > 0, IntToStr(AAtLine)), ''], SuyosK);
      if SobraK <> '' then
        Exit(MsgFmt(SR_CHANGESET_NO_ES_DE_KIND_FMT, [SobraK, AKind, AKind,
          ONinguno('path ' + SuyosK)]));
      if APath.Trim = '' then
        Exit(MsgText(SR_CHANGESET_NEED_PATH));
      // Lo que se escribe o se borra, por la puerta de DESTINO (jaula +
      // carpetas muertas), como delphi_edit y delphi_move; el ORIGEN de un
      // move puede salir de una de ellas (restaurar), como en delphi_move.
      if Op.Kind = opMove then
        Denied := PathDenied(APath)
      else
        Denied := WriteTargetDenied(APath);
      if Denied <> '' then
        Exit(Denied);
      // un fichero con separador final nombra una CARPETA (GUARD-025), y una
      // carpeta en su sitio no es un fichero: se dice al apilar, no en el
      // preview (octava revision)
      if Op.Kind in [opEdit, opCreate, opDelete, opDeleteLine] then
      begin
        Denied := CarpetaEnVezDeFichero(APath);
        if Denied <> '' then
          Exit(Denied);
      end;
      Op.Path := TPath.GetFullPath(APath);
      // What the commit is going to refuse, refuse now. A .dproj staged
      // happily, previewed "clean" and then blew up at commit, taking the
      // three good operations of the batch down with it (measured
      // 2026-08-25): a preview that says clean about something the commit
      // will reject is a preview that lies.
      if MatchText(TPath.GetExtension(Op.Path), ['.dproj', '.groupproj', '.dpk']) and
         (Op.Kind in [opEdit, opDeleteLine]) then
        Exit(MsgFmt(SR_CHANGESET_PROJECT_FILE_FMT, [TPath.GetFileName(Op.Path)]));
      case Op.Kind of
        opEdit:
          begin
            if (AOldLine = '') and (AFragment = '') then
              Exit(MsgText(SR_CHANGESET_EDIT_NEEDS));
            // un old de VARIAS lineas se apilaba y el preview decia NOT FOUND
            // aconsejando atline (decima revision): lo que el commit va a
            // rechazar (EDIT-001), se rechaza ahora
            if TieneSalto(AOldLine) then
              Exit(MsgText(SR_CHANGESET_EDIT_NEEDS));
            Op.OldLine := AOldLine;
            Op.NewText := ANewText;
            Op.AtLine := AAtLine;
            if not WillExist(C, Op.Path) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
            // MODO FRAGMENTO: se resuelve AHORA, al apuntar, en un ancla de
            // linea completa, y la operacion queda como cualquier otra - el
            // preview y el commit no se enteran. Si una operacion anterior
            // del mismo lote cambia esa linea, el ancla no casara y el lote
            // entero se rechaza: todo o nada, como siempre.
            if AFragment <> '' then
            begin
              var Otros := '';
              if AOldLine <> '' then
                Otros := 'old';
              var LineaVieja, LineaNueva: string;
              Denied := FragmentoALinea(Op.Path, AFragment, ANewText, AAtLine,
                Otros, LineaVieja, LineaNueva);
              if Denied <> '' then
                Exit(Denied);
              Op.OldLine := LineaVieja;
              Op.NewText := LineaNueva;
            end;
          end;
        opCreate:
          begin
            // delphi_create writes CRLF; a create inside a changeset wrote
            // whatever arrived, so the same source produced a CRLF file one
            // way and an LF one the other (measured 2026-08-25). One project,
            // one convention.
            // con el normalizador de todos (un CR suelto tambien es salto)
            Op.Content := ConSalto(AContent, #13#10);
            if (Op.Content <> '') and not TieneSaltoFinal(Op.Content) then
              Op.Content := Op.Content + #13#10;
            if WillExist(C, Op.Path) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_EXISTS_FMT, [Op.Path]));
          end;
        opDelete:
          if not WillExist(C, Op.Path) then
            Exit(MsgFmt(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
        opDeleteLine:
          begin
            // a BLANK line has no usable anchor, so atline decides; old is
            // optional and, when given, must match that line (field
            // 2026-08-24: no way to remove the blank lines a cleanup leaves)
            if not WillExist(C, Op.Path) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
            if AAtLine <= 0 then
              Exit(MsgText(SR_CHANGESET_DELLINE_NEEDS));
            if TieneSalto(AOldLine) then // old, si va, es UNA linea
              Exit(MsgText(SR_CHANGESET_DELLINE_NEEDS));
            Op.AtLine := AAtLine;
            Op.OldLine := AOldLine;
          end;
        opMove:
          begin
            if ADest.Trim = '' then
              Exit(MsgText(SR_CHANGESET_NEED_DEST));
            Denied := WriteTargetDenied(ADest);
            if Denied <> '' then
              Exit(Denied);
            // el destino de un FICHERO no acaba en separador (GUARD-025)
            if TFile.Exists(Op.Path) then
            begin
              Denied := CarpetaEnVezDeFichero(ADest);
              if Denied <> '' then
                Exit(Denied);
            end;
            Op.Dest := TPath.GetFullPath(ADest);
            if not WillExist(C, Op.Path) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
            if WillExist(C, Op.Dest) then
              Exit(MsgFmt(SR_CHANGESET_VIRT_DEST_FMT, [Op.Dest]));
          end;
      end;
      C.Ops.Add(Op);
      Exit(MsgFmt(SN_CHANGESET_STAGED_FMT,
        [KindName(Op.Kind), Op.Path, C.Ops.Count]));
    end;

    // Taking one operation back out. Without this, a single mistyped anchor
    // meant rolling back the whole batch and staging everything again
    // (field round 8). n = the number `preview` prints; 0 = the last one.
    if (Cmd = 'unstage') or (Cmd = 'undo') then
    begin
      if C.Ops.Count = 0 then
        Exit(MsgText(SR_CHANGESET_EMPTY));
      N := AN;
      if N = 0 then
        N := C.Ops.Count;
      if (N < 1) or (N > C.Ops.Count) then
        Exit(MsgFmt(SR_CHANGESET_UNSTAGE_N_FMT, [N, C.Ops.Count]));
      Op := C.Ops[N - 1];
      C.Ops.Delete(N - 1);
      C.Previewed := False;
      Exit(MsgFmt(SN_CHANGESET_UNSTAGED_FMT,
        [N, KindName(Op.Kind), Op.Path, C.Ops.Count]));
    end;

    if Cmd = 'preview' then
    begin
      if C.Ops.Count = 0 then
        Exit(MsgText(SR_CHANGESET_EMPTY));
      // The plan can stop being valid AFTER an operation was staged - unstage
      // the delete of X and the create of X behind it is suddenly a create
      // over a file that exists. It failed safe (commit refused, byte-exact
      // rollback) but preview had said "clean" (measured 2026-08-25).
      // Re-validate the whole plan here, in order, against the disk.
      Err := PlanConflict(C);
      if Err <> '' then
        Exit(Err);
      Ret := TJSONObject.Create;
      try
        Ret.AddPair('id', Id);
        Arr := TJSONArray.Create;
        Ret.AddPair('operations', Arr);
        N := 0;
        for I := 0 to C.Ops.Count - 1 do
        begin
          Op := C.Ops[I];
          Obj := TJSONObject.Create;
          Arr.AddElement(Obj);
          Obj.AddPair('n', TJSONNumber.Create(I + 1));
          Obj.AddPair('kind', KindName(Op.Kind));
          Obj.AddPair('path', Op.Path);
          if (Op.Kind in [opEdit, opDeleteLine]) and not TFile.Exists(Op.Path) then
          begin
            // un fichero que un move ANTERIOR del lote trae de otro sitio se
            // ensaya contra el ORIGEN del move: el mismo contenido, y su +R
            // viaja con el (el commit lo rechazaba con SYS-029 tras un preview
            // limpio; decima revision). Uno que un create del lote estrena no
            // tiene contra que ensayar hasta el commit
            var Fuente := RutaHoy(C, I, Op.Path);
            if Fuente = '' then
            begin
              Obj.AddPair('anchor', MsgText(SF_CHSET_ANCLA_PENDIENTE));
              Obj.AddPair('note', MsgText(SN_CHANGESET_PREVIEW_VIRTUAL));
              Continue;
            end;
            Op.Path := Fuente; // la copia local; lo apilado no cambia
          end;
          // un fichero +R que la operacion escribe (delete, edit, delete-line):
          // el commit lo rechaza (SYS-029) y deshace la tanda; el preview decia
          // limpio (octava revision el delete, novena los otros dos). Su ancla
          // no se mira: la operacion no puede hacerse
          if (Op.Kind in [opDelete, opEdit, opDeleteLine]) and TFile.Exists(Op.Path) and
             (SoloLecturaDenegado(Op.Path) <> '') then
          begin
            Obj.AddPair('anchor', SoloLecturaDenegado(Op.Path));
            Inc(N);
            Continue;
          end;
          // delete-line: el preview dice lo que el commit va a rechazar (una
          // linea que no existe, o que no es la de old); decia "clean" y el
          // commit deshacia la tanda entera (septima revision)
          if Op.Kind = opDeleteLine then
          begin
            var Ls := LineasDelTexto(PatchLoadText(Op.Path, EncName));
            Obj.AddPair('atline', TJSONNumber.Create(Op.AtLine));
            if Op.AtLine > Length(Ls) then
            begin
              Obj.AddPair('anchor', MsgFmt(SF_CHSET_LINEA_NO_EXISTE_FMT,
                [Op.AtLine, TPath.GetFileName(Op.Path), Length(Ls)]));
              Inc(N);
            end
            else if (Op.OldLine <> '') and not LineaEsLaDeOld(Ls[Op.AtLine - 1], Op.OldLine, Op.Path) then
            begin
              Obj.AddPair('anchor', MsgFmt(SF_CHSET_LINEA_NO_ESPERADA_FMT,
                [Op.AtLine, Ls[Op.AtLine - 1]]));
              Inc(N);
            end
            else
              Obj.AddPair('anchor', 'ok');
          end;
          if Op.Kind = opEdit then
          begin
            Text := PatchLoadText(Op.Path, EncName);
            // The line the anchor landed on. delphi_read numbers lines,
            // delphi_rename_symbol numbers lines, and the changeset was the
            // only one of the three that never showed its own (field round
            // 10) - which is also the earliest warning that an anchor
            // resolved somewhere unexpected.
            var LineaAncla: Integer;
            var CuantasAncla := ResuelveAncla(Text, Op.Path, Op.OldLine, Op.AtLine, LineaAncla);
            Obj.AddPair('atline', TJSONNumber.Create(LineaAncla));
            case CuantasAncla of
              1: // el ENSAYO del motor: todo lo que el commit va a comprobar
                 // (codificacion, binario, la puerta, el +R) sin escribir; el
                 // preview copiaba tres reglas del commit y le faltaban las
                 // demas (decima revision)
                 if ApplyOne(Op, Err, True) then
                   Obj.AddPair('anchor', 'ok')
                 else
                 begin
                   Obj.AddPair('anchor', Err);
                   Inc(N);
                 end;
              0: begin
                   Obj.AddPair('anchor', MsgText(SF_CHSET_ANCLA_NO_ENCONTRADA));
                   Inc(N);
                 end;
            else
              Obj.AddPair('anchor', MsgText(SF_CHSET_ANCLA_AMBIGUA));
              Inc(N);
            end;
          end;
          // un create: la codificacion de su contenido y la puerta (decima)
          if (Op.Kind = opCreate) and not ApplyOne(Op, Err, True) then
          begin
            Obj.AddPair('anchor', Err);
            Inc(N);
          end;
        end;
        C.Fingerprints.Clear;
        for P in TouchedPaths(C) do
          C.Fingerprints.AddOrSetValue(P, FingerprintBytes(P));
        Ret.AddPair('files', TJSONNumber.Create(C.Fingerprints.Count));
        Ret.AddPair('unresolved', TJSONNumber.Create(N));
        C.Previewed := N = 0;
        if C.Previewed then
          Ret.AddPair('note', MsgText(SN_CHANGESET_PREVIEW_OK))
        else
          Ret.AddPair('note', MsgText(SN_CHANGESET_PREVIEW_BAD));
        Exit(Ret.ToJSON);
      finally
        Ret.Free;
      end;
    end;

    if Cmd = 'commit' then
    begin
      if C.Ops.Count = 0 then
        Exit(MsgText(SR_CHANGESET_EMPTY));
      if not C.Previewed then
        Exit(MsgText(SR_CHANGESET_NOT_PREVIEWED));
      // 1. nothing may have moved since the preview
      // Deltas2 is created further down, but the finally below frees it, and
      // the FILE_CHANGED exit above jumps straight there: an uninitialised
      // local was being freed, which is an access violation whenever the
      // stack happens not to hold nil. That is exactly the shape of the crash
      // an auditor hit on the TOCTOU rejection path (2026-08-25) and could
      // not always reproduce. A local is nil because we say so, never by luck.
      Deltas2 := nil;
      Changed := TList<string>.Create;
      // El cerrojo de escritura de la huella al deshacer: sin el, lo que otro
      // agente escribia a mitad del commit se lo llevaba la vuelta atras
      // (tercera revision, 27-sep-2026, medido)
      EnterFileEdit;
      try
        for P in C.Fingerprints.Keys do
          if FingerprintBytes(P) <> C.Fingerprints[P] then
            Changed.Add(P);
        if Changed.Count > 0 then
          Exit(MsgFmt(SR_CHANGESET_FILE_CHANGED_FMT,
            [string.Join('; ', Changed.ToArray)]));
        // 2. byte snapshots of everything BEFORE the first change
        Foto.Toma(TouchedPaths(C));
        // 3. apply in order; any failure = restore every snapshot
        Applied := True;
        Err := '';
        N := 0;
        // Earlier operations MOVE the lines later ones pin with atline: the
        // preview resolves against the original text, the commit applies
        // against the mutated one (field 2026-08-24). Every op is rebased
        // by what the previous ones did ABOVE its line in ITS file (the rule
        // of the batch, Lsp.Patch.ZonaDelCambio): it moved by the change of
        // the WHOLE file, and a change BELOW shifted the line - COMMIT
        // COMPLETE on the wrong line (tenth review)
        Deltas2 := TDictionary<string, Integer>.Create;
        var Lineas: TArray<Integer>;
        SetLength(Lineas, C.Ops.Count);
        for I := 0 to C.Ops.Count - 1 do
          Lineas[I] := C.Ops[I].AtLine;
        begin
          for I := 0 to C.Ops.Count - 1 do
          begin
            Op := C.Ops[I];
            Op.AtLine := Lineas[I];
            // Una excepcion a mitad (una carpeta que no se puede crear, un
            // fichero que alguien tiene abierto) es un fallo como otro
            // cualquiera: se saltaba la restauracion de las copias y lo
            // anterior quedaba aplicado (revision 27-sep-2026, medido)
            var Ok := False;
            try
              // antes de cada paso: lo que otro proceso cambio entre medias no
              // se lo lleva el deshacer (TFotoDeFicheros.Vigila)
              Foto.Vigila(Op.Path);
              if Op.Kind = opMove then
                Foto.Vigila(Op.Dest);
              var AntesL := LineasDeFichero(Op.Path);
              Before := Length(AntesL);
              Ok := ApplyOne(Op, Err);
              // contar las lineas de DESPUES tambien lee el fichero, y otro
              // proceso lo puede tener: dentro del mismo try, o la excepcion
              // salia sin deshacer nada (tercera revision, medido)
              if Ok then
              begin
                // lo que ESTE paso dejo: lo unico que el deshacer puede
                // dar por suyo (Lsp.Guard.TFotoDeFicheros.Anota)
                Foto.Anota(Op.Path);
                if Op.Kind = opMove then
                  Foto.Anota(Op.Dest);
                var DespuesL := LineasDeFichero(Op.Path);
                After := Length(DespuesL);
                if After <> Before then
                begin
                  var Acc := 0;
                  Deltas2.TryGetValue(Op.Path.ToLower, Acc);
                  Deltas2.AddOrSetValue(Op.Path.ToLower, Acc + (After - Before));
                  // las siguientes de ESTE fichero: solo lo que queda por
                  // debajo de lo que cambio este paso se mueve
                  var Desde, Delta: Integer;
                  ZonaDelCambio(AntesL, DespuesL, Desde, Delta);
                  for var J := I + 1 to C.Ops.Count - 1 do
                    if SameText(C.Ops[J].Path, Op.Path) then
                      Lineas[J] := LineaTrasCambio(Lineas[J], Desde, Delta);
                end;
              end;
            except
              on E: Exception do
              begin
                Ok := False;
                Err := MsgExcepcion(E.ClassName, E.Message);
              end;
            end;
            if not Ok then
            begin
              Applied := False;
              N := I + 1;
              Break;
            end;
          end;
        end;
        // Counts BEFORE dropping the changeset: GSets owns it, so Remove
        // FREES C and reading C.Ops.Count afterwards returned 0 - the
        // commit said "0 operaciones aplicadas" having applied 16 (field
        // report 2026-08-24). Never read a freed object.
        OpCount := C.Ops.Count;
        FileCount := Foto.Cuantos;
        // What actually changed, file by file. delphi_edit has always
        // answered with an audit of its own edit; commit answered with two
        // numbers, so after a 16-operation batch nobody could tell WHICH
        // files moved without going to look (field round 7).
        // Per FILE, not per operation. The delta belongs to the file, and
        // printing it next to every operation that touched it made two edits
        // of one file look like twice the change - and put a "+79" next to a
        // DELETE (measured 2026-08-25). Operations are listed, the numbers
        // are the file's.
        Audit := TStringBuilder.Create;
        Seen := TStringList.Create;
        try
          Seen.CaseSensitive := False;
          for Op in C.Ops do
          begin
            if Seen.IndexOf(Op.Path) < 0 then
              Seen.Add(Op.Path);
          end;
          for var FPath in Seen do
          begin
            var Kinds := '';
            for Op in C.Ops do
              if SameText(Op.Path, FPath) then
                Kinds := Kinds + IfThen(Kinds <> '', ' + ', '') + KindName(Op.Kind);
            var D := 0;
            Deltas2.TryGetValue(FPath.ToLower, D);
            Audit.AppendLine(Format('  %s: %s%s',
              [MaskDriveText('', FPath), Kinds,
               IfThen(D = 0, MsgText(SF_CHSET_MISMO_NUMERO_LINEAS),
                 MsgFmt(SF_CHSET_LINEAS_EN_TOTAL_FMT,
                   [IfThen(D > 0, '+', ''), D]))]));
          end;
          AuditText := Audit.ToString.TrimRight;
        finally
          Seen.Free;
          Audit.Free;
        end;
        if not Applied then
        begin
          // el deshacer no lanza (Lsp.Guard.TFotoDeFicheros): el changeset
          // se cierra SIEMPRE; antes una restauracion que fallaba lo dejaba
          // abierto, ocupando uno de los huecos durante 30 minutos
          var NoVolvio := Foto.Restaura;
          GSets.Remove(Id);
          Result := MsgConCausa(SR_CHANGESET_ROLLED_BACK_FMT, Err, [N, OpCount, Err]);
          if NoVolvio <> '' then
            Result := MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Err]);
          Exit;
        end;
        GSets.Remove(Id);
        // nada cambio en disco (ediciones que ya decian lo que dice el
        // fichero): se dice, sin prometer copias que no hay
        if Foto.Cambiados = 0 then
          Exit(MsgFmt(SN_CHANGESET_SIN_CAMBIOS_FMT, [OpCount]));
        Exit(MsgFmt(SN_CHANGESET_COMMITTED_FMT,
          [OpCount, FileCount, AuditText]));
      finally
        LeaveFileEdit;
        Changed.Free;
        Deltas2.Free; // nil-safe: TObject.Free checks Self
      end;
    end;

    Result := MsgText(SR_CHANGESET_CMD);
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GSets := TObjectDictionary<string, TChangeset>.Create([doOwnsValues]);

finalization
  GSets.Free;
  GLock.Free;

end.
