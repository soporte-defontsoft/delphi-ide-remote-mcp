program DatasetPinTest;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  CodeRules in '..\examples\delphi\e04-pin-callers-before-change\answer\CodeRules.pas',
  CodeRulesTests in '..\examples\delphi\e04-pin-callers-before-change\answer\CodeRulesTests.pas',
  PriceRounding in '..\examples\delphi\e07-pin-callers-round-half-up\answer\PriceRounding.pas',
  PriceRoundingTests in '..\examples\delphi\e07-pin-callers-round-half-up\answer\PriceRoundingTests.pas';

var
  Runner: ITestRunner;
  Logger: ITestLogger;
  Results: IRunResults;

begin
  try
    // --run:<filter> (delphi_test's filter) is read here
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    // every [TestFixture] runs, registered or not
    Runner.UseRTTI := True;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
