program DatasetSpecTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.Rtti,
  System.Diagnostics,
  System.RegularExpressions,
  System.JSON,
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
  ExportNames in '..\examples\delphi\e02-one-writer-one-reader\answer\ExportNames.pas',
  WordList in '..\examples\delphi\r07-tstringlist-needs-classes\fixed\WordList.pas',
  ScoreBoard in '..\examples\delphi\r08-missing-implementation\fixed\ScoreBoard.pas',
  FileStem in '..\examples\delphi\r09-invented-rtl-function\fixed\FileStem.pas',
  ConsoleReport in '..\examples\delphi\r11-writeln-is-system\fixed\ConsoleReport.pas',
  TaskOrder in '..\examples\delphi\r13-sort-needs-icomparer\fixed\TaskOrder.pas',
  ChangeWatch in '..\examples\delphi\r14-event-needs-a-method\fixed\ChangeWatch.pas',
  WordFrequency in '..\examples\delphi\u01-dictionary-word-count\WordFrequency.pas',
  Timing in '..\examples\delphi\u02-stopwatch-timing\Timing.pas',
  EmailCheck in '..\examples\delphi\u03-regex-email\EmailCheck.pas',
  PersonJson in '..\examples\delphi\u04-json-object\PersonJson.pas',
  TextFiles in '..\examples\delphi\u05-ioutils-files\TextFiles.pas',
  LeapYears in '..\examples\delphi\x01-rtl-leap-year\LeapYears.pas',
  DayCount in '..\examples\delphi\x02-rtl-days-between\DayCount.pas',
  IsoStamp in '..\examples\delphi\x03-rtl-iso8601\IsoStamp.pas',
  DayKeys in '..\examples\delphi\e03-day-key-one-writer\answer\DayKeys.pas';

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
  Board: TScoreBoard;
  Tasks: TList<TTask>;
  Task: TTask;
  Words: TStringList;
  Watcher: TListWatcher;
  Ctx: TRttiContext;
  Dir: string;
  D3: TDateTime;
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

  // r07, r08, r09, r11, r13, r14
  Check('r07 SortedWords', SortedWords('pear apple fig') = 'apple fig pear');
  Board := TScoreBoard.Create;
  try
    Board.Add(5);
    Board.Add(-3);
    Board.Add(2);
    Check('r08 ScoreBoard', Board.Total = 7);
  finally
    Board.Free;
  end;
  Check('r09 ReportName', ReportName('C:\data\sales.csv') = 'sales-report.txt');
  Check('r09 fact: TPath.GetFileNameWithoutExtension',
    TPath.GetFileNameWithoutExtension('C:\data\sales.csv') = 'sales');
  PrintTotal('r11 PrintTotal wrote this line', 3);
  Check('r11 PrintTotal runs', True);
  Tasks := TList<TTask>.Create;
  try
    Task.Title := 'c';
    Task.Priority := 3;
    Tasks.Add(Task);
    Task.Title := 'a';
    Task.Priority := 1;
    Tasks.Add(Task);
    Task.Title := 'b';
    Task.Priority := 2;
    Tasks.Add(Task);
    SortByPriority(Tasks);
    Check('r13 SortByPriority', (Tasks[0].Title = 'a') and (Tasks[1].Title = 'b') and (Tasks[2].Title = 'c'));
  finally
    Tasks.Free;
  end;
  Words := TStringList.Create;
  Watcher := TListWatcher.Create;
  try
    WatchList(Words, Watcher);
    Words.Add('x');
    Words.Add('y');
    Check('r14 the method handler counts the changes', Watcher.Changes = 2);
  finally
    Watcher.Free;
    Words.Free;
  end;

  // where each type lives, asked of the type itself
  Ctx := TRttiContext.Create;
  Check('fact: the unit of each RTL type',
    (TStringList.UnitName = 'System.Classes') and (TComponent.UnitName = 'System.Classes') and
    (TComparer<Integer>.UnitName = 'System.Generics.Defaults') and
    (Ctx.GetType(TypeInfo(TNotifyEvent)).QualifiedName = 'System.Classes.TNotifyEvent') and
    (Ctx.GetType(TypeInfo(TPointF)).QualifiedName = 'System.Types.TPointF'));

  // e03: one writer of the day key, and its inverse
  Check('e03 writer', DayKey(EncodeDate(2026, 3, 7)) = '20260307');
  Check('e03 both callers agree', ArchiveDayKey(EncodeDate(2026, 3, 7)) = DayKey(EncodeDate(2026, 3, 7)));
  Check('e03 reader is the inverse', TryDayKeyToDate(DayKey(EncodeDate(2026, 3, 7)), D3) and
    SameDate(D3, EncodeDate(2026, 3, 7)));
  Check('e03 reader refuses a day that does not exist', not TryDayKeyToDate('20261341', D3));
  Check('e03 reader refuses another shape without an exception',
    not TryDayKeyToDate('2026-1-1', D3) and not TryDayKeyToDate('-2026111', D3));

  // u01..u05: the unit map, in real tasks
  Check('u01 MostFrequentWord', MostFrequentWord('b A b a  a') = 'a');
  Check('u02 ElapsedMs', ElapsedMs(procedure begin Sleep(30); end) >= 20);
  Check('u03 LooksLikeEmail', LooksLikeEmail('ann@example.com') and not LooksLikeEmail('ann@example') and
    not LooksLikeEmail('ann example.com'));
  Check('u04 PersonToJson', PersonToJson('Ann', 30) = '{"name":"Ann","age":30}');
  Dir := TPath.Combine(TPath.GetTempPath, TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'a.txt'), 'a');
    TFile.WriteAllText(TPath.Combine(Dir, 'b.txt'), 'b');
    TFile.WriteAllText(TPath.Combine(Dir, 'c.csv'), 'c');
    Check('u05 CountTextFiles', CountTextFiles(Dir) = 2);
  finally
    TDirectory.Delete(Dir, True);
  end;
  Check('fact: the unit of each type the u examples use',
    (TDictionary<string, Integer>.UnitName = 'System.Generics.Collections') and
    (Ctx.GetType(TypeInfo(TStopwatch)).QualifiedName = 'System.Diagnostics.TStopwatch') and
    (Ctx.GetType(TypeInfo(TRegEx)).QualifiedName = 'System.RegularExpressions.TRegEx') and
    (TJSONObject.UnitName = 'System.JSON') and
    (Ctx.GetType(TypeInfo(TDirectory)).QualifiedName = 'System.IOUtils.TDirectory'));

  // x01..x03: the RTL already has it
  Check('x01 IsLeap', IsLeap(2024) and IsLeap(2000) and not IsLeap(1900) and not IsLeap(2026));
  Check('x02 DaysApart', (DaysApart(EncodeDate(2026, 11, 1), EncodeDate(2026, 11, 12)) = 11) and
    (DaysApart(EncodeDate(2026, 11, 12), EncodeDate(2026, 11, 1)) = 11));
  Check('x02 fact: only whole 24-hour days count',
    DaysApart(EncodeDate(2026, 11, 12) + EncodeTime(8, 0, 0, 0), EncodeDate(2026, 11, 13) + EncodeTime(7, 0, 0, 0)) = 0);
  Check('x02 fact: with DateOf, calendar days count',
    DaysApart(DateOf(EncodeDate(2026, 11, 12) + EncodeTime(8, 0, 0, 0)),
      DateOf(EncodeDate(2026, 11, 13) + EncodeTime(7, 0, 0, 0))) = 1);
  Check('x03 ParseStamp', SameDateTime(ParseStamp('2026-11-12T09:05:07'),
    EncodeDate(2026, 11, 12) + EncodeTime(9, 5, 7, 0)));
  Check('x03 fact: fractions of a second', MilliSecondOf(ParseStamp('2026-11-12T09:05:07.250')) = 250);
  Check('x03 fact: no offset = UTC; the default returns it as written',
    SameDateTime(ISO8601ToDate('2026-11-12T09:05:07'), EncodeDate(2026, 11, 12) + EncodeTime(9, 5, 7, 0)));
  Check('x03 fact: AReturnUTC = False converts that UTC time to local time',
    SameDateTime(ISO8601ToDate('2026-11-12T09:05:07', False),
      TTimeZone.Local.ToLocalTime(EncodeDate(2026, 11, 12) + EncodeTime(9, 5, 7, 0))));
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
