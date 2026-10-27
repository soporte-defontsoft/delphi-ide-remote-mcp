unit LspTests.RutasOrdinal;

// H1 de la 1.23: la jaula comparaba rutas con StartsText / SameText / MatchText
// (lingueisticos: CompareString con el LOCALE del usuario), que dan por DENTRO
// o IGUALES dos nombres que el sistema de ficheros trata como entradas
// DISTINTAS -la eszett U+00DF y su mayuscula U+1E9E, el par U+01C5/U+01C4- y por
// ahi se leia y se escribia fuera de la jaula (medido contra r1222ci con la
// sonda sonda_raiz_lingu). El arreglo: RutaDentroDe (Lsp.Rutas) para el prefijo
// y SameFileName (RTL) para la igualdad, las dos por la comparacion ORDINAL
// (CompareStringOrdinal con IgnoreCase), que es la del sistema de ficheros.
//
// El juez de esta prueba es el DISCO: crea cada par de nombres en su temporal y
// le pregunta a NTFS si son la MISMA entrada (GetFileInformationByHandle: mismo
// volumen y mismo indice). RutaDentroDe y SameFileName tienen que contestar lo
// que el disco; y se mide que los lingueisticos NO -ahi vivia el agujero-. Sin
// privilegios (solo crea carpetas en su temporal): va en PURAS.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRutasDelDiscoTests = class
  private
    FBase: string;
  public
    [Setup] procedure Prepara;
    [TearDown] procedure Limpia;
    [Test] procedure LaIgualdadEsLaDelDisco;
    [Test] procedure ElDentroDeEsElDelDisco;
    [Test] procedure LosLinguisticosNoSonElDisco;
    [Test] procedure ElDentroDeRespetaElLimite;
    [Test] procedure LosDentroDePorTextoSonElDisco;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,     // StartsText, SameText (los lingueisticos que se miden)
  Winapi.Windows,
  Lsp.Rutas,           // RutaDentroDe (el juez nuevo); SameFileName es de la RTL
  Lsp.ProjectUnits,    // IncludeFor: la ruta que se escribe en el .dpr (V81)
  Lsp.References,      // RelToRoot: lo que cuelga de una raiz (V81)
  Lsp.Casa;            // FragmentoUnico

type
  TPar = record
    A, B, Etiqueta: string;
  end;

// un nombre con un punto de codigo concreto, para que el fuente quede en ASCII
function Letra(C: Word): string;
begin
  Result := WideChar(C);
end;

function Pares: TArray<TPar>;
  function P(const A, B, E: string): TPar;
  begin
    Result.A := A;
    Result.B := B;
    Result.Etiqueta := E;
  end;
begin
  Result := [
    P('stra' + Letra($00DF) + 'e', 'stra' + Letra($1E9E) + 'e', 'eszett U+00DF / U+1E9E'),
    P(Letra($01C5) + 'x', Letra($01C4) + 'x', 'U+01C5 / U+01C4'),
    P('caf' + Letra($00E9), 'caf' + Letra($00C9), 'e-aguda U+00E9 / U+00C9'),
    P('a' + Letra($00F1), 'a' + Letra($00D1), 'ene U+00F1 / U+00D1'),
    P('casa', 'CASA', 'ASCII casa / CASA')];
end;

