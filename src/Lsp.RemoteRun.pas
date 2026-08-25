unit Lsp.RemoteRun;

{ Remote execution THROUGH PAServer's file transport - the run half the IDE
  keeps to itself. paclient.exe has no exec operation (measured 2026-08-24:
  its whole surface is file copy, codesign and Android packaging; launching
  processes is the IDE<->PAServer private protocol). So the run goes by
  MAILBOX, the same idea as delphi_messages:

    server:  --put  scratch\_mcp-runner\jobs\job-<id>.json   (the order)
    target:  scripts/mcp-runner.py executes it and writes
             scratch\_mcp-runner\out\result-<id>.json + .out (the outcome)
    server:  --get  polls the result until it lands or times out

  The runner on the target is the OPT-IN: no runner installed, no execution
  (the job file just sits there and this call times out saying so). The
  runner only executes binaries inside PAServer's own scratch-dir - the
  deploy target - never the rest of the machine.

  DELPHI_MCP_PACLIENT overrides the paclient.exe path (the test battery
  points it at a stub that copies to a local folder). }

interface

uses
  System.JSON;

{ Copies runner/mcp-runner.py to <scratch>/_mcp-runner/ on the target of
  AProfile (the agent asking for remote-run usually has no other way in:
  measured 2026-08-24, Hermes lives in a container with no route to the
  target). Returns '' plus the launch line in AHowTo, or a refusal. }
function InstallRunner(const AProfile: string; out AHowTo: string): string;

{ Starts (or confirms) the runner on the target of AProfile. Measured
  2026-08-25: paclient's --put FLAGS are not just permissions - flag 5 makes
  PAServer EXECUTE the file with /bin/sh on the target, and flag 3 executes
  it directly. So the launch needs no human shell: we send a small sh script
  that sets the runner going with setsid (surviving PAServer's cleanup) and
  writes what it saw. }
function StartRunner(const AProfile: string; out AStatus: string): string;

{ Runs the program DEPLOYED for ADprojPath on the machine of PAServer profile
  AProfile. The remote path is DERIVED here, never taken from the caller:
  <windows user>-<profile>/<Project>/<Project> - the folder delphi_build
  target=Deploy writes and announces in its deployNote. AExeName, when given,
  picks another file of THAT SAME folder (a helper binary of the deploy) and
  may not contain path separators. Returns the JSON the tool hands back. }
function RemoteRun(const AProfile, ADprojPath, AExeName, AArgs: string;
  ATimeoutMs: Integer): TJSONObject;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Diagnostics,
  Lsp.BuildRunner,
  Lsp.Discovery,
  Lsp.Texts;

const
  RUNNER_DIR = '_mcp-runner';
  POLL_MS = 1500;
  GRACE_MS = 20000; // runner pickup + result write margin over the job timeout

function PaClientPath: string;
var
  Installs: TArray<TRadStudioInfo>;
  Info: TRadStudioInfo;
  P: string;
begin
  Result := GetEnvironmentVariable('DELPHI_MCP_PACLIENT');
  if (Result <> '') and TFile.Exists(Result) then
    Exit;
  Result := '';
  Installs := DiscoverAllRadStudios;
  for Info in Installs do
  begin
    if not Info.Found then
      Continue;
    P := TPath.Combine(TPath.Combine(
      ExcludeTrailingPathDelimiter(Info.RootDir), 'bin'), 'paclient.exe');
    if TFile.Exists(P) then
      Exit(P);
  end;
end;

function Paclient(const APaclient, AOps, AProfile: string;
  out AOutput: string): Integer;
var
  Exit_: Cardinal;
begin
  AOutput := RunCaptured(Format('"%s" %s "%s"', [APaclient, AOps, AProfile]),
    120000, Exit_);
  Result := Integer(Exit_);
end;

function JsonEsc(const S: string): string;
var
  J: TJSONString;
begin
  J := TJSONString.Create(S);
  try
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

function RunnerScriptPath: string;
begin
  // next to the exe in a deployment, or in the repo when running from src
  Result := TPath.Combine(TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), 'runner'), 'mcp-runner.py');
  if TFile.Exists(Result) then
    Exit;
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)),
    '..' + PathDelim + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
    'runner' + PathDelim + 'mcp-runner.py'));
  if not TFile.Exists(Result) then
    Result := '';
end;

function InstallRunner(const AProfile: string; out AHowTo: string): string;
var
  Pc, Script, Ops, Output: string;
  Rc: Integer;
begin
  AHowTo := '';
  Pc := PaClientPath;
  if Pc = '' then
    Exit(SR_REMOTERUN_NO_PACLIENT);
  Script := RunnerScriptPath;
  if Script = '' then
    Exit(SR_REMOTERUN_NO_SCRIPT);
  // flag 0 = plain data. NOT 5: measured 2026-08-25, PAServer EXECUTES a
  // flag-5 file (with /bin/sh, so a .py dies) and the copy does not stay.
  Ops := Format('"--put=%s,%s,0,mcp-runner.py"', [Script, RUNNER_DIR]);
  Rc := Paclient(Pc, Ops, AProfile, Output);
  if Rc <> 0 then
    Exit(Format(SR_REMOTERUN_PUT_FMT, [Rc, Output.Trim]));
  AHowTo := SN_REMOTERUN_INSTALLED;
