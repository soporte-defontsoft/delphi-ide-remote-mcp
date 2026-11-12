unit ConsoleReport;

interface

procedure PrintTotal(const ALabel: string; const AValue: Integer);

implementation

uses
  System.SysUtils;

procedure PrintTotal(const ALabel: string; const AValue: Integer);
begin
  System.SysUtils.WriteLn(ALabel + ': ' + IntToStr(AValue));
end;

end.
