unit LspTests.DesignerMeta;

// La nota de las tablas del disenador (Lsp.DesignerMeta.NotaDeBuild): las
// tablas salieron de UNA build de RAD Studio (META_BUILD), y con otra activa
// "no esta en la tabla" deja de querer decir "no existe" (DSGN-049). En esta
// maquina la activa ES la de las tablas, asi que la rama de otra build solo se
// prueba aqui, con la build dada.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNotaDeBuildTests = class
  public
    [Test] procedure LaMismaBuildNoDiceNada;
    [Test] procedure SinBuildConocidaNoDiceNada;
    [Test] procedure OtraBuildLoDiceConLasDos;
  end;

implementation

uses
  System.SysUtils,
  Lsp.Texts,
  Lsp.DesignerMeta;

procedure TNotaDeBuildTests.LaMismaBuildNoDiceNada;
begin
  Assert.AreEqual('', NotaDeBuild(META_BUILD));
  // la build es un numero: las mayusculas no cambian nada, pero se comparan igual
  Assert.AreEqual('', NotaDeBuild(LowerCase(META_BUILD)));
end;

procedure TNotaDeBuildTests.SinBuildConocidaNoDiceNada;
begin
  // sin instalacion activa (o sin su build) no se avisa de nada
  Assert.AreEqual('', NotaDeBuild(''));
end;

procedure TNotaDeBuildTests.OtraBuildLoDiceConLasDos;
var
  Nota: string;
begin
  // la 13.2 de la VM (build 37.0.60952): mismo 37.0, otra build
  Nota := NotaDeBuild('37.0.60952.1234');
  Assert.IsTrue(EsMsg(Nota, SN_DESIGNER_TABLA_OTRA_BUILD_FMT), 'DSGN-049: ' + Nota);
  Assert.IsTrue(Nota.Contains(META_BUILD), 'la build de la tabla: ' + Nota);
  Assert.IsTrue(Nota.Contains('37.0.60952.1234'), 'la activa: ' + Nota);
end;

initialization
  TDUnitX.RegisterTestFixture(TNotaDeBuildTests);

end.