end;

function StartRunner(const AProfile: string; out AStatus: string): string;
var
  Pc, TmpDir, ShPath, StatusPath, Ops, Output, Sh: string;
  Enc: TEncoding;
begin
  AStatus := '';
  Pc := PaClientPath;
  if Pc = '' then
    Exit(SR_REMOTERUN_NO_PACLIENT);
  TmpDir := TPath.Combine(TPath.GetTempPath, 'delphi-mcp-remoterun');
  TDirectory.CreateDirectory(TmpDir);
  ShPath := TPath.Combine(TmpDir, 'start-runner.sh');
  StatusPath := TPath.Combine(TmpDir, 'mcp-runner-status.txt');
  if TFile.Exists(StatusPath) then
    TFile.Delete(StatusPath);
  // POSIX script, LF endings, no BOM: /bin/sh chokes on CRLF and on a BOM
  Sh :=
    '#!/bin/sh'#10 +
    'D="$(cd "$(dirname "$0")" && pwd)"'#10 +
    '{'#10 +
    '  if pgrep -f "python3 .*mcp-runner.py" >/dev/null 2>&1; then'#10 +
    '    echo "RUNNER YA VIVO"'#10 +
    '  else'#10 +
    '    cd "$D" && setsid /usr/bin/python3 "$D/mcp-runner.py" >> "$D/runner.log" 2>&1 < /dev/null &'#10 +
    '    sleep 2'#10 +
    '  fi'#10 +
    '  pgrep -af "mcp-runner.py" || echo "NO ARRANCO - mira runner.log"'#10 +
    '  tail -3 "$D/runner.log" 2>/dev/null'#10 +
    '} > /tmp/mcp-runner-status.txt 2>&1'#10 +
    'exit 0'#10;
  Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(ShPath, Sh, Enc);
  finally
    Enc.Free;
  end;
  // flag 5: PAServer RUNS it on the target (this is the whole trick)
  Ops := Format('"--put=%s,%s,5,start-runner.sh"', [ShPath, RUNNER_DIR]);
  Paclient(Pc, Ops, AProfile, Output); // a non-zero exit is the script's own
  TFile.Delete(ShPath);
  Sleep(1500);
  Ops := Format('"--get=/tmp/mcp-runner-status.txt,%s"', [TmpDir]);
  if (Paclient(Pc, Ops, AProfile, Output) = 0) and TFile.Exists(StatusPath) then
  begin
    AStatus := TFile.ReadAllText(StatusPath, TEncoding.UTF8).TrimRight;
    TFile.Delete(StatusPath);
  end;
  if AStatus = '' then
    Exit(SR_REMOTERUN_START_NOSTATUS);
  if not AStatus.Contains('mcp-runner.py') then
    Exit(Format(SR_REMOTERUN_START_FAILED_FMT, [AStatus]));
  AStatus := Format(SN_REMOTERUN_STARTED_FMT, [AProfile, AStatus]);
end;

function RemoteRun(const AProfile, ADprojPath, AExeName, AArgs: string;
  ATimeoutMs: Integer): TJSONObject;
var
  ProjName, DeployRel, ARemoteExe: string;
  Pc, JobId, TmpDir, JobFile, ResFile, OutFile, Ops, Output, ResText: string;
  Rc: Integer;
  Sw: TStopwatch;
  Res: TJSONObject;
  Waited: Boolean;
