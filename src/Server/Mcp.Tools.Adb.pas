unit Mcp.Tools.Adb;

{ delphi_adb: the Android side of remote targets. The IDE's Project Manager
  lists deployable Android devices by asking adb; this is that list without
  the IDE - see the devices hanging off THIS server (USB or wifi adb),
  attach one over the network (adb connect ip:port), and install a built
  .apk on one. The adb binary is the IDE's own Android SDK's (SDKAdbPath in
  the .sdk files the SDK Manager writes), discovered per install - never
  hardcoded.

  The point (the deploy "matiz"): the agent programs from anywhere, but the
  DEVICES hang off this server's machine/network. A deploy target is always
  a parameter (a PAServer profile, an adb serial) - never the agent's own
  machine. Arguments are vetted at the gate (AdbArgDenied) like every other
  command-line sink; connect/disconnect/install are write-level. }

interface

uses
  System.SysUtils,
  MCPServer.Tool.Base,
  MCPServer.Types,
  Lsp.Texts,
  Lsp.Attributes;  // [RutaDelServidor]: que parametro es una ruta NUESTRA

type
  TDelphiAdbParams = class
  private
    FCommand: string;
    FAddress: string;
    FDevice: string;
    FApk: string;
    FApp: string;
    FOut: string;
    FX: string;
    FY: string;
    FKey: string;
    FFilter: string;
    FLines: string;
    FInline: string;
    FMaxWidth: Integer;
    FFrame: string;
  public
    [SchemaDescription(SP_ADB_COMMAND)]
    property Command: string read FCommand write FCommand;
    [SchemaDescription(SP_ADB_ADDRESS)]
    property Address: string read FAddress write FAddress;
    [SchemaDescription(SP_ADB_DEVICE)]
    property Device: string read FDevice write FDevice;
    [SchemaDescription(SP_ADB_APK)]
    [RutaDelServidor]
    property Apk: string read FApk write FApk;
    [SchemaDescription(SP_ADB_APP)]
    property App: string read FApp write FApp;
    // Fichero LOCAL donde se escribe (la captura del movil, el logcat). Ojo:
    // aqui "out" es un FICHERO y en delphi_desktop es una CARPETA - misma
    // familia, contrato distinto. Ruta nuestra las dos.
    [SchemaDescription(SP_ADB_OUT)]
    [RutaDelServidor]
    property Out: string read FOut write FOut;
    [SchemaDescription(SP_ADB_X)]
    property X: string read FX write FX;
    [SchemaDescription(SP_ADB_Y)]
    property Y: string read FY write FY;
    [SchemaDescription(SP_ADB_KEY)]
    property Key: string read FKey write FKey;
    [SchemaDescription(SP_ADB_FILTER)]
    property Filter: string read FFilter write FFilter;
    [SchemaDescription(SP_ADB_LINES)]
    property Lines: string read FLines write FLines;
    [SchemaDescription(SP_CAPTURE_INLINE)]
    property Inline_: string read FInline write FInline;
    [SchemaDescription(SP_CAPTURE_MAXWIDTH)]
    property MaxWidth: Integer read FMaxWidth write FMaxWidth;
    [SchemaDescription(SP_CAPTURE_FRAME)]
    property Frame: string read FFrame write FFrame;
  end;

  TDelphiAdbTool = class(TMCPToolBase<TDelphiAdbParams>)
  protected
    function ExecuteWithParams(const Params: TDelphiAdbParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.StrUtils,
  MCPServer.Registration,
  Lsp.Discovery,
  Lsp.Dproj,
  Lsp.Guard,
  Lsp.Imagen,
  Lsp.InlineImages, // DeliverCapture: la entrega de una captura, la de toda la casa
  Lsp.BuildRunner;

{ El valor de una linea "<clave>: <valor>" de la salida de `wm size` / `wm
  density` ("Physical size: 1080x1920", "Override density: 320"); '' si no
  esta. Un solo lector para las cuatro claves. }
function ValorWm(const ASalida, AClave: string): string;
var
  L: string;
begin
  Result := '';
  for L in ASalida.Split([#10]) do
    if L.Trim.StartsWith(AClave + ':', True) then
      Exit(L.Trim.Substring(Length(AClave) + 1).Trim);
end;

{ "1080x1920" -> 1080, 1920. }
function PartirTamano(const S: string; out W, H: Integer): Boolean;
var
  P: TArray<string>;
begin
  P := S.ToLower.Split(['x']);
  Result := (Length(P) = 2) and TryStrToInt(P[0].Trim, W) and
    TryStrToInt(P[1].Trim, H) and (W > 0) and (H > 0);
end;

constructor TDelphiAdbTool.Create;
begin
  inherited;
  FName := 'delphi_adb';
  FDescription := SD_ADB;
end;

{ The SDK Manager's own adb, recorded in the Android .sdk files it writes
  (SDKAdbPath). Newest install first; '' when no Android SDK is configured. }
function FindAdb: string;
var
  Info: TRadStudioInfo;
  Dir, F, P: string;
begin
  Result := '';
  for Info in DiscoverAllRadStudios do
  begin
    if not Info.Found then Continue;
    Dir := IdeProfilesDir(Info.Version);
    if not TDirectory.Exists(Dir) then Continue;
    for F in TDirectory.GetFiles(Dir, '*.sdk') do
    begin
      P := TagValue(TFile.ReadAllText(F), 'SDKAdbPath');
      if (P <> '') and TFile.Exists(P) then
        Exit(P);
    end;
  end;
end;

function RunAdb(const AAdb, AArgs: string; ATimeoutMs: Integer;
  out AExitCode: Cardinal): string;
begin
  // El demonio de adb (puerto 5037) tiene que sobrevivir a ESTA llamada:
  // lanzado desde dentro del job moria con ella y cada conexion wifi se
  // perdia entre una llamada y la siguiente - connect decia "connected" y
  // el devices siguiente no veia nada (medido 2026-09-23, con el movil de
  // David). start-server es idempotente y barato; fuera del job se queda.
  RunDetached('"' + AAdb + '" start-server', 15000);
  Result := RunCaptured('"' + AAdb + '" ' + AArgs, ATimeoutMs, AExitCode);
end;

{ Field report (EDA51): Android switches wireless debugging OFF on its own
  after a while, and the port changes on re-enable. Nothing to auto-reconnect
  server-side - it takes a hand on the device - so the honest move is to
  RECOGNIZE adb's device-loss messages and append the recovery path. }
function DeviceGone(const AOutput: string): Boolean;
var
  L: string;
begin
  L := AOutput.ToLower;
  Result := L.Contains('not found') or L.Contains('offline') or
    L.Contains('no devices/emulators') or L.Contains('failed to connect') or
    L.Contains('cannot connect') or L.Contains('connection refused') or
    L.Contains('waiting for device');
end;

function GoneHint(const AOutput: string): string;
begin
  Result := AOutput.Trim;
  if DeviceGone(Result) then
    Result := Result + sLineBreak + SN_ADB_GONE;
end;

const
  // command=key: the whole vocabulary - fixed navigation keys, no free
  // keycodes, no text injection.
  KEY_NAMES: array[0..9] of string = ('back', 'home', 'enter', 'appswitch',
    'wakeup', 'up', 'down', 'left', 'right', 'tab');
  KEY_CODES: array[0..9] of string = ('KEYCODE_BACK', 'KEYCODE_HOME',
    'KEYCODE_ENTER', 'KEYCODE_APP_SWITCH', 'KEYCODE_WAKEUP',
    'KEYCODE_DPAD_UP', 'KEYCODE_DPAD_DOWN', 'KEYCODE_DPAD_LEFT',
    'KEYCODE_DPAD_RIGHT', 'KEYCODE_TAB');

function TDelphiAdbTool.ExecuteWithParams(const Params: TDelphiAdbParams): string;
var
  Cmd, Adb, Args, Output, L, Denied, DevArg: string;
  ExitCode: Cardinal;
  Return: TJSONObject;
  Devices: TJSONArray;
  N: Integer;
begin
  Cmd := Params.Command.Trim.ToLower;
  Adb := FindAdb;
  if Adb = '' then
    Exit(SR_ADB_NO_SDK);
  // a serial goes BEFORE the subcommand (adb -s <serial> <cmd>). The gate
  // already vetted the device token.
  DevArg := '';
  if Params.Device.Trim <> '' then
    DevArg := '-s ' + Params.Device.Trim + ' ';
  if Cmd = 'discover' then
  begin
    // mDNS: the devices ANNOUNCING wireless debugging, each with its ip:port.
    // "adb-XXXX  _adb-tls-connect._tcp  192.168.1.163:5556" (or _adb._tcp).
    Output := RunAdb(Adb, 'mdns services', 20000, ExitCode);
    Return := TJSONObject.Create;
    Devices := TJSONArray.Create;
    Return.AddPair('discovered', Devices);
    try
      for L in Output.Split([#13#10, #10]) do
        if L.Contains('_adb') and L.Contains(':') then
          Devices.Add(L.Trim);
      Return.AddPair('note', SN_ADB_DISCOVER);
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
  end
  else if (Cmd = '') or (Cmd = 'devices') then
  begin
    Output := RunAdb(Adb, 'devices -l', 30000, ExitCode);
    Return := TJSONObject.Create;
    Devices := TJSONArray.Create;
    Return.AddPair('devices', Devices);
    try
      for L in Output.Split([#13#10, #10]) do
        if (L.Trim <> '') and not L.StartsWith('List of devices') and
           not L.Contains('daemon') then
          Devices.Add(L.Trim);
      Return.AddPair('note', SN_ADB_DEVICES);
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
  end
  else if Cmd = 'logcat' then
  begin
    // A bounded DUMP (-d), never a stream: a request/response tool cannot
    // tail. -t N is the last N lines; filter is applied here, not as an adb
    // tag spec, so it matches anywhere in the line.
    N := StrToIntDef(Params.Lines.Trim, 300);
    // clients that type every parameter send lines=0 for "unset" (measured
    // in the field: hermes' client fills all fields with zero defaults) -
    // 0 means the default, same as an absent param
    if N = 0 then
      N := 300;
    if Params.Lines.Trim <> '' then
      if (N < 1) or (N > 5000) then
        Exit(Format(SR_ADB_LINES_FMT, [Params.Lines.Trim]));
    // out= vetted BEFORE touching adb (fail fast)
    if Params.Out.Trim <> '' then
    begin
      Denied := PathDenied(Params.Out);
      if Denied <> '' then
        Exit(Denied);
      if not (Params.Out.Trim.ToLower.EndsWith('.txt') or
              Params.Out.Trim.ToLower.EndsWith('.log')) then
        Exit(SR_ADB_OUT_LOG);
    end;
    // logcat on a missing device WAITS instead of erroring (measured:
    // "- waiting for device -" until the timeout); get-state answers the
    // absence instantly.
    if DevArg <> '' then
    begin
      Output := RunAdb(Adb, DevArg + 'get-state', 10000, ExitCode);
      if DeviceGone(Output) or (ExitCode <> 0) then
        Exit(GoneHint(Output));
    end;
    Output := RunAdb(Adb, DevArg + 'logcat -d -v time -t ' + IntToStr(N),
      45000, ExitCode);
    // a lost device must say so, not hide as "(logcat vacio)" - but only
    // when adb ITSELF failed. The dump's content is the device's own system
    // log, which naturally carries "failed to connect"/"offline" noise:
    // field 2026-08-21 (hermes report), a 5000-line dump false-positived
    // the marker scan and Exit'ed the RAW dump inline - 611KB past the
    // filter, the out= file and the 400-line cap in one move. The get-state
    // precheck above already answers for a device gone BEFORE the call.
    if (ExitCode <> 0) and DeviceGone(Output) then
      Exit(GoneHint(Output));
    var Txt: string;
    if Params.Filter.Trim <> '' then
    begin
      var Filtered := TStringBuilder.Create;
      try
        for L in Output.Split([#13#10, #10]) do
          if L.Contains(Params.Filter.Trim) then
            Filtered.AppendLine(L.TrimRight);
        Txt := Filtered.ToString.TrimRight;
      finally
        Filtered.Free;
      end;
    end
    else
      Txt := Output.TrimRight;
    if Txt.Trim = '' then
      Txt := '(logcat vacio: sin lineas' +
        IfThen(Params.Filter.Trim <> '', ' que contengan "' +
          Params.Filter.Trim + '"', '') + ')';
    if Params.Out.Trim <> '' then
    begin
      // The dump goes to a FILE the agent reads in ranges (delphi_read
      // pages at 400): a thousands-of-lines inline dump drowned a
      // 200k-context client in the field (312k tokens, 4 compressions).
      var OutDir := TPath.GetDirectoryName(Params.Out.Trim);
      if OutDir <> '' then
        CrearCarpeta(OutDir);
      TFile.WriteAllText(Params.Out.Trim, Txt, TEncoding.UTF8);
      Return := TJSONObject.Create;
      try
        Return.AddPair('logfile', Params.Out.Trim);
        Return.AddPair('lines',
          TJSONNumber.Create(Length(Txt.Split([#13#10, #10]))));
        Return.AddPair('size', TJSONNumber.Create(TFile.GetSize(Params.Out.Trim)));
        Return.AddPair('note', SN_ADB_LOGFILE);
        Result := Return.ToJSON;
      finally
        Return.Free;
      end;
    end
    else
    begin
      // inline: never more than the newest 400 lines - protecting the
      // client's context is the server's job too
      var Ls := Txt.Split([#13#10, #10]);
      if Length(Ls) > 400 then
      begin
        var Tail := TStringBuilder.Create;
        try
          Tail.AppendLine(Format(SN_ADB_TAIL_FMT, [Length(Ls), 400]));
          for var I := Length(Ls) - 400 to High(Ls) do
            Tail.AppendLine(Ls[I].TrimRight);
          Result := Tail.ToString.TrimRight;
        finally
          Tail.Free;
        end;
      end
      else
        Result := Txt;
    end;
  end
  else if (Cmd = 'connect') or (Cmd = 'disconnect') then
  begin
    if Params.Address.Trim = '' then
      Exit(SR_ADB_NEED_ADDRESS);
    // adb's own output line already says connected/failed - pass it through
    Output := RunAdb(Adb, Cmd + ' ' + Params.Address.Trim, 30000, ExitCode);
    Result := GoneHint(Output);
  end
  else if Cmd = 'install' then
  begin
    if Params.Apk.Trim = '' then
      Exit(SR_ADB_NEED_APK);
    Denied := ReadPathDenied(Params.Apk);
    if Denied <> '' then
      Exit(Denied);
    if not TFile.Exists(Params.Apk) then
      Exit('error: no existe el .apk: ' + Params.Apk);
    Output := RunAdb(Adb, DevArg + 'install -r "' + Params.Apk + '"',
      180000, ExitCode);
    Result := GoneHint(Output);
  end
  else if Cmd = 'run' then
  begin
    if Params.App.Trim = '' then
      Exit(SR_ADB_NEED_APP);
    // The IDE's "Deploy and Run": am start on the FMX native activity -
    // every Delphi app's activity (the AndroidManifest template names it).
    // This executes on the DEVICE, sandboxed by Android - nothing runs on
    // the server machine. Vetted at the gate.
    Output := RunAdb(Adb, DevArg + 'shell am start -n ' + Params.App.Trim +
      '/com.embarcadero.firemonkey.FMXNativeActivity', 30000, ExitCode);
    Result := GoneHint(Output);
  end
  else if Cmd = 'screenshot' then
  begin
    // The agent's remote eyes (read-level, like logcat): capture on the
    // device, pull to a server path, clean up. A direct exec-out redirect
    // mangles the PNG through the console (measured) - hence the tmp file.
    // "out" ya no es obligatorio ni tiene que acabar en ".png" a mano: lo
    // resuelve CaptureTarget (Lsp.Guard), el mismo para toda la familia de
    // capturas. El formato sale del fichero que screencap escribe en el
    // dispositivo, no de una segunda constante. Se resuelve ANTES de tocar
    // el dispositivo: un argumento malo de quien llama se contesta sin
    // preguntarle a nadie.
    const DevPng = '/sdcard/delphi_mcp_screen.png';
    var Destino: string;
    Denied := CaptureTarget(Params.Out, CAPTURE_SUB_ANDROID, 'android',
      TPath.GetExtension(DevPng), Destino);
    if Denied <> '' then
      Exit(Denied);
    CrearCarpeta(TPath.GetDirectoryName(Destino));
    Output := RunAdb(Adb, DevArg + 'shell screencap -p ' + DevPng, 30000,
      ExitCode);
    if (ExitCode <> 0) or DeviceGone(Output) then
      Exit(GoneHint(Output));
    Output := RunAdb(Adb, DevArg + 'pull ' + DevPng + ' "' +
      Destino + '"', 60000, ExitCode);
    RunAdb(Adb, DevArg + 'shell rm ' + DevPng, 15000, ExitCode);
    if not TFile.Exists(Destino) then
      Exit(GoneHint(Output));
    Return := TJSONObject.Create;
    try
      Return.AddPair('screenshot', Destino);
      Return.AddPair('size', TJSONNumber.Create(TFile.GetSize(Destino)));
      { La pantalla REAL del dispositivo, de `wm size` y `wm density`: lo
        que `input tap` entiende son pixeles de la pantalla en vigor (la
        Override si la hay, la Physical si no). Normalmente el PNG de
        screencap mide exactamente eso y las coordenadas medidas sobre la
        imagen valen tal cual; si no coinciden (un dispositivo que captura
        a otra escala), se da el factor y la nota lo dice, en vez de dejar
        que el agente pulse donde no es. Girado (WxH frente a HxW) no es
        escala: screencap e input miran la misma orientacion. }
      var SalidaWm := RunAdb(Adb, DevArg + 'shell wm size', 15000, ExitCode);
      var Fisica := ValorWm(SalidaWm, 'Physical size');
      var Forzada := ValorWm(SalidaWm, 'Override size');
      var Densidad := '';
      if Fisica <> '' then
      begin
        var SalidaDen := RunAdb(Adb, DevArg + 'shell wm density', 15000, ExitCode);
        Densidad := ValorWm(SalidaDen, 'Override density');
        if Densidad = '' then
          Densidad := ValorWm(SalidaDen, 'Physical density');
      end;
      var ImgW, ImgH, DW, DH: Integer;
      var HayImagen := TamanoPng(Destino, ImgW, ImgH);
      if HayImagen then
        Return.AddPair('image', Format('%dx%d', [ImgW, ImgH]));
      var Nota := SN_ADB_SCREENSHOT;
      // del PNG a la pantalla en vigor: lo lleva el frame, el agente no multiplica
      var TSX: Double := 1.0;
      var TSY: Double := 1.0;
      if Fisica <> '' then
      begin
        var Pantalla := TJSONObject.Create;
        Return.AddPair('display', Pantalla);
        Pantalla.AddPair('physical', Fisica);
        if Forzada <> '' then
          Pantalla.AddPair('override', Forzada);
        if Densidad <> '' then
          Pantalla.AddPair('density', TJSONNumber.Create(StrToIntDef(Densidad, 0)));
        var EnVigor := Forzada;
        if EnVigor = '' then
          EnVigor := Fisica;
        if HayImagen and PartirTamano(EnVigor, DW, DH) then
        begin
          { misma orientacion que la imagen antes de comparar }
          if (ImgW > ImgH) <> (DW > DH) then
          begin
            var T := DW; DW := DH; DH := T;
          end;
          if (ImgW <> DW) or (ImgH <> DH) then
          begin
            var Escala := TJSONObject.Create;
            Return.AddPair('tapScale', Escala);
            Escala.AddPair('x', TJSONNumber.Create(DW / ImgW));
            Escala.AddPair('y', TJSONNumber.Create(DH / ImgH));
            TSX := DW / ImgW;
            TSY := DH / ImgH;
            Nota := Format(SN_ADB_TAP_SCALE_FMT, [ImgW, ImgH, DW, DH,
              FormatFloat('0.###', DW / ImgW, TFormatSettings.Invariant),
              FormatFloat('0.###', DH / ImgH, TFormatSettings.Invariant)]);
          end;
        end;
      end;
      Return.AddPair('note', Nota);
      // UN SOLO PASO: la misma entrega que delphi_desktop (Lsp.InlineImages).
      // Antes una captura de Android se quedaba en la carpeta temporal para
      // siempre y no traia enlace de descarga.
      DeliverCapture('delphi_adb', Destino, Params.Inline_, Params.MaxWidth, 0, 0,
        TSX, TSY, Return);
      Result := Return.ToJSON;
    finally
      Return.Free;
    end;
  end
  else if Cmd = 'tap' then
  begin
    if (Params.X.Trim = '') or (Params.Y.Trim = '') then
      Exit(SR_ADB_NEED_XY);
    // coordinates vetted digits-only at the gate; with frame, measured on
    // that image and converted here to DISPLAY pixels (Lsp.InlineImages)
    var PX, PY: Integer;
    var FP := FramePoint(Params.Frame, Params.X, Params.Y, PX, PY);
    if FP <> '' then
      Exit(FP);
    Output := RunAdb(Adb, DevArg + 'shell input tap ' + IntToStr(PX) + ' ' +
      IntToStr(PY), 15000, ExitCode);
    Result := GoneHint(('TAP en (' + IntToStr(PX) + ',' + IntToStr(PY) +
      ') ' + Output.Trim).Trim);
  end
  else if Cmd = 'key' then
  begin
    N := IndexText(Params.Key.Trim, KEY_NAMES);
    if N < 0 then
      Exit(Format(SR_ADB_KEY_FMT, [Params.Key.Trim]));
    Output := RunAdb(Adb, DevArg + 'shell input keyevent ' + KEY_CODES[N],
      15000, ExitCode);
    Result := GoneHint(('KEY ' + KEY_NAMES[N] + ' ' + Output.Trim).Trim);
  end
  else
    Result := SR_ADB_CMD;
end;

initialization
  TMCPRegistry.RegisterTool('delphi_adb',
    function: IMCPTool begin Result := TDelphiAdbTool.Create; end);

end.
