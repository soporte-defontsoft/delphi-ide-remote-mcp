unit Lsp.TextEdit;

{ delphi_textedit engine: SAFE editing of plain-text NON-Delphi files (docs,
  web assets, scripts, config: .md .txt .html .js .css .sql .py .bat .ini
  .json .yml .xml - ANY plain text, it is a DENYLIST not a whitelist) with the same
  discipline as Lsp.Patch - one-full-line unique anchor with hints and atline
  tie-break, real encoding preserved (UTF-8 +/- BOM / CP1252), dominant EOL
  preserved, automatic backup, atomic write - but without the Pascal semantic
  gates. Delphi sources and designer files are refused (delphi_edit is their
  path) and so are project files and binaries. }

interface

type
  TTextEditArgs = record
    Path: string;
    OldLine: string;   // EDIT: the exact line to replace (ONE full line)
    NewText: string;   // EDIT: replacement, may be several lines
    HasOld: Boolean;
    HasNew: Boolean;
    AtLine: Integer;   // tie-break when the anchor repeats
    CreateFile_: Boolean; // CREATE: new file (never overwrites)
    Content: string;      // CREATE: initial content (may be empty)
  end;

function ExecuteTextEdit(const A: TTextEditArgs): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  Lsp.Guard,
  Lsp.Patch;

const
  // These belong to other tools: Delphi sources/designers to delphi_edit,
  // project files to the IDE / delphi_create.
  DELPHI_EXTS: array [0 .. 7] of string = ('.pas', '.dpr', '.dpk', '.inc',
    '.dfm', '.fmx', '.dproj', '.groupproj');

function LooksBinary(const APath: string): Boolean;
var
  B: TBytes;
  I, Limit: Integer;
begin
  B := TFile.ReadAllBytes(APath);
  Limit := Length(B);
  if Limit > 65536 then
    Limit := 65536;
  for I := 0 to Limit - 1 do
    if B[I] = 0 then
      Exit(True);
  Result := False;
end;

function DominantEol(const T: string): string;
var
  I, Crlf, Lf: Integer;
