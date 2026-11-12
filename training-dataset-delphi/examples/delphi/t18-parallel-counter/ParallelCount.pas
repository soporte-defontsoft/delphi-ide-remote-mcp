unit ParallelCount;

interface

function CountMultiples(const ALimit, AStep: Integer): Integer;

implementation

uses
  System.Threading, System.SyncObjs;

function CountMultiples(const ALimit, AStep: Integer): Integer;
var
  Count: Integer;
begin
  Count := 0;
  TParallel.For(1, ALimit,
    procedure(I: Integer)
    begin
      // Inc(Count) is not atomic: from several threads at once, updates can be lost
      if I mod AStep = 0 then
        TInterlocked.Increment(Count);
    end);
  Result := Count;
end;

end.
