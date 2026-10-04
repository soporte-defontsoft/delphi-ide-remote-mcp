unit Lsp.TestRunner;

// delphi_test: the difference between "it compiles" and "it works".
//
// Measured 2026-08-25, twice and independently: an agent working only through
// the MCP can write code, compile it and never find out whether it does what
// it should. `delphi_build` answers "0 errors"; nothing answers "17 passed, 1
// failed". The sandbox even had a console test runner sitting there that
// nobody could execute. That is the wall this unit removes.
//
// What counts as a test project (discovery, in this order):
// - a .dpr whose uses clause mentions DUnitX (the framework), or
// - a .dpr marked {$APPTYPE CONSOLE} whose name says Test/Tests/Spec.
// Anything else is not a test project and is not run.
//
// Running it is EXECUTION, and execution is opt-in on this server. It has its
// own switch, AllowTests en el workspace, and it is the ONLY execution this
// machine offers (delphi_run, arbitrary binaries, was retired 2026-09-23:
// one door). The binary is built here, from a project of the jail, and run in
// a Windows container of its own on a COPY of its output folder in the
// server's house (Lsp.Sandbox, 2-oct-2026: the low-integrity label it had
// before did not hold on network folders), with a timeout - and only ever
// the artifact delphi_build declared.
//
// The result is STRUCTURED, which is the whole point: an agent must be able
// to act on "which test failed and why" without parsing prose. Two dialects
// are understood - DUnitX's own summary, and the plain PASS/FAIL + ExitCode
// convention a hand-written console runner uses (the one in the sandbox).


interface

uses
  System.JSON;

{ Test projects under APath (a folder, or a .dproj/.dpr itself). }
function TestDiscover(const APath: string): TJSONObject;

{ Builds (unless ANoBuild) and runs the test project, returning the
  structured outcome. AFilter, when the framework supports it, narrows. }
function TestRun(const AProject, AConfig, AFilter, APlatform: string;
  ATimeoutMs: Integer; ANoBuild: Boolean): TJSONObject;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math,
  Lsp.Guard,
  Lsp.Dproj,
  Lsp.BuildRunner,
  Lsp.References,
  Lsp.Patch,
  Lsp.Pascal, // DirectivasPascal: el lector de directivas
  Lsp.Sandbox, // la jaula: un contenedor por ejecucion
  Lsp.Texts,
  System.Character,
  System.Diagnostics,
  MCPServer.Logger;

type
  TTestKind = (tkNone, tkDUnitX, tkConsole);

{ What kind of test project a .dpr is (tkNone = not one). }
function KindOf(const ADpr: string; out AWhy: string): TTestKind;
var
  Text, Name: string;
begin
  AWhy := '';
  Result := tkNone;
  if not TFile.Exists(ADpr) then
    Exit;
  try
    Text := PatchLoadText(ADpr, Name);
  except
    Exit;
  end;
  Name := TPath.GetFileNameWithoutExtension(ADpr);
  // en su CODIGO: un DUnitX nombrado en un comentario no hace un proyecto de
  // tests (censo del lexico, 2-oct-2026)
  if TRegEx.IsMatch(CodigoPascal(Text), '(?i)\bDUnitX\.') then
  begin
    AWhy := MsgText(SF_TEST_USA_DUNITX);
    Exit(tkDUnitX);
  end;
  // por el lector de directivas: una comentada no hace de un programa una consola
  var Consola := False;
  for var D in DirectivasPascal(Text) do
    if (D.Nombre = 'APPTYPE') and SameText(D.Argumento.Trim, 'CONSOLE') then
      Consola := True;
  if Consola and
     TRegEx.IsMatch(Name, '(?i)(test|tests|spec)') then
  begin
    AWhy := MsgText(SF_TEST_CONSOLA_NOMBRE_TEST);
    Exit(tkConsole);
  end;
end;

function KindName(K: TTestKind): string;
begin
  case K of
    tkDUnitX: Result := 'DUnitX';
    tkConsole: Result := MsgText(SF_TEST_CONSOLA_PASS_FAIL);
  else
    Result := '';
  end;
end;

function TestDiscover(const APath: string): TJSONObject;
var
  Denied, Dir, F, Why: string;
  Arr: TJSONArray;
  Obj: TJSONObject;
  K: TTestKind;
  N: Integer;
