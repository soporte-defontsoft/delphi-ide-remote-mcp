program DatasetSpecTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.DateUtils,
  System.Generics.Collections,
  TimeText in '..\examples\delphi\t01-minute-second\TimeText.pas',
  SendStatus in '..\examples\delphi\t03-char-code-outside-quotes\SendStatus.pas',
  Shifts in '..\examples\delphi\t04-global-function-not-method\answer\Shifts.pas',
  OrderMath in '..\examples\delphi\t05-signature-in-both-places\answer\OrderMath.pas',
  TextLines in '..\examples\delphi\t06-try-finally-free\TextLines.pas',
  PeopleSort in '..\examples\delphi\t07-sort-generic-list\PeopleSort.pas',
  CodePrefix in '..\examples\delphi\t08-copy-is-one-based\CodePrefix.pas',
  AppLogger in '..\examples\delphi\t09-interface-reference-counting\AppLogger.pas',
  Shop in '..\examples\delphi\t10-forward-class-declaration\Shop.pas',
  ColorCodes in '..\examples\delphi\t11-case-needs-ordinal\ColorCodes.pas',
  StockSum in '..\examples\delphi\r01-missing-end\fixed\StockSum.pas',
  Counters in '..\examples\delphi\r02-unsatisfied-forward\fixed\Counters.pas',
  SizeCodes in '..\examples\delphi\r04-case-on-string\fixed\SizeCodes.pas',
  InvoiceMath in '..\examples\delphi\r05-declaration-differs\fixed\InvoiceMath.pas',
  CustomerText in '..\examples\delphi\l01-reuse-existing-helper\answer\CustomerText.pas',
  ProductCodes in '..\examples\delphi\l02-reuse-normalizer\answer\ProductCodes.pas',
  ReportLines in '..\examples\delphi\l03-third-copy-makes-a-helper\answer\ReportLines.pas',
  Percentages in '..\examples\delphi\e01-rule-in-one-place\answer\Percentages.pas',
  ExportNames in '..\examples\delphi\e02-one-writer-one-reader\answer\ExportNames.pas';

// The judge of the dataset's Delphi examples: every answer unit is in the
// uses clause above (so it compiles) and every check below runs it.
// PASS/FAIL lines + ExitCode = number of failures (delphi_test reads both).

var
  Failures: Integer = 0;

procedure Check(const AName: string; const AOk: Boolean);
begin
  if AOk then
    Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName);
    Inc(Failures);
  end;
end;

function Raises(const AProc: TProc): Boolean;
begin
  Result := False;
  try
    AProc;
  except
    on EArgumentOutOfRangeException do
      Result := True;
  end;
end;

procedure RunChecks;
var
  D, D2: TDateTime;
  Shift: TShift;
  Order: OrderMath.TOrder;
  People: TList<TPerson>;
  Person: TPerson;
  Logger: ILogger;
  Customer: TCustomer;
  ShopOrder: Shop.TOrder;
  Counter: TCounter;
  Invoice: TInvoice;
  Year, Number: Integer;
