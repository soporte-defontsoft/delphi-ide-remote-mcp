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
  System.NetEncoding,
  System.Hash,
  System.Threading,
  System.SyncObjs,
  System.Math,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.ConsoleUI.Wait,
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
  DayKeys in '..\examples\delphi\e03-day-key-one-writer\answer\DayKeys.pas',
  DecimalText in '..\examples\delphi\r15-strtofloat-locale\fixed\DecimalText.pas',
  DailyAverage in '..\examples\delphi\r16-integer-division\fixed\DailyAverage.pas',
  NameFilter in '..\examples\delphi\r17-fdmemtable-filter-quotes\fixed\NameFilter.pas',
  Money in '..\examples\delphi\t12-currency-for-money\Money.pas',
  ScoreCopy in '..\examples\delphi\t13-dynamic-array-shares\ScoreCopy.pas',
  Utf8Size in '..\examples\delphi\t14-utf8-bytes\Utf8Size.pas',
  Base64Text in '..\examples\delphi\t15-base64-one-line\Base64Text.pas',
  Fingerprint in '..\examples\delphi\t16-sha256-hex\Fingerprint.pas',
  BackgroundSum in '..\examples\delphi\t17-queue-to-main-thread\BackgroundSum.pas',
  ParallelCount in '..\examples\delphi\t18-parallel-counter\ParallelCount.pas',
  PriceFilter in '..\examples\delphi\d01-fdmemtable-filter\PriceFilter.pas',
  ConfigPath in '..\examples\delphi\x04-rtl-path-combine\ConfigPath.pas',
  QuantityList in '..\examples\delphi\g01-never-swallow-errors\answer\QuantityList.pas',
  TextBlob in '..\examples\delphi\r18-stream-needs-classes\fixed\TextBlob.pas',
  ProductTable in '..\examples\delphi\r20-field-types-need-data-db\fixed\ProductTable.pas',
  Geometry in '..\examples\delphi\u07-interface-uses\Geometry.pas',
  SafeLog in '..\examples\delphi\u08-critical-section\SafeLog.pas',
  OrderRefs in '..\examples\delphi\e05-second-writer-bug-report\answer\OrderRefs.pas',
  InvoiceRefs in '..\examples\delphi\e06-third-writer-reuses\answer\InvoiceRefs.pas',
  CustomerJson in '..\examples\delphi\x05-json-by-hand\answer\CustomerJson.pas',
  SearchUrl in '..\examples\delphi\x06-rtl-url-encode\SearchUrl.pas',
  MonthDays in '..\examples\delphi\x07-rtl-days-in-month\MonthDays.pas',
  FileKinds in '..\examples\delphi\x08-rtl-file-extension\FileKinds.pas',
  PageText in '..\examples\delphi\x09-rtl-html-encode\answer\PageText.pas',
  ValueBands in '..\examples\delphi\x10-rtl-floor\ValueBands.pas',
  CustomerQueries in '..\examples\delphi\x11-sql-parameters\answer\CustomerQueries.pas',
  BackupFiles in '..\examples\delphi\e08-second-writer-file-name\answer\BackupFiles.pas',
  SpecChecks in 'SpecChecks.pas';

