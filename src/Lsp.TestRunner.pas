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
// own switch, [Security] AllowTests, deliberately NOT AllowRun: allowing a
// test suite to run is not the same decision as allowing arbitrary binaries
// (AllowRun implies AllowTests - full execution is a superset). The binary is
// built here, from a project of the jail, run in the same low-integrity
// sandbox delphi_run uses, with a timeout, and only ever the artifact
// delphi_build declared.
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
  Lsp.Guard,
  Lsp.Dproj,
  Lsp.BuildRunner,
  Lsp.References,
  Lsp.Patch,
  Lsp.Texts;

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
  if TRegEx.IsMatch(Text, '(?i)\bDUnitX\.') then
  begin
    AWhy := 'usa DUnitX';
    Exit(tkDUnitX);
  end;
  if TRegEx.IsMatch(Text, '(?i)\{\$APPTYPE\s+CONSOLE\}') and
     TRegEx.IsMatch(Name, '(?i)(test|tests|spec)') then
  begin
    AWhy := 'consola y el nombre dice test';
    Exit(tkConsole);
  end;
end;

function KindName(K: TTestKind): string;
begin
  case K of
    tkDUnitX: Result := 'DUnitX';
    tkConsole: Result := 'consola (PASS/FAIL + ExitCode)';
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
    Result.AddPair('error', Format(SR_TEST_NOPATH_FMT, [APath]));
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
      Obj.AddPair('countsFormat', SN_TEST_CONSOLE_FORMAT);
  end;
  Result.AddPair('total', TJSONNumber.Create(N));
  if N = 0 then
    Result.AddPair('note', SN_TEST_NONE)
  else
  begin
    Result.AddPair('note', SN_TEST_DISCOVER_NOTE);
    Result.AddPair('runsOn', SN_TEST_RUNS_ON);
  end;
end;

