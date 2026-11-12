unit MemoLog;

interface

uses
  FMX.Memo;

procedure AddLogLine(const AMemo: TMemo; const AText: string);

implementation

procedure AddLogLine(const AMemo: TMemo; const AText: string);
begin
  // FireMonkey's TMemo has a unit of its own, FMX.Memo (not FMX.StdCtrls)
  AMemo.Lines.Add(AText);
end;

end.
