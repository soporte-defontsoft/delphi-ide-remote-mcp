unit ConsoleReport;

interface

procedure PrintTotal(const ALabel: string; const AValue: Integer);

implementation

uses
  System.SysUtils;

procedure PrintTotal(const ALabel: string; const AValue: Integer);
begin
  // WriteLn is a standard routine of the System unit: no prefix, nothing to add to uses
  WriteLn(ALabel + ': ' + IntToStr(AValue));
end;

end.
