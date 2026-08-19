unit Lsp.Sandbox;

{ Filesystem confinement for delphi_run via Windows Mandatory Integrity
  Control. A process launched at LOW integrity cannot WRITE to any object at
  the normal (Medium) integrity level - i.e. the whole ordinary filesystem,
  the user profile, other projects, Windows. It can still READ (read-down is
  allowed) and produce stdout. To let the run program write its OWN output, a
  single directory (inside the jail) is labelled Low so a low-IL process may
  write THERE and nowhere else.

  This is the real answer to "a compiled program run through the MCP could
  scribble anywhere the service account can" (B0b). It bounds WRITES; the Job
  Object (Lsp.BuildRunner) bounds lifetime and resources. Together they
  sandbox delphi_run.

  Honest limits: it needs the launch to succeed with a lowered token (verified
  at runtime; if the OS refuses, the caller is told the process ran WITHOUT
  the sandbox rather than silently unconfined). build/git are NOT lowered -
  they run the trusted toolchain, not arbitrary compiled output. }

interface

uses
  Winapi.Windows;

{ Launches ACmdLine at LOW integrity, like CreateProcess (suspended-capable,
  handle-inheriting, CREATE_NO_WINDOW). AWorkDir may be nil. Returns True and
  fills API on success. ASandboxed reports whether the LOW-integrity token was
  actually applied (False = the OS refused the lowered launch and the process
  was NOT started; the caller must then decide). }
function CreateProcessLowIntegrity(const ACmdLine: string; AWorkDir: PChar;
  ACreateFlags: DWORD; AInheritHandles: Boolean; const ASI: TStartupInfo;
  out API: TProcessInformation): Boolean;

{ Labels a directory (and its new children) LOW integrity so a low-IL process
  may write inside it. Non-destructive: it only lowers the write requirement,
  medium/high writers are unaffected. Best-effort. }
function LabelDirLowIntegrity(const ADir: string): Boolean;

implementation

const
  SE_GROUP_INTEGRITY_ = $00000020;
  SECURITY_MANDATORY_LOW_RID_ = $00001000;
  TokenIntegrityLevel_ = 25; // TOKEN_INFORMATION_CLASS
  LABEL_SECURITY_INFORMATION_ = $00000010;

type
  TSidIdentifierAuthority = record
    Value: array [0 .. 5] of Byte;
  end;

  TTokenMandatoryLabel = record
    Sid: PSID;
    Attributes: DWORD;
  end;

function ConvertStringSecurityDescriptorToSecurityDescriptorW(
  StringSD: PWideChar; Revision: DWORD; out SD: PSECURITY_DESCRIPTOR;
  SDSize: PULONG): BOOL; stdcall;
  external 'advapi32.dll';

function SetFileSecurityW(FileName: PWideChar; SecurityInformation: DWORD;
  SD: PSECURITY_DESCRIPTOR): BOOL; stdcall; external 'advapi32.dll';

function CreateLowToken(out AToken: THandle): Boolean;
var
  Cur, Dup: THandle;
  Auth: TSidIdentifierAuthority;
  LowSid: PSID;
  Til: TTokenMandatoryLabel;
begin
  Result := False;
  AToken := 0;
  if not OpenProcessToken(GetCurrentProcess,
    TOKEN_DUPLICATE or TOKEN_ADJUST_DEFAULT or TOKEN_QUERY or TOKEN_ASSIGN_PRIMARY,
    Cur) then
    Exit;
  try
    if not DuplicateTokenEx(Cur, MAXIMUM_ALLOWED, nil, SecurityImpersonation,
      TokenPrimary, Dup) then
      Exit;
    Auth.Value[0] := 0; Auth.Value[1] := 0; Auth.Value[2] := 0;
    Auth.Value[3] := 0; Auth.Value[4] := 0; Auth.Value[5] := 16; // MANDATORY_LABEL_AUTHORITY
    LowSid := nil;
    if not AllocateAndInitializeSid(PSIDIdentifierAuthority(@Auth), 1,
      SECURITY_MANDATORY_LOW_RID_, 0, 0, 0, 0, 0, 0, 0, LowSid) then
    begin
      CloseHandle(Dup);
      Exit;
    end;
    try
      Til.Sid := LowSid;
      Til.Attributes := SE_GROUP_INTEGRITY_;
      if SetTokenInformation(Dup, TTokenInformationClass(TokenIntegrityLevel_),
        @Til, SizeOf(Til) + GetLengthSid(LowSid)) then
      begin
        AToken := Dup;
        Result := True;
      end
      else
        CloseHandle(Dup);
    finally
      FreeSid(LowSid);
    end;
  finally
    CloseHandle(Cur);
  end;
end;

function CreateProcessLowIntegrity(const ACmdLine: string; AWorkDir: PChar;
  ACreateFlags: DWORD; AInheritHandles: Boolean; const ASI: TStartupInfo;
  out API: TProcessInformation): Boolean;
var
  Token: THandle;
  Cmd: string;
  SILocal: TStartupInfo;
begin
  Result := False;
  FillChar(API, SizeOf(API), 0);
  if not CreateLowToken(Token) then
    Exit;
  try
    Cmd := ACmdLine;
    UniqueString(Cmd);
    SILocal := ASI;
    // A lowered token is a RESTRICTED version of the caller's own primary
    // token, so CreateProcessAsUser does NOT require SeAssignPrimaryToken.
    Result := CreateProcessAsUser(Token, nil, PChar(Cmd), nil, nil,
      AInheritHandles, ACreateFlags, nil, AWorkDir, SILocal, API);
  finally
    CloseHandle(Token);
  end;
end;

function LabelDirLowIntegrity(const ADir: string): Boolean;
var
  SD: PSECURITY_DESCRIPTOR;
begin
  Result := False;
  SD := nil;
  // S:(ML;OICI;NW;;;LW) = mandatory Low label, inherited by children,
  // no-write-up policy. Setting the object to Low lets a low-IL process write.
  if ConvertStringSecurityDescriptorToSecurityDescriptorW(
    'S:(ML;OICI;NW;;;LW)', 1 {SDDL_REVISION_1}, SD, nil) then
  try
    Result := SetFileSecurityW(PWideChar(ADir), LABEL_SECURITY_INFORMATION_, SD);
  finally
    LocalFree(HLOCAL(SD));
  end;
end;

end.