begin
  Result := TJSONObject.Create;
  try
  Denied := ReadPathDenied(APath);
  if Denied <> '' then
  begin
    Result.AddPair('error', Denied);
    Exit;
  end;
  if TFile.Exists(APath) then
    Dir := TPath.GetDirectoryName(APath)
  else
    Dir := APath;
  if not TDirectory.Exists(Dir) then
  begin
    Result.AddPair('error', MsgFmt(SR_TEST_NOPATH_FMT, [APath]));
    Exit;
  end;
  Arr := TJSONArray.Create;
  Result.AddPair('projects', Arr);
  N := 0;
  for F in TDirectory.GetFiles(Dir, '*.dpr', TSearchOption.soAllDirectories) do
  begin
    if SkipIdeArtifacts(F) then
      Continue;
    K := KindOf(F, Why);
    if K = tkNone then
      Continue;
    Inc(N);
    Obj := TJSONObject.Create;
    Arr.AddElement(Obj);
    Obj.AddPair('project', TPath.ChangeExtension(F, '.dproj'));
    Obj.AddPair('dpr', F);
    Obj.AddPair('framework', KindName(K));
    Obj.AddPair('why', Why);
    Obj.AddPair('hasDproj', TJSONBool.Create(
      TFile.Exists(TPath.ChangeExtension(F, '.dproj'))));
    if K = tkConsole then
      Obj.AddPair('countsFormat', MsgText(SN_TEST_CONSOLE_FORMAT));
  end;
  Result.AddPair('total', TJSONNumber.Create(N));
  if N = 0 then
    Result.AddPair('note', MsgText(SN_TEST_NONE))
  else
  begin
    Result.AddPair('note', MsgText(SN_TEST_DISCOVER_NOTE));
    Result.AddPair('runsOn', MsgText(SN_TEST_RUNS_ON));
  end;
  except
    // una excepcion a medio camino dejaba sin liberar lo que se devuelve
    // (el patron del Result de Rename, menor de la ronda 16)
    Result.Free;
    raise;
  end;
end;

{ DUnitX prints, among other things:
    Tests Found   : 12
    Tests Passed  : 11
    Tests Failed  : 1
    Tests Errored : 0   (a test that RAISED: listed under "Tests With Errors")
  and lists failures. The hand-written console convention is one line per
  check: "PASS <name>" / "FAIL <name>", plus ExitCode <> 0 when something
  failed. Both are parsed; whatever is missing stays absent instead of
  invented. }
procedure ParseOutcome(const AOutput: string; AKind: TTestKind;
  AExitCode: Integer; ARet: TJSONObject);
var
  M: TMatch;
  Fails: TJSONArray;
  L: string;
  Found, Passed, Failed, Errored: Integer;
  HasNumbers: Boolean;
  Near: TStringList;