// la MISMA entrada para el disco: mismo volumen y mismo indice de fichero
// (GetFileInformationByHandle). Las dos rutas tienen que existir ya.
function MismaEntradaDisco(const A, B: string): Boolean;
  function Abre(const P: string; out Info: TByHandleFileInformation): Boolean;
  var
    H: THandle;
  begin
    Result := False;
    H := CreateFile(PChar(P), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
    if H = INVALID_HANDLE_VALUE then
      Exit;
    try
      Result := GetFileInformationByHandle(H, Info);
    finally
      CloseHandle(H);
    end;
  end;
var
  ia, ib: TByHandleFileInformation;
begin
  Result := Abre(A, ia) and Abre(B, ib) and
    (ia.dwVolumeSerialNumber = ib.dwVolumeSerialNumber) and
    (ia.nFileIndexHigh = ib.nFileIndexHigh) and
    (ia.nFileIndexLow = ib.nFileIndexLow);
end;

// crea las dos carpetas del par y devuelve sus rutas completas
procedure CreaPar(const ABase: string; const APar: TPar; out FullA, FullB: string);
begin
  FullA := TPath.Combine(ABase, APar.A);
  FullB := TPath.Combine(ABase, APar.B);
  ForceDirectories(FullA);
  ForceDirectories(FullB);
end;

{ TRutasDelDiscoTests }

procedure TRutasDelDiscoTests.Prepara;
begin
  // en la carpeta del exe (la copia de la salida que el contenedor SI puede
  // escribir; TPath.GetTempPath es del lowbox y no se deja), no en el temporal
  FBase := TPath.Combine(ExtractFileDir(ParamStr(0)), 'rutas-disco-' + FragmentoUnico);
  ForceDirectories(FBase);
end;

procedure TRutasDelDiscoTests.Limpia;
begin
  if TDirectory.Exists(FBase) then
    TDirectory.Delete(FBase, True);
end;

procedure TRutasDelDiscoTests.LaIgualdadEsLaDelDisco;
var
  Par: TPar;
  FullA, FullB: string;
begin
  for Par in Pares do
  begin
    CreaPar(FBase, Par, FullA, FullB);
    Assert.AreEqual(MismaEntradaDisco(FullA, FullB), SameFileName(FullA, FullB),
      'SameFileName tiene que decir lo que el disco (' + Par.Etiqueta + ')');
  end;
end;

procedure TRutasDelDiscoTests.ElDentroDeEsElDelDisco;
var
  Par: TPar;
  FullA, FullB: string;
begin
  // hermanas bajo FBase: B esta "dentro de" A solo si son la MISMA entrada
  for Par in Pares do
  begin
    CreaPar(FBase, Par, FullA, FullB);
    Assert.AreEqual(MismaEntradaDisco(FullA, FullB), RutaDentroDe(FullA, FullB),
      'RutaDentroDe tiene que decir lo que el disco (' + Par.Etiqueta + ')');
  end;
end;

procedure TRutasDelDiscoTests.LosLinguisticosNoSonElDisco;
var
  FullA, FullB: string;
begin
  // el agujero, medido: en el par eszett el disco dice DISTINTAS y el prefijo
  // lingueistico (StartsText, el de la jaula hasta r1222ci) dice DENTRO
  CreaPar(FBase, Pares[0], FullA, FullB);
  Assert.IsFalse(MismaEntradaDisco(FullA, FullB), 'el disco: eszett son dos entradas');
  Assert.IsTrue(StartsText(IncludeTrailingPathDelimiter(FullA), IncludeTrailingPathDelimiter(FullB)),
    'StartsText (lingueistico) las da por DENTRO: ahi estaba la fuga');
  Assert.IsFalse(RutaDentroDe(FullA, FullB), 'RutaDentroDe (ordinal) no las da por dentro');
  // y al reves: en el par e-aguda el disco dice IGUALES y SameText (pliega solo
  // a..z) las da por DISTINTAS -negaba un renombrado de mayusculas con acento-
  CreaPar(FBase, Pares[2], FullA, FullB);
  Assert.IsTrue(MismaEntradaDisco(FullA, FullB), 'el disco: e-aguda es la misma entrada');
  Assert.IsFalse(SameText(FullA, FullB), 'SameText no pliega la acentuada: las da por distintas');
  Assert.IsTrue(SameFileName(FullA, FullB), 'SameFileName (ordinal) si las da por iguales');
end;

procedure TRutasDelDiscoTests.ElDentroDeRespetaElLimite;
var
  Foo, FooBar, Raiz, Sub: string;
begin
  Foo := TPath.Combine(FBase, 'foo');
  FooBar := TPath.Combine(FBase, 'foobar');
  ForceDirectories(Foo);
  ForceDirectories(FooBar);
  Assert.IsFalse(RutaDentroDe(Foo, FooBar), 'foobar NO esta dentro de foo (el limite es un separador)');
  Raiz := TPath.Combine(FBase, 'root');
  Sub := TPath.Combine(Raiz, 'sub');
  ForceDirectories(Sub);
  Assert.IsTrue(RutaDentroDe(Raiz, Sub), 'sub SI esta dentro de root');
  Assert.IsTrue(RutaDentroDe(Raiz, Raiz), 'una ruta esta dentro de si misma (o es ella)');
end;

procedure TRutasDelDiscoTests.LosDentroDePorTextoSonElDisco;
var
  Kelvin, Ka: string;
begin
  // V81 de la 1.23.1: dos "dentro de" que quedaron por TEXTO (.ToLower.StartsWith),
  // fuera de la jaula. Medido el 27-oct: el signo Kelvin (U+212A) lo pasa ToLower a
  // 'k', y para el disco P<Kelvin> y Pk son DOS carpetas - aqui el texto se equivoca
  // hacia DENTRO -
  Kelvin := TPath.Combine(FBase, 'P' + Letra($212A));
  Ka := TPath.Combine(FBase, 'Pk');
  ForceDirectories(Kelvin);
  ForceDirectories(Ka);
  Assert.IsFalse(MismaEntradaDisco(Kelvin, Ka), 'el disco: P<Kelvin> y Pk son dos carpetas');
  // IncludeFor escribia 'U.pas' (al lado del .dpr) de una unidad que esta en otra
  Assert.AreNotEqual('U.pas', IncludeFor(TPath.Combine(Kelvin, 'Amb.dpr'), TPath.Combine(Ka, 'U.pas')),
    'IncludeFor: la unidad de Pk no esta junto al .dpr de P<Kelvin>');
  // RelToRoot quitaba la raiz de una ruta que no cuelga de ella
  Assert.AreEqual(TPath.Combine(Ka, 'Win32\a.pas'), RelToRoot(TPath.Combine(Ka, 'Win32\a.pas'), Kelvin),
    'RelToRoot: lo de Pk no cuelga de P<Kelvin>');
  // ...y lo que si cuelga, igual que antes
  Assert.AreEqual('Sub\U.pas', IncludeFor(TPath.Combine(Ka, 'Amb.dpr'), TPath.Combine(Ka, 'Sub\U.pas')));
  Assert.AreEqual('\Win32\a.pas', RelToRoot(TPath.Combine(Ka, 'Win32\a.pas'), Ka));
end;

initialization

TDUnitX.RegisterTestFixture(TRutasDelDiscoTests);

end.
