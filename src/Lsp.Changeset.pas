unit Lsp.Changeset;

{ Multi-file TRANSACTIONS over the safe-editing engine - the piece the
  single-file engine could not give: when one operation touches five files
  and the fifth fails, files one to four must not stay changed (today the
  project tools can only REPORT a partial change; measured origin:
  SN_FILE_PARTIAL_FMT). A changeset makes the whole batch land or none of it.

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
  AOldLine, ANewText, AContent: string; AAtLine: Integer; AN: Integer = 0): string;

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

  TSnapshot = record
    Path: string;
    Existed: Boolean;
    Bytes: TBytes;
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
function LineCountOf(const APath: string): Integer;
var
  Enc: string;
begin
  if not TFile.Exists(APath) then
    Exit(0);
  Result := Length(PatchLoadText(APath, Enc).Replace(#13#10, #10).Split([#10]));
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

{ Resolves one edit anchor against the CURRENT text: 1 = unique, 0 = absent,
  >1 = ambiguous (AtLine may pin it). }
function AnchorCount(const AText, ALine: string; AAtLine: Integer): Integer;
var
  Lines: TArray<string>;
  I: Integer;
begin
  Result := 0;
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  if AAtLine > 0 then
  begin
    if (AAtLine <= Length(Lines)) and (Lines[AAtLine - 1] = ALine) then
      Result := 1;
    Exit;
  end;
  for I := 0 to High(Lines) do
    if Lines[I] = ALine then
      Inc(Result);
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

function ApplyOne(const Op: TStagedOp; out AError: string): Boolean;
var
  A: TPatchArgs;
  T: TTextEditArgs;
  R, Enc: string;
begin
  AError := '';
  Result := False;
  case Op.Kind of
    opEdit:
      begin
        // Delphi sources go through the pascal engine; anything else through
        // the plain-text one - a transaction that could not touch a .md or a
        // .json next to the code would be half a transaction (field
        // 2026-08-24).
        if MatchText(TPath.GetExtension(Op.Path),
          ['.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx']) then
        begin
          FillChar(A, SizeOf(A), 0);
          A.Path := Op.Path;
          A.OldLine := Op.OldLine;
          A.NewText := Op.NewText;
          A.HasOld := True;
          A.HasNew := True;
          A.AtLine := Op.AtLine;
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
          R := ExecuteTextEdit(T);
        end;
        Result := not (R.StartsWith('RECHAZADO') or R.StartsWith('ERROR') or
          R.StartsWith('error'));
        if not Result then
          AError := R;
      end;
    opCreate:
      begin
        if TFile.Exists(Op.Path) then
        begin
          AError := 'ya existe ' + Op.Path;
          Exit;
        end;
        TDirectory.CreateDirectory(TPath.GetDirectoryName(Op.Path));
        if MatchText(TPath.GetExtension(Op.Path), ['.pas', '.dpr', '.dpk', '.inc', '.dfm', '.fmx']) then
          Enc := NewFileEncName
        else
          Enc := 'utf8';
        PatchSaveText(Op.Path, Op.Content, Enc);
        Result := True;
      end;
    opDelete:
      begin
        if not TFile.Exists(Op.Path) then
        begin
          AError := 'no existe ' + Op.Path;
          Exit;
        end;
        TFile.Delete(Op.Path); // the snapshot is the way back
        Result := True;
      end;
    opDeleteLine:
      begin
        if not TFile.Exists(Op.Path) then
        begin
          AError := 'no existe ' + Op.Path;
          Exit;
        end;
        var Txt := PatchLoadText(Op.Path, Enc);
        var Eol := IfThen(Txt.Contains(#13#10), #13#10, #10);
        var Ls := Txt.Replace(#13#10, #10).Split([#10]);
        if (Op.AtLine < 1) or (Op.AtLine > Length(Ls)) then
        begin
          AError := Format('la linea %d no existe (%s tiene %d)',
            [Op.AtLine, TPath.GetFileName(Op.Path), Length(Ls)]);
          Exit;
        end;
        if (Op.OldLine <> '') and (Ls[Op.AtLine - 1] <> Op.OldLine) then
        begin
          AError := Format('la linea %d no es la esperada (es "%s")',
            [Op.AtLine, Ls[Op.AtLine - 1]]);
          Exit;
        end;
        Delete(Ls, Op.AtLine - 1, 1);
        PatchSaveText(Op.Path, string.Join(Eol, Ls), Enc);
        Result := True;
      end;
    opMove:
      begin
        if not TFile.Exists(Op.Path) then
        begin
          AError := 'no existe ' + Op.Path;
          Exit;
        end;
        if TFile.Exists(Op.Dest) then
        begin
          AError := 'el destino ya existe: ' + Op.Dest;
          Exit;
        end;
        TDirectory.CreateDirectory(TPath.GetDirectoryName(Op.Dest));
        TFile.Move(Op.Path, Op.Dest);
        Result := True;
      end;
  end;
end;

function ChangesetExecute(const ACommand, AId, AKind, APath, ADest,
  AOldLine, ANewText, AContent: string; AAtLine: Integer; AN: Integer): string;
var
  Cmd, Id, Denied, EncName, Text, Err: string;
  C: TChangeset;
  Op: TStagedOp;
  Ret, Obj: TJSONObject;
  Arr: TJSONArray;
  P: string;
  N, I: Integer;
  Snaps: TList<TSnapshot>;
  Snap: TSnapshot;
  Changed: TList<string>;
  Applied: Boolean;
  OpCount, FileCount, Before, After: Integer;
  Deltas: TDictionary<string, Integer>;
  Deltas2: TDictionary<string, Integer>;  // survives the block that frees Deltas
  Audit: TStringBuilder;
  AuditText: string;
begin
  Cmd := ACommand.Trim.ToLower;
  GLock.Enter;
  try
    Prune;

    if Cmd = 'begin' then
    begin
      if GSets.Count >= MAX_SETS then
        Exit(SR_CHANGESET_TOO_MANY);
      Inc(GSeq); // Now has ~16 ms granularity: two begins can share it
      Id := FormatDateTime('hhnnss', Now) + '-' + IntToStr(GSeq);
      GSets.Add(Id, TChangeset.Create(Id));
      Exit(Format(SN_CHANGESET_BEGUN_FMT, [Id]));
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
          Obj.AddPair('id', Id);
          Obj.AddPair('ops', TJSONNumber.Create(GSets[Id].Ops.Count));
          Obj.AddPair('previewed', TJSONBool.Create(GSets[Id].Previewed));
        end;
        Exit(Ret.ToJSON);
      finally
        Ret.Free;
      end;
    end;

    Id := AId.Trim;
    if (Id = '') or not GSets.TryGetValue(Id, C) then
      Exit(SR_CHANGESET_UNKNOWN);
    C.LastUsed := Now;

    if Cmd = 'rollback' then
    begin
      GSets.Remove(Id);
      Exit(SN_CHANGESET_DISCARDED);
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
        Exit(SR_CHANGESET_KIND);
      if APath.Trim = '' then
        Exit(SR_CHANGESET_NEED_PATH);
      Denied := PathDenied(APath);
      if Denied <> '' then
        Exit(Denied);
      Op.Path := TPath.GetFullPath(APath);
      case Op.Kind of
        opEdit:
          begin
            if (AOldLine = '') then
              Exit(SR_CHANGESET_EDIT_NEEDS);
            Op.OldLine := AOldLine;
            Op.NewText := ANewText;
            Op.AtLine := AAtLine;
            if not WillExist(C, Op.Path) then
              Exit(Format(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
          end;
        opCreate:
          begin
            Op.Content := AContent;
            if WillExist(C, Op.Path) then
              Exit(Format(SR_CHANGESET_VIRT_EXISTS_FMT, [Op.Path]));
          end;
        opDelete:
          if not WillExist(C, Op.Path) then
            Exit(Format(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
        opDeleteLine:
          begin
            // a BLANK line has no usable anchor, so atline decides; old is
            // optional and, when given, must match that line (field
            // 2026-08-24: no way to remove the blank lines a cleanup leaves)
            if not WillExist(C, Op.Path) then
              Exit(Format(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
            if AAtLine <= 0 then
              Exit(SR_CHANGESET_DELLINE_NEEDS);
            Op.AtLine := AAtLine;
            Op.OldLine := AOldLine;
          end;
        opMove:
          begin
            if ADest.Trim = '' then
              Exit(SR_CHANGESET_NEED_DEST);
            Denied := PathDenied(ADest);
            if Denied <> '' then
              Exit(Denied);
            Op.Dest := TPath.GetFullPath(ADest);
            if not WillExist(C, Op.Path) then
              Exit(Format(SR_CHANGESET_VIRT_MISSING_FMT, [Op.Path]));
            if WillExist(C, Op.Dest) then
              Exit(Format(SR_CHANGESET_VIRT_DEST_FMT, [Op.Dest]));
          end;
      end;
      C.Ops.Add(Op);
      Exit(Format(SN_CHANGESET_STAGED_FMT,
        [KindName(Op.Kind), Op.Path, C.Ops.Count]));
    end;

    // Taking one operation back out. Without this, a single mistyped anchor
    // meant rolling back the whole batch and staging everything again
    // (field round 8). n = the number `preview` prints; 0 = the last one.
    if (Cmd = 'unstage') or (Cmd = 'undo') then
    begin
      if C.Ops.Count = 0 then
        Exit(SR_CHANGESET_EMPTY);
      N := AN;
      if N = 0 then
        N := C.Ops.Count;
      if (N < 1) or (N > C.Ops.Count) then
        Exit(Format(SR_CHANGESET_UNSTAGE_N_FMT, [N, C.Ops.Count]));
      Op := C.Ops[N - 1];
      C.Ops.Delete(N - 1);
      C.Previewed := False;
      Exit(Format(SN_CHANGESET_UNSTAGED_FMT,
        [N, KindName(Op.Kind), Op.Path, C.Ops.Count]));
    end;

    if Cmd = 'preview' then
    begin
      if C.Ops.Count = 0 then
        Exit(SR_CHANGESET_EMPTY);
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
            // staged over a file an earlier op of this same batch creates:
            // there is nothing to anchor against until commit runs
            Obj.AddPair('anchor', 'pendiente');
            Obj.AddPair('note', SN_CHANGESET_PREVIEW_VIRTUAL);
            Continue;
          end;
          if Op.Kind = opEdit then
          begin
            Text := PatchLoadText(Op.Path, EncName);
            case AnchorCount(Text, Op.OldLine, Op.AtLine) of
              1: Obj.AddPair('anchor', 'ok');
              0: begin
                   Obj.AddPair('anchor', 'NO ENCONTRADA');
                   Inc(N);
                 end;
            else
              Obj.AddPair('anchor', 'AMBIGUA (fija atline)');
              Inc(N);
            end;
          end;
        end;
        C.Fingerprints.Clear;
        for P in TouchedPaths(C) do
          C.Fingerprints.AddOrSetValue(P, FingerprintBytes(P));
        Ret.AddPair('files', TJSONNumber.Create(C.Fingerprints.Count));
        Ret.AddPair('unresolved', TJSONNumber.Create(N));
        C.Previewed := N = 0;
        if C.Previewed then
          Ret.AddPair('note', SN_CHANGESET_PREVIEW_OK)
        else
          Ret.AddPair('note', SN_CHANGESET_PREVIEW_BAD);
        Exit(Ret.ToJSON);
      finally
        Ret.Free;
      end;
    end;

    if Cmd = 'commit' then
    begin
      if C.Ops.Count = 0 then
        Exit(SR_CHANGESET_EMPTY);
      if not C.Previewed then
        Exit(SR_CHANGESET_NOT_PREVIEWED);
      // 1. nothing may have moved since the preview
      Changed := TList<string>.Create;
      Snaps := TList<TSnapshot>.Create;
      try
        for P in C.Fingerprints.Keys do
          if FingerprintBytes(P) <> C.Fingerprints[P] then
            Changed.Add(P);
        if Changed.Count > 0 then
          Exit(Format(SR_CHANGESET_FILE_CHANGED_FMT,
            [string.Join('; ', Changed.ToArray)]));
        // 2. byte snapshots of everything BEFORE the first change
        for P in TouchedPaths(C) do
        begin
          Snap.Path := P;
          Snap.Existed := TFile.Exists(P);
          if Snap.Existed then
            Snap.Bytes := TFile.ReadAllBytes(P)
          else
            Snap.Bytes := nil;
          Snaps.Add(Snap);
        end;
        // 3. apply in order; any failure = restore every snapshot
        Applied := True;
        Err := '';
        N := 0;
        // Earlier operations MOVE the lines later ones pin with atline: the
        // preview resolves against the original text, the commit applies
        // against the mutated one (field 2026-08-24). Every op is rebased
        // by what the previous ones did to ITS file.
        Deltas := TDictionary<string, Integer>.Create;
        Deltas2 := TDictionary<string, Integer>.Create;
        try
          for I := 0 to C.Ops.Count - 1 do
          begin
            Op := C.Ops[I];
            if (Op.AtLine > 0) and Deltas.ContainsKey(Op.Path.ToLower) then
              Op.AtLine := Op.AtLine + Deltas[Op.Path.ToLower];
            Before := LineCountOf(Op.Path);
            if not ApplyOne(Op, Err) then
            begin
              Applied := False;
              N := I + 1;
              Break;
            end;
            After := LineCountOf(Op.Path);
            if After <> Before then
            begin
              var Acc := 0;
              Deltas.TryGetValue(Op.Path.ToLower, Acc);
              Deltas.AddOrSetValue(Op.Path.ToLower, Acc + (After - Before));
              Deltas2.AddOrSetValue(Op.Path.ToLower, Acc + (After - Before));
            end;
          end;
        finally
          Deltas.Free;
        end;
        // Counts BEFORE dropping the changeset: GSets owns it, so Remove
        // FREES C and reading C.Ops.Count afterwards returned 0 - the
        // commit said "0 operaciones aplicadas" having applied 16 (field
        // report 2026-08-24). Never read a freed object.
        OpCount := C.Ops.Count;
        FileCount := Snaps.Count;
        // What actually changed, file by file. delphi_edit has always
        // answered with an audit of its own edit; commit answered with two
        // numbers, so after a 16-operation batch nobody could tell WHICH
        // files moved without going to look (field round 7).
        Audit := TStringBuilder.Create;
        try
          for Op in C.Ops do
          begin
            var D := 0;
            Deltas2.TryGetValue(Op.Path.ToLower, D);
            Audit.AppendLine(Format('  %s %s%s', [KindName(Op.Kind),
              MaskDriveText('delphi_changeset', Op.Path),
              IfThen(D = 0, '', Format('  (%s%d lineas)',
                [IfThen(D > 0, '+', ''), D]))]));
          end;
          AuditText := Audit.ToString.TrimRight;
        finally
          Audit.Free;
        end;
        if not Applied then
        begin
          for Snap in Snaps do
            if Snap.Existed then
              TFile.WriteAllBytes(Snap.Path, Snap.Bytes)
            else if TFile.Exists(Snap.Path) then
              TFile.Delete(Snap.Path);
          GSets.Remove(Id);
          Exit(Format(SR_CHANGESET_ROLLED_BACK_FMT, [N, OpCount, Err]));
        end;
        GSets.Remove(Id);
        Exit(Format(SN_CHANGESET_COMMITTED_FMT,
          [OpCount, FileCount, AuditText]));
      finally
        Snaps.Free;
        Changed.Free;
        Deltas2.Free;
      end;
    end;

    Result := SR_CHANGESET_CMD;
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
