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
    Ensayo: Boolean;      // todo menos escribir (el preview de un changeset)
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
  Lsp.Patch,
  Lsp.Casa,
  Lsp.Codificacion, // IsAscii
  Lsp.Mascara;

// Las extensiones de otras tools (fuentes y designers de delphi_edit, los de
// proyecto del IDE / delphi_create) son las listas del motor: SOURCE_EXTS,
// DESIGNER_EXTS y PROJECT_EXTS de Lsp.Patch (aqui habia una copia; decima)

// IsAscii vive en Lsp.Codificacion (4.1 de la 1.18.0: habia otra en linea)


// LeadingWhite vive en Lsp.Patch, con la regla de la sangria de las dos tools

function ExtGate(const APath: string): string;
var
  Ext: string;
begin
  Result := '';
  Ext := LowerCase(TPath.GetExtension(APath));
  // lo del motor de Pascal es EL predicado de delphi_edit (fuentes y designers)
  if EsDelMotorPascal(APath) or MatchText(Ext, PROJECT_EXTS) then
    Exit(MsgFmt(SR_TEXT_FICHERO_DELPHI_FUENTES_DESIGNERS_FMT, [Ext]));
end;

function DoCreate(const A: TTextEditArgs): string;
var
  Dir, Text, EolName, EncVacio: string;
