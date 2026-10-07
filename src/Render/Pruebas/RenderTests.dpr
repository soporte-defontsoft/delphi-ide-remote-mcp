program RenderTests;

{ Bateria MANUAL de los dos renderizadores (DelphiFormRenderVcl/Fmx): los
  lanza como los lanza el servidor y comprueba el protocolo, los codigos de
  salida y los PNG. Fuera de run_all y de delphi_test (en su contenedor los
  ayudantes no pueden crear ventanas): se corre desde la sesion del usuario,
  tras tocar un ayudante y antes de una release (src\Render\README.md). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  URenderTests in 'URenderTests.pas';

var
  Runner: ITestRunner;
  Logger: ITestLogger;
  Results: IRunResults;

begin
  try
    // --run:<filter> (delphi_test's filter) is read here
    TDUnitX.CheckCommandLine;
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
