unit Lsp.ProcessLaunch;

{ El lanzamiento Windows con herencia explicita. La lista de stdhandles es
  la que ya usaba la jaula de tests; transporte, runner y lanzador remoto
  comparten ahora esa misma regla. Un SID opcional anade el AppContainer.
  El vigia remoto declara tambien el handle del proceso que debe esperar.

  Y la linea de una orden: el troceador con las reglas del CRT (TrocearArgs)
  y su inversa, el compositor (EnComillas). Llegan de Lsp.Args el 9-oct-2026
  sin cambiar una linea: aqui no dependen de nada del servidor, y McpRunJob,
  que enlaza esta unidad, deja su gemela (ComillasWin). }

interface

uses
  Winapi.Windows, System.SysUtils;

function CreateProcessConHandles(const ACmdLine: string; AWorkDir: PChar;
  AFlags: DWORD; AEntorno: Pointer; const ASI: TStartupInfo;
  out API: TProcessInformation; ASid: PSID = nil;
  const AExtra: TArray<THandle> = nil): Boolean;

{ Trocea una linea de argumentos con las reglas del runtime de C de Windows
  (CommandLineToArgvW), las mismas que aplica git.exe: las comillas dobles
  agrupan y desaparecen ("mis notas.txt" es UNO), "" dentro de comillas es una
  comilla literal, y una barra invertida solo es especial ante una comilla. Es
  el UNICO troceador: el argv que remote-run da al programa, las rutas de stash
  push de delphi_git y el filtro de opciones de git (GitArgDenied/
  GitRemoteDenied), que asi juzga cada argumento TAL COMO lo recibira git. Su
  inversa, aqui al lado, es el compositor EnComillas. Vivia en
  Lsp.RemoteRun y la 1.5.1 le escribio un gemelo en Lsp.Guard (PartirArgs)
  sin verlo: ahora es uno, donde lo alcanzan los dos. }
function TrocearArgs(const AArgs: string): TArray<string>;

{ La INVERSA de TrocearArgs: compone UN argumento para una linea de comando que
  el CRT de Windows (git.exe, spawn directo sin shell) vuelve a trocear EXACTO
  en este argumento. Dobla las barras invertidas que preceden a una comilla -
  incluida la de cierre - y escapa cada comilla con \". Un solo nombrador: quien
  COMPONE una linea de git la usa; quien la LEE, TrocearArgs. Vivia en
  Mcp.Tools.Workspace y volvio a Lsp.Guard, con su inversa, el 26-sep-2026. }
function EnComillas(const AValor: string): string;

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

{ Trocea una linea de comando con las reglas del runtime de C de Windows
  (CommandLineToArgvW), las mismas que aplica git.exe (spawn directo, sin
  shell): las comillas dobles agrupan y desaparecen, "" dentro de comillas es
  una comilla literal, y una barra invertida SOLO es especial ante una comilla
  (2n barras = n y la comilla delimita; 2n+1 = n y comilla literal). Es el
  UNICO troceador, y su inversa es EnComillas (aqui al lado): la puerta valida
  el argv que este devuelve y el ejecutor
  recompone la linea desde el MISMO argv, asi que nadie lee la cadena de dos
  formas distintas (medido 26-sep-2026: --o"utput"= colaba una opcion prohibida
  ante un troceo que solo miraba espacios). }
function TrocearArgs(const AArgs: string): TArray<string>;
var
  I, N, Barras, K: Integer;
  Actual: string;
  Dentro, Hay: Boolean;
begin
  Result := nil;
  Actual := '';
  Dentro := False; // dentro de comillas dobles
  Hay := False;    // hay un argumento en curso (aunque sea "", que es uno vacio)
  I := 1;
  N := Length(AArgs);
  while I <= N do
  begin
    if AArgs[I] = '\' then
    begin
      // Una barra invertida SOLO es especial ante una comilla. Cuenta la racha.
      Barras := 0;
      while (I <= N) and (AArgs[I] = '\') do
      begin
        Inc(Barras);
        Inc(I);
      end;
      if (I <= N) and (AArgs[I] = '"') then
      begin
        // 2n barras + comilla = n barras y la comilla delimita; 2n+1 barras =
        // n barras y una comilla LITERAL (no delimita).
        for K := 1 to Barras div 2 do
          Actual := Actual + '\';
        Hay := True;
        if Odd(Barras) then
        begin
          Actual := Actual + '"';
          Inc(I); // la comilla se consume como literal
        end;
        // Barras par: la comilla queda para la vuelta siguiente (delimita).
      end
      else
      begin
        for K := 1 to Barras do
          Actual := Actual + '\'; // no preceden a comilla: literales
        Hay := True; // hubo contenido: un arg de SOLO barras no se pierde
      end
    end
    else if AArgs[I] = '"' then
    begin
      if Dentro and (I < N) and (AArgs[I + 1] = '"') then
      begin
        Actual := Actual + '"'; // "" dentro de comillas = una comilla literal
        Hay := True;
        Inc(I, 2);
      end
      else
      begin
        Dentro := not Dentro; // abre o cierra: agrupa, no es un caracter
        Hay := True;
        Inc(I);
      end;
    end
    else if CharInSet(AArgs[I], [' ', #9, #13, #10]) and not Dentro then
    begin
      if Hay then
        Result := Result + [Actual];
      Actual := '';
      Hay := False;
      Inc(I);
    end
    else
    begin
      Actual := Actual + AArgs[I];
      Hay := True;
      Inc(I);
    end;
  end;
  if Hay then
    Result := Result + [Actual];
end;

function EnComillas(const AValor: string): string;
var
  I, N, Barras, K: Integer;
begin
  // La inversa de TrocearArgs (arriba): deja un token que el runtime de C de
  // Windows (git.exe, spawn directo sin shell) vuelve a trocear EXACTAMENTE en
  // este argumento. Dobla las barras invertidas que preceden a una comilla -
  // incluida la de cierre - y escapa cada comilla con \".
  if (AValor <> '') and (AValor.IndexOfAny([' ', #9, #13, #10, '"']) < 0) then
    Exit(AValor); // sin blancos ni comillas: no necesita comillas
  Result := '"';
  I := 1;
  N := Length(AValor);
  while I <= N do
  begin
    Barras := 0;
    while (I <= N) and (AValor[I] = '\') do
    begin
      Inc(Barras);
      Inc(I);
    end;
    if I > N then
    begin
      for K := 1 to Barras * 2 do
        Result := Result + '\'; // barras finales: dobladas ante la comilla de cierre
    end
    else if AValor[I] = '"' then
    begin
      for K := 1 to Barras * 2 + 1 do
        Result := Result + '\';
      Result := Result + '"';
      Inc(I);
    end
    else
    begin
      for K := 1 to Barras do
        Result := Result + '\';
      Result := Result + AValor[I];
      Inc(I);
    end;
  end;
  Result := Result + '"';
end;

end.
