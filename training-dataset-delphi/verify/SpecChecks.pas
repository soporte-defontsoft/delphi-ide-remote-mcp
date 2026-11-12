unit SpecChecks;

// What every judge of the dataset shares: one PASS/FAIL line per check, and the number of failures as its verdict
// (delphi_test reads both).

interface

uses
  System.SysUtils;

procedure Check(const AName: string; const AOk: Boolean);
// Runs the checks of a judge, in order, and writes its verdict: an exception that escapes them is one more failure.
// Returns the number of failures, the judge's exit code.
function RunJudge(const AChecks: array of TProc): Integer;

implementation

var
  Failures: Integer = 0;

procedure Check(const AName: string; const AOk: Boolean);
begin
  if AOk then
    Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName);
    Inc(Failures);
  end;
end;

function RunJudge(const AChecks: array of TProc): Integer;
var
  Checks: TProc;
begin
  try
    for Checks in AChecks do
      Checks();
  except
    on E: Exception do
    begin
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  Writeln(Failures, ' failure(s)');
  Result := Failures;
end;

end.
