program LspUnitTests;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  LspTests.Encodings in 'LspTests.Encodings.pas',
  LspTests.DesignerBin in 'LspTests.DesignerBin.pas',
  LspTests.Dproj in 'LspTests.Dproj.pas',
  LspTests.Images in 'LspTests.Images.pas',
  LspTests.GitArgs in 'LspTests.GitArgs.pas',
  LspTests.Pascal in 'LspTests.Pascal.pas',
  LspTests.Mensajes in 'LspTests.Mensajes.pas',
  LspTests.Foto in 'LspTests.Foto.pas',
  LspTests.Log in 'LspTests.Log.pas';

var
  Runner: ITestRunner;
  Logger: ITestLogger;
  Results: IRunResults;

begin
  try
    // Una jaula propia si nadie le da otra: lanzado por un servidor de
    // workspaces el ejecutor corria sin DELPHI_MCP_ROOTS, o sea en SOLO
    // LECTURA, y las pruebas que escriben por la puerta de escritura (la foto
    // del deshacer, LspTests.Foto) no median nada. Su carpeta, nada mas.
    if GetEnvironmentVariable('DELPHI_MCP_ROOTS') = '' then
      SetEnvironmentVariable('DELPHI_MCP_ROOTS', PChar(ExtractFileDir(ParamStr(0))));
    // --run:<filtro> (el filter de delphi_test): sin esto corria todo
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
