unit SafeLog;

interface

uses
  System.Classes, System.SyncObjs;

type
  // the field types are part of the class declaration, so their units go in the interface uses
  TSafeLog = class
  private
    FLines: TStringList;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string);
    function Count: Integer;
  end;

implementation

constructor TSafeLog.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FLock := TCriticalSection.Create;
end;

destructor TSafeLog.Destroy;
begin
  FLock.Free;
  FLines.Free;
  inherited Destroy;
end;

procedure TSafeLog.Add(const AText: string);
begin
  FLock.Enter;
  try
    FLines.Add(AText);
  finally
    FLock.Leave;
  end;
end;

function TSafeLog.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FLines.Count;
  finally
    FLock.Leave;
  end;
end;

end.