begin
  Result := TJSONObject.Create;
  Pc := PaClientPath;
  if Pc = '' then
  begin
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', SR_REMOTERUN_NO_PACLIENT);
    Exit;
  end;
  if ATimeoutMs <= 0 then
    ATimeoutMs := 30000;
  if ATimeoutMs > 300000 then
    ATimeoutMs := 300000;

  // The ONE thing that may run: what THIS project deployed, in its own
  // folder of the scratch dir. The caller never names a path (David's rule
  // 2026-08-24: "no se debe poder ejecutar otra cosa que no sea el programa
  // desplegado"), so a script or any other binary sitting in the scratch is
  // out of reach even for a full-access token.
  // The runner lives in <scratch>/<user>-<profile>/_mcp-runner, so ITS root
  // is already the profile folder: the path we send is relative to THAT,
  // just <Project>/<Project>. Sending the <user>-<profile> segment too
  // doubled it (measured end to end 2026-08-25 - the first real remote run).
  ProjName := TPath.GetFileNameWithoutExtension(ADprojPath);
  DeployRel := ProjName;
  if AExeName = '' then
    ARemoteExe := DeployRel + '/' + ProjName
  else
    ARemoteExe := DeployRel + '/' + AExeName;

  JobId := FormatDateTime('yyyymmdd"-"hhnnsszzz', Now);
  TmpDir := TPath.Combine(TPath.GetTempPath, 'delphi-mcp-remoterun');
  TDirectory.CreateDirectory(TmpDir);
  JobFile := TPath.Combine(TmpDir, 'job-' + JobId + '.json');
  // UTF-8 WITHOUT BOM: a BOM breaks a strict json.load on the target
  // (measured 2026-08-24 - the runner refused every job as unreadable).
  var Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(JobFile, Format(
      '{"id":%s,"exe":%s,"allowDir":%s,"args":%s,"timeoutMs":%d}',
      [JsonEsc(JobId), JsonEsc(ARemoteExe), JsonEsc(DeployRel),
       JsonEsc(AArgs), ATimeoutMs]), Enc);
  finally
    Enc.Free;
  end;

  // the order goes up
  Ops := Format('"--put=%s,%s/jobs,0,job-%s.json"', [JobFile, RUNNER_DIR, JobId]);
  Rc := Paclient(Pc, Ops, AProfile, Output);
  TFile.Delete(JobFile);
  if Rc <> 0 then
  begin
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', Format(SR_REMOTERUN_PUT_FMT, [Rc, Output.Trim]));
    Exit;
  end;

  // poll for the outcome
  ResFile := TPath.Combine(TmpDir, 'result-' + JobId + '.json');
  OutFile := TPath.Combine(TmpDir, 'result-' + JobId + '.out');
  Sw := TStopwatch.StartNew;
  Waited := False;
  repeat
    Sleep(POLL_MS);
    Ops := Format('"--get=%s/out/result-%s.json,%s"', [RUNNER_DIR, JobId, TmpDir]);
    Rc := Paclient(Pc, Ops, AProfile, Output);
    if (Rc = 0) and TFile.Exists(ResFile) then
    begin
      Waited := True;
      Break;
    end;
  until Sw.ElapsedMilliseconds > ATimeoutMs + GRACE_MS;

  if not Waited then
  begin
    // Copied but never launched is a DIFFERENT problem from not installed,
    // and the agent cannot tell them apart (field 2026-08-24, Hermes). One
    // extra paclient call, only on this failure path: is the script there?
    var Probe := TPath.Combine(TmpDir, 'mcp-runner.py');
    if TFile.Exists(Probe) then
      TFile.Delete(Probe);
    Ops := Format('"--get=%s/mcp-runner.py,%s"', [RUNNER_DIR, TmpDir]);
    var Installed := (Paclient(Pc, Ops, AProfile, Output) = 0) and TFile.Exists(Probe);
    if Installed then
      TFile.Delete(Probe);
    Result.AddPair('success', TJSONBool.Create(False));
    if Installed then
      Result.AddPair('error', Format(SR_REMOTERUN_NOT_STARTED_FMT,
        [(ATimeoutMs + GRACE_MS) div 1000, RUNNER_DIR]))
    else
      Result.AddPair('error', Format(SR_REMOTERUN_TIMEOUT_FMT,
        [(ATimeoutMs + GRACE_MS) div 1000, RUNNER_DIR]));
    Result.AddPair('runnerInstalled', TJSONBool.Create(Installed));
    Result.AddPair('jobId', JobId);
    Exit;
  end;

  ResText := TFile.ReadAllText(ResFile, TEncoding.UTF8);
  TFile.Delete(ResFile);
  Res := TJSONObject.ParseJSONValue(ResText) as TJSONObject;
  if Res = nil then
  begin
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', 'runner devolvio un result ilegible: ' +
      Copy(ResText, 1, 400));
    Exit;
  end;
  try
    Result.AddPair('success', TJSONBool.Create(
      (Res.GetValue('exitCode') <> nil) and
      (Res.GetValue('exitCode').GetValue<Integer> = 0)));
    Result.AddPair('exitCode', TJSONNumber.Create(
      Res.GetValue('exitCode').GetValue<Integer>));
    if Res.GetValue('durationMs') <> nil then
      Result.AddPair('durationMs', TJSONNumber.Create(
        Res.GetValue('durationMs').GetValue<Integer>));
    if Res.GetValue('error') <> nil then
      Result.AddPair('runnerError', Res.GetValue('error').Value);
  finally
    Res.Free;
  end;

  // the output tail travels as its own file (may not exist for a rejection)
  Ops := Format('"--get=%s/out/result-%s.out,%s"', [RUNNER_DIR, JobId, TmpDir]);
  if (Paclient(Pc, Ops, AProfile, Output) = 0) and TFile.Exists(OutFile) then
  begin
    Result.AddPair('output', TFile.ReadAllText(OutFile, TEncoding.UTF8));
    TFile.Delete(OutFile);
  end;

  // best-effort remote cleanup (the runner already moved the job to done\)
  Ops := Format('"--Remove=%s/out/result-%s.json;%s/out/result-%s.out"',
    [RUNNER_DIR, JobId, RUNNER_DIR, JobId]);
  Paclient(Pc, Ops, AProfile, Output);

  Result.AddPair('profile', AProfile);
  Result.AddPair('remoteExe', ARemoteExe);
  Result.AddPair('project', ProjName);
  Result.AddPair('note', SN_REMOTERUN_NOTE);
end;

end.
