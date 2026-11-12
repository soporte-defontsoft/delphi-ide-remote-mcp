unit Timing;

interface

uses
  System.SysUtils;

function ElapsedMs(const AWork: TProc): Int64;

implementation

uses
  System.Diagnostics;

function ElapsedMs(const AWork: TProc): Int64;
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  AWork();
  Result := Watch.ElapsedMilliseconds;
end;

end.
