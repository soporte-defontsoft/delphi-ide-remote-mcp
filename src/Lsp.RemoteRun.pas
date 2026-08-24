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

{ Runs ARemoteExe on the machine of PAServer profile AProfile. ARemoteExe is
  a path ON THE TARGET, absolute or relative to the scratch dir (the
  deployNote of delphi_build target=Deploy names the folder). Returns the
  JSON the tool hands back (success, exitCode, output tail...). }
function RemoteRun(const AProfile, ARemoteExe, AArgs: string;
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

function RemoteRun(const AProfile, ARemoteExe, AArgs: string;
  ATimeoutMs: Integer): TJSONObject;
var
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

  JobId := FormatDateTime('yyyymmdd"-"hhnnsszzz', Now);
  TmpDir := TPath.Combine(TPath.GetTempPath, 'delphi-mcp-remoterun');
  TDirectory.CreateDirectory(TmpDir);
  JobFile := TPath.Combine(TmpDir, 'job-' + JobId + '.json');
  // UTF-8 WITHOUT BOM: a BOM breaks a strict json.load on the target
  // (measured 2026-08-24 - the runner refused every job as unreadable).
  var Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(JobFile, Format(
      '{"id":%s,"exe":%s,"args":%s,"timeoutMs":%d}',
      [JsonEsc(JobId), JsonEsc(ARemoteExe), JsonEsc(AArgs), ATimeoutMs]), Enc);
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
    Result.AddPair('success', TJSONBool.Create(False));
    Result.AddPair('error', Format(SR_REMOTERUN_TIMEOUT_FMT,
      [(ATimeoutMs + GRACE_MS) div 1000, RUNNER_DIR]));
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
  Result.AddPair('note', SN_REMOTERUN_NOTE);
end;

end.
