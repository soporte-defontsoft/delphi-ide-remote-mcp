unit Geometry;

interface

uses
  System.Types;

// TRectF and TPointF appear in the declaration, so System.Types goes in the INTERFACE uses
function CenterOf(const ARect: TRectF): TPointF;

implementation

function CenterOf(const ARect: TRectF): TPointF;
begin
  Result := ARect.CenterPoint;
end;

end.