begin
  // create=true sobre una CARPETA salia "atomic rename failed" (INTERNAL)
  Result := CarpetaEnVezDeFichero(A.Path);
  if Result <> '' then
    Exit;
  Result := EolDesconocido(A.Eol);
  if Result <> '' then
    Exit;
  if TFile.Exists(A.Path) then
  begin
    // vacio (o solo blancos): no hay ancla posible, se dice que camino hay
    try
      if PatchLoadText(A.Path, EncVacio).Trim = '' then
        Exit(MsgFmt(SR_TEXT_YA_EXISTE_VACIO_FMT, [A.Path]));
    except
      // no se puede leer: la negativa de siempre
    end;
    Exit(MsgFmt(SR_TEXT_YA_EXISTE_NUNCA_SOBREESCRIBE_FMT, [A.Path]));
  end;
  Dir := TPath.GetDirectoryName(A.Path);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    CrearCarpeta(Dir);
  // Line endings are explicit: the JSON channel often delivers LF-only text,
  // so CRLF (the Windows default here) is applied unless 'lf' is asked for.
  // el normalizador de todos (Lsp.Patch.ConSalto): un CR suelto tambien
  if SameText(A.Eol, 'lf') then
  begin
    Text := ConSalto(A.Content, #10);
    EolName := 'LF';
  end
  else
  begin
    Text := ConSalto(A.Content, #13#10);
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
  Result := MsgFmt(SK_TEXT_CREADO_ENCODING_FINALES_FMT,
    [MaskDriveText('', A.Path),
     IfThen(IsAscii(Text), MsgText(SF_TEXT_ASCII_COMPATIBLES), 'utf8'),
     EolName, Length(TFile.ReadAllBytes(A.Path))]);
end;

function DoEditLine(const A: TTextEditArgs): string;
var
  EncNm, Text, Eol, S: string;
  Lines, NewLines: TArray<string>;
  Matches: TArray<Integer>;
  I, Target: Integer;
  Sb: TStringBuilder;
  EndsWithEol: Boolean;
begin
  // una carpeta decia "no existe; creala con create=true" - y el agente que
  // obedecia recibia un INTERNAL
  Result := CarpetaEnVezDeFichero(A.Path);
  if Result <> '' then
    Exit;
  if not TFile.Exists(A.Path) then
    Exit(NoEsFichero(A.Path, MsgFmt(SR_TEXT_NO_EXISTE_CREARLO_FMT, [A.Path])));
  // La regla "esto no es texto" es LooksBinaryBytes (Lsp.Patch), la misma de
  // delphi_read: aqui habia una copia con otra ventana y sin UTF-16.
  if LooksBinaryBytes(TFile.ReadAllBytes(A.Path)) then
    Exit(MsgFmt(SR_TEXT_PARECE_BINARIO_FMT, [TPath.GetFileName(A.Path)]));
  // El gemelo de la negativa de delphi_edit, y por eso comparten el texto:
  // decian cosas distintas de la misma regla, y la de aqui ni siquiera
  // mencionaba que en "edits" el ancla SI puede ser un bloque.
  if TieneSalto(A.OldLine) then
    Exit(MsgText(SR_PATCH_ANCHOR_MULTILINE));

  Text := PatchLoadText(A.Path, EncNm);
  var Antes := Text; // para saber si la edicion cambia algo
  Eol := SaltoDominante(Text); // el de todos (Lsp.Patch)
  EndsWithEol := TieneSaltoFinal(Text); // un CR suelto tambien ("uno\rdos\r" lo perdia)
  Lines := LineasDelTexto(Text); // sin la fantasma del salto final (Lsp.Patch)

  // One-full-line anchor: trimmed comparison, so indentation may be omitted.
  Matches := LineasDondeCasaElAncla(Lines, A.OldLine, False); // la regla del motor

  if Length(Matches) = 0 then
    // La negativa es la de delphi_edit, su gemela: UN texto
    // (Lsp.Patch.AnclaPerdida). Aqui ya se ensenaban las lineas que lo
    // contienen y alli no; ahora las dos dicen lo mismo.
    Exit(AnclaPerdida(Lines, A.OldLine, TPath.GetFileName(A.Path)));

  Target := -1;
  // Un atline que no es el de la unica ocurrencia se rechaza, como en
  // delphi_edit: se ignoraba y se editaba la otra linea (quinta revision)
  if (Length(Matches) = 1) and (A.AtLine <= 0) then
    Target := Matches[0]
  else
  begin
    if A.AtLine <= 0 then
    begin
      S := '';
      for I in Matches do
        S := S + IntToStr(I + 1) + ' ';
      Exit(MsgFmt(SR_TEXT_ANCLA_APARECE_LINEAS_FMT,
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
      Exit(MsgFmt(SR_TEXT_ATLINE_NINGUNA_OCURRENCIAS_FMT,
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

  // Replacement, con LA regla de la sangria que el ancla dejo fuera, la de
  // las dos tools (Lsp.Patch.SangraComoLaLinea: aqui vivia una copia propia,
  // distinta de la de delphi_edit - 6-oct-2026).
  if A.DeleteLine then
    SetLength(NewLines, 0)  // la linea se va entera: ni una vacia queda
  else
    NewLines := SangraComoLaLinea(Lines[Target], A.OldLine,
      LineasDeNew(A.NewText)); // la regla del salto final, una

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
  // Nada cambia: ni se escribe ni se copia (la gemela de delphi_edit, UN texto)
  if Text = Antes then
    Exit(MsgFmt(SN_EDIT_SIN_CAMBIOS_FMT, [Target + 1, TPath.GetFileName(A.Path)]));

  try
    PatchSaveText(A.Path, Text, EncNm, A.Ensayo); // backup + atomic + same encoding (o el ensayo)
  except
    on E: Exception do
      Exit(MsgEnvuelve(SR_TEXT_AL_CODIFICAR_FMT, E.Message));
  end;
  if A.Ensayo then
    Exit(''); // nada escrito: nada que ensenar

  if Cuantas > 1 then
    Exit(MsgFmt(SK_TEXT_RANGO_VERIFICACION_FMT,
      [Format(IfThen(A.DeleteLine, MsgText(SN_RANGE_DELETED_FMT), MsgText(SN_RANGE_REPLACED_FMT)),
         [Cuantas, Target + 1, Target + Cuantas, TPath.GetFileName(A.Path)]),
       EncNm, TrashFolderName,
       EcoNumerado(A.Path, Target, Target + Length(NewLines) + 1)]));
  if A.DeleteLine then
    Exit(MsgFmt(SK_TEXT_OK_BORRADA_LINEA_FMT,
      [Target + 1, TPath.GetFileName(A.Path), EncNm, TrashFolderName,
       EcoNumerado(A.Path, Target, Target + 2)]));
  // old sin new deja la linea en blanco: se dice, como delphi_edit (EDIT-089);
  // contestaba "OK line N" (decima revision)
  if (Length(NewLines) = 1) and (NewLines[0] = '') then
    Exit(MsgFmt(SK_TEXT_BLANQUEADA_LINEA_FMT,
      [Target + 1, TPath.GetFileName(A.Path), EncNm, TrashFolderName,
       EcoNumerado(A.Path, Target, Target + Length(NewLines) + 1)]));
  Result := MsgFmt(SK_TEXT_OK_LINEA_FMT,
    [Target + 1, TPath.GetFileName(A.Path), EncNm, TrashFolderName,
     EcoNumerado(A.Path, Target, Target + Length(NewLines) + 1)]);
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
      Exit(MsgFmt(SR_RANGE_WRONG_MODE_FMT, ['create']));
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
      Exit(MsgText(SR_TEXT_DELETE_TRUE_NECESITA_OLD));
    if not A.HasOld then
      Exit(MsgText(SR_TEXT_FALTA_ANCLA_OLD_ESTA));
    Result := DoEditLine(A);
  except
    on E: Exception do
      Result := MsgExcepcion(E.ClassName, E.Message);
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
    Exit(NoEsFichero(APath, MsgFmt(SR_TEXT_NO_EXISTE_CREARLO_FMT, [APath])));
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
