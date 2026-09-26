unit Lsp.TextEdit;

{ delphi_textedit engine: SAFE editing of plain-text NON-Delphi files (docs,
  web assets, scripts, config: .md .txt .html .js .css .sql .py .bat .ini
  .json .yml .xml - ANY plain text, it is a DENYLIST not a whitelist) with the same
  discipline as Lsp.Patch - one-full-line unique anchor with hints and atline
  tie-break, real encoding preserved (UTF-8 +/- BOM / CP1252 / UTF-16), dominant EOL
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
    ToLine: Integer;   // 1-based LAST line of the range; 0 = just the anchor
    DeleteLine: Boolean;  // DELETE: remove the anchored line entirely
    Fragment: string;     // modo fragmento: un trozo de la linea AtLine
    CreateFile_: Boolean; // CREATE: new file (never overwrites)
    Content: string;      // CREATE: initial content (may be empty)
    Eol: string;          // CREATE: 'lf' = LF; anything else = CRLF (default)
  end;

function ExecuteTextEdit(const A: TTextEditArgs): string;

{ VARIAS ediciones sobre ESTE MISMO fichero, en una sola llamada y TODO O
  NADA, igual que delphi_edit: un array JSON de objetos con old, new, atline
  delete y occurrence, aplicado EN ORDEN. El ancla puede ser UNA linea o un
  BLOQUE de varias seguidas, que se sustituye entero. Si una falla, el
  fichero vuelve byte a byte
  a como estaba y se dice cual fallo.

  Por que: sin esto, cambiar un comentario de tres lineas costaba TRES
  llamadas, y entre una y otra el fichero quedaba a medias (medido el
  2026-09-20 usando este servidor como agente). }
function ExecuteTextEdits(const APath, AEditsJson: string): string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.IOUtils,
  System.Math,
  System.JSON,
  Lsp.Guard,
  Lsp.Texts,
  Lsp.Patch;

const
  // These belong to other tools: Delphi sources/designers to delphi_edit,
  // project files to the IDE / delphi_create.
  DELPHI_EXTS: array [0 .. 7] of string = ('.pas', '.dpr', '.dpk', '.inc',
    '.dfm', '.fmx', '.dproj', '.groupproj');

function IsAscii(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if Ord(C) > 127 then
      Exit(False);
  Result := True;
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
  Dir, Text, EolName: string;
begin
  if TFile.Exists(A.Path) then
    Exit('RECHAZADO: ' + A.Path + ' ya existe. Esta tool nunca sobreescribe; ' +
      'edita con old/new.');
  Dir := TPath.GetDirectoryName(A.Path);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    CrearCarpeta(Dir);
  // Line endings are explicit: the JSON channel often delivers LF-only text,
  // so CRLF (the Windows default here) is applied unless 'lf' is asked for.
  Text := A.Content.Replace(#13#10, #10).Replace(#13, #10);
  if SameText(A.Eol, 'lf') then
    EolName := 'LF'
  else
  begin
    Text := Text.Replace(#10, #13#10);
    EolName := 'CRLF';
  end;
  // New text files are UTF-8 without BOM.
  PatchSaveText(A.Path, Text, 'utf8');
  // Report the encoding as a later delphi_read will DETECT it: pure ASCII
  // content is indistinguishable from CP1252 (no high bytes to tell them
  // apart), and claiming "utf8" there confused agents in the field test.
  // La ruta va por el ENMASCARADOR a mano. Esta tool esta EXENTA del filtro
  // de salida (MaskDriveText la salta entera, porque su eco es contenido
  // LITERAL del disco y un ancla enmascarada no casaria con el fichero), asi
  // que lo poco que compone ella misma tiene que taparse aqui: esta linea no
  // es eco, es la unica de la respuesta que lleva una ruta NUESTRA, y salia
  // con la letra REAL del servidor - inservible ademas para el cliente, que
  // solo puede pasar unidades virtuales. Su gemela delphi_edit nunca fallo
  // porque imprime el NOMBRE del fichero: asi es como derivan dos gemelas
  // (medido 2026-09-21, bateria test_round40).
  Result := Format('CREADO %s  encoding=%s  finales=%s  bytes=%d',
    [MaskDriveText('', A.Path),
     IfThen(IsAscii(Text), 'ascii (utf8/cp1252 compatibles)', 'utf8'),
     EolName, Length(TFile.ReadAllBytes(A.Path))]);
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
  // La regla "esto no es texto" es LooksBinaryBytes (Lsp.Patch), la misma de
  // delphi_read: aqui habia una copia con otra ventana y sin UTF-16.
  if LooksBinaryBytes(TFile.ReadAllBytes(A.Path)) then
    Exit('RECHAZADO: ' + TPath.GetFileName(A.Path) +
      ' parece BINARIO (bytes nulos). Esta tool es solo para texto.');
  // El gemelo de la negativa de delphi_edit, y por eso comparten el texto:
  // decian cosas distintas de la misma regla, y la de aqui ni siquiera
  // mencionaba que en "edits" el ancla SI puede ser un bloque.
  if A.OldLine.Contains(#10) or A.OldLine.Contains(#13) then
    Exit(SR_PATCH_ANCHOR_MULTILINE);

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

  // EL RANGO: con toline el ancla es la PRIMERA linea de un tramo que acaba
  // ahi, incluida. Las reglas las pone RangoHasta, en Lsp.Patch, que es de
  // donde tira tambien el motor de Pascal: un rango no tiene nada de Pascal
  // ni nada de Markdown, y escribirlo dos veces es como nacieron los bugs
  // gemelos de este mes.
  var Fin: Integer;
  var MalRango := RangoHasta(A.Path, Target, A.ToLine, Length(Lines), Fin);
  if MalRango <> '' then
    Exit(MalRango);
  var Cuantas := Fin - Target + 1;

  // Replacement. If the anchor was given without its indentation, the
  // original prefix is preserved on the first replacement line.
  if A.DeleteLine then
    SetLength(NewLines, 0)  // la linea se va entera: ni una vacia queda
  else
    NewLines := LineasDeNew(A.NewText); // la regla del salto final, una
  if (not A.DeleteLine) and (Length(NewLines) > 0) and (LeadingWhite(A.OldLine) = '') and
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
      if (I > Target) and (I <= Fin) then
        Continue; // resto del rango: se lo lleva la edicion
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

  if Cuantas > 1 then
    Exit(Format('%s  encoding=%s  (backup en %s\)'#10 +
      'Verificacion (releido de disco):'#10'%s',
      [Format(IfThen(A.DeleteLine, SN_RANGE_DELETED_FMT, SN_RANGE_REPLACED_FMT),
         [Cuantas, Target + 1, Target + Cuantas, TPath.GetFileName(A.Path)]),
       EncNm, '__delphi-patch',
       ReadNumbered(A.Path, Target, Target + Length(NewLines) + 1)]));
  if A.DeleteLine then
    Exit(Format('OK borrada la linea %d de %s  encoding=%s  (backup en %s\)'#10 +
      'Verificacion (releido de disco):'#10'%s',
      [Target + 1, TPath.GetFileName(A.Path), EncNm, '__delphi-patch',
       ReadNumbered(A.Path, Target, Target + 2)]));
  Result := Format('OK linea %d de %s  encoding=%s  (backup en %s\)'#10 +
    'Verificacion (releido de disco):'#10'%s',
    [Target + 1, TPath.GetFileName(A.Path), EncNm, '__delphi-patch',
     ReadNumbered(A.Path, Target, Target + Length(NewLines) + 1)]);
end;

{ El trabajo; ExecuteTextEdit lo envuelve en el cerrojo de escritura. }
function TextEditNucleo(const A: TTextEditArgs): string;
begin
  try
    Result := WriteTargetDenied(A.Path); // jaula + carpetas muertas, UNA puerta
    if Result <> '' then
      Exit;
    Result := ExtGate(A.Path);
    if Result <> '' then
      Exit;
    // delphi_edit refused the trash and sent non-Delphi text here; this tool
    // did not know the rule, so the trash was writable after all. Now the
    // rule is part of WriteTargetDenied, above - no tool can forget it.
    // Antes del reparto de modos: "toline" solo significa algo con un ancla,
    // y un parametro que se traga en silencio es como se cree haber borrado
    // algo que sigue ahi.
    if (A.ToLine > 0) and A.CreateFile_ then
      Exit(Format(SR_RANGE_WRONG_MODE_FMT, ['create']));
    // MODO FRAGMENTO: el mismo resolvedor que delphi_edit, y despues el
    // motor de siempre con la linea COMPLETA (ver Lsp.Patch.FragmentoALinea).
    if A.Fragment <> '' then
    begin
      var Otros := '';
      if A.HasOld and (A.OldLine <> '') then Otros := 'old'
      else if A.DeleteLine then Otros := 'delete'
      else if A.ToLine > 0 then Otros := 'toline'
      else if A.CreateFile_ then Otros := 'create';
      var AF := A;
      var LineaVieja, LineaNueva: string;
      Result := FragmentoALinea(A.Path, A.Fragment, A.NewText, A.AtLine,
        Otros, LineaVieja, LineaNueva);
      if Result <> '' then
        Exit;
      AF.OldLine := LineaVieja;
      AF.NewText := LineaNueva;
      AF.HasOld := True;
      AF.HasNew := True;
      Exit(DoEditLine(AF));
    end;
    if A.CreateFile_ then
      Exit(DoCreate(A));
    if A.DeleteLine and not A.HasOld then
      Exit('RECHAZADO: delete=true necesita "old": la linea que se va.');
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

{ El trabajo de la tanda; ExecuteTextEdits lo envuelve en el cerrojo. }
function TextEditsNucleo(const APath, AEditsJson: string): string;
begin
  // Los gates SI son propios: esta tool vigila extensiones que la otra no, y
  // al reves. Lo que era comun -parseo, occurrence, bucle, todo o nada, eco-
  // vive ahora en Lsp.Patch.AplicaTanda y lo comparten las dos. Aqui queda
  // solo como se aplica UNA edicion suelta sobre texto que no es Pascal.
  Result := WriteTargetDenied(APath); // jaula + carpetas muertas, UNA puerta
  if Result <> '' then
    Exit;
  Result := ExtGate(APath);
  if Result <> '' then
    Exit;
  if not TFile.Exists(APath) then
    Exit('RECHAZADO: no existe ' + APath + '. Para crearlo usa create=true.');
  Result := AplicaTanda(APath, AEditsJson,
    function(const AOld, ANew: string; AAtLine, AToLine: Integer;
      ADelete: Boolean): string
    var
      A: TTextEditArgs;
    begin
      A := Default(TTextEditArgs);
      A.Path := APath;
      A.OldLine := AOld;
      A.NewText := ANew;
      A.HasOld := AOld <> '';
      A.HasNew := (ANew <> '') or A.HasOld;
      A.AtLine := AAtLine;
      A.ToLine := AToLine;
      A.DeleteLine := ADelete;
      Result := TextEditNucleo(A);
    end);
end;


function ExecuteTextEdits(const APath, AEditsJson: string): string;
begin
  EnterFileEdit;
  try
    Result := TextEditsNucleo(APath, AEditsJson);
  finally
    LeaveFileEdit;
  end;
end;

function ExecuteTextEdit(const A: TTextEditArgs): string;
begin
  // Dentro del cerrojo de escritura, igual que delphi_edit: leer-modificar-
  // escribir no es atomico, y dos agentes sobre el mismo fichero perdian
  // ediciones dando exito (medido 2026-09-20, bateria de concurrencia).
  EnterFileEdit;
  try
    Result := TextEditNucleo(A);
  finally
    LeaveFileEdit;
  end;
end;

end.
