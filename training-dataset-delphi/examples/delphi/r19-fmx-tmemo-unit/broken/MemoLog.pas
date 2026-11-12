unit MemoLog;

interface

uses
  FMX.StdCtrls;

procedure AddLogLine(const AMemo: TMemo; const AText: string);

implementation

procedure AddLogLine(const AMemo: TMemo; const AText: string);
begin
  AMemo.Lines.Add(AText);
end;

end.
