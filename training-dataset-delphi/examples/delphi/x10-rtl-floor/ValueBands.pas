unit ValueBands;

interface

function BandOf(const AValue: Double): Integer;

implementation

uses
  System.Math;

function BandOf(const AValue: Double): Integer;
begin
  // Floor rounds toward minus infinity: -2.5 / 5 = -0.5 -> -1.
  // Trunc (and div) round toward zero: they would put -2.5 in band 0
  Result := Floor(AValue / 5);
end;

end.
