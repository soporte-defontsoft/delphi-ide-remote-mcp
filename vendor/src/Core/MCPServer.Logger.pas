unit MCPServer.Logger;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  {$SCOPEDENUMS ON}
  TLogLevel = (Debug, Info, Warning, Error);
  {$SCOPEDENUMS OFF}
  
  TLogMessageProc = reference to procedure(const Message: string);

  TLogger = class
  private
    class var FInstance: TLogger;
    class var FLock: TCriticalSection;
    
    FLogToConsole: Boolean;
    // [local change] no log file of its own: the server's log is written by
    // Lsp.LogSink through OnLogMessage, in the server's home. This one went
    // to ParamStr(0) + '.log' with no gate and nobody turned it on (V47 of
    // 1.23: test_paisaje did not look into vendor)
    FMinLogLevel: TLogLevel;
    FOnLogMessage: TLogMessageProc;
    FUseStdErr: Boolean;
    
    class procedure SetLogToConsole(const Value: Boolean); static;
    class procedure SetMinLogLevel(const Value: TLogLevel); static;
    class procedure SetOnLogMessage(const Value: TLogMessageProc); static;
    class procedure SetUseStdErr(const Value: Boolean); static;

    class function GetLogToConsole: Boolean; static;
    class function GetMinLogLevel: TLogLevel; static;
    class function GetOnLogMessage: TLogMessageProc; static;
    class function GetUseStdErr: Boolean; static;
    
    constructor CreateInstance;
    procedure DoWriteLog(const Level: TLogLevel; const Message: string);
  public
    class constructor Create;
    class destructor Destroy;
    
    class function Instance: TLogger;
    
    class procedure Debug(const Message: string); overload;
    class procedure Debug(const Format: string; const Args: array of const); overload;
    
    class procedure Info(const Message: string); overload;
    class procedure Info(const Format: string; const Args: array of const); overload;
    
    class procedure Warning(const Message: string); overload;
    class procedure Warning(const Format: string; const Args: array of const); overload;
    
    class procedure Error(const Message: string); overload;
    class procedure Error(const Format: string; const Args: array of const); overload;
    class procedure Error(const Exception: Exception); overload;
    
    class property LogToConsole: Boolean read GetLogToConsole write SetLogToConsole;
    class property MinLogLevel: TLogLevel read GetMinLogLevel write SetMinLogLevel;
    class property OnLogMessage: TLogMessageProc read GetOnLogMessage write SetOnLogMessage;
    class property UseStdErr: Boolean read GetUseStdErr write SetUseStdErr;
  end;

// [local change] Values of secret-named JSON keys ("password", "passkey",
// "passfile", "token") never reach the log: the HTTP and stdio transports log
// the whole request body BEFORE the tool gate runs, and delphi_paserver
// add-profile carries the PAServer password in its arguments. One masker,
// called by every transport line that logs a raw request.
function MaskSecretValues(const S: string): string;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

// [local change] See the interface comment. String-scan on purpose (no regex
// dependency in the vendor): finds each secret key, walks to its quoted JSON
// value (escapes respected) and replaces the value with ***.
function MaskSecretValues(const S: string): string;
const
  KEYS: array[0..3] of string = ('"password"', '"passkey"', '"passfile"',
    '"token"');
var
  Key: string;
  I, J, K: Integer;
