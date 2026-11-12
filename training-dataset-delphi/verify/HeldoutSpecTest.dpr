program HeldoutSpecTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  System.Threading,
  System.SyncObjs,
  System.Generics.Collections,
  System.Generics.Defaults,
  SpecChecks in 'SpecChecks.pas',
  HitCounter in '..\eval\heldout\delphi\ho10-interlocked-needs-syncobjs\fixed\HitCounter.pas',
  NameOrder in '..\eval\heldout\delphi\ho11-tcomparer-needs-defaults\fixed\NameOrder.pas',
  LapTimes in '..\eval\heldout\delphi\ho20-lap-time-format\LapTimes.pas',
  CardMask in '..\eval\heldout\delphi\ho21-last-four-digits\CardMask.pas',
  WeekdayNames in '..\eval\heldout\delphi\ho22-weekday-number\WeekdayNames.pas',
  PackCount in '..\eval\heldout\delphi\ho23-round-half-up\PackCount.pas',
  WeekNumbers in '..\eval\heldout\delphi\ho30-rtl-iso-week\WeekNumbers.pas',
  DueDates in '..\eval\heldout\delphi\ho31-rtl-add-months\DueDates.pas',
  PreviewFiles in '..\eval\heldout\delphi\ho32-rtl-change-extension\PreviewFiles.pas',
  PhoneBook in '..\eval\heldout\delphi\ho40-reuse-phone-normalizer\answer\PhoneBook.pas',
  CartTotals in '..\eval\heldout\delphi\ho45-free-shipping-rule\answer\CartTotals.pas',
  LotCodes in '..\eval\heldout\delphi\ho46-second-writer-lot-code\answer\LotCodes.pas',
  Vectors in '..\eval\heldout\delphi\ho60-record-operators\Vectors.pas';

// The judge of the held-out questions of the RTL (eval/heldout): questions that are NEVER trained on, the patterns
// of the examples in new code. Every answer unit is in the uses clause above (so it compiles) and every check below
// runs it. PASS/FAIL lines + ExitCode = number of failures (delphi_test reads both).

procedure RunChecks;
const
  Around: array[0..2] of Currency = (49.99, 50, 50.01);
var
  Counter: THitCounter;
  Names: TArray<string>;
  Ms, Line: Integer;
  Ok: Boolean;
  Day, D: TDateTime;
  S: Currency;
  V: TVec2;
