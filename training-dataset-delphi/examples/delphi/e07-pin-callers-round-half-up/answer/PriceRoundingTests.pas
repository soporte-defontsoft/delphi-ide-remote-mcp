unit PriceRoundingTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPriceRoundingTests = class
  public
    // What already worked, pinned BEFORE the change: both callers of RoundPrice
    [Test]
    procedure LineTotalKeepsWorking;
    [Test]
    procedure WithTaxKeepsWorking;
    // The new rule
    [Test]
    procedure HalvesRoundUp;
  end;

implementation

uses
  PriceRounding;

procedure TPriceRoundingTests.LineTotalKeepsWorking;
begin
  Assert.AreEqual(7.5, LineTotal(2.5, 3), 0.000001);
end;

procedure TPriceRoundingTests.WithTaxKeepsWorking;
begin
  Assert.AreEqual(121.0, WithTax(100, 0.21), 0.000001);
end;

procedure TPriceRoundingTests.HalvesRoundUp;
begin
  Assert.AreEqual(0.13, RoundPrice(0.125), 0.000001);
end;

initialization
  TDUnitX.RegisterTestFixture(TPriceRoundingTests);

end.
