unit LspTests.Dproj;

{ El escaner de peligros de un .dproj antes de compilarlo: lo que delphi_build
  rechaza (tareas que ejecutan) y lo que SALTA en vez de rechazar (los eventos
  pre/post build de la build firmada, decision de David del 24-sep-2026). }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDprojHazardTests = class
  public
    [Test] procedure ProyectoLimpioNoTienePeligro;
    [Test] procedure EventoDeBuildEsPeligro;
    [Test] procedure EventoDeBuildSeIgnoraSiSePide;
    [Test] procedure EventoVacioNoEsPeligro;
    [Test] procedure UnaTareaExecEsPeligroAunqueSeIgnorenEventos;
  end;

implementation

uses
  System.SysUtils,
  Lsp.Dproj;

const
  RUTA = 'C:\Proyecto\App.dproj';
  CABECERA = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup>'#13#10;
  PIE = '</Project>'#13#10;

procedure TDprojHazardTests.ProyectoLimpioNoTienePeligro;
begin
  Assert.AreEqual('', DprojBuildHazard(CABECERA + PIE, RUTA));
end;

procedure TDprojHazardTests.EventoDeBuildEsPeligro;
var
  R: string;
begin
  R := DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PostBuildEvent>signtool sign $(OUTPUTPATH)</PostBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA);
  Assert.AreNotEqual('', R);
  Assert.IsTrue(Pos('postbuildevent', R) > 0, 'nombra el evento: ' + R);
end;

procedure TDprojHazardTests.EventoDeBuildSeIgnoraSiSePide;
begin
  // delphi_build vacia los eventos en la linea de msbuild y avisa: la build
  // es para trabajar, la firmada es del operador fuera del servidor.
  Assert.AreEqual('', DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PreBuildEvent>copy a b</PreBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA, True));
end;

procedure TDprojHazardTests.EventoVacioNoEsPeligro;
begin
  Assert.AreEqual('', DprojBuildHazard(CABECERA +
    '  <PropertyGroup><PreBuildEvent></PreBuildEvent><PostBuildEvent>  </PostBuildEvent></PropertyGroup>'#13#10 +
    PIE, RUTA));
end;

procedure TDprojHazardTests.UnaTareaExecEsPeligroAunqueSeIgnorenEventos;
var
  R: string;
begin
  R := DprojBuildHazard(CABECERA +
    '  <Target Name="Rompe" BeforeTargets="Build"><Exec Command="cmd /c del *.*"/></Target>'#13#10 +
    PIE, RUTA, True);
  Assert.AreNotEqual('', R, 'ignorar eventos no abre la puerta a las tareas');
  Assert.IsTrue(Pos('exec', R) > 0, 'nombra la tarea: ' + R);
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojHazardTests);

end.