begin
  Crlf := 0;
  Lf := 0;
  for I := 1 to Length(T) do
    if T[I] = #10 then
      if (I > 1) and (T[I - 1] = #13) then
        Inc(Crlf)
      else
        Inc(Lf);
  if Lf > Crlf then
    Result := #10
  else
    Result := #13#10; // Windows default, also for files with no EOL yet
end;

function LeadingWhite(const S: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and ((S[I] = ' ') or (S[I] = #9)) do
    Inc(I);
  Result := Copy(S, 1, I - 1);
end;

function ExtGate(const APath: string): string;
var
  Ext, E: string;
begin
  Result := '';
  Ext := LowerCase(TPath.GetExtension(APath));
  for E in DELPHI_EXTS do
    if E = Ext then
      Exit(Format('RECHAZADO: "%s" es un fichero Delphi. Para fuentes y ' +
        'designers usa delphi_edit; los ficheros de proyecto (.dproj) los ' +
        'mantiene el IDE / delphi_create.', [Ext]));
end;

function DoCreate(const A: TTextEditArgs): string;
var
  Dir: string;
begin
  if TFile.Exists(A.Path) then
    Exit('RECHAZADO: ' + A.Path + ' ya existe. Esta tool nunca sobreescribe; ' +
      'edita con old/new.');
  Dir := TPath.GetDirectoryName(A.Path);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  // New text files are UTF-8 without BOM; the agent's line breaks are kept.
  PatchSaveText(A.Path, A.Content, 'utf8');
  Result := Format('CREADO %s  encoding=utf8  bytes=%d',
    [A.Path, Length(TFile.ReadAllBytes(A.Path))]);
end;

function DoEditLine(const A: TTextEditArgs): string;
var
  EncNm, Text, Eol, Prefix, S: string;
  Lines, NewLines: TArray<string>;
  Matches: TArray<Integer>;
  I, Target: Integer;
  Sb: TStringBuilder;
  EndsWithEol: Boolean;
  Hints: string;
begin
  if not TFile.Exists(A.Path) then
    Exit('RECHAZADO: no existe ' + A.Path + '. Para crearlo usa create=true.');
  if LooksBinary(A.Path) then
    Exit('RECHAZADO: ' + TPath.GetFileName(A.Path) +
      ' parece BINARIO (bytes nulos). Esta tool es solo para texto.');
  if A.OldLine.Contains(#10) or A.OldLine.Contains(#13) then
    Exit('RECHAZADO: old debe ser UNA sola linea completa (copiala de ' +
      'delphi_read, todo lo que hay tras la barra |).');

  Text := PatchLoadText(A.Path, EncNm);
  Eol := DominantEol(Text);
  EndsWithEol := Text.EndsWith(#10);
  Lines := Text.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if EndsWithEol and (Length(Lines) > 0) and (Lines[High(Lines)] = '') then
    SetLength(Lines, Length(Lines) - 1); // drop the phantom line after final EOL

  // One-full-line anchor: trimmed comparison, so indentation may be omitted.
  SetLength(Matches, 0);
  for I := 0 to High(Lines) do
    if Trim(Lines[I]) = Trim(A.OldLine) then
      Matches := Matches + [I];

  if Length(Matches) = 0 then
  begin
    Hints := '';
    if Trim(A.OldLine) <> '' then
      for I := 0 to High(Lines) do
        if (Hints.CountChar(#10) < 5) and Lines[I].Contains(Trim(A.OldLine)) then
          Hints := Hints + Format('  %d|%s'#10, [I + 1, Lines[I]]);
    if Hints <> '' then
      Hints := #10'Lineas que CONTIENEN ese texto (el ancla debe ser la linea COMPLETA):'#10 + Hints;
    Exit('RECHAZADO: el ancla no aparece en ' + TPath.GetFileName(A.Path) +
      '. Copia la linea exacta de delphi_read.' + Hints);
  end;

  Target := -1;
  if Length(Matches) = 1 then
    Target := Matches[0]
  else
  begin
    if A.AtLine <= 0 then
    begin
      S := '';
      for I in Matches do
        S := S + IntToStr(I + 1) + ' ';
      Exit(Format('RECHAZADO: el ancla aparece en %d lineas (%s). Repite con ' +
        'atline=<numero> para elegir la ocurrencia exacta.',
        [Length(Matches), S.Trim]));
    end;
    for I in Matches do
      if I + 1 = A.AtLine then
        Target := I;
    if Target < 0 then
    begin
      S := '';
      for I in Matches do
        S := S + IntToStr(I + 1) + ' ';
      Exit(Format('RECHAZADO: atline=%d no es ninguna de las ocurrencias (%s).',
        [A.AtLine, S.Trim]));
    end;
  end;

  // Replacement. If the anchor was given without its indentation, the
  // original prefix is preserved on the first replacement line.
  NewLines := A.NewText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if (Length(NewLines) > 0) and (LeadingWhite(A.OldLine) = '') and
     (LeadingWhite(NewLines[0]) = '') then
  begin
    Prefix := LeadingWhite(Lines[Target]);
    for I := 0 to High(NewLines) do
      if NewLines[I] <> '' then
        NewLines[I] := Prefix + NewLines[I];
  end;

  Sb := TStringBuilder.Create;
  try
    for I := 0 to High(Lines) do
    begin
      if I = Target then
      begin
        for S in NewLines do
        begin
          Sb.Append(S);
          Sb.Append(Eol);
        end;
      end
      else
      begin
        Sb.Append(Lines[I]);
        Sb.Append(Eol);
      end;
    end;
    Text := Sb.ToString;
  finally
    Sb.Free;
  end;
  if not EndsWithEol then
    SetLength(Text, Length(Text) - Length(Eol));

  try
    PatchSaveText(A.Path, Text, EncNm); // backup + atomic + same encoding
  except
    on E: Exception do
      Exit('RECHAZADO al codificar: ' + E.Message);
  end;

  Result := Format('OK linea %d de %s  encoding=%s  (backup en %s\)'#10 +
    'Verificacion (releido de disco):'#10'%s',
    [Target + 1, TPath.GetFileName(A.Path), EncNm, '__delphi-patch',
     ReadNumbered(A.Path, Target, Target + Length(NewLines) + 1)]);
end;

function ExecuteTextEdit(const A: TTextEditArgs): string;
begin
  try
    Result := PathDenied(A.Path);
    if Result <> '' then
      Exit;
    Result := ExtGate(A.Path);
    if Result <> '' then
      Exit;
    if A.CreateFile_ then
      Exit(DoCreate(A));
    if not A.HasOld then
      Exit('RECHAZADO: falta el ancla (old). Esta tool no reescribe ficheros ' +
        'enteros: una linea existente + su sustituto, o create=true para ' +
        'ficheros nuevos.');
    Result := DoEditLine(A);
  except
    on E: Exception do
      Result := 'RECHAZADO: ' + E.Message;
  end;
end;

end.
