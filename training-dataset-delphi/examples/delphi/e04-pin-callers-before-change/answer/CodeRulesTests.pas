unit CodeRulesTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCodeRulesTests = class
  public
    // What already worked, pinned BEFORE the change: both callers of NormalizeCode
    [Test]
    procedure DiscontinuedIgnoresCaseAndOuterSpaces;
    [Test]
    procedure SeasonalKnowsOnlyItsCodes;
    // The new rule
    [Test]
    procedure InnerSpacesAreIgnored;
  end;

implementation

uses
  CodeRules;

procedure TCodeRulesTests.DiscontinuedIgnoresCaseAndOuterSpaces;
begin
  Assert.IsTrue(IsDiscontinued(' k-100 '));
  Assert.IsFalse(IsDiscontinued('K-101'));
end;

procedure TCodeRulesTests.SeasonalKnowsOnlyItsCodes;
begin
  Assert.IsTrue(IsSeasonal('w-020'));
  Assert.IsFalse(IsSeasonal('K-100'));
end;

procedure TCodeRulesTests.InnerSpacesAreIgnored;
begin
  Assert.IsTrue(IsDiscontinued('k - 100'));
  Assert.AreEqual('W-010', NormalizeCode(' w - 010 '));
end;

initialization
  TDUnitX.RegisterTestFixture(TCodeRulesTests);

end.
