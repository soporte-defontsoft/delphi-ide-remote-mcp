unit LspTests.GitArgs;

{ El troceador de argumentos de la puerta de git (Lsp.Guard.TrocearArgs) tiene
  que leer una linea EXACTAMENTE como la trocea el runtime de C de Windows (lo
  que hace git.exe, spawn directo sin shell): si no, una opcion prohibida
  escrita con comillas o barras invertidas se cuela por la puerta y git la
  ejecuta. Medido 26-sep-2026: --o"utput"= paso un filtro que troceaba solo por
  espacios. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTrocearArgsTests = class
  public
    [Test] procedure EspaciosSimples;
    [Test] procedure ComillasAgrupan;
    [Test] procedure ComillaEnMedioRevelaLaOpcion;
    [Test] procedure ComillaEscapadaConBarraEsLiteral;
    [Test] procedure DosBarrasAntesDeComillaSonUnaYAgrupa;
    [Test] procedure BarrasSueltasSonLiterales;
    [Test] procedure ComillasVaciasSonArgumentoVacio;
    [Test] procedure DobleComillaDentroEsLiteral;
    [Test] procedure GuionCComillado;
    [Test] procedure NombreDelMensajeGitEsUnicoYEstaEnSuCarpeta;
    [Test]
    procedure ConfiguracionEnPrefijosYGruposNoPasa;
    [Test]
    procedure ValorDeUnaOpcionCortaNoEsUnGrupo;
  end;

  { EnComillas (compositor) y TrocearArgs (lector) tienen que ser INVERSOS: la
    linea compuesta desde un argv, troceada, devuelve el MISMO argv - con
    vacios, comillas y barras finales incluidos. Un solo nombrador. }
  [TestFixture]
  TIdaYVueltaTests = class
  private
    procedure IdaYVuelta(const AArgv: array of string);
  public
    [Test] procedure Simples;
    [Test] procedure ConEspacios;
    [Test] procedure ConComillas;
    [Test] procedure RutaConBarras;
    [Test] procedure BarraFinalSinEspacio;
    [Test] procedure BarraFinalConEspacio;
    [Test] procedure VaciosEnMedioYFinal;
    [Test] procedure SoloUnaComilla;
    [Test] procedure ComillaYBarraFinalJuntas;
    [Test] procedure SoloBarras;
    [Test] procedure PathspecLiteralConEspacio;
  end;

implementation

uses
  System.SysUtils,
  Lsp.Guard,
  System.JSON,
  Lsp.Casa;

procedure TTrocearArgsTests.EspaciosSimples;
var
  R: TArray<string>;
begin
  R := TrocearArgs('diff --stat HEAD~1');
  Assert.AreEqual<Integer>(3, Length(R));
  Assert.AreEqual('diff', R[0]);
  Assert.AreEqual('--stat', R[1]);
  Assert.AreEqual('HEAD~1', R[2]);
end;

procedure TTrocearArgsTests.ComillasAgrupan;
var
  R: TArray<string>;
begin
  R := TrocearArgs('--grep="dos palabras" x');
  Assert.AreEqual<Integer>(2, Length(R));
  Assert.AreEqual('--grep=dos palabras', R[0]);
  Assert.AreEqual('x', R[1]);
end;

procedure TTrocearArgsTests.ComillaEnMedioRevelaLaOpcion;
var
  R: TArray<string>;
begin
  // El ataque: una puerta que troceaba por espacios veia --o"utput"=... y no
  // casaba con --output; git quitaba las comillas y escribia el fichero.
  R := TrocearArgs('--o"utput"=/tmp/x');
  Assert.AreEqual<Integer>(1, Length(R));
  Assert.AreEqual('--output=/tmp/x', R[0]);
end;

procedure TTrocearArgsTests.ComillaEscapadaConBarraEsLiteral;
var
  R: TArray<string>;
begin
  // \" = una comilla LITERAL, no delimita: a"b es un solo token con comilla.
  R := TrocearArgs('a\"b');
  Assert.AreEqual<Integer>(1, Length(R));
  Assert.AreEqual('a"b', R[0]);
end;

procedure TTrocearArgsTests.DosBarrasAntesDeComillaSonUnaYAgrupa;
var
  R: TArray<string>;
begin
  // \\" = una barra literal y la comilla AGRUPA (abre): a\b c es un token.
  R := TrocearArgs('a\\"b c"');
  Assert.AreEqual<Integer>(1, Length(R));
  Assert.AreEqual('a\b c', R[0]);
end;

procedure TTrocearArgsTests.BarrasSueltasSonLiterales;
var
  R: TArray<string>;
begin
  // Barras que no preceden a una comilla: literales (una ruta de Windows).
  R := TrocearArgs('C:\Users\x\y');
  Assert.AreEqual<Integer>(1, Length(R));
  Assert.AreEqual('C:\Users\x\y', R[0]);
end;

procedure TTrocearArgsTests.ComillasVaciasSonArgumentoVacio;
var
  R: TArray<string>;
begin
  R := TrocearArgs('a "" b');
  Assert.AreEqual<Integer>(3, Length(R));
  Assert.AreEqual('a', R[0]);
  Assert.AreEqual('', R[1]);
  Assert.AreEqual('b', R[2]);
end;

procedure TTrocearArgsTests.DobleComillaDentroEsLiteral;
var
  R: TArray<string>;
begin
  // "" DENTRO de comillas = una comilla literal (regla del CRT moderno).
  R := TrocearArgs('"a""b"');
  Assert.AreEqual<Integer>(1, Length(R));
  Assert.AreEqual('a"b', R[0]);
end;

procedure TTrocearArgsTests.GuionCComillado;
var
  R: TArray<string>;
begin
  // -c comillado sigue siendo -c: la puerta lo tiene que ver para rechazarlo.
  R := TrocearArgs('-"c" core.pager=x');
  Assert.AreEqual<Integer>(2, Length(R));
  Assert.AreEqual('-c', R[0]);
  Assert.AreEqual('core.pager=x', R[1]);
end;

{ TIdaYVueltaTests }

procedure TIdaYVueltaTests.IdaYVuelta(const AArgv: array of string);
var
  Linea: string;
  R: TArray<string>;
  I: Integer;
begin
  Linea := '';
  for I := 0 to High(AArgv) do
  begin
    if I > 0 then
      Linea := Linea + ' ';
    Linea := Linea + EnComillas(AArgv[I]);
  end;
  R := TrocearArgs(Linea);
  Assert.AreEqual<Integer>(Length(AArgv), Length(R),
    Format('numero de args en la linea compuesta <%s>', [Linea]));
  for I := 0 to High(AArgv) do
    Assert.AreEqual(AArgv[I], R[I], Format('arg %d de <%s>', [I, Linea]));
end;

procedure TIdaYVueltaTests.Simples;
begin
  IdaYVuelta(['diff', '--stat', 'HEAD']);
end;

procedure TIdaYVueltaTests.ConEspacios;
begin
  IdaYVuelta(['--author=John Doe', 'x']);
end;

procedure TIdaYVueltaTests.ConComillas;
begin
  IdaYVuelta(['a' + #34 + 'b', 'c']);
end;

procedure TIdaYVueltaTests.RutaConBarras;
begin
  IdaYVuelta(['C:' + #92 + 'Users' + #92 + 'x' + #92 + 'y', 'z']);
end;

procedure TIdaYVueltaTests.BarraFinalSinEspacio;
begin
  IdaYVuelta(['C:' + #92 + 'path' + #92]);
end;

procedure TIdaYVueltaTests.BarraFinalConEspacio;
begin
  // La que ROMPIA el EnComillas viejo: una barra final ante la comilla de
  // cierre, sin doblar, se comia el argumento siguiente.
  IdaYVuelta(['C:' + #92 + 'dir con espacio' + #92, 'otro']);
end;

procedure TIdaYVueltaTests.VaciosEnMedioYFinal;
begin
  IdaYVuelta(['a', '', 'b', '']);
end;

procedure TIdaYVueltaTests.SoloUnaComilla;
begin
  IdaYVuelta(['' + #34]);
end;

procedure TIdaYVueltaTests.ComillaYBarraFinalJuntas;
begin
  IdaYVuelta(['a' + #34 + 'b' + #92, 'c']);
end;

procedure TIdaYVueltaTests.SoloBarras;
begin
  IdaYVuelta([#92#92#92#92, 'x']);
end;

procedure TIdaYVueltaTests.PathspecLiteralConEspacio;
begin
  IdaYVuelta([':(literal)sub dir/f.txt']);
end;

procedure TTrocearArgsTests.NombreDelMensajeGitEsUnicoYEstaEnSuCarpeta;
var
  A, B, Nombre: string;
  Id: TGUID;
begin
  A := NombreDeMensajeGit;
  B := NombreDeMensajeGit;
  Assert.AreNotEqual(A, B, 'cada mensaje tiene su propio fichero');
  Assert.AreEqual(IncludeTrailingPathDelimiter(ServerTempDir('git')),
    ExtractFilePath(A), 'el temporal del servidor');
  Nombre := ExtractFileName(A);
  Assert.IsTrue(Nombre.StartsWith('msg-') and Nombre.EndsWith('.txt'), Nombre);
  Id := StringToGUID(Copy(Nombre, 5, Length(Nombre) - 8));
  Assert.AreEqual(Copy(Nombre, 5, Length(Nombre) - 8), GUIDToString(Id),
    'la parte variable es un GUID');
end;

function DenegacionDeArgumentosGit(const AArgs: string): string;
var
  Argumentos: TJSONObject;
begin
  Argumentos := TJSONObject.Create;
  try
    Argumentos.AddPair('command', 'status');
    Argumentos.AddPair('args', AArgs);
    Result := ToolCallDenied('delphi_git', Argumentos);
  finally
    Argumentos.Free;
  end;
end;

procedure TTrocearArgsTests.ConfiguracionEnPrefijosYGruposNoPasa;
begin
  for var Args in ['--conf core.sshCommand=x', '-nc core.sshCommand=x',
    '-vqnc core.sshCommand=x', '-c core.sshCommand=x'] do
    Assert.AreNotEqual('', DenegacionDeArgumentosGit(Args), Args);
end;

procedure TTrocearArgsTests.ValorDeUnaOpcionCortaNoEsUnGrupo;
begin
  for var Args in ['-bfeaturec', '-nbfeaturec', '-j4', '--branch=featurec'] do
    Assert.AreEqual('', DenegacionDeArgumentosGit(Args), Args);
end;

initialization
  TDUnitX.RegisterTestFixture(TTrocearArgsTests);
  TDUnitX.RegisterTestFixture(TIdaYVueltaTests);

end.