begin
  // ho10
  Counter := THitCounter.Create;
  try
    TParallel.For(1, 100000,
      procedure(I: Integer)
      begin
        Counter.Hit;
      end);
    Check('ho10 THitCounter counts every hit from parallel threads', Counter.Hits = 100000);
  finally
    Counter.Free;
  end;
  Check('ho10 fact: TInterlocked lives in System.SyncObjs', TInterlocked.UnitName = 'System.SyncObjs');

  // ho11
  Names := ['ccc', 'bb', 'a', 'aa', 'b'];
  SortByLength(Names);
  Check('ho11 SortByLength', (Length(Names) = 5) and (Names[0] = 'a') and (Names[1] = 'b') and (Names[2] = 'aa') and
    (Names[3] = 'bb') and (Names[4] = 'ccc'));
  Check('ho11 fact: TComparer lives in System.Generics.Defaults, TArray in System.Generics.Collections',
    (TComparer<string>.UnitName = 'System.Generics.Defaults') and (TArray.UnitName = 'System.Generics.Collections'));

  // ho20
  Check('ho20 LapText', (LapText(83250) = '01:23.250') and (LapText(500) = '00:00.500') and
    (LapText(0) = '00:00.000') and (LapText(3599999) = '59:59.999'));
  Ok := True;
  Ms := 0;
  while Ms < 3600000 do
  begin
    if LapText(Ms) <> Format('%.2d:%.2d.%.3d', [Ms div 60000, Ms div 1000 mod 60, Ms mod 1000]) then
      Ok := False;
    Inc(Ms, 997);
  end;
  Check('ho20 LapText over the whole hour, every 997 ms', Ok);
  Check('ho20 fact: mm before ss is the month', FormatDateTime('mm:ss.zzz', 83250 / MSecsPerDay) = '12:23.250');

  // ho21, ho22, ho23
  Check('ho21 MaskCard', (MaskCard('4111111111111234') = '**** 1234') and (MaskCard('1234') = '**** 1234') and
    (MaskCard('98765') = '**** 8765'));
  Check('ho22 WeekdayNumber', (WeekdayNumber('Monday') = 1) and (WeekdayNumber('TUESDAY') = 2) and
    (WeekdayNumber('Thursday') = 4) and (WeekdayNumber('sunday') = 7) and (WeekdayNumber('funday') = 0) and
    (WeekdayNumber('') = 0));
  Check('ho23 WholeUnits', (WholeUnits(2.4) = 2) and (WholeUnits(2.5) = 3) and (WholeUnits(3.5) = 4) and
    (WholeUnits(0.5) = 1) and (WholeUnits(0) = 0) and (WholeUnits(7.5) = 8) and (WholeUnits(10.49) = 10));
  Check('ho23 fact: Round gives the even number for a half', (Round(2.5) = 2) and (Round(0.5) = 0) and
    (Round(3.5) = 4));

  // ho30, ho31, ho32
  Check('ho30 IsoWeek', (IsoWeek(EncodeDate(2021, 1, 3)) = 53) and (IsoWeek(EncodeDate(2021, 1, 4)) = 1) and
    (IsoWeek(EncodeDate(2024, 12, 30)) = 1) and (IsoWeek(EncodeDate(2027, 1, 1)) = 53) and
    (IsoWeek(EncodeDate(2026, 12, 31)) = 53) and (IsoWeek(EncodeDate(2026, 11, 12)) = 46) and
    (IsoWeek(EncodeDateTime(2021, 1, 3, 23, 59, 0, 0)) = 53));
  Check('ho31 DueDate', SameDateTime(DueDate(EncodeDate(2026, 1, 31), 1), EncodeDate(2026, 2, 28)) and
    SameDateTime(DueDate(EncodeDate(2024, 1, 31), 1), EncodeDate(2024, 2, 29)) and
    SameDateTime(DueDate(EncodeDate(2026, 3, 31), -1), EncodeDate(2026, 2, 28)) and
    SameDateTime(DueDate(EncodeDate(2026, 8, 31), 6), EncodeDate(2027, 2, 28)) and
    SameDateTime(DueDate(EncodeDate(2026, 5, 15), 1), EncodeDate(2026, 6, 15)) and
    SameDateTime(DueDate(EncodeDate(2026, 11, 30), 3), EncodeDate(2027, 2, 28)));
  Check('ho31 DueDate keeps the time of day', SameDateTime(DueDate(EncodeDateTime(2026, 1, 31, 10, 30, 0, 0), 1),
    EncodeDateTime(2026, 2, 28, 10, 30, 0, 0)));
  Check('ho32 PreviewName', (PreviewName('report.final.docx') = 'report.final.pdf') and
    (PreviewName('notes') = 'notes.pdf') and (PreviewName('C:\my.docs\notes') = 'C:\my.docs\notes.pdf') and
    (PreviewName('C:\docs\a.txt') = 'C:\docs\a.pdf') and (PreviewName('archive.tar.gz') = 'archive.tar.pdf'));

  // ho40
  Check('ho40 SamePhone: the same number written two ways', SamePhone('0034 600 123 456', '+34 600-12 34 56') and
    SamePhone('600 12 34 56', '600123456'));
  Check('ho40 SamePhone: different numbers', not SamePhone('+34 600 123 456', '34 600 123 456') and
    not SamePhone('600 123 456', '600 123 457'));

  // ho45
  Check('ho45 at exactly 50 the invoice charges no shipping', ShippingCost(50) = 0);
  Ok := True;
  for S in Around do
    if ((CartBanner(S) = 'Free shipping!') <> (ShippingCost(S) = 0)) or (CheckoutTotal(S) <> S + ShippingCost(S)) then
      Ok := False;
  Check('ho45 the banner, the invoice and the checkout agree around the threshold', Ok);
  Check('ho45 below the threshold', (ShippingCost(49.99) = 4.95) and (CheckoutTotal(49.99) = 54.94) and
    (CartBanner(49.99) = 'Add 0.01 more for free shipping') and (CartBanner(50.01) = 'Free shipping!'));

  // ho46
  Day := EncodeDate(2026, 3, 7);
  Check('ho46 LotCode', LotCode(3, Day) = 'L3-20260307');
  Check('ho46 a printed code now reads back', TryParseLotCode(LabelLotCode(3, Day), Line, D) and (Line = 3) and
    (D = Day));
  Check('ho46 both writers agree', LabelLotCode(3, Day) = LotCode(3, Day));
  Check('ho46 the reader stays strict', not TryParseLotCode('L3-07.03.2026', Line, D) and
    not TryParseLotCode('L3-20260230', Line, D) and not TryParseLotCode('X3-20260307', Line, D));

  // ho60: a control - something no example teaches
  V := Vec2(1, 2) + Vec2(3, 4);
  Check('ho60 TVec2 Add', (V.X = 4) and (V.Y = 6));
  V := Vec2(1, 2) * 2.5;
  Check('ho60 TVec2 Multiply', (V.X = 2.5) and (V.Y = 5));
  Check('ho60 TVec2 Equal', (Vec2(1, 1) = Vec2(1, 1)) and not (Vec2(1, 1) = Vec2(1, 2)));
  V := Vec2(3, 4);
  Check('ho60 TVec2 Length', SameValue(V.Length, 5));
end;

begin
  ExitCode := RunJudge([RunChecks]);
end.