begin
  Found := -1; Passed := -1; Failed := -1; Errored := 0;
  HasNumbers := False;
  Fails := TJSONArray.Create;
  ARet.AddPair('failures', Fails);
  Near := TStringList.Create;
  if AKind = tkDUnitX then
  begin
    M := TRegEx.Match(AOutput, '(?i)Tests?\s+Found\s*:\s*(\d+)');
    if M.Success then begin Found := StrToIntDef(M.Groups[1].Value, -1); HasNumbers := True; end;
    M := TRegEx.Match(AOutput, '(?i)Tests?\s+Passed\s*:\s*(\d+)');
    if M.Success then begin Passed := StrToIntDef(M.Groups[1].Value, -1); HasNumbers := True; end;
    M := TRegEx.Match(AOutput, '(?i)Tests?\s+Failed\s*:\s*(\d+)');
    if M.Success then begin Failed := StrToIntDef(M.Groups[1].Value, -1); HasNumbers := True; end;
    // Un test que LANZA es un error, no un fallo, y DUnitX lo cuenta aparte:
    // sin leerlo, una suite con un test que lanzaba salia 'pass' por las
    // cuentas (Failed: 0), con el ejecutable acabando en 1 (medido el
    // 2-oct-2026 en la mutacion de la 1.10.0: 'pass 16/17' sin fallos)
    M := TRegEx.Match(AOutput, '(?i)Tests?\s+Errored\s*:\s*(\d+)');
    if M.Success then
      Errored := StrToIntDef(M.Groups[1].Value, 0);
    // Los bloques "Failing Tests" y "Tests With Errors" del logger de consola
    // de DUnitX (DUnitX.ResStrs): el nombre del test en una linea y su
    // "Message:" en la siguiente. Sin leerlo, failures venia VACIO con
    // failed=1 (medido el 2026-09-22, el dia que DUnitX se instalo en esta
    // maquina). Aqui ponia "Errored Tests", que DUnitX no escribe: los que
    // lanzaban no salian nunca. "Tests With Memory Leak" cierra, no es fallo.
    var Rojos := TStringList.Create;
    try
      var EnFallos := False;
      for L in AOutput.Replace(#13#10, #10).Split([#10]) do
      begin
        var T := L.Trim;
        if not EnFallos then
        begin
          EnFallos := TRegEx.IsMatch(T, '(?i)^(Failing\s+Tests|Tests\s+With\s+Errors)\s*$');
          Continue;
        end;
        // DUnitX deja una linea EN BLANCO justo despues de "Failing Tests"
        // (medido en la salida cruda): un blanco no cierra el bloque.
        if T = '' then
          Continue;
        if TRegEx.IsMatch(T, '(?i)^(Tests?\s+[a-z]+\s*:|Done\b|Tests\s+With\s+Memory\s+Leak\s*$)') then
        begin
          EnFallos := False;
          Continue;
        end;
        if TRegEx.IsMatch(T, '(?i)^(Failing\s+Tests|Tests\s+With\s+Errors)\s*$') then
          Continue;
        if T.StartsWith('Message:', True) and (Rojos.Count > 0) then
          Rojos[Rojos.Count - 1] := Rojos[Rojos.Count - 1] + ' - ' + T.Substring(8).Trim
        else
          Rojos.Add(T);
      end;
      for var R in Rojos do
        if Fails.Count < 50 then
          Fails.Add(R);
    finally
      Rojos.Free;
    end;
  end;
  if not HasNumbers then
  begin
    // plain PASS/FAIL lines (also present in many DUnitX console outputs)
    Passed := 0; Failed := 0;
    // Case-insensitive, and the common English past forms count too. The old
    // rule was "exactly PASS/OK/FAIL/ERROR, uppercase", while the note said
    // "the first word decides": a runner printing "Fail: email invalido" or
    // "FAILED seis" scored NOTHING, so a red suite came back green (measured
    // 2026-08-25 - the only place this server called broken code working).
    // A word boundary still protects PASSABLE and OKAY from counting.
    for L in AOutput.Replace(#13#10, #10).Split([#10]) do
    begin
      if TRegEx.IsMatch(L, '(?i)^\s*(PASS|PASSED|OK)\b') then
        Inc(Passed)
      else if TRegEx.IsMatch(L, '(?i)^\s*(FAIL|FAILED|ERROR)\b') then
      begin
        Inc(Failed);
        if Fails.Count < 50 then
          Fails.Add(L.Trim);
      end
      else if TRegEx.IsMatch(L, '(?i)^\s*[\[\(<*-]*\s*(PASS|FAIL|OK|ERROR)') then
        // looks like a result and is NOT in the shape that counts: a silent
        // miscount is the worst outcome here, so it gets said out loud
        Near.Add(L.Trim);
    end;
    Found := Passed + Failed;
    HasNumbers := Found > 0;
  end;
  if Found >= 0 then
    ARet.AddPair('total', TJSONNumber.Create(Found));
  if Passed >= 0 then
    ARet.AddPair('passed', TJSONNumber.Create(Passed));
  if Failed >= 0 then
    ARet.AddPair('failed', TJSONNumber.Create(Failed));
  if Errored > 0 then
    ARet.AddPair('errored', TJSONNumber.Create(Errored));
  // The verdict never guesses: with numbers, they decide; without them, the
  // exit code does (0 = green), and we say which one spoke.
  try
    if Near.Count > 0 then
    begin
      ARet.AddPair('linesNotCounted', TJSONNumber.Create(Near.Count));
      ARet.AddPair('linesNotCountedNote', MsgFmt(SN_TEST_NEAR_MISS_FMT,
        [Near.Count, Near[0]]));
    end;
  finally
    Near.Free;
  end;
  if HasNumbers and (Failed >= 0) then
  begin
    ARet.AddPair('result', IfThen((Failed = 0) and (Errored = 0), 'pass', 'fail'));
    ARet.AddPair('verdictFrom', 'counts');
  end
  else
  begin
    ARet.AddPair('result', IfThen(AExitCode = 0, 'pass', 'fail'));
    ARet.AddPair('verdictFrom', 'exitCode');
  end;
end;

const
  // La copia de la salida de un test, en la casa del servidor: con tope
  TOPE_COPIA = Int64(256) * 1024 * 1024;
  // Lo que el test deje vuelve EN LA RESPUESTA, con tope (David, 2-oct-2026):
  // nombre y tamano de todo, y el contenido de los de texto, en CARACTERES
  TOPE_POR_FICHERO = 16 * 1024;
  TOPE_DE_FICHEROS = 64 * 1024;
  TOPE_DE_LECTURA = 4 * 1024 * 1024; // un fichero mayor ni se lee
  // y la lista misma: 100.000 ficheros de un byte la inundaban (revision de
  // la 1.11.0); los que no caben se cuentan
  TOPE_DE_ENTRADAS = 500;

type
  ETopeDeCopia = class(Exception);

{ La foto de la carpeta del contenedor: ruta relativa -> tamano y fecha,
  leidos sin abrir nada (HuellaDeFichero, la de la foto de los escritores).
  Sin cruzar enlaces: si el test planta uno, ni se sigue ni se lee. }
function FotoDe(const ADir: string): TDictionary<string, string>;
var
  Foto: TDictionary<string, string>;
  Base: string;
begin
  Foto := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  Base := IncludeTrailingPathDelimiter(ADir);
  RecorreSinEnlaces(ADir,
    procedure(const APath: string)
    var
      Tam: Int64;
      Fecha: TDateTime;
    begin
      // uno que no se deja mirar no esta en la foto
      if not TDirectory.Exists(APath) and HuellaDeFichero(APath, Tam, Fecha) then
        Foto.AddOrSetValue(APath.Substring(Length(Base)),
          IntToStr(Tam) + '|' + FormatDateTime('yyyymmddhhnnsszzz', Fecha));
    end);
  Result := Foto;
end;

{ Lo que el test ha dejado en su carpeta: lo nuevo o cambiado respecto a
  AAntes, en orden, TOPE_DE_ENTRADAS como mucho (AFuera, los que no caben).
  nil si nada. Con contenido, lo que es texto por LA regla de la casa
  (LooksBinaryBytes, la de delphi_read), no por su extension, cortado en
  caracteres y sin partir un par sustituto; el que viene sin el dice por que
  en "noContent". Agotado el total no se lee nada mas. ARecortado: falta
  texto que podia interesar (cortado, demasiado grande o fuera del total). }
function FicherosDelTest(const ADir: string; AAntes: TDictionary<string, string>;
  out ARecortado: Boolean; out AFuera: Integer): TJSONArray;
var
  Despues: TDictionary<string, string>;
  Nombres: TArray<string>;
  Quedan, Cabe: Integer;
  V, Texto: string;
  O: TJSONObject;
  Tam: Int64;
  B: TArray<Byte>;
begin
  Result := nil;
  ARecortado := False;
  AFuera := 0;
  Despues := FotoDe(ADir);
  try
    Nombres := Despues.Keys.ToArray;
    TArray.Sort<string>(Nombres);
    Quedan := TOPE_DE_FICHEROS;
    for var N in Nombres do
    begin
      if AAntes.TryGetValue(N, V) and (V = Despues[N]) then
        Continue; // estaba y no ha cambiado
      if (Result <> nil) and (Result.Count >= TOPE_DE_ENTRADAS) then
      begin
        Inc(AFuera);
        Continue;
      end;
      if Result = nil then
        Result := TJSONArray.Create;
      O := TJSONObject.Create;
      Result.AddElement(O);
      O.AddPair('name', N);
      Tam := StrToInt64Def(Despues[N].Split(['|'])[0], 0);
      O.AddPair('size', TJSONNumber.Create(Tam));
      // sin contenido, y por que: lo que ya no cabe ni se lee
      if Tam > TOPE_DE_LECTURA then
      begin
        O.AddPair('noContent', 'too-big');
        ARecortado := True;
        Continue;
      end;
      if Quedan <= 0 then
      begin
        O.AddPair('noContent', 'past-total');
        ARecortado := True;
        Continue;
      end;
      try
        B := TFile.ReadAllBytes(TPath.Combine(ADir, N));
      except
        O.AddPair('noContent', 'unreadable');
        Continue;
      end;
      if LooksBinaryBytes(B) then
      begin
        O.AddPair('noContent', 'binary');
        Continue;
      end;
      Texto := DecodeSourceBytes(B);
      Cabe := Min(TOPE_POR_FICHERO, Quedan);
      if Length(Texto) > Cabe then
      begin
        if Texto[Cabe].IsHighSurrogate then
          Dec(Cabe); // el par entero o nada
        Texto := Copy(Texto, 1, Cabe);
        O.AddPair('truncated', TJSONBool.Create(True));
        ARecortado := True;
      end;
      O.AddPair('content', Texto);
      Dec(Quedan, Length(Texto));
    end;
  finally
    Despues.Free;
  end;
end;

{ Corre AExe (con AArgs) en un contenedor POR EJECUCION sobre una COPIA de su
  carpeta de salida en la casa del servidor (Lsp.Sandbox): se crea el
  contenedor, se le da la carpeta vacia, se copia la salida sin .dcu ni .rsm,
  se lanza, se recoge lo que el test haya dejado y se borra todo. False con
  el error ya en ARet si algo de eso no se pudo: falla cerrado, sin
  contenedor no corre. ADuracionMs, lo que corrio el test: sin la copia. }
function CorreEnContenedor(const AExe, AArgs: string; ATimeoutMs: Integer;
  ARet: TJSONObject; out AOutput: string; out AExitCode: Cardinal;
  out ATimedOut: Boolean; out AFicheros: TJSONArray;
  out ARecortado: Boolean; out AFuera: Integer; out ADuracionMs: Int64): Boolean;
var
  AC: TContenedor;
  Etapa: string;
  Err: Cardinal;
  NoSeguidos: TArray<string>;
  Copiado: Int64;
  Antes: TDictionary<string, string>;
  Reloj: TStopwatch;
begin
  Result := False;
  ADuracionMs := 0;
  AFuera := 0;
  AOutput := '';
  AExitCode := 0;
  ATimedOut := False;
  AFicheros := nil;
  ARecortado := False;
  Err := CreaContenedor(AC);
  if Err <> 0 then
  begin
    ARet.AddPair('error', MsgFmt(SR_TEST_CONTENEDOR_FMT,
      [IntToHex(Err, 8), SysErrorMessage(Err)]));
    Exit;
  end;
  Etapa := ServerTempDir('test-' + FragmentoUnico);
  Antes := nil;
  try
    CrearCarpeta(Etapa);
    Err := PreparaCarpetaDelContenedor(AC, Etapa);
    if Err <> 0 then
    begin
      ARet.AddPair('error', MsgFmt(SR_TEST_CONTENEDOR_FMT,
        [IntToHex(Err, 8), SysErrorMessage(Err)]));
      Exit;
    end;
    Copiado := 0;
    try
      CopiaArbol(TPath.GetDirectoryName(AExe), Etapa, False, NoSeguidos, True,
        function(const APath: string): Boolean
        var
          Tam: Int64;
          Fecha: TDateTime;
        begin
          // ni las carpetas del servidor (CarpetasDesechables), ni los .dcu
          // (son de compilar), ni los .rsm (los simbolos del depurador
          // remoto: 18 MB en un test vacio, medido)
          if TDirectory.Exists(APath) then
            Exit(MatchText(TPath.GetFileName(APath), CarpetasDesechables));
          Result := MatchText(TPath.GetExtension(APath), ['.dcu', '.rsm']);
          // lo que SI se copia, se cuenta: el copiador pregunta esto lo
          // ultimo, por lo que va a copiar de verdad
          // (un enlace que se sigue copia lo de DETRAS: se cuenta eso, no
          // la entrada del enlace, que mide 0)
          if not Result and HuellaDeFichero(
            IfThen(EsEnlace(APath), RealPath(APath), APath), Tam, Fecha) then
          begin
            Inc(Copiado, Tam);
            if Copiado > TOPE_COPIA then
              raise ETopeDeCopia.Create('');
          end;
        end);
    except
      on ETopeDeCopia do
      begin
        ARet.AddPair('error', MsgFmt(SR_TEST_COPIA_TOPE_FMT,
          [TOPE_COPIA div (1024 * 1024)]));
        Exit;
      end;
      // un enlace roto, un fichero que otro tiene cerrado: con su etiqueta,
      // no como un fallo interno sin nombre (revision de la 1.11.0)
      on E: Exception do
      begin
        ARet.AddPair('error', MsgFmt(SR_TEST_COPIA_FMT, [E.Message]));
        Exit;
      end;
    end;
    Antes := FotoDe(Etapa);
    Reloj := TStopwatch.StartNew;
    try
      AOutput := RunCapturedEnContenedor(Format('"%s"%s',
        [TPath.Combine(Etapa, TPath.GetFileName(AExe)), AArgs]), Etapa, AC,
        ATimeoutMs, AExitCode, ATimedOut);
    except
      on E: ETestNoConfinado do
      begin
        ARet.AddPair('error', E.Message); // ya es TEST-032, sin codigo residual
        Exit;
      end;
      on E: EOSError do
      begin
        ARet.AddPair('error', MsgFmt(SR_TEST_LANZAR_FMT,
          [E.ErrorCode, SysErrorMessage(E.ErrorCode)]));
        Exit;
      end;
    end;
    ADuracionMs := Reloj.ElapsedMilliseconds;
    AFicheros := FicherosDelTest(Etapa, Antes, ARecortado, AFuera);
    Result := True;
  finally
    Antes.Free;
    BorraContenedor(AC);
    try
      BorraArbol(Etapa);
    except
      // una copia huerfana se va con la temporal en el proximo arranque, y
      // queda apuntada, como el contenedor que Windows no borra
      on E: Exception do
        try
          TLogger.Warning(MsgFmt(SL_TEST_COPIA_NO_BORRADA_FMT, [Etapa, E.Message]));
        except
        end;
    end;
  end;
end;

function TestRun(const AProject, AConfig, AFilter, APlatform: string;
  ATimeoutMs: Integer; ANoBuild: Boolean): TJSONObject;
var
  Denied, Dpr, Dproj, Why, Cfg, Exe, Output, Args, Plat: string;
  K: TTestKind;
  Build: TJSONObject;
  Info: TDprojInfo;
  ExitCode: Cardinal;
  TimedOut, Recortado: Boolean;
  Ficheros: TJSONArray;
  Fuera: Integer;
  DuracionMs: Int64;
  Tail: TArray<string>;
  I, From: Integer;
  Sb: TStringBuilder;
begin
  Result := TJSONObject.Create;
  try
  // A bare name ("InventarioTest") is what delphi_projects lists, so it is
  // the obvious thing to send - and it came back as "outside the allowed
  // workspaces", which is true of any relative name and explains nothing
  // (field round 12).
  if (AProject.Trim <> '') and not TPath.IsPathRooted(AProject.Trim) and
     not AProject.Contains('\') and not AProject.Contains('/') then
  begin
    Result.AddPair('error', MsgFmt(SR_TEST_NAME_NOT_PATH_FMT, [AProject.Trim]));
    Exit;
  end;
  Denied := PathDenied(AProject); // running what a project built is a write-side act
  if Denied <> '' then
  begin
    Result.AddPair('error', Denied);
    Exit;
  end;
  // un proyecto, o nada: con cualquier otra cosa (un .txt, una carpeta) se
  // derivaba un .dpr que no existe y se contestaba "no existe" de un
  // fichero que si existia (segunda revision, 27-sep-2026)
  if not MatchText(TPath.GetExtension(AProject), ['.dproj', '.dpr']) then
  begin
    Result.AddPair('error', MsgFmt(SR_UNIT_PROJECT_EXT_FMT, [AProject]));
    Exit;
  end;
  Dproj := AProject;
  if SameText(TPath.GetExtension(Dproj), '.dpr') then
    Dproj := TPath.ChangeExtension(Dproj, '.dproj');
  Dpr := TPath.ChangeExtension(Dproj, '.dpr');
  if not TFile.Exists(Dpr) then
  begin
    Result.AddPair('error', MsgFmt(SR_TEST_NOPATH_FMT, [AProject]));
    Exit;
  end;
  K := KindOf(Dpr, Why);
  if K = tkNone then
  begin
    Result.AddPair('error', MsgFmt(SR_TEST_NOTATEST_FMT,
      [TPath.GetFileName(Dpr)]));
    Exit;
  end;
  Result.AddPair('project', Dproj);
  Result.AddPair('framework', KindName(K));
  Cfg := AConfig;
  if Cfg = '' then
    Cfg := 'Debug';
  // A configuration the project does not have used to be accepted in silence
  // and built into Win64\Inventada\ (measured 2026-08-25). Say the ones
  // that exist instead.
  Info := ReadDproj(Dproj);
  var Mala := ConfigDesconocida(Dproj, Cfg);
  if Mala <> '' then
  begin
    Result.AddPair('error', Mala);
    Exit;
  end;
  // Which platform this runs on was hardcoded and never said out loud, so an
  // agent that had built Win32 by hand watched delphi_test run a Win64 binary
  // it did not recognise (field round 9). It is said now, and it can be
  // chosen; whatever it is, the build and the run use the SAME one.
  Plat := CanonicalPlatform(APlatform);
  if (Plat = '') and (APlatform.Trim <> '') then
  begin
    // platform=Marte used to run Win64 without a word, while config=Turbo and
    // platform=Android64 were both refused properly (measured 2026-08-25).
    Result.AddPair('error', MsgFmt(SR_TEST_PLATFORM_UNKNOWN_FMT,
      [APlatform.Trim]));
    Exit;
  end;
  if Plat = '' then
    Plat := 'Win64';
  if not IsLocalPlatform(Plat) then
  begin
    Result.AddPair('error', MsgFmt(SR_TEST_PLATFORM_FMT, [Plat]));
    Exit;
  end;
  Result.AddPair('platform', Plat);
  Result.AddPair('config', Cfg);
  if ATimeoutMs <= 0 then
    ATimeoutMs := 120000;
  if ATimeoutMs > 600000 then
    ATimeoutMs := 600000;
  // Sin paquetes en tiempo de ejecucion: la jaula no deja leer los .bpl de
  // fuera y el exe ni arrancaria (David, 2-oct-2026: "lo compilas entero o
  // no molestes"). Se dice ANTES de compilar.
  if UsaPaquetesEnEjecucion(Dproj, Plat, Cfg) then
  begin
    Result.AddPair('error', MsgFmt(SR_TEST_PAQUETES_FMT,
      [TPath.GetFileName(Dproj), Cfg, Plat]));
    Exit;
  end;

  // 1. build, unless told not to: running a stale binary is a lie
  if not ANoBuild then
  begin
    Build := RunMsBuild(Dproj, Plat, Cfg, 'Build', '', '', 600000);
    try
      if not Build.GetValue('success').GetValue<Boolean> then
      begin
        Result.AddPair('result', 'build-failed');
        Result.AddPair('build', TJSONObject(Build.Clone));
        Result.AddPair('note', MsgText(SN_TEST_BUILD_FAILED));
        Exit;
      end;
      if Build.GetValue('output') <> nil then
        Exe := Build.GetValue('output').Value;
    finally
      Build.Free;
    end;
  end;
  if Exe = '' then
    Exe := ResolveBuildOutput(Dproj, Plat, Cfg);
  if (Exe = '') or not TFile.Exists(Exe) then
  begin
    Result.AddPair('error', IfThen(ANoBuild, MsgText(SR_TEST_NOBINARY_NOBUILD),
      MsgText(SR_TEST_NOBINARY)));
    Exit;
  end;
  Result.AddPair('binary', Exe);
  if ANoBuild then
  begin
    // nobuild=true ran whatever was lying there and reported its numbers as
    // if they were today's: 200000 passing tests out of a binary whose source
    // no longer compiled (measured 2026-08-25). Say how old it is.
    Result.AddPair('builtAt', DateTimeToStr(TFile.GetLastWriteTime(Exe)));
    Result.AddPair('noBuildNote', MsgText(SN_TEST_NOBUILD_NOTE));
    // We hold both dates: comparing them is free, and "the source is newer
    // than the binary" is the whole reason nobuild is dangerous.
    try
      if TFile.GetLastWriteTime(Dpr) > TFile.GetLastWriteTime(Exe) then
        Result.AddPair('staleBinary', MsgFmt(SN_TEST_STALE_FMT,
          [TPath.GetFileName(Dpr)]));
    except
    end;
  end;

  // 2. run it: a COPY of its output folder in the server's house, inside an
  //    AppContainer of its own, born with this call and gone with its answer
  //    (Lsp.Sandbox). Falla cerrado: sin contenedor no corre.
  Args := '';
  if AFilter <> '' then
    Args := ' --run:' + AFilter; // DUnitX honours it; a plain runner ignores it
  if not CorreEnContenedor(Exe, Args, ATimeoutMs, Result, Output, ExitCode,
    TimedOut, Ficheros, Recortado, Fuera, DuracionMs) then
    Exit;
  Result.AddPair('durationMs', TJSONNumber.Create(DuracionMs));
  Result.AddPair('exitCode', TJSONNumber.Create(Integer(ExitCode)));
  Result.AddPair('sandboxed', TJSONBool.Create(True)); // no hay otra forma de correr
  // lo que dejo el test es de Result desde YA: si algo de abajo falla, no se
  // pierde con la lista en la mano (revision de la 1.11.0)
  if Ficheros <> nil then
  begin
    Result.AddPair('files', Ficheros);
    if Recortado then
      Result.AddPair('filesNote', MsgFmt(SN_TEST_FICHEROS_RECORTE_FMT,
        [TOPE_POR_FICHERO, TOPE_DE_FICHEROS, TOPE_DE_LECTURA div (1024 * 1024)]));
    if Fuera > 0 then
    begin
      Result.AddPair('filesNotListed', TJSONNumber.Create(Fuera));
      Result.AddPair('filesListNote', MsgFmt(SN_TEST_FICHEROS_FUERA_FMT,
        [Fuera, TOPE_DE_ENTRADAS]));
    end;
  end;

  // 3. structured outcome + a bounded tail of what it printed
  ParseOutcome(Output, K, Integer(ExitCode), Result);
  if TimedOut then
  begin
    // A killed suite used to look exactly like one that dies on startup:
    // exitCode 1, no output, everything at zero. Now it says so, and says
    // why the output is missing - a console program's stdout is buffered, so
    // what it printed before the kill never reached the pipe.
    Result.RemovePair('result').Free;
    Result.AddPair('result', 'timeout');
    Result.AddPair('timedOut', TJSONBool.Create(True));
    Result.AddPair('timeoutMs', TJSONNumber.Create(ATimeoutMs));
    Result.AddPair('timeoutNote', MsgText(SN_TEST_TIMEOUT_NOTE));
  end
  else if (Result.GetValue('total') <> nil) and
          (Result.GetValue('total').GetValue<Integer> = 0) then
  begin
    // Zero tests is not a pass. "It compiles" was being reported as "it
    // works" whenever the runner printed nothing this parser understood.
    //
    // And zero tests is not "it ended fine" either: this branch used to
    // overwrite the verdict the EXIT CODE had already given, so a runner that
    // returned 1 after printing "1 failed" in a format nobody here parses came
    // back as no-tests with a note saying it had ended well (measured
    // 2026-08-25). Not knowing how to count is my problem; the exit code is
    // still the runner telling me it failed, and it wins.
    Result.RemovePair('result').Free;
    if ExitCode <> 0 then
    begin
      Result.AddPair('result', 'fail');
      Result.AddPair('noTestsNote', MsgFmt(SN_TEST_NO_COUNTS_FAILED_FMT,
        [ExitCode]));
    end
    else
    begin
      Result.AddPair('result', 'no-tests');
      Result.AddPair('noTestsNote', MsgText(SN_TEST_NO_COUNTS));
    end;
  end;
  Tail := Output.Replace(#13#10, #10).Split([#10]);
  From := Length(Tail) - 40;
  if From < 0 then
    From := 0;
  Sb := TStringBuilder.Create;
  try
    for I := From to High(Tail) do
      // el recuadro de DUnitX (copyright y licencia, '*' a los dos lados)
      // iba en cada cola: cinco lineas que no dicen nada del resultado
      // (revisor de tokens, 4-oct-2026)
      if (Tail[I].Trim <> '') and not ((K = tkDUnitX) and Tail[I].Trim.StartsWith('*') and
         Tail[I].Trim.EndsWith('*')) then
        Sb.AppendLine(Tail[I].TrimRight);
    Result.AddPair('outputTail', Sb.ToString.TrimRight);
  finally
    Sb.Free;
  end;
  if Length(Tail) > 40 then
    Result.AddPair('outputTruncated', TJSONBool.Create(True));
  // TEST-024 (de donde sale el veredicto, el contenedor) iba en CADA
  // ejecucion: lo dice la descripcion de la tool, y el tiempo agotado y el
  // sin-tests llevan su propia nota (revisor de tokens, 4-oct-2026)
  except
    // una excepcion a medio camino dejaba sin liberar lo que se devuelve
    // (el patron del Result de Rename, menor de la ronda 16)
    Result.Free;
    raise;
  end;
end;

end.
