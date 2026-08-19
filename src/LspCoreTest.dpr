program LspCoreTest;

{ Console harness for the LSP core. Validates the plumbing against a real
  DelphiLSP.exe without any MCP layer on top.

  Usage:
    LspCoreTest capabilities
    LspCoreTest symbols --file <unit.pas>
    LspCoreTest hover   --file <unit.pas> --line N --col N
    LspCoreTest def     --file <unit.pas> --line N --col N
    LspCoreTest lint    --file <unit.pas> [--inject]
    LspCoreTest battery --file <unit.pas> [--settings <x.delphilsp.json>]

  Common options:
    --lsp <path>       DelphiLSP.exe (default: discovered via registry)
    --settings <path>  .delphilsp.json project settings for full semantics
    --root <dir>       workspace root (default: directory of --file)

  Positions are 0-based (LSP convention). Exit code: 0 = OK / all PASS. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  Lsp.Transport.Process in 'Lsp.Transport.Process.pas',
  Lsp.Client in 'Lsp.Client.pas',
  Lsp.Discovery in 'Lsp.Discovery.pas',
  Lsp.ConfigFabricator in 'Lsp.ConfigFabricator.pas';

var
  GOpts: TDictionary<string, string>;
  GCommand: string;
  GFailures: Integer;

procedure ParseCommandLine;
var
  I: Integer;
  P: string;
begin
  GCommand := ParamStr(1).ToLower;
  I := 2;
  while I <= ParamCount do
  begin
    P := ParamStr(I);
    if P.StartsWith('--') and (I < ParamCount) then
    begin
      GOpts.AddOrSetValue(P.Substring(2).ToLower, ParamStr(I + 1));
      Inc(I, 2);
    end
    else if P.StartsWith('--') then
    begin
      GOpts.AddOrSetValue(P.Substring(2).ToLower, 'true');
      Inc(I);
    end
    else
      Inc(I);
  end;
end;

function Opt(const AName: string; const ADefault: string = ''): string;
begin
  if not GOpts.TryGetValue(AName, Result) then
    Result := ADefault;
end;

function RequireFileOpt: string;
begin
  Result := Opt('file');
  if Result = '' then
    raise Exception.Create('Missing --file <unit.pas>');
  if not FileExists(Result) then
    raise Exception.CreateFmt('File not found: %s', [Result]);
  Result := TPath.GetFullPath(Result);
end;

function ResolveLspExe: string;
var
  Info: TRadStudioInfo;
begin
  Result := Opt('lsp');
  if Result <> '' then
    Exit;
  Info := DiscoverRadStudio;
  if not Info.Found then
    raise Exception.Create(
      'No RAD Studio installation with DelphiLSP.exe found in the registry. ' +
      'Pass --lsp <path to DelphiLSP.exe>.');
  Writeln('# DelphiLSP: ', Info.DelphiLspExe, ' (BDS ', Info.Version, ')');
  Result := Info.DelphiLspExe;
end;

function MakeClient(AServerType: TLspServerType; const ARootDir: string): TLspClient;
var
  Transport: TLspProcessTransport;
  Resp: TJSONObject;
  SettingsPath: string;
begin
  Transport := TLspProcessTransport.Create(ResolveLspExe);
  Transport.Start;
  Result := TLspClient.Create(Transport, True);
  Resp := Result.Initialize(TLspClient.PathToUri(ARootDir), AServerType);
  try
    if Resp.GetValue('error') <> nil then
      raise Exception.Create('initialize failed: ' + Resp.ToJSON);
  finally
    Resp.Free;
  end;
  Result.SendInitialized;
  SettingsPath := Opt('settings');
  if SettingsPath <> '' then
  begin
    if not FileExists(SettingsPath) then
      raise Exception.CreateFmt('Settings file not found: %s', [SettingsPath]);
    Result.SetSettingsFile(TPath.GetFullPath(SettingsPath));
    Sleep(2000); // give the server a beat to load project settings
  end;
end;

function RootFor(const AFilePath: string): string;
begin
  Result := Opt('root');
  if Result = '' then
    Result := TPath.GetDirectoryName(AFilePath);
end;

procedure PrintResponse(const ATitle: string; AResp: TJSONObject);
begin
  Writeln('## ', ATitle);
  Writeln(AResp.Format(2));
  AResp.Free;
end;

procedure Check(const AName: string; ACondition: Boolean; const ADetail: string);
begin
  if ACondition then
    Writeln('PASS - ', AName, ' - ', ADetail)
  else
  begin
    Writeln('FAIL - ', AName, ' - ', ADetail);
    Inc(GFailures);
  end;
end;

procedure Skip(const AName, AWhy: string);
begin
  Writeln('SKIP - ', AName, ' - ', AWhy);
end;

{ Recursively count DocumentSymbols and find a hover/definition target.
  Declaration symbols are preferred: their selectionRange is the identifier
  token itself, while implementation symbols start the range at column 0
  (the 'procedure'/'function' keyword), which is useless as a position. }
procedure WalkSymbols(AArr: TJSONArray; var ACount: Integer;
  var ATargetName: string; var ATargetLine, ATargetCol: Integer;
  var AFallbackName: string; var AFallbackLine: Integer);
var
  V: TJSONValue;
  Sym: TJSONObject;
  Detail: string;
  Children: TJSONArray;
  Pos: TJSONValue;
begin
  if AArr = nil then
    Exit;
  for V in AArr do
  begin
    Sym := V as TJSONObject;
    Inc(ACount);
    Detail := '';
    if Sym.GetValue('detail') <> nil then
      Detail := Sym.GetValue('detail').Value;
    Pos := Sym.FindValue('selectionRange.start');
    if Pos <> nil then
    begin
      if (ATargetName = '') and SameText(Detail, 'declaration') then
      begin
        ATargetName := Sym.GetValue('name').Value;
        ATargetLine := (Pos as TJSONObject).GetValue<Integer>('line');
        ATargetCol := (Pos as TJSONObject).GetValue<Integer>('character');
      end
      else if (AFallbackName = '') and SameText(Detail, 'implementation') then
      begin
        AFallbackName := Sym.GetValue('name').Value;
        AFallbackLine := (Pos as TJSONObject).GetValue<Integer>('line');
      end;
    end;
    Children := Sym.GetValue('children') as TJSONArray;
    WalkSymbols(Children, ACount, ATargetName, ATargetLine, ATargetCol,
      AFallbackName, AFallbackLine);
  end;
end;

{ For a fallback implementation symbol, locate the identifier column on its
  source line: take the simple name (after the last dot, before any paren)
  and find it in the line text. Returns -1 if not found. }
function IdentifierColumn(const ASourceText, AFullName: string; ALine: Integer): Integer;
var
  Lines: TStringList;
  Simple, LineText: string;
  P: Integer;
begin
  Result := -1;
  Simple := AFullName;
  P := System.Pos('(', Simple);
  if P > 0 then
    Simple := Copy(Simple, 1, P - 1);
  P := Simple.LastIndexOf('.');
  if P >= 0 then
    Simple := Simple.Substring(P + 1);
  Simple := Simple.Trim;
  if Simple = '' then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := ASourceText;
    if (ALine < 0) or (ALine >= Lines.Count) then
      Exit;
    LineText := Lines[ALine];
    P := System.Pos(Simple, LineText);
    if P > 0 then
      Result := P - 1 + (Length(Simple) div 2); // land mid-identifier
  finally
    Lines.Free;
  end;
end;

{ Insert a guaranteed compile error right after the 'implementation' line
  (memory only - the file on disk is never touched). }
function InjectError(const AText: string; out ALine: Integer): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    ALine := -1;
    for I := 0 to Lines.Count - 1 do
      if SameText(Trim(Lines[I]), 'implementation') then
      begin
        Lines.Insert(I + 1, 'ThisIdentifierDoesNotExist9x := 1;');
        ALine := I + 1;
        Break;
      end;
    if ALine < 0 then
    begin
      Lines.Insert(0, 'ThisIdentifierDoesNotExist9x := 1;');
      ALine := 0;
    end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

{ Find a usage of a well-known RTL identifier to use as a hover probe.
  Skips the uses clauses (a unit reference is not a symbol usage). }
procedure FindRtlUsage(const AText: string; var AName: string;
  var ALine, ACol: Integer);
const
  Candidates: array [0 .. 5] of string =
    ('TStringList', 'TStringStream', 'IntToStr', 'FormatDateTime',
     'Exception', 'TObject');
var
  Lines: TStringList;
  I, P, C: Integer;
begin
  ALine := -1;
  ACol := -1;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for C := Low(Candidates) to High(Candidates) do
      for I := 0 to Lines.Count - 1 do
      begin
        if Lines[I].TrimLeft.ToLower.StartsWith('uses') then
          Continue;
        P := System.Pos(Candidates[C], Lines[I]);
        if P > 0 then
        begin
          AName := Candidates[C];
          ALine := I;
          ACol := P - 1 + (Length(Candidates[C]) div 2);
          Exit;
        end;
      end;
  finally
    Lines.Free;
  end;
end;

function CountDiagnostics(AParams: TJSONObject; out AErrors: Integer;
  out AFirst: string): Integer;
var
  Diags: TJSONArray;
  V: TJSONValue;
  Sev: Integer;
begin
  Result := 0;
  AErrors := 0;
  AFirst := '';
  Diags := AParams.GetValue('diagnostics') as TJSONArray;
  if Diags = nil then
    Exit;
  Result := Diags.Count;
  for V in Diags do
  begin
    Sev := (V as TJSONObject).GetValue<Integer>('severity');
    if Sev = 1 then
      Inc(AErrors);
    if AFirst = '' then
      AFirst := (V as TJSONObject).GetValue('message').Value;
  end;
end;

// ---------------------------------------------------------------- commands

procedure CmdFabricate;
var
  Dproj, OutFile: string;
  Info: TRadStudioInfo;
begin
  Dproj := Opt('dproj');
  if (Dproj = '') or not FileExists(Dproj) then
    raise Exception.Create('Missing or not found: --dproj <project.dproj>');
  Info := DiscoverRadStudio;
  OutFile := FabricateSettings(TPath.GetFullPath(Dproj), Info);
  Writeln('# fabricated settings: ', OutFile);
  Writeln(TFile.ReadAllText(OutFile));
end;

procedure CmdCapabilities;
var
  Transport: TLspProcessTransport;
  Client: TLspClient;
  Resp: TJSONObject;
begin
  Transport := TLspProcessTransport.Create(ResolveLspExe);
  Transport.Start;
  Client := TLspClient.Create(Transport, True);
  try
    Resp := Client.Initialize(TLspClient.PathToUri(GetCurrentDir), lstAgent);
    PrintResponse('initialize (announced server capabilities)', Resp);
  finally
    Client.Free;
  end;
end;

procedure CmdSymbols;
var
  FilePath: string;
  Client: TLspClient;
  Resp: TJSONObject;
begin
  FilePath := RequireFileOpt;
  Client := MakeClient(lstAgent, RootFor(FilePath));
  try
    Client.DidOpenFile(FilePath);
    Sleep(2000);
    Resp := Client.DocumentSymbols(TLspClient.PathToUri(FilePath));
    PrintResponse('documentSymbol ' + FilePath, Resp);
  finally
    Client.Free;
  end;
end;

procedure CmdHoverOrDef(const AWhat: string);
var
  FilePath: string;
  Client: TLspClient;
  Resp: TJSONObject;
  Line, Col: Integer;
begin
  FilePath := RequireFileOpt;
  Line := StrToInt(Opt('line', '0'));
  Col := StrToInt(Opt('col', '0'));
  Client := MakeClient(lstAgent, RootFor(FilePath));
  try
    Client.DidOpenFile(FilePath);
    Sleep(2000);
    if AWhat = 'hover' then
      Resp := Client.Hover(TLspClient.PathToUri(FilePath), Line, Col)
    else
      Resp := Client.Definition(TLspClient.PathToUri(FilePath), Line, Col);
    PrintResponse(Format('%s %s @%d:%d', [AWhat, FilePath, Line, Col]), Resp);
  finally
    Client.Free;
  end;
end;

procedure CmdLint;
var
  FilePath, Text: string;
  Client: TLspClient;
  Params: TJSONObject;
  InjectedLine: Integer;
begin
  FilePath := RequireFileOpt;
  Client := MakeClient(lstLinter, RootFor(FilePath));
  try
    Text := TLspClient.LoadSourceText(FilePath);
    if Opt('inject') <> '' then
    begin
      Text := InjectError(Text, InjectedLine);
      Writeln('# error injected at 0-based line ', InjectedLine, ' (memory only)');
    end;
    Client.DidOpenText(TLspClient.PathToUri(FilePath), Text);
    Writeln('# waiting for publishDiagnostics (up to 180 s)...');
    Params := Client.WaitForNotification('textDocument/publishDiagnostics', 180000);
    if Params = nil then
      Writeln('# no diagnostics received (timeout)')
    else
      PrintResponse('publishDiagnostics', Params);
  finally
    Client.Free;
  end;
end;

procedure CmdBattery;
var
  FilePath, Uri, Root: string;
  Client, Linter: TLspClient;
  Resp, Params: TJSONObject;
  ResultArr: TJSONArray;
  SymCount, TgtLine, TgtCol, FbLine: Integer;
  TgtName, FbName: string;
  HasSettings: Boolean;
  Text: string;
  InjectedLine, Total, Errors: Integer;
  First: string;
  V: TJSONValue;
begin
  FilePath := RequireFileOpt;
  Uri := TLspClient.PathToUri(FilePath);
  Root := RootFor(FilePath);
  HasSettings := Opt('settings') <> '';

  Writeln('== LSP core battery ==');
  Writeln('file:     ', FilePath);
  Writeln('settings: ', Opt('settings', '(none - semantic checks limited)'));

  // 1) initialize
  Client := MakeClient(lstAgent, Root);
  try
    Check('initialize', True, 'agent mode handshake completed');

    // 2) documentSymbol
    Client.DidOpenFile(FilePath);
    Sleep(3000);
    Resp := Client.DocumentSymbols(Uri);
    try
      SymCount := 0;
      TgtName := '';
      TgtLine := 0;
      TgtCol := 0;
      FbName := '';
      FbLine := 0;
      ResultArr := Resp.GetValue('result') as TJSONArray;
      WalkSymbols(ResultArr, SymCount, TgtName, TgtLine, TgtCol, FbName, FbLine);
      Check('documentSymbol', SymCount > 0, Format('%d symbols', [SymCount]));
    finally
      Resp.Free;
    end;

    if TgtName = '' then
    begin
      // No declaration symbol: aim at an implementation identifier instead.
      TgtCol := IdentifierColumn(TLspClient.LoadSourceText(FilePath), FbName, FbLine);
      if TgtCol >= 0 then
      begin
        TgtName := FbName;
        TgtLine := FbLine;
      end;
    end;

    // 3) definition / 4) hover on a symbol identifier
    if TgtName = '' then
      Skip('definition/hover', 'no suitable symbol found in unit')
    else if not HasSettings then
    begin
      Skip('definition', 'needs --settings (DelphiLSP answers null unconfigured)');
      Skip('hover', 'needs --settings');
    end
    else
    begin
      Resp := Client.Definition(Uri, TgtLine, TgtCol + 1);
      try
        V := Resp.GetValue('result');
        var Detail := Format('"%s" @%d:%d', [TgtName, TgtLine, TgtCol]);
        if (V <> nil) and not (V is TJSONNull) then
          Detail := Detail + ' -> ' + Copy(V.ToJSON, 1, 120);
        Check('definition', (V <> nil) and not (V is TJSONNull), Detail);
      finally
        Resp.Free;
      end;

      // Hover answers on identifier USAGES only (measured: declarations and
      // implementation headers return null). Find a usage of a common RTL
      // symbol in the unit and hover it - the same probe that was validated
      // against DelphiLSP by hand.
      var UsageName := '';
      var UsageLine := -1;
      var UsageCol := -1;
      FindRtlUsage(TLspClient.LoadSourceText(FilePath), UsageName, UsageLine, UsageCol);
      if UsageLine < 0 then
        Skip('hover', 'no RTL symbol usage found to hover on')
      else
      begin
        Resp := Client.Hover(Uri, UsageLine, UsageCol);
        try
          V := Resp.GetValue('result');
          var HDetail := Format('"%s" usage @%d:%d', [UsageName, UsageLine, UsageCol]);
          if (V <> nil) and not (V is TJSONNull) then
            HDetail := HDetail + ' -> ' + Copy(V.ToJSON, 1, 100);
          Check('hover', (V <> nil) and not (V is TJSONNull), HDetail);
        finally
          Resp.Free;
        end;
      end;
    end;
  finally
    Client.Free;
  end;

  // 5) diagnostics via linter mode with an injected error (memory only)
  Linter := MakeClient(lstLinter, Root);
  try
    Text := InjectError(TLspClient.LoadSourceText(FilePath), InjectedLine);
    Linter.DidOpenText(Uri, Text);
    if HasSettings then
      Params := Linter.WaitForNotification('textDocument/publishDiagnostics', 120000)
    else
      Params := Linter.WaitForNotification('textDocument/publishDiagnostics', 45000);
    if Params = nil then
    begin
      if HasSettings then
        Check('diagnostics', False, 'no publishDiagnostics within timeout')
      else
        Skip('diagnostics', 'nothing received without --settings (expected on some setups)');
    end
    else
    try
      Total := CountDiagnostics(Params, Errors, First);
      Check('diagnostics', Errors >= 1,
        Format('%d diagnostics, %d errors; first: %s', [Total, Errors,
          Copy(First, 1, 80)]));
    finally
      Params.Free;
    end;
  finally
    Linter.Free;
  end;

  Writeln('== battery done: ', GFailures, ' failure(s) ==');
end;

// ------------------------------------------------------------------- main

begin
  GOpts := TDictionary<string, string>.Create;
  GFailures := 0;
  try
    try
      ParseCommandLine;
      if GCommand = 'capabilities' then
        CmdCapabilities
      else if GCommand = 'symbols' then
        CmdSymbols
      else if (GCommand = 'hover') or (GCommand = 'def') then
        CmdHoverOrDef(GCommand)
      else if GCommand = 'lint' then
        CmdLint
      else if GCommand = 'battery' then
        CmdBattery
      else if GCommand = 'fabricate' then
        CmdFabricate
      else
      begin
        Writeln('Unknown or missing command.');
        Writeln('Commands: capabilities | symbols | hover | def | lint | battery | fabricate');
        ExitCode := 2;
      end;
      if GFailures > 0 then
        ExitCode := 1;
    except
      on E: Exception do
      begin
        Writeln('ERROR: ', E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    GOpts.Free;
  end;
end.
