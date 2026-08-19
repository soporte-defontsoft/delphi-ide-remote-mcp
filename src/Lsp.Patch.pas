unit Lsp.Patch;

{ Safe Delphi source editing engine - the port of an internally
  battle-tested tool (30+ measured test rounds against several LLMs, small
  and large). Every gate below exists because a model was measured breaking
  a file through that exact hole. Design rules:

  - Anchor = ONE full existing line (leading indentation may be omitted);
    never substrings, never multi-line anchors, never whole-file rewrites.
  - Encoding is detected (UTF-8 BOM / strict UTF-8 / CP1252) and preserved;
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
    DeleteLine: Boolean;  // true = remove the anchored line entirely
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

{ Encoding-correct numbered read (also serves the remote file toolset). }
function ReadNumbered(const APath: string; AFrom, ATo: Integer): string;

{ Encoding-preserving load/save for other engines (scaffolder): text is
  decoded with the real encoding; save re-encodes with the SAME one, makes
  the pre-edit backup and writes atomically. AEncName as in delphi_read. }
function PatchLoadText(const APath: string; out AEncName: string): string;
procedure PatchSaveText(const APath, AText, AEncName: string);

{ Encoding for NEW Delphi files, honouring the IDE's configured default
  (Tools > Options > Editor): 'utf8-bom' when the IDE is set to UTF-8,
  'cp1252' when ANSI. }
function NewFileEncName: string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.SyncObjs,
  System.Generics.Collections,
  System.RegularExpressions,
  Winapi.Windows,
  Lsp.Guard,
  Lsp.Discovery;

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

type
  TEncKind = (ekUtf8Bom, ekUtf8, ekCp1252);

  TMetrics = record
    Bytes, CR, LF, CRLF, Loose, High, Corruption: Integer;
  end;

function EncName(K: TEncKind): string;
begin
  case K of
    ekUtf8Bom: Result := 'utf8-bom';
    ekUtf8: Result := 'utf8';
  else
    Result := 'cp1252';
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
begin
  Result := Default(TMetrics);
  Result.Bytes := Length(B);
  // The UTF-8 BOM is filesystem plumbing, not text: counting its 3 bytes as
  // "acentos" confused the accounting shown to the agent (measured).
  Start := 0;
  if (Length(B) >= 3) and (B[0] = $EF) and (B[1] = $BB) and (B[2] = $BF) then
    Start := 3;
  for I := Start to High(B) do
  begin
    if B[I] = 13 then
      Inc(Result.CR)
    else if B[I] = 10 then
    begin
      Inc(Result.LF);
      if (I > 0) and (B[I - 1] = 13) then
        Inc(Result.CRLF);
    end
    else if B[I] > 127 then
      Inc(Result.High);
    if (I + 2 <= High(B)) and (B[I] = $EF) and (B[I + 1] = $BF) and (B[I + 2] = $BD) then
      Inc(Result.Corruption);
  end;
  Result.Loose := Result.LF - Result.CRLF;
end;

function Summary(const M: TMetrics): string;
begin
  Result := Format('bytes=%d lineas=%d CRLF=%d LFsueltos=%d acentos=%d corrupcion=%d',
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

procedure AtomicWrite(const APath: string; const B: TBytes);
var
  Tmp: string;
begin
  Tmp := TPath.Combine(TPath.GetDirectoryName(APath),
    '.' + TPath.GetFileName(APath) + '.delphi-patch-tmp');
  TFile.WriteAllBytes(Tmp, B);
  if not MoveFileEx(PChar(Tmp), PChar(APath), MOVEFILE_REPLACE_EXISTING) then
  begin
    TFile.Delete(Tmp);
    raise Exception.CreateFmt('rename atomico fallido (%d)', [GetLastError]);
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
        TDirectory.Delete(D, True);
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
  DayDir := TPath.Combine(Dir, FormatDateTime('yyyymmdd', Now));
  Dest := TPath.Combine(DayDir, TPath.GetFileName(APath));
  if TFile.Exists(Dest) then
    Exit('ya existia (' + Dest + ')');
  TDirectory.CreateDirectory(DayDir);
  TFile.Copy(APath, Dest);
  PurgeOldBackups(Dir);
  Result := Dest;
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
  if AEncName = 'utf8-bom' then
    K := ekUtf8Bom
  else if AEncName = 'utf8' then
    K := ekUtf8
  else
    K := ekCp1252;
  if TFile.Exists(APath) then
    BackupFile(APath); // new files have nothing to back up
  AtomicWrite(APath, EncodeText(AText, K));
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
  Cut: string;
begin
  Denied := ReadPathDenied(APath); // reading may enter the library zone
  if Denied <> '' then
    Exit(Denied);
  if not TFile.Exists(APath) then
    Exit('RECHAZADO: no existe ' + APath);
  B := TFile.ReadAllBytes(APath);
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
  Result := Format('%s  encoding=%s  finales=%s  %s'#10 +
    'Lineas %d-%d de %d (formato numero|contenido: el ancla se copia desde justo despues de la barra):'#10'%s%s',
    [TPath.GetFileName(APath), EncName(K), Eol, Summary(M), IniL, FinL,
     Length(Lines), Body, Cut]);
end;

// -------------------------------------------------------------------------
// The edit pipeline (also the primitive that the insert modes call).
// -------------------------------------------------------------------------

function DoEdit(const APath, AOld, ANew: string; AAtLine: Integer;
  AIsDesigner: Boolean; ADelete: Boolean = False): string; forward;

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
      Result := PathDenied(A.Path);
      if Result <> '' then
        Exit;
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

      PLower := A.Path.ToLower.Replace('/', '\');
      if PLower.Contains('\' + BACKUP_SUB + '\') then
        Exit('RECHAZADO: ' + BACKUP_SUB + '\ es la carpeta de copias de seguridad de esta tool. Copias muertas: no se leen, no se editan. El fichero vivo esta un nivel mas arriba.');
      if PLower.Contains('\__history\') or PLower.Contains('\__recovery\') then
        Exit('RECHAZADO: __history\ y __recovery\ son copias muertas del IDE. El fichero vivo esta en la carpeta del proyecto.');

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
        TDirectory.CreateDirectory(TPath.GetDirectoryName(TPath.GetFullPath(A.Path)));
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
      if IsDesigner and (Length(B) >= 4) and (B[0] = $54) and (B[1] = $50) and
         (B[2] = $46) and (B[3] = $30) then
        Exit(Format('RECHAZADO: %s es un %s BINARIO (firma TPF0). No es texto y no se puede editar asi. ' +
          'Abrelo en el IDE ("View as Text") o entrega el cambio a una persona.',
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
            Exit(Format('RESTAURAR %s desde %s: aun NO he hecho nada.'#10 +
              'Estas %d lineas del fichero ACTUAL no estan en la copia y SE PERDERAN:'#10'%s'#10 +
              'Si de verdad quieres restaurar, repite con confirm: true.',
              [TPath.GetFileName(A.Path), Src, Losses.Count, Lista]));
          end;

          var PreCopy := TPath.Combine(TPath.Combine(DirBk, FormatDateTime('yyyymmdd', Now)),
            TPath.GetFileName(A.Path) + '.antes-restaurar-' + FormatDateTime('hhnnss', Now));
          TDirectory.CreateDirectory(TPath.GetDirectoryName(PreCopy));
          TFile.Copy(A.Path, PreCopy);
          AtomicWrite(A.Path, BkBytes);
          Exit(Format('RESTAURADO %s desde %s'#10'  ahora: %s'#10 +
            '  OJO: se han perdido %d lineas que tenias escritas. Rehaz y RE-VERIFICA cada tarea de este fichero.'#10 +
            '  (estado previo guardado en %s)',
            [TPath.GetFileName(A.Path), Src, Summary(Measure(TFile.ReadAllBytes(A.Path))),
             Losses.Count, PreCopy]));
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

        var Firma := '';
        for var L in CodeLines do
          if L.Trim <> '' then
          begin
            Firma := L.Trim;
            Break;
          end;
        var MF := TRegEx.Match(Firma,
          '^(procedure|function|constructor|destructor)\s+([A-Za-z_]\w*)\s*([.(;:])?', [roIgnoreCase]);
        if not MF.Success then
          Exit(Format('RECHAZADO: el bloque no empieza por una firma de rutina. Primera linea: |%s|', [Copy(Firma, 1, 80)]));
        if MF.Groups[3].Value = '.' then
          Exit('RECHAZADO: la firma viene CUALIFICADA con clase. Pasala SIN cualificar; con insert:"metodo" la tool pone el prefijo.');

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
              var Decl := Firma;
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
        var IFin := -1;
        for I := IClase + 1 to High(Lines) do
          if Lines[I].Trim.ToLower = 'end;' then
          begin
            IFin := I;
            Break;
          end;
        if IFin = -1 then
          Exit(Format('RECHAZADO: no encuentro el ''end;'' de cierre de la clase %s.', [A.ClassName_]));

        var Secs := TArray<string>.Create('private', 'protected', 'public', 'published',
          'strict private', 'strict protected');
        var IDecl := IFin;
        var Vis := A.Visibility.Trim.ToLower;
        if Vis = 'default' then
          Vis := 'published';
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
                  if S2 = TrimL then IsSec := True;
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
                if S2 = TrimL then IsSec := True;
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
            if S2 = TrimL.ToLower then IsSec := True;
          if (TrimL <> '') and not IsSec then
          begin
            Sangria := Copy(Lines[I], 1, Length(Lines[I]) - Length(Lines[I].TrimLeft));
            Break;
          end;
        end;
        var DeclLinea := Sangria + Firma;
        if not DeclLinea.EndsWith(';') then DeclLinea := DeclLinea + ';';
        var AnclaDecl := Lines[IDecl - 1];
        var R1 := DoEdit(A.Path, AnclaDecl, AnclaDecl + #10 + DeclLinea, IDecl, False);
        if not R1.StartsWith('ESCRITO') then
          Exit(Format('INSERT metodo - FALLO en la mitad 1 (declaracion en la clase %s):'#10'%s', [A.ClassName_, R1]));
        var FirmaCual := TRegEx.Replace(Firma,
          '^(procedure|function|constructor|destructor)(\s+)', '$1$2' + A.ClassName_ + '.', [roIgnoreCase]);
        var Primera := True;
        for I := 0 to High(CodeLines) do
          if Primera and (CodeLines[I].Trim = Firma) then
          begin
            CodeLines[I] := FirmaCual;
            Primera := False;
          end;
        var R2 := DoEdit(A.Path, FrontLine, string.Join(#10, CodeLines) + #10#10 + FrontLine, 0, False);
        if not R2.StartsWith('ESCRITO') then
          Exit('INSERT metodo - mitad 1 (declaracion) ESCRITA pero FALLO en la mitad 2 (implementacion). ' +
            'El fichero ha quedado A MEDIAS: restaura con restore:true y reintenta.'#10 + R2);
        Exit(Format('INSERT metodo en %s: la tool ha hecho las DOS mitades.'#10 +
          '--- Mitad 1: declaracion ''%s'' dentro de la clase ---'#10'%s'#10 +
          '--- Mitad 2: implementacion ''%s'' en la frontera legal ---'#10'%s',
          [A.ClassName_, DeclLinea.Trim, R1, Copy(FirmaCual, 1, 70), R2]));
      end;

      // ---------- DELETE LINE ----------
      if A.DeleteLine then
      begin
        if not A.HasOld or (A.OldLine = '') then
          Exit('RECHAZADO: delete:true necesita "old" con la linea exacta a borrar (copiada de delphi_read).');
        if A.NewText <> '' then
          Exit('RECHAZADO: delete:true no lleva "new": elimina la linea del ancla entera. Para sustituirla usa old+new sin delete.');
        Exit(DoEdit(A.Path, A.OldLine, '', A.AtLine, IsDesigner, True));
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

      Result := DoEdit(A.Path, A.OldLine, A.NewText, A.AtLine, IsDesigner);
    except
      on E: Exception do
        Result := 'ERROR: ' + E.ClassName + ': ' + E.Message;
    end;
  finally
    GLock.Leave;
  end;
end;

function DoEdit(const APath, AOld, ANew: string; AAtLine: Integer;
  AIsDesigner: Boolean; ADelete: Boolean = False): string;
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
    if KH = ekUtf8Bom then
      KH := ekUtf8;
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
    Exit('RECHAZADO: el ancla tiene mas de una linea. Regla: ancla de UNA sola linea.'#10 +
      '- Para CAMBIAR varias lineas: una llamada por linea.'#10 +
      '- Para INSERTAR: ancla en UNA linea existente y en "new" devuelves esa misma linea junto con lo nuevo.');
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

    // The anchor may omit leading indentation: whatever prefix the real line
    // has beyond the anchor is preserved in front of the new text.
    Prefix := Copy(Lines[HitIdx], 1, Length(Lines[HitIdx]) - Length(AOld));
    Replacement := ANew.Replace(#13#10, #10).Replace(#13, #10);
    // Empty replacement (old given + new='') blanks the line - a legitimate
    // edit. Never index Split()[0] on it: '' yields an empty array (measured
    // Access Violation in the field test). Line DELETION is delete:true.
    var NewFirst := '';
    if Replacement <> '' then
      NewFirst := Replacement.Split([#10])[0];
    if ADelete then
    begin
      for I := HitIdx to High(Lines) - 1 do
        Lines[I] := Lines[I + 1];
      SetLength(Lines, Length(Lines) - 1);
    end
    else
      Lines[HitIdx] := Prefix + Replacement;

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
    var Idx := -1;
    if NewFirst <> '' then
    begin
      for I := 0 to High(AfterLines) do
        if AfterLines[I].Contains(NewFirst) then
        begin
          Idx := I;
          Break;
        end;
    end
    else
    begin
      // Blanked or deleted line: the spot is exactly known - show it instead
      // of the confusing "no he sabido localizar" (measured, round 2 C2).
      Idx := HitIdx;
      if Idx > High(AfterLines) then
        Idx := High(AfterLines);
    end;
    if Idx >= 0 then
    begin
      var IniC := Idx - 1;
      if IniC < 0 then IniC := 0;
      var FinC := Idx + 2;
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
    var Salen := HighCount(AOld);
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
      Warnings.Add('(fichero del designer en formato texto: editado, pero lo gobierna el IDE. MENCIONALO en tu informe.)');

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
    if ADelete then
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
