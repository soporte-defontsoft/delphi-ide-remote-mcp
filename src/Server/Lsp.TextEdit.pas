unit Lsp.TextEdit;

{ delphi_textedit engine: SAFE editing of plain-text NON-Delphi files (docs,
  web assets, scripts, config: .md .txt .html .js .css .sql .py .bat .ini
  .json .yml .xml - ANY plain text, it is a DENYLIST not a whitelist) with the same
  discipline as Lsp.Patch - one-full-line unique anchor with hints and atline
  tie-break, real encoding preserved (UTF-8 +/- BOM / ANSI / UTF-16 / UTF-32), dominant EOL
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

{ Lo que FMX dice de un .style que se acaba de escribir con exito (STYLE-055
  si no lo carga; '' si lo carga, si AResultado es una negativa o no es un
  .style). Pregunta al conversor, un proceso: NUNCA con el cerrojo de
  escritura cogido - quien lo tiene por encima (el commit de un changeset) la
  pide al soltarlo (V173f de la 1.23.1). }
function NotaDeEstiloFmx(const APath, AResultado: string): string;

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
  Lsp.Mascara,
  Lsp.Styles;       // IgnoradoPorFmx: lo que FMX hace con un .style escrito

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
  // un proyecto del IDE: delphi_config, con el MISMO texto que delphi_edit
  if EsRutaDeProyecto(APath) then
    Exit(MsgFmt(SR_EDIT_FICHERO_DE_PROYECTO_FMT, [TPath.GetFileName(APath)]));
  // lo del motor de Pascal (EL predicado de delphi_edit: fuentes y designers)
  if EsFicheroDeDelphi(APath) then
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
  // el normalizador de todos (Lsp.Patch.ConSalto): un CR suelto tambien; el
  // salto pedido, por su lector (SaltoPedido, A38)
  Text := ConSalto(A.Content, SaltoPedido(A.Eol));
  EolName := NombreDelSalto(SaltoPedido(A.Eol));
  // la codificacion en que nace, la de todo el que crea (Lsp.Patch.
  // EncDeFicheroNuevo, A21): un texto, UTF-8 sin BOM; un manifiesto del IDE,
  // con el
  var Enc := EncDeFicheroNuevo(A.Path);
  PatchSaveText(A.Path, Text, Enc);
  // Report the encoding as a later delphi_read will DETECT it: pure ASCII
  // content is indistinguishable from ANSI (no high bytes to tell them
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
     EtiquetaDeCodificacion(EncKindOf(Enc), IsAscii(Text)), // LA etiqueta (Lsp.Patch, A41)
     EolName, Length(TFile.ReadAllBytes(A.Path))]);
end;