begin
  D := EncodeDate(2026, 11, 12) + EncodeTime(9, 5, 7, 0);

  // t01
  Check('t01 MinuteSecond', MinuteSecond(D) = '05:07');
  Check('t01 fact: mm:ss shows the month', FormatDateTime('mm:ss', D) = '11:07');
  Check('t01 fact: hh:mm shows the minutes', FormatDateTime('hh:mm', D) = '09:05');

  // t03
  Check('t03 SentText', (Length(SentText) = 6) and (SentText[6] = #$2714));
  Check('t03 fact: a quoted code is literal text', Length('#$2714') = 6);

  // t04
  Check('t04 IsWeekend', IsWeekend(EncodeDate(2026, 11, 14)) and
    IsWeekend(EncodeDate(2026, 11, 15)) and not IsWeekend(EncodeDate(2026, 11, 13)));
  Check('t04 fact: DayOfTheWeek is ISO, DayOfWeek starts on Sunday',
    (DayOfTheWeek(EncodeDate(2026, 11, 15)) = 7) and (DayOfWeek(EncodeDate(2026, 11, 15)) = 1));
  Shift := TShift.Create(D);
  try
    Check('t04 TShift unchanged', Shift.Start = D);
  finally
    Shift.Free;
  end;

  // t05
  Order := OrderMath.TOrder.Create(200);
  try
    Check('t05 Total with discount', Order.Total(10) = 180);
  finally
    Order.Free;
  end;

  // t06
  Check('t06 CountNonEmptyLines', CountNonEmptyLines('a'#13#10#13#10'  '#13#10'b') = 2);

  // t07
  People := TList<TPerson>.Create;
  try
    Person.Age := 0;
    Person.Name := 'carol';
    People.Add(Person);
    Person.Name := 'Alice';
    People.Add(Person);
    Person.Name := 'bob';
    People.Add(Person);
    SortByName(People);
    Check('t07 SortByName ignores case', (People[0].Name = 'Alice') and
      (People[1].Name = 'bob') and (People[2].Name = 'carol'));
  finally
    People.Free;
  end;

  // t08
  Check('t08 Prefix3', (Prefix3('ABCDEF') = 'ABC') and (Prefix3('AB') = 'AB'));
  Check('t08 fact: helpers count from 0, Copy and Pos from 1',
    ('ABCDEF'.Substring(1, 3) = 'BCD') and ('ABCDEF'.IndexOf('A') = 0) and (Pos('A', 'ABCDEF') = 1));

  // t09
  Logger := NewMemoryLogger;
  Logger.Log('a');
  Logger.Log('b');
  Check('t09 logger counts', Logger.Count = 2);
  Logger := nil;

  // t10
  Customer := TCustomer.Create('Ann');
  try
    ShopOrder := Customer.AddOrder;
    Check('t10 forward-declared classes', (ShopOrder.Customer = Customer) and
      (Customer.Orders.Count = 1));
  finally
    Customer.Free;
  end;

  // t11
  Check('t11 ColorCode', (ColorCode('Green') = $00FF00) and (ColorCode('RED') = $0000FF) and
    (ColorCode('pink') = -1));

  // r01, r02, r04, r05 (the fixed units)
  Check('r01 SumPositive', SumPositive([3, -2, 5]) = 8);
  Counter := TCounter.Create;
  try
    Counter.Increment;
    Counter.Increment;
    Counter.Reset;
    Check('r02 Reset', Counter.Value = 0);
  finally
    Counter.Free;
  end;
  Check('r04 SizeOrder', (SizeOrder('M') = 2) and (SizeOrder('XL') = 0));
  Invoice := TInvoice.Create(100);
  try
    Check('r05 Gross', Invoice.Gross(21) = 121);
  finally
    Invoice.Free;
  end;

  // l01, l02, l03
  Check('l01 CustomerLabel', (CustomerLabel(' Ann ', 'Lee') = 'Customer: Ann Lee') and
    (CustomerLabel('', 'Lee') = 'Customer: Lee'));
  Check('l02 IsSeasonal', IsSeasonal(' s-010 ') and not IsSeasonal('S-030') and
    IsDiscontinued('a-100'));
  D2 := EncodeDate(2026, 11, 12);
  Check('l03 lines', (InvoiceLine(7, D2) = 'Invoice 7 - 2026-11-12') and
    (DeliveryLine(7, D2) = 'Delivery 7 - 2026-11-12') and
    (ReturnLine(7, D2) = 'Return 7 - 2026-11-12'));

  // e01, e02
  Check('e01 Commission refuses a negative percent',
    Raises(procedure begin Commission(100, -5); end));
  Check('e01 the three refuse 101',
    Raises(procedure begin ApplyDiscount(100, 101); end) and
    Raises(procedure begin ApplySurcharge(100, 101); end) and
    Raises(procedure begin Commission(100, 101); end));
  Check('e01 values', (ApplyDiscount(200, 10) = 180) and (ApplySurcharge(200, 10) = 220) and
    (Commission(200, 10) = 20));
  Check('e02 writer', ExportFileName(2026, 7) = 'export-2026-0007.csv');
  Check('e02 both callers agree', ArchiveFileName(2026, 7) = ExportFileName(2026, 7));
  Check('e02 reader is the inverse', TryParseExportFileName(ExportFileName(2026, 7), Year, Number) and
    (Year = 2026) and (Number = 7));
  Check('e02 reader refuses another name', not TryParseExportFileName('report.csv', Year, Number));
end;

begin
  try
    RunChecks;
  except
    on E: Exception do
    begin
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  Writeln(Failures, ' failure(s)');
  ExitCode := Failures;
end.