{ DUnitX prints, among other things:
    Tests Found   : 12
    Tests Passed  : 11
    Tests Failed  : 1
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
  Found, Passed, Failed: Integer;
  HasNumbers: Boolean;
  Near: TStringList;
begin
  Found := -1; Passed := -1; Failed := -1;
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
  // The verdict never guesses: with numbers, they decide; without them, the
  // exit code does (0 = green), and we say which one spoke.
  try
    if Near.Count > 0 then
    begin
      ARet.AddPair('linesNotCounted', TJSONNumber.Create(Near.Count));
      ARet.AddPair('linesNotCountedNote', Format(SN_TEST_NEAR_MISS_FMT,
        [Near.Count, Near[0]]));
    end;
  finally
    Near.Free;
  end;
  if HasNumbers and (Failed >= 0) then
  begin
    ARet.AddPair('result', IfThen(Failed = 0, 'pass', 'fail'));
    ARet.AddPair('verdictFrom', 'counts');
  end
  else
  begin
    ARet.AddPair('result', IfThen(AExitCode = 0, 'pass', 'fail'));
    ARet.AddPair('verdictFrom', 'exitCode');
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
  Sandboxed, TimedOut: Boolean;
  T0: TDateTime;
  Tail: TArray<string>;
  I, From: Integer;
  Sb: TStringBuilder;
begin
  Result := TJSONObject.Create;
  // A bare name ("InventarioTest") is what delphi_projects lists, so it is
  // the obvious thing to send - and it came back as "outside the allowed
  // workspaces", which is true of any relative name and explains nothing
  // (field round 12).
  if (AProject.Trim <> '') and not TPath.IsPathRooted(AProject.Trim) and
     not AProject.Contains('') and not AProject.Contains('/') then
  begin
    Result.AddPair('error', Format(SR_TEST_NAME_NOT_PATH_FMT, [AProject.Trim]));
    Exit;
  end;
  Denied := PathDenied(AProject); // running what a project built is a write-side act
  if Denied <> '' then
  begin
    Result.AddPair('error', Denied);
    Exit;
  end;
  Dproj := AProject;
  if SameText(TPath.GetExtension(Dproj), '.dpr') then
    Dproj := TPath.ChangeExtension(Dproj, '.dproj');
  Dpr := TPath.ChangeExtension(Dproj, '.dpr');
  if not TFile.Exists(Dpr) then
  begin
    Result.AddPair('error', Format(SR_TEST_NOPATH_FMT, [AProject]));
    Exit;
  end;
  K := KindOf(Dpr, Why);
  if K = tkNone then
  begin
    Result.AddPair('error', Format(SR_TEST_NOTATEST_FMT,
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
  if (Length(Info.Configs) > 0) and not Info.HasConfig(Cfg) then
  begin
    Result.AddPair('error', Format(SR_TEST_CONFIG_FMT,
      [Cfg, string.Join(', ', Info.Configs)]));
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
    Result.AddPair('error', Format(SR_TEST_PLATFORM_UNKNOWN_FMT,
      [APlatform.Trim]));
    Exit;
  end;
  if Plat = '' then
    Plat := 'Win64';
  if not IsLocalPlatform(Plat) then
  begin
    Result.AddPair('error', Format(SR_TEST_PLATFORM_FMT, [Plat]));
    Exit;
  end;
  Result.AddPair('platform', Plat);
  Result.AddPair('config', Cfg);
  if ATimeoutMs <= 0 then
    ATimeoutMs := 120000;
  if ATimeoutMs > 600000 then
    ATimeoutMs := 600000;

  // 1. build, unless told not to: running a stale binary is a lie
  if not ANoBuild then
  begin
    Build := RunMsBuild(Dproj, Plat, Cfg, 'Build', '', '', 600000);
    try
      if not Build.GetValue('success').GetValue<Boolean> then
      begin
        Result.AddPair('result', 'build-failed');
        Result.AddPair('build', TJSONObject(Build.Clone));
        Result.AddPair('note', SN_TEST_BUILD_FAILED);
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
    Result.AddPair('error', IfThen(ANoBuild, SR_TEST_NOBINARY_NOBUILD,
      SR_TEST_NOBINARY));
    Exit;
  end;
  Result.AddPair('binary', Exe);
  if ANoBuild then
  begin
    // nobuild=true ran whatever was lying there and reported its numbers as
    // if they were today's: 200000 passing tests out of a binary whose source
    // no longer compiled (measured 2026-08-25). Say how old it is.
    Result.AddPair('builtAt', DateTimeToStr(TFile.GetLastWriteTime(Exe)));
    Result.AddPair('noBuildNote', SN_TEST_NOBUILD_NOTE);
    // We hold both dates: comparing them is free, and "the source is newer
    // than the binary" is the whole reason nobuild is dangerous.
    try
      if TFile.GetLastWriteTime(Dpr) > TFile.GetLastWriteTime(Exe) then
        Result.AddPair('staleBinary', Format(SN_TEST_STALE_FMT,
          [TPath.GetFileName(Dpr)]));
    except
    end;
  end;

  // 2. run it, sandboxed and bounded
  Args := '';
  if AFilter <> '' then
    Args := ' --run:' + AFilter; // DUnitX honours it; a plain runner ignores it
  T0 := Now;
  Output := RunCapturedSandboxedT(Format('"%s"%s', [Exe, Args]),
    TPath.GetDirectoryName(Exe), ATimeoutMs, ExitCode, Sandboxed, TimedOut);
  Result.AddPair('durationMs', TJSONNumber.Create(
    Round((Now - T0) * 24 * 60 * 60 * 1000)));
  Result.AddPair('exitCode', TJSONNumber.Create(Integer(ExitCode)));
  Result.AddPair('sandboxed', TJSONBool.Create(Sandboxed));

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
    Result.AddPair('timeoutNote', SN_TEST_TIMEOUT_NOTE);
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
      Result.AddPair('noTestsNote', Format(SN_TEST_NO_COUNTS_FAILED_FMT,
        [ExitCode]));
    end
    else
    begin
      Result.AddPair('result', 'no-tests');
      Result.AddPair('noTestsNote', SN_TEST_NO_COUNTS);
    end;
  end;
  Tail := Output.Replace(#13#10, #10).Split([#10]);
  From := Length(Tail) - 40;
  if From < 0 then
    From := 0;
  Sb := TStringBuilder.Create;
  try
    for I := From to High(Tail) do
      if Tail[I].Trim <> '' then
        Sb.AppendLine(Tail[I].TrimRight);
    Result.AddPair('outputTail', Sb.ToString.TrimRight);
  finally
    Sb.Free;
  end;
  if Length(Tail) > 40 then
    Result.AddPair('outputTruncated', TJSONBool.Create(True));
  Result.AddPair('note', SN_TEST_RUN_NOTE);
end;

end.
