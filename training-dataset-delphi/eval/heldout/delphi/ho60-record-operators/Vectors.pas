unit Vectors;

interface

type
  TVec2 = record
    X, Y: Double;
    class operator Add(const A, B: TVec2): TVec2;
    class operator Multiply(const A: TVec2; const K: Double): TVec2;
    class operator Equal(const A, B: TVec2): Boolean;
    function Length: Double;
  end;

function Vec2(const AX, AY: Double): TVec2;

implementation

function Vec2(const AX, AY: Double): TVec2;
begin
  Result.X := AX;
  Result.Y := AY;
end;

class operator TVec2.Add(const A, B: TVec2): TVec2;
begin
  Result := Vec2(A.X + B.X, A.Y + B.Y);
end;

class operator TVec2.Multiply(const A: TVec2; const K: Double): TVec2;
begin
  Result := Vec2(A.X * K, A.Y * K);
end;

class operator TVec2.Equal(const A, B: TVec2): Boolean;
begin
  Result := (A.X = B.X) and (A.Y = B.Y);
end;

function TVec2.Length: Double;
begin
  Result := Sqrt(X * X + Y * Y);
end;

end.