// The judge of the dataset's Delphi examples: every answer unit is in the
// uses clause above (so it compiles) and every check below runs it.
// PASS/FAIL lines + ExitCode = number of failures (delphi_test reads both).

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
  ES: TFormatSettings;
  Msg, S, S2: string;
  A, B, Scores, Bonus: TArray<Integer>;
  DA, DB2: Double;
  Mem: TFDMemTable;
  Bad, Wait: Integer;
  Done: Boolean;
  GotTotal: Int64;
  GotThread: TThreadID;
  Pt: TPointF;
  Log: TSafeLog;
  J: TJSONValue;
  Conn: TFDConnection;
  Day: TDateTime;
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

  // r15, r16, r17
  Check('r15 ParseDecimal reads a dot whatever the locale', ParseDecimal('1.5') = 1.5);
  ES := TFormatSettings.Create('es-ES');
  Msg := '';
  try
    StrToFloat('1.5', ES);
  except
    on E: EConvertError do
      Msg := E.Message;
  end;
  Check('r15 fact: with the Spanish settings StrToFloat raises the EConvertError of exception.txt',
    Msg = '''1.5'' is not a valid floating point value');
  Check('r16 UnitsPerDay truncates', (UnitsPerDay(10, 4) = 2) and (UnitsPerDay(12, 4) = 3));
  Mem := TFDMemTable.Create(nil);
  try
    Mem.FieldDefs.Add('Name', ftString, 30);
    Mem.CreateDataSet;
    Mem.AppendRecord(['Ann']);
    Mem.AppendRecord(['bob']);
    Mem.AppendRecord(['O''Brien']);
    Msg := '';
    try
      Mem.Filter := 'Name = Ann';
      Mem.Filtered := True;
    except
      on E: Exception do
        Msg := E.Message;
    end;
    Mem.Filtered := False;
    Check('r17 fact: an unquoted value is read as a column (the message of exception.txt)',
      Msg = '[FireDAC][Stan][Eval]-100. Column or function [Ann] is not found. Hint: if the name is a ' +
      'function name, then add FireDAC.Stan.ExprFuncs to uses clause');
    FilterByName(Mem, 'BOB');
    Check('r17 FilterByName quotes the value and ignores case', Mem.RecordCount = 1);
    Mem.Filtered := False;
    FilterByName(Mem, 'o''brien');
    Check('r17 FilterByName survives a quote inside the name', Mem.RecordCount = 1);
  finally
    Mem.Free;
  end;

  // t12..t18
  Check('t12 TotalOf is exact to the cent', TotalOf([0.10, 0.20]) = 0.30);
  DA := 0.1;
  DB2 := 0.2;
  Check('t12 fact: with Double, 0.1 + 0.2 is not 0.3', DA + DB2 <> 0.3);
  A := [1, 2, 3];
  B := A;
  B[0] := 99;
  Check('t13 fact: assigning a dynamic array shares it', A[0] = 99);
  S := 'abc';
  S2 := S;
  S2[1] := 'x';
  Check('t13 fact: a string is copy-on-write - changing the copy leaves the original', (S = 'abc') and (S2 = 'xbc'));
  Scores := [1, 2, 3];
  Bonus := WithBonus(Scores, 10);
  Check('t13 WithBonus leaves the caller''s array alone', (Bonus[0] = 11) and (Bonus[2] = 13) and (Scores[0] = 1));
  Check('t14 Utf8ByteCount', (Utf8ByteCount('Caf' + #$00E9) = 5) and (Length('Caf' + #$00E9) = 4));
  S := ToBase64(StringOfChar('a', 100));
  Check('t15 ToBase64 is one line and decodes back', (Pos(#13, S) = 0) and (Pos(#10, S) = 0) and
    (TNetEncoding.Base64String.Decode(S) = StringOfChar('a', 100)));
  S := TNetEncoding.Base64.Encode(StringOfChar('a', 100));
  Check('t15 fact: TNetEncoding.Base64 breaks the same text into lines', (Pos(#13, S) > 0) or (Pos(#10, S) > 0));
  Check('t16 Sha256Hex(abc)', Sha256Hex('abc') = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  Done := False;
  GotTotal := 0;
  GotThread := 0;
  SumInBackground(100,
    procedure(ATotal: Int64)
    begin
      GotTotal := ATotal;
      GotThread := TThread.CurrentThread.ThreadID;
      Done := True;
    end);
  Wait := 0;
  while not Done and (Wait < 500) do
  begin
    CheckSynchronize(10);
    Inc(Wait);
  end;
  Check('t17 the callback ran on the main thread, with the total', Done and (GotTotal = 5050) and
    (GotThread = MainThreadID));
  Check('t18 CountMultiples', CountMultiples(100000, 3) = 33333);

  // d01, x04, g01
  Check('d01 CountAbove', (CountAbove([5, 12, 30, 10.5], 10) = 3) and (CountAbove([5, 12, 30, 10.5], 10.5) = 2));
  Mem := TFDMemTable.Create(nil);
  try
    Mem.FieldDefs.Add('Price', ftCurrency);
    Mem.CreateDataSet;
    Mem.AppendRecord([12]);
    Msg := '';
    try
      Mem.Filter := 'Price > 10,5';
      Mem.Filtered := True;
    except
      on E: Exception do
        Msg := E.ClassName;
    end;
    Check('d01 fact: a decimal comma in the filter expression is refused', Msg <> '');
  finally
    Mem.Free;
  end;
  Check('x04 ConfigFileIn', (ConfigFileIn('C:\data') = 'C:\data\config.ini') and
    (ConfigFileIn('C:\data\') = 'C:\data\config.ini'));
  Check('g01 SumQuantities sums the numbers and counts the rest',
    (SumQuantities(['3', ' 4 ', 'x', '', '5'], Bad) = 12) and (Bad = 2));
  Check('fact: the unit of each type the v4 examples use',
    (TFDMemTable.UnitName = 'FireDAC.Comp.Client') and (TEncoding.UnitName = 'System.SysUtils') and
    (TNetEncoding.UnitName = 'System.NetEncoding') and
    (Ctx.GetType(TypeInfo(THashSHA2)).QualifiedName = 'System.Hash.THashSHA2') and
    (TThread.UnitName = 'System.Classes') and (TParallel.UnitName = 'System.Threading') and
    (TInterlocked.UnitName = 'System.SyncObjs'));

  // v5: r18, r20, u07, u08
  Check('r18 Utf8StreamSize', Utf8StreamSize('Caf' + #$00E9) = 5);
  Mem := NewProductTable;
  try
    Check('r20 NewProductTable', (Mem.FieldDefs.Count = 2) and (Mem.FieldByName('Name').DataType = ftString));
  finally
    Mem.Free;
  end;
  Pt := CenterOf(RectF(0, 0, 10, 20));
  Check('u07 CenterOf', (Pt.X = 5) and (Pt.Y = 10));
  Log := TSafeLog.Create;
  try
    TParallel.For(1, 2000,
      procedure(I: Integer)
      begin
        Log.Add(IntToStr(I));
      end);
    Check('u08 TSafeLog keeps every line added from several threads', Log.Count = 2000);
  finally
    Log.Free;
  end;

  // e05, e06: one writer, entered through a bug report and through a third writer
  Check('e05 the archive writer now writes what the reader reads',
    TryParseOrderRef(ArchiveOrderRef(2026, 42), Year, Number) and (Year = 2026) and (Number = 42));
  Check('e05 both writers agree', ArchiveOrderRef(2026, 42) = OrderRef(2026, 42));
  Check('e05 the reader stays strict', not TryParseOrderRef('ORD-2026-42', Year, Number));
  Check('e06 ReminderSubject reuses the reference', ReminderSubject(2026, 7) = 'Payment reminder: INV-2026-00007');
  Check('e06 its reference reads back', TryParseInvoiceRef(Copy(ReminderSubject(2026, 7),
    Length('Payment reminder: ') + 1, MaxInt), Year, Number) and (Number = 7));

  // x05..x08: the RTL already has it
  S := CustomerToJson('Ann "the boss"', 30);
  J := TJSONObject.ParseJSONValue(S);
  try
    Check('x05 CustomerToJson stays valid JSON with a quote in the name',
      (J <> nil) and ((J as TJSONObject).GetValue<string>('name') = 'Ann "the boss"'));
  finally
    J.Free;
  end;
  J := TJSONObject.ParseJSONValue('{"name":"' + 'Ann "the boss"' + '","age":30}');
  Check('x05 fact: the same JSON built by concatenation does not parse', J = nil);
  J.Free;
  S := CustomerToJson('back\slash' + #9 + 'tab' + #10 + 'line', 1);
  J := TJSONObject.ParseJSONValue(S);
  try
    Check('x05 CustomerToJson escapes a backslash, a tab and a line break too',
      (J <> nil) and ((J as TJSONObject).GetValue<string>('name') = 'back\slash' + #9 + 'tab' + #10 + 'line'));
  finally
    J.Free;
  end;
  // Delphi's parser accepts a raw control character inside a string, so parsing is not the judge here:
  // RFC 8259 says U+0000..U+001F are escaped, so the output must not carry #1 itself
  S := CustomerToJson('a' + #1 + 'b', 1);
  J := TJSONObject.ParseJSONValue(S);
  try
    Check('x05 CustomerToJson escapes any other control character (#1): none raw in the output, and it reads back',
      (Pos(#1, S) = 0) and (J <> nil) and ((J as TJSONObject).GetValue<string>('name') = 'a' + #1 + 'b'));
  finally
    J.Free;
  end;
  J := TJSONObject.ParseJSONValue('{"name":"a' + #1 + 'b"}');
  try
    Check('x05 fact: Delphi''s parser accepts a raw #1 inside a string (it is not a strict judge)', J <> nil);
  finally
    J.Free;
  end;
  Check('x06 SearchUrlFor', SearchUrlFor('a b&c=d/e') = 'https://example.com/search?q=a+b%26c%3Dd%2Fe');
  Check('x06 SearchUrlFor encodes a question mark too', SearchUrlFor('why?') = 'https://example.com/search?q=why%3F');
  Check('x07 DaysIn', (DaysIn(2024, 2) = 29) and (DaysIn(2026, 2) = 28) and (DaysIn(2026, 4) = 30));
  Check('x08 ExtensionOf', (ExtensionOf('C:\data\report.pdf') = '.pdf') and (ExtensionOf('C:\v1.2\readme') = '') and
    (ExtensionOf('archive.tar.gz') = '.gz') and (ExtensionOf('.gitignore') = '.gitignore'));
  Check('x08 fact: TPath.GetExtension gives the same on these paths',
    (TPath.GetExtension('C:\data\report.pdf') = '.pdf') and (TPath.GetExtension('C:\v1.2\readme') = '') and
    (TPath.GetExtension('archive.tar.gz') = '.gz') and (TPath.GetExtension('.gitignore') = '.gitignore'));
  Check('x08 fact: Pos(''.'') finds the dot of the folder',
    Copy('C:\v1.2\readme', Pos('.', 'C:\v1.2\readme'), MaxInt) = '.2\readme');

  // e07: its tests run in DatasetPinTest; here, the rounding facts it states
  Check('e07 fact: Round and RoundTo round a half to the even digit',
    (Round(2.5) = 2) and (Round(3.5) = 4) and SameValue(RoundTo(0.125, -2), 0.12));
  Check('e07 fact: SimpleRoundTo rounds a half away from zero',
    SameValue(SimpleRoundTo(0.125, -2), 0.13) and SameValue(SimpleRoundTo(-0.125, -2), -0.13));
  Check('fact: the unit of each type the v5 examples use',
    (TStringStream.UnitName = 'System.Classes') and (TMemoryStream.UnitName = 'System.Classes') and
    (TFileStream.UnitName = 'System.Classes') and (TEncoding.UnitName = 'System.SysUtils') and
    (TCriticalSection.UnitName = 'System.SyncObjs') and (Ctx.GetType(TypeInfo(TPointF)).QualifiedName = 'System.Types.TPointF') and
    (Ctx.GetType(TypeInfo(TRectF)).QualifiedName = 'System.Types.TRectF') and
    (Ctx.GetType(TypeInfo(TFieldType)).QualifiedName = 'Data.DB.TFieldType'));

  // v6: x09, x10, x11, e08
  Check('x09 HtmlText', HtmlText('<b>Tom & Jerry</b>') = '&lt;b&gt;Tom &amp; Jerry&lt;/b&gt;');
  Check('x09 HtmlText encodes a double quote', HtmlText('say "hi"') = 'say &quot;hi&quot;');
  Check('x09 fact: TNetEncoding.HTML leaves the apostrophe as it is', TNetEncoding.HTML.Encode('Jerry''s') = 'Jerry''s');
  S := StringReplace('<b>', '<', '&lt;', [rfReplaceAll]);
  S := StringReplace(S, '>', '&gt;', [rfReplaceAll]);
  S := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Check('x09 fact: replacing & after < and > encodes them twice', S = '&amp;lt;b&amp;gt;');
  Check('x10 BandOf', (BandOf(0) = 0) and (BandOf(4.9) = 0) and (BandOf(5) = 1) and (BandOf(-2.5) = -1) and
    (BandOf(-5) = -1) and (BandOf(-5.1) = -2));
  Check('x10 fact: Trunc and div round toward zero, Floor toward minus infinity',
    (Trunc(-0.5) = 0) and (Floor(-0.5) = -1) and ((-7) div 5 = -1) and (Floor(-7 / 5) = -2) and
    (Trunc(-2.5) = -2) and (Floor(-2.5) = -3));
  Conn := TFDConnection.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := ':memory:';
    Conn.Open;
    Conn.ExecSQL('create table customers (name varchar(40))');
    Conn.ExecSQL('insert into customers (name) values (:name)', ['O''Brien']);
    Conn.ExecSQL('insert into customers (name) values (:name)', ['Ann']);
    Conn.ExecSQL('insert into customers (name) values (:name)', ['Bob']);
    Check('x11 CountCustomersNamed with a quote in the name', CountCustomersNamed(Conn, 'O''Brien') = 1);
    Check('x11 CountCustomersNamed: a name that tries to change the query counts nothing',
      CountCustomersNamed(Conn, 'x'' or ''1''=''1') = 0);
    Msg := '';
    try
      Conn.ExecSQLScalar('select count(*) from customers where name = ''' + 'O''Brien' + '''');
    except
      on E: Exception do
        Msg := E.Message;
    end;
    Check('x11 fact: concatenated, the quote breaks the SQL (the message of exception.txt)',
      Msg = '[FireDAC][Phys][SQLite] ERROR: near "Brien": syntax error');
    Check('x11 fact: concatenated, that other name counts EVERY row',
      Conn.ExecSQLScalar('select count(*) from customers where name = ''' + 'x'' or ''1''=''1' + '''') = 3);
  finally
    Conn.Free;
  end;
  Day := EncodeDate(2026, 3, 7);
  Check('e08 BackupFileName', BackupFileName(Day) = 'backup_2026-03-07.zip');
  Check('e08 the nightly file name now reads back', TryBackupDay(NightlyBackupFileName(Day), D3) and (D3 = Day));
  Check('e08 both writers agree', NightlyBackupFileName(Day) = BackupFileName(Day));
  Check('e08 the reader stays strict', not TryBackupDay('backup_20260307.zip', D3) and
    not TryBackupDay('backup_2026-02-30.zip', D3));
  Check('fact: the unit of each class the v6 examples use',
    (TNetEncoding.UnitName = 'System.NetEncoding') and (TFDConnection.UnitName = 'FireDAC.Comp.Client'));
end;

begin
  ExitCode := RunJudge([RunChecks]);
end.
