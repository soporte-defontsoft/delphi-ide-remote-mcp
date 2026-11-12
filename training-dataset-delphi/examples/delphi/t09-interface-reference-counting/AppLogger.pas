unit AppLogger;

interface

type
  ILogger = interface
    ['{6F1C2B3A-8D4E-4F5A-9B7C-1D2E3F4A5B6C}']
    procedure Log(const AText: string);
    function Count: Integer;
  end;

function NewMemoryLogger: ILogger;

implementation

uses
  System.Classes;

type
  TMemoryLogger = class(TInterfacedObject, ILogger)
  private
    FLines: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Log(const AText: string);
    function Count: Integer;
  end;

constructor TMemoryLogger.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
end;

destructor TMemoryLogger.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TMemoryLogger.Log(const AText: string);
begin
  FLines.Add(AText);
end;

function TMemoryLogger.Count: Integer;
begin
  Result := FLines.Count;
end;

function NewMemoryLogger: ILogger;
begin
  Result := TMemoryLogger.Create;
end;

end.
