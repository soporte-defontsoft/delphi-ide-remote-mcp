unit HitCounter;

interface

type
  // Counts the hits of a page; Hit is called from several threads at once
  THitCounter = class
  private
    FHits: Integer;
  public
    procedure Hit;
    function Hits: Integer;
  end;

implementation

procedure THitCounter.Hit;
begin
  TInterlocked.Increment(FHits);
end;

function THitCounter.Hits: Integer;
begin
  Result := FHits;
end;

end.
