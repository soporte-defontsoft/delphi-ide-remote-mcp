program HeldoutFmxSpecTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Rtti,
  FMX.Types,
  FMX.Graphics,
  FMX.Controls,
  FMX.Layouts,
  FMX.Objects,
  FMX.StdCtrls,
  FMX.SpinBox,
  SpecChecks in 'SpecChecks.pas',
  FmxSpecChecks in 'FmxSpecChecks.pas',
  QuantityField in '..\eval\heldout\delphi\ho01-fmx-spinbox-field\QuantityField.pas',
  TermsBox in '..\eval\heldout\delphi\ho02-fmx-checkbox-invented-unit\fixed\TermsBox.pas',
  PanelFill in '..\eval\heldout\delphi\ho03-fmx-alclient\fixed\PanelFill.pas',
  ColorSwatch in '..\eval\heldout\delphi\ho04-fmx-swatch-rectangle\ColorSwatch.pas',
  AvatarBadge in '..\eval\heldout\delphi\ho05-fmx-badge-takes-click\answer\AvatarBadge.pas';

// The judge of the held-out FireMonkey questions (eval/heldout): questions that are NEVER trained on, the patterns
// of the examples in new code. Control trees in memory (no form, no window), as DatasetFmxSpecTest builds them, and
// FireMonkey itself says which control gets a click. PASS/FAIL lines + exit code = number of failures.

procedure RunChecks;
var
  Ctx: TRttiContext;
  Probe, Root: TLayout;
  Spin: TSpinBox;
  Box: TCheckBox;
  Pnl: TPanel;
  Swatch, Plain: TRectangle;
  Btn: TButton;
  Badge: TImage;
begin
  Ctx := TRttiContext.Create;

  // ho01
  Probe := TLayout.Create(nil);
  try
    Spin := AddQuantityField(Probe);
    Check('ho01 AddQuantityField', (Spin.Parent = Probe) and (Spin.Min = 1) and (Spin.Max = 99) and (Spin.Value = 1) and
      (Spin.Align = TAlignLayout.Top));
  finally
    Probe.Free;
  end;
  Check('ho01 fact: TSpinBox lives in FMX.SpinBox', TSpinBox.UnitName = 'FMX.SpinBox');

  // ho02
  Box := TCheckBox.Create(nil);
  try
    Box.IsChecked := True;
    SetupTermsBox(Box);
    Check('ho02 SetupTermsBox', (Box.Text = 'I accept the terms') and not Box.IsChecked);
  finally
    Box.Free;
  end;
  Check('ho02 fact: TCheckBox lives in FMX.StdCtrls, with IsChecked and no Caption',
    (TCheckBox.UnitName = 'FMX.StdCtrls') and (Ctx.GetType(TCheckBox).GetProperty('IsChecked') <> nil) and
    (Ctx.GetType(TCheckBox).GetProperty('Caption') = nil) and (Ctx.GetType(TCheckBox).GetProperty('Checked') = nil));

  // ho03
  Pnl := TPanel.Create(nil);
  try
    FillParent(Pnl);
    Check('ho03 FillParent', Pnl.Align = TAlignLayout.Client);
  finally
    Pnl.Free;
  end;
  Check('ho03 fact: TPanel lives in FMX.StdCtrls, TAlignLayout in FMX.Types', (TPanel.UnitName = 'FMX.StdCtrls') and
    (Ctx.GetType(TypeInfo(TAlignLayout)).QualifiedName = 'FMX.Types.TAlignLayout'));

  // ho04
  Probe := TLayout.Create(nil);
  try
    Swatch := AddSwatch(Probe, TAlphaColors.Red);
    Check('ho04 AddSwatch', (Swatch.Parent = Probe) and (Swatch.Width = 24) and (Swatch.Height = 24) and
      (Swatch.Fill.Kind = TBrushKind.Solid) and (Swatch.Fill.Color = TAlphaColors.Red) and
      (Swatch.Stroke.Kind = TBrushKind.None));
  finally
    Probe.Free;
  end;
  Plain := TRectangle.Create(nil);
  try
    Check('ho04 fact: a new TRectangle has a solid fill and a solid border', (Plain.Fill.Kind = TBrushKind.Solid) and
      (Plain.Stroke.Kind = TBrushKind.Solid));
  finally
    Plain.Free;
  end;
  Check('ho04 fact: TRectangle in FMX.Objects, TBrushKind in FMX.Graphics, TAlphaColor in System.UITypes',
    (TRectangle.UnitName = 'FMX.Objects') and
    (Ctx.GetType(TypeInfo(TBrushKind)).QualifiedName = 'FMX.Graphics.TBrushKind') and
    (Ctx.GetType(TypeInfo(TAlphaColor)).QualifiedName = 'System.UITypes.TAlphaColor'));

  // ho05
  Root := TLayout.Create(nil);
  try
    Root.SetBounds(0, 0, 200, 100);
    Btn := TButton.Create(Root);
    Btn.Parent := Root;
    Btn.SetBounds(20, 20, 100, 40);
    Badge := TImage.Create(Root);
    Badge.Parent := Root;
    Badge.SetBounds(108, 16, 16, 16);
    Check('ho05 fact: a TImage over the corner of a button takes the clicks there', Hit(Root, 115, 25) = Badge);
    Check('ho05 fact: the rest of the button gets its clicks', Hit(Root, 50, 40) = Btn);
    PlaceBadge(Btn, Badge);
    Check('ho05 PlaceBadge: the badge still sits over the corner', (Badge.AbsoluteRect = RectF(108, 16, 124, 32)) and
      Badge.Visible);
    Check('ho05 PlaceBadge: a click on the corner reaches the button', Hit(Root, 115, 25) = Btn);
  finally
    Root.Free;
  end;
end;

begin
  // LeaveJudge says why a FireMonkey judge leaves without the unit finalization
  LeaveJudge(RunJudge([RunChecks]));
end.