function DoEditLine(const A: TTextEditArgs): string;
var
  EncNm, Text, Eol: string;
  Lines, NewLines: TArray<string>;
  Matches: TArray<Integer>;
  Target: Integer;
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
  Lines := LineasDelTexto(Text); // sin la fantasma del salto final (Lsp.Patch)
  // Un ancla vacia o de solo blancos: la regla de delphi_edit (EDIT-060). Aqui
  // casaba con TODAS las lineas en blanco (un old "   " llegaba desde el
  // changeset) y la gemela la negaba. Solo vale para borrar una linea EN
  // BLANCO por su numero, sin old (P3-L9): la regla y su negativa son las de
  // delphi_edit (Lsp.Patch.LineaEnBlancoDenegada)
  if A.OldLine.Trim = '' then
  begin
    // ...y UNA: un rango (toline) sin un ancla de texto no (M-3 del revisor)
    if A.DeleteLine and (A.ToLine > 0) then
      Exit(MsgText(SR_EDIT_RANGO_SIN_OLD));
    if not (A.DeleteLine and (A.AtLine > 0)) then
      Exit(MsgText(SR_EDIT_ANCLA_ESTA_VACIA_SOLO));
    Result := LineaEnBlancoDenegada(Lines, Length(Lines), A.AtLine,
      TPath.GetFileName(A.Path));
    if Result <> '' then
      Exit;
  end;

  // el ancla de una linea, por LA regla de las dos tools (LineaEsLaDelAncla)
  Matches := LineasDondeCasaElAncla(Lines, A.OldLine);

  if Length(Matches) = 0 then
    // La negativa es la de delphi_edit, su gemela: UN texto
    // (Lsp.Patch.AnclaPerdida). Aqui ya se ensenaban las lineas que lo
    // contienen y alli no; ahora las dos dicen lo mismo.
    Exit(AnclaPerdida(Lines, A.OldLine, TPath.GetFileName(A.Path)));

  // cual de ellas: LA eleccion y LAS negativas de las dos tools (Lsp.Patch.
  // LineaElegida); aqui eran otros dos codigos para lo mismo (TEXT-009 y
  // TEXT-002, A15)
  Result := LineaElegida(Matches, A.AtLine, Target);
  if Result <> '' then
    Exit;

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

  // las lineas del rango por las nuevas, y cada linea de fuera con SU salto:
  // unidas todas con el dominante, un fichero mixto salia entero a ese salto
  // (1.18.2). El salto final, el que tenia: lo guarda el compositor
  Text := CambiaLineasEnSuTexto(Text, Target, Cuantas, NewLines, Eol);
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
  // la etiqueta de lo que QUEDO en el disco, por EL detector y EL nombrador
  // (un ASCII sin BOM no es utf8 ni ansi: las dos lo leen igual; A41 de la
  // 1.23). Decia la codificacion LEIDA, y el primer acento de un texto ASCII lo
  // escribe EncAlEscribir en la de uno nuevo de su clase, que puede ser otra
  var Escritos := TFile.ReadAllBytes(A.Path);
  var Etiqueta := EtiquetaDeCodificacion(DetectEnc(Escritos, EsRutaDeDesigner(A.Path)),
    not HayByteAlto(Escritos));

  if Cuantas > 1 then
    Exit(MsgFmt(SK_TEXT_RANGO_VERIFICACION_FMT,
      [Format(IfThen(A.DeleteLine, MsgText(SN_RANGE_DELETED_FMT), MsgText(SN_RANGE_REPLACED_FMT)),
         [Cuantas, Target + 1, Target + Cuantas, TPath.GetFileName(A.Path)]),
       Etiqueta, TrashFolderName,
       EcoNumerado(A.Path, Target, Target + Length(NewLines) + 1)]));
  if A.DeleteLine then
    Exit(MsgFmt(SK_TEXT_OK_BORRADA_LINEA_FMT,
      [Target + 1, TPath.GetFileName(A.Path), Etiqueta, TrashFolderName,
       EcoNumerado(A.Path, Target, Target + 2)]));
  // old sin new deja la linea en blanco: se dice, como delphi_edit (EDIT-089);
  // contestaba "OK line N" (decima revision)
  if (Length(NewLines) = 1) and (NewLines[0] = '') then
    Exit(MsgFmt(SK_TEXT_BLANQUEADA_LINEA_FMT,
      [Target + 1, TPath.GetFileName(A.Path), Etiqueta, TrashFolderName,
       EcoNumerado(A.Path, Target, Target + Length(NewLines) + 1)]));
  Result := MsgFmt(SK_TEXT_OK_LINEA_FMT,
    [Target + 1, TPath.GetFileName(A.Path), Etiqueta, TrashFolderName,
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
      // lo que choca con fragment, por LA escalera (Lsp.Patch, D7)
      var Otros := OtroModoConFragmento(A.HasOld, A.OldLine, A.DeleteLine, A.ToLine,
        IfThen(A.CreateFile_, 'create', ''));
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
    // delete, por LA regla de las dos gemelas (Lsp.Patch.DeleteDeLineaDenegado):
    // aqui faltaba lo de new, y la linea se borraba tirandolo
    if A.DeleteLine then
    begin
      Result := DeleteDeLineaDenegado(A.HasOld, A.OldLine, A.NewText, A.AtLine);
      if Result <> '' then
        Exit;
    end
    else if not A.HasOld then
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
      SignificadoDeOldNew(AOld, ANew, A.HasOld, A.HasNew); // UNA regla (D7)
      A.AtLine := AAtLine;
      A.ToLine := AToLine;
      A.DeleteLine := ADelete;
      Result := TextEditNucleo(A);
    end);
end;


{ Un .style escrito por aqui no pasa por el juez de delphi_styles set
  (STYLE-053, que niega antes de escribir): se pregunta a FMX DESPUES de
  escribir y se dice si no lo carga (Hermes, rondas de la 1.21.0: lint lo
  veia despues). Solo lo escrito con exito; una negativa, nada. }
function NotaDeEstiloFmx(const APath, AResultado: string): string;
var
  Ignorado: TArray<string>;
  NoCarga: string;
begin
  Result := '';
  if EsFallo(AResultado) or not EsRutaDeEstilo(APath) then
    Exit;
  // con el cerrojo de alguien por encima (el commit de un changeset): el
  // conversor paraba todas las escrituras, y el lector de avisos del commit
  // perdia la nota; la pide el al soltarlo (V173f de la 1.23.1, medido)
  if EnCerrojoDeEscritura then
    Exit;
  if IgnoradoPorFmx(APath, Ignorado, NoCarga) and (NoCarga <> '') then
    Result := #10 + MsgFmt(SN_TEXTEDIT_STYLE_FMX_NO_CARGA_FMT, [NoCarga]);
end;

function ExecuteTextEdits(const APath, AEditsJson: string): string;
begin
  EnterFileEdit;
  try
    Result := TextEditsNucleo(APath, AEditsJson);
  finally
    LeaveFileEdit;
  end;
  Result := Result + NotaDeEstiloFmx(APath, Result);
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
  if not A.Ensayo then // (un ensayo no escribe: nada que preguntar a FMX)
    Result := Result + NotaDeEstiloFmx(A.Path, Result);
end;

end.