begin
  Result := S;
  for Key in KEYS do
  begin
    I := 1;
    repeat
      I := Pos(Key, LowerCase(Result), I);
      if I = 0 then Break;
      J := I + Length(Key);
      while (J <= Length(Result)) and CharInSet(Result[J], [' ', #9, ':']) do
        Inc(J);
      if (J <= Length(Result)) and (Result[J] = '"') then
      begin
        K := J + 1;
        while (K <= Length(Result)) and (Result[K] <> '"') do
        begin
          if Result[K] = '\' then
            Inc(K); // an escaped character never closes the value
          Inc(K);
        end;
        Result := Copy(Result, 1, J) + '***' + Copy(Result, K, MaxInt);
      end;
      Inc(I);
    until False;
  end;
end;

const
  LOG_LEVEL_NAMES: array[TLogLevel] of string = ('DEBUG', 'INFO', 'WARN', 'ERROR');
  LOG_LEVEL_COLORS: array[TLogLevel] of Word = (7, 15, 14, 12);

{ TLogger }

class constructor TLogger.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TLogger.Destroy;
begin
  FreeAndNil(FInstance);
  FreeAndNil(FLock);
end;

constructor TLogger.CreateInstance;
begin
  inherited Create;
  FLogToConsole := False;
  FMinLogLevel := TLogLevel.Info;
end;

class function TLogger.Instance: TLogger;
begin
  if not Assigned(FInstance) then
  begin
    FLock.Enter;
    try
      if not Assigned(FInstance) then
        FInstance := TLogger.CreateInstance;
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

procedure TLogger.DoWriteLog(const Level: TLogLevel; const Message: string);
var
  Timestamp: string;
  LogLine: string;
  {$IFDEF MSWINDOWS}
  ConsoleHandle: THandle;
  {$ENDIF}
begin
  if Level < FMinLogLevel then
    Exit;
    
  Timestamp := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now);
  LogLine := Format('[%s] [%-5s] %s', [Timestamp, LOG_LEVEL_NAMES[Level], Message]);
  
  FLock.Enter;
  try
    if FLogToConsole then
    begin
      {$IFDEF MSWINDOWS}
      if FUseStdErr then
        ConsoleHandle := GetStdHandle(STD_ERROR_HANDLE)
      else
        ConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
      SetConsoleTextAttribute(ConsoleHandle, LOG_LEVEL_COLORS[Level]);
      {$ENDIF}

      // [local change 2026-09-28] un cliente que cierra el stderr (o una
      // consola que no esta) no tumba el servidor al arrancar: el log de
      // consola se apaga y el de Lsp.LogSink (OnLogMessage) sigue (octava revision)
      try
        if FUseStdErr then
          WriteLn(ErrOutput, LogLine)
        else
          WriteLn(LogLine);
      except
        FLogToConsole := False;
      end;

      {$IFDEF MSWINDOWS}
      SetConsoleTextAttribute(ConsoleHandle, 7);
      {$ENDIF}
    end;
      
    if Assigned(FOnLogMessage) then
      FOnLogMessage(LogLine);
  finally
    FLock.Leave;
  end;
end;

class procedure TLogger.Debug(const Message: string);
begin
  Instance.DoWriteLog(TLogLevel.Debug, Message);
end;

class procedure TLogger.Debug(const Format: string; const Args: array of const);
begin
  Instance.DoWriteLog(TLogLevel.Debug, System.SysUtils.Format(Format, Args));
end;

class procedure TLogger.Info(const Message: string);
begin
  Instance.DoWriteLog(TLogLevel.Info, Message);
end;

class procedure TLogger.Info(const Format: string; const Args: array of const);
begin
  Instance.DoWriteLog(TLogLevel.Info, System.SysUtils.Format(Format, Args));
end;

class procedure TLogger.Warning(const Message: string);
begin
  Instance.DoWriteLog(TLogLevel.Warning, Message);
end;

class procedure TLogger.Warning(const Format: string; const Args: array of const);
begin
  Instance.DoWriteLog(TLogLevel.Warning, System.SysUtils.Format(Format, Args));
end;

class procedure TLogger.Error(const Message: string);
begin
  Instance.DoWriteLog(TLogLevel.Error, Message);
end;

class procedure TLogger.Error(const Format: string; const Args: array of const);
begin
  Instance.DoWriteLog(TLogLevel.Error, System.SysUtils.Format(Format, Args));
end;

class procedure TLogger.Error(const Exception: Exception);
begin
  Instance.DoWriteLog(TLogLevel.Error, System.SysUtils.Format('%s: %s', [Exception.ClassName, Exception.Message]));
end;

class function TLogger.GetLogToConsole: Boolean;
begin
  Result := Instance.FLogToConsole;
end;


class function TLogger.GetMinLogLevel: TLogLevel;
begin
  Result := Instance.FMinLogLevel;
end;

class function TLogger.GetOnLogMessage: TLogMessageProc;
begin
  Result := Instance.FOnLogMessage;
end;

class procedure TLogger.SetLogToConsole(const Value: Boolean);
var
  lInstance: TLogger;
begin
  lInstance := Instance;
  if Assigned(lInstance) then
    lInstance.FLogToConsole := Value;
end;


class procedure TLogger.SetMinLogLevel(const Value: TLogLevel);
var
  lInstance: TLogger;
begin
  lInstance := Instance;
  if Assigned(lInstance) then
    lInstance.FMinLogLevel := Value;
end;

class procedure TLogger.SetOnLogMessage(const Value: TLogMessageProc);
var
  lInstance: TLogger;
begin
  lInstance := Instance;
  if Assigned(lInstance) then
    lInstance.FOnLogMessage := Value;
end;

class function TLogger.GetUseStdErr: Boolean;
begin
  Result := Instance.FUseStdErr;
end;

class procedure TLogger.SetUseStdErr(const Value: Boolean);
var
  lInstance: TLogger;
begin
  lInstance := Instance;
  if Assigned(lInstance) then
    lInstance.FUseStdErr := Value;
end;

end.