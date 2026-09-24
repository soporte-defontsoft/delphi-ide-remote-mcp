program LspUnitTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  LspTests.Encodings in 'LspTests.Encodings.pas',
  LspTests.DesignerBin in 'LspTests.DesignerBin.pas',
  LspTests.Dproj in 'LspTests.Dproj.pas';

var
  Runner: ITestRunner;
  Logger: ITestLogger;
  Results: IRunResults;

begin
  try
    Runner := TDUnitX.CreateRunner;
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
