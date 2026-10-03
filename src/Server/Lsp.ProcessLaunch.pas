unit Lsp.ProcessLaunch;

{ El lanzamiento Windows con herencia explicita. La lista de stdhandles es
  la que ya usaba la jaula de tests; transporte, runner y lanzador remoto
  comparten ahora esa misma regla. Un SID opcional anade el AppContainer.
  El vigia remoto declara tambien el handle del proceso que debe esperar. }

interface

uses
  Winapi.Windows, System.SysUtils;

function CreateProcessConHandles(const ACmdLine: string; AWorkDir: PChar;
  AFlags: DWORD; AEntorno: Pointer; const ASI: TStartupInfo;
  out API: TProcessInformation; ASid: PSID = nil;
  const AExtra: TArray<THandle> = nil): Boolean;

implementation

const
  PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES_ = $00020009;
  PROC_THREAD_ATTRIBUTE_HANDLE_LIST_ = $00020002;
  EXTENDED_STARTUPINFO_PRESENT_ = $00080000;

type
  TSecurityCapabilities = record
    AppContainerSid: PSID;
    Capabilities: Pointer;
    CapabilityCount: DWORD;
    Reserved: DWORD;
  end;
  TStartupInfoExW_ = record
    StartupInfo: TStartupInfo;
    lpAttributeList: Pointer;
  end;

function InitializeProcThreadAttributeList_(lpAttributeList: Pointer;
  dwAttributeCount, dwFlags: DWORD; var lpSize: NativeUInt): BOOL; stdcall;
  external kernel32 name 'InitializeProcThreadAttributeList';
function UpdateProcThreadAttribute_(lpAttributeList: Pointer; dwFlags: DWORD;
  Attribute: NativeUInt; lpValue: Pointer; cbSize: NativeUInt;
  lpPreviousValue, lpReturnSize: Pointer): BOOL; stdcall;
  external kernel32 name 'UpdateProcThreadAttribute';
procedure DeleteProcThreadAttributeList_(lpAttributeList: Pointer); stdcall;
  external kernel32 name 'DeleteProcThreadAttributeList';

function HandlesDeArranque(const ASI: TStartupInfo;
  const AExtra: TArray<THandle>): TArray<THandle>;

  procedure Anade(H: THandle);
  begin
    if (H = 0) or (H = INVALID_HANDLE_VALUE) then
      Exit;
    for var X in Result do
      if X = H then
        Exit;
    Result := Result + [H];
  end;

begin
  Result := [];
  if (ASI.dwFlags and STARTF_USESTDHANDLES) <> 0 then
  begin
    Anade(ASI.hStdInput);
    Anade(ASI.hStdOutput);
    Anade(ASI.hStdError);
  end;
  for var H in AExtra do
    Anade(H);
end;

function CreateProcessConHandles(const ACmdLine: string; AWorkDir: PChar;
  AFlags: DWORD; AEntorno: Pointer; const ASI: TStartupInfo;
  out API: TProcessInformation; ASid: PSID;
  const AExtra: TArray<THandle>): Boolean;
var
  Caps: TSecurityCapabilities;
  Tam: NativeUInt;
  Lista: Pointer;
  SIX: TStartupInfoExW_;
  Cmd: string;
  Err, NAttrs: DWORD;
  H: TArray<THandle>;
  Hereda: BOOL;
begin
  Result := False;
  FillChar(API, SizeOf(API), 0);
  H := HandlesDeArranque(ASI, AExtra);
  Hereda := Length(H) > 0;
  NAttrs := 0;
  if Hereda then Inc(NAttrs);
  if ASid <> nil then Inc(NAttrs);
  Cmd := ACmdLine;
  UniqueString(Cmd);
  // Sin handles ni contenedor no se hereda nada y no hace falta una lista.
  if NAttrs = 0 then
    Exit(CreateProcess(nil, PChar(Cmd), nil, nil, False, AFlags,
      AEntorno, AWorkDir, ASI, API));
  FillChar(Caps, SizeOf(Caps), 0);
  Caps.AppContainerSid := ASid;
  Tam := 0;
  InitializeProcThreadAttributeList_(nil, NAttrs, 0, Tam);
  GetMem(Lista, Tam);
  try
    if not InitializeProcThreadAttributeList_(Lista, NAttrs, 0, Tam) then
      Exit;
    try
      if (ASid <> nil) and not UpdateProcThreadAttribute_(Lista, 0,
        PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES_, @Caps, SizeOf(Caps),
        nil, nil) then
        Exit;
      // Fallar cerrado: si la lista no se puede instalar no se lanza el hijo.
      if Hereda and not UpdateProcThreadAttribute_(Lista, 0,
        PROC_THREAD_ATTRIBUTE_HANDLE_LIST_, @H[0], Length(H) * SizeOf(THandle),
        nil, nil) then
        Exit;
      FillChar(SIX, SizeOf(SIX), 0);
      SIX.StartupInfo := ASI;
      SIX.StartupInfo.cb := SizeOf(SIX);
      SIX.lpAttributeList := Lista;
      Result := CreateProcess(nil, PChar(Cmd), nil, nil, Hereda,
        AFlags or EXTENDED_STARTUPINFO_PRESENT_, AEntorno, AWorkDir,
        PStartupInfo(@SIX)^, API);
    finally
      Err := GetLastError;
      DeleteProcThreadAttributeList_(Lista);
      SetLastError(Err);
    end;
  finally
    Err := GetLastError;
    FreeMem(Lista);
    SetLastError(Err);
  end;
end;

end.
