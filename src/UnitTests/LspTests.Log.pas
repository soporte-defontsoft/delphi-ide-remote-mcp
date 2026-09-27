unit LspTests.Log;

// El buzon de lineas del log (Lsp.LogSink.TBuzonDeLineas): lo usan el disco y
// la ventana de la bandeja. Acotado a LOG_BUF_CAP; lo que no cabe se cuenta y
// se dice UNA vez, al recoger (28-sep: estaba escrito dos veces y la nota ya
// decia dos cosas).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBuzonTests = class
  public
    [Test] procedure VacioNoEntregaNada;
    [Test] procedure LoQueNoCabeSeCuentaYSeDice;
    [Test] procedure LoDevueltoVaDelante;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Lsp.Texts,
  Lsp.LogSink;

procedure TBuzonTests.VacioNoEntregaNada;
var
  B: TBuzonDeLineas;
begin
  B := TBuzonDeLineas.Create;
  try
    Assert.IsNull(B.Recoge, 'vacio: nada que recoger');
  finally
    B.Free;
  end;
end;

procedure TBuzonTests.LoQueNoCabeSeCuentaYSeDice;
var
  B: TBuzonDeLineas;
  L: TStringList;
  I: Integer;
begin
  B := TBuzonDeLineas.Create;
  try
    for I := 1 to LOG_BUF_CAP + 3 do
      B.Anade('linea ' + IntToStr(I));
    L := B.Recoge;
    try
      Assert.IsTrue(L.Count = LOG_BUF_CAP + 1, 'el tope y la nota: ' + IntToStr(L.Count));
      Assert.AreEqual('linea 1', L[0]);
      Assert.AreEqual(MsgFmt(SL_SYS_LOG_LINEAS_DESCARTADAS_FMT, [3]), L[L.Count - 1],
        'la nota de lo descartado, la ultima');
    finally
      L.Free;
    end;
    // recogido, el buzon queda vacio y la cuenta a cero
    Assert.IsNull(B.Recoge, 'despues de recoger: nada');
  finally
    B.Free;
  end;
end;

procedure TBuzonTests.LoDevueltoVaDelante;
var
  B: TBuzonDeLineas;
  L, Otra: TStringList;
begin
  B := TBuzonDeLineas.Create;
  try
    B.Anade('a');
    L := B.Recoge;
    // llega "b" mientras "a" no se pudo escribir: "a" vuelve DELANTE
    B.Anade('b');
    try
      B.Devuelve(L);
    finally
      L.Free;
    end;
    Otra := B.Recoge;
    try
      Assert.IsTrue(Otra.Count = 2, 'dos: ' + IntToStr(Otra.Count));
      Assert.AreEqual('a', Otra[0], 'lo devuelto, delante');
      Assert.AreEqual('b', Otra[1]);
    finally
      Otra.Free;
    end;
  finally
    B.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuzonTests);

end.
