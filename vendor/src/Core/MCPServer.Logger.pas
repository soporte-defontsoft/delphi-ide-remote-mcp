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
    FLogToFile: Boolean;
    FLogFile: TStreamWriter;
    FLogFileName: string;
    FMinLogLevel: TLogLevel;
    FOnLogMessage: TLogMessageProc;
    FUseStdErr: Boolean;
    
    class procedure SetLogToConsole(const Value: Boolean); static;
    class procedure SetLogToFile(const Value: Boolean); static;
    class procedure SetLogFileName(const Value: string); static;
    class procedure SetMinLogLevel(const Value: TLogLevel); static;
    class procedure SetOnLogMessage(const Value: TLogMessageProc); static;
    class procedure SetUseStdErr(const Value: Boolean); static;

    class function GetLogToConsole: Boolean; static;
    class function GetLogToFile: Boolean; static;
    class function GetLogFileName: string; static;
    class function GetMinLogLevel: TLogLevel; static;
    class function GetOnLogMessage: TLogMessageProc; static;
    class function GetUseStdErr: Boolean; static;
    
    constructor CreateInstance;
    procedure DoWriteLog(const Level: TLogLevel; const Message: string);
    procedure EnsureLogFile;
    procedure DoCloseLogFile;
  public
    class constructor Create;
    class destructor Destroy;
    destructor Destroy; override;
    
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
    class property LogToFile: Boolean read GetLogToFile write SetLogToFile;
    class property LogFileName: string read GetLogFileName write SetLogFileName;
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
  FLogToFile := False;
  FLogFileName := ChangeFileExt(ParamStr(0), '.log');
  FMinLogLevel := TLogLevel.Info;
end;

destructor TLogger.Destroy;
begin
  DoCloseLogFile;
  inherited;
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


procedure TLogger.EnsureLogFile;
begin
  if FLogToFile and not Assigned(FLogFile) then
  begin
    FLogFile := TStreamWriter.Create(FLogFileName, True, TEncoding.UTF8);
    FLogFile.AutoFlush := True;
  end;
end;

procedure TLogger.DoCloseLogFile;
begin
  FLock.Enter;
  try
    if Assigned(FLogFile) then
      FreeAndNil(FLogFile);
  finally
    FLock.Leave;
  end;
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

      if FUseStdErr then
        WriteLn(ErrOutput, LogLine)
      else
        WriteLn(LogLine);

      {$IFDEF MSWINDOWS}
      SetConsoleTextAttribute(ConsoleHandle, 7);
      {$ENDIF}
    end;
      
    if FLogToFile then
    begin
      EnsureLogFile;
      if Assigned(FLogFile) then
      begin
        FLogFile.WriteLine(LogLine);
        // [local change] flush per line: the tray host has no console and
        // never closes the writer on Stop-Process, so a buffered log showed
        // nothing of the last hours (field 2026-08-23, 11:54 -> 14:00 blank).
        FLogFile.Flush;
      end;
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

class function TLogger.GetLogToFile: Boolean;
begin
  Result := Instance.FLogToFile;
end;

class function TLogger.GetLogFileName: string;
begin
  Result := Instance.FLogFileName;
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

class procedure TLogger.SetLogToFile(const Value: Boolean);
var
  lInstance: TLogger;
begin
  lInstance := Instance;
  if Assigned(lInstance) then
    lInstance.FLogToFile := Value;
end;

class procedure TLogger.SetLogFileName(const Value: string);
var
  lInstance: TLogger;
begin
  FLock.Enter;
  try
    lInstance := Instance;
    if lInstance = nil then
      Exit;

    lInstance.FLogFileName := Value;

    if Assigned(lInstance.FLogFile) then
      FreeAndNil(lInstance.FLogFile);
  finally
    FLock.Leave;
  end;
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