program DatasetFmxSpecTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  FMX.Types,
  FMX.Graphics,
  FMX.Controls,
  FMX.Layouts,
  FMX.Objects,
  FMX.StdCtrls,
  FMX.Edit,
  FMX.ListBox,
  FMX.Memo,
  StatusLabel in '..\examples\delphi\t02-fmx-label-text\StatusLabel.pas',
  PayButton in '..\examples\delphi\r03-fmx-has-no-caption\fixed\PayButton.pas',
  NameField in '..\examples\delphi\r06-fmx-unit-of-tedit\fixed\NameField.pas',
  CardSetup in '..\examples\delphi\h01-fmx-layout-click\CardSetup.pas',
  CardContent in '..\examples\delphi\h02-fmx-child-takes-click\CardContent.pas',
  LinkLabel in '..\examples\delphi\h03-fmx-label-click\LinkLabel.pas',
  BusyOverlay in '..\examples\delphi\h04-fmx-invisible-overlay\BusyOverlay.pas',
  ClickProbe in '..\examples\delphi\h05-fmx-who-gets-the-click\ClickProbe.pas',
  CardStyle in '..\examples\delphi\r10-fmx-invented-type\fixed\CardStyle.pas',
  BadgeShape in '..\examples\delphi\r12-fmx-invented-unit\fixed\BadgeShape.pas',
  CardBuilder in '..\examples\delphi\u06-fmx-card-in-code\CardBuilder.pas',
  MemoLog in '..\examples\delphi\r19-fmx-tmemo-unit\fixed\MemoLog.pas',
  ScrollList in '..\examples\delphi\u09-fmx-scroll-list\ScrollList.pas',
  ToolbarSetup in '..\examples\delphi\r21-fmx-talign\fixed\ToolbarSetup.pas',
  SizePicker in '..\examples\delphi\r22-fmx-tcombobox-unit\fixed\SizePicker.pas',
  SettingRow in '..\examples\delphi\u10-fmx-setting-row\SettingRow.pas',
  TabPages in '..\examples\delphi\u11-fmx-tab-page\TabPages.pas',
  FMX.TabControl,
  Winapi.Windows;

// The judge of the dataset's FireMonkey examples: it builds control trees in memory (no form, no
// window) and asks FireMonkey itself which control gets a click (TControl.ObjectAtPoint).
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

// Which object gets a click at (X, Y), asked of FireMonkey
function Hit(const ARoot: TControl; const X, Y: Single): TFmxObject;
var
  C: IControl;
begin
  // ObjectAtPoint is protected in TControl and public through IControl, as the form uses it
  C := (ARoot as IControl).ObjectAtPoint(PointF(X, Y));
  if C = nil then
    Result := nil
  else
    Result := C.GetObject;
end;

procedure RunFacts;
var
  Layout: TLayout;
  Lbl: TLabel;
  Rect, Overlay: TRectangle;
  Txt: TText;
  Img: TImage;
begin
  // the defaults, from the classes themselves
  Layout := TLayout.Create(nil);
  Lbl := TLabel.Create(nil);
  Rect := TRectangle.Create(nil);
  Txt := TText.Create(nil);
  Img := TImage.Create(nil);
  try
    Check('fact: TLayout.HitTest is False by default', not Layout.HitTest);
    Check('fact: TLabel.HitTest is False by default', not Lbl.HitTest);
    Check('fact: TRectangle.HitTest is True by default', Rect.HitTest);
    Check('fact: TText.HitTest is True by default', Txt.HitTest);
    Check('fact: TImage.HitTest is True by default', Img.HitTest);
  finally
    Img.Free;
    Txt.Free;
    Rect.Free;
    Lbl.Free;
    Layout.Free;
  end;

  // a card: a layout with a text on top of it
  Layout := TLayout.Create(nil);
  try
    Layout.SetBounds(0, 0, 200, 100);
    Txt := TText.Create(Layout);
    Txt.Parent := Layout;
    Txt.SetBounds(10, 10, 180, 30);
    Check('fact: a TLayout with HitTest off is not hit', Hit(Layout, 100, 80) = nil);
    Layout.HitTest := True;
    Check('fact: with HitTest on, the layout is hit', Hit(Layout, 100, 80) = Layout);
    Check('fact: the child on top takes the click', Hit(Layout, 50, 20) = Txt);
    Txt.HitTest := False;
    Check('fact: a child with HitTest off lets it through', Hit(Layout, 50, 20) = Layout);

    // an overlay nobody sees still takes the click: the bounds count, not the pixels
    Overlay := TRectangle.Create(Layout);
    Overlay.Parent := Layout;
    Overlay.SetBounds(0, 0, 200, 100);
    Overlay.Fill.Kind := TBrushKind.None;
    Overlay.Stroke.Kind := TBrushKind.None;
    Overlay.Opacity := 0;
    Check('fact: an overlay with no fill and Opacity 0 takes the click', Hit(Layout, 100, 80) = Overlay);
    Overlay.Opacity := 1;
    Overlay.Fill.Kind := TBrushKind.Solid;
    Overlay.Fill.Color := TAlphaColors.Null;
    Check('fact: an overlay filled with a transparent colour takes the click', Hit(Layout, 100, 80) = Overlay);
    Overlay.HitTest := False;
    Check('fact: the overlay with HitTest off lets it through', Hit(Layout, 100, 80) = Layout);
    Overlay.HitTest := True;
    Overlay.Visible := False;
    Check('fact: a hidden overlay is never hit', Hit(Layout, 100, 80) = Layout);
    Overlay.Visible := True;
    Overlay.Enabled := False;
    Check('fact: a disabled overlay is never hit', Hit(Layout, 100, 80) = Layout);
  finally
    Layout.Free;
  end;
end;

type
  TClickSink = class
  public
    Clicks: Integer;
    procedure Clicked(Sender: TObject);
  end;

procedure TClickSink.Clicked(Sender: TObject);
begin
  Inc(Clicks);
end;

procedure RunExamples;
var
  Sink: TClickSink;
  Card, Inner, Probe: TLayout;
  Box, Root, Target, Overlay: TRectangle;
  Title: TText;
  Icon: TImage;
  Lbl: TLabel;
  Btn: TButton;
  Edit: TEdit;
  Outline, Badge, Card2: TRectangle;
  Memo: TMemo;
  VBox: TVertScrollBox;
  Ctx: TRttiContext;
  Bar: TToolBar;
  Combo: TComboBox;
  Switch: TSwitch;
  Tabs: TTabControl;
  Page: TTabItem;
begin
  Sink := TClickSink.Create;
  try
    // t02, r03: a FireMonkey text control shows its text in Text
    Lbl := TLabel.Create(nil);
    try
      ShowReady(Lbl);
      Check('t02 ShowReady', Lbl.Text = 'Ready');
    finally
      Lbl.Free;
    end;
    Btn := TButton.Create(nil);
    try
      Check('fact: TButton.HitTest is True by default', Btn.HitTest);
      ShowPay(Btn);
      Check('r03 ShowPay', Btn.Text = 'Pay');
    finally
      Btn.Free;
    end;

    // r06: TEdit lives in FMX.Edit; where each class lives, asked of the class itself
    Edit := TEdit.Create(nil);
    try
      Edit.Text := 'Ann';
      ClearName(Edit);
      Check('r06 ClearName', Edit.Text = '');
    finally
      Edit.Free;
    end;
    Check('r06 fact: the unit of each FireMonkey control',
      (TEdit.UnitName = 'FMX.Edit') and (TLabel.UnitName = 'FMX.StdCtrls') and
      (TButton.UnitName = 'FMX.StdCtrls') and (TListBox.UnitName = 'FMX.ListBox') and
      (TComboBox.UnitName = 'FMX.ListBox') and (TMemo.UnitName = 'FMX.Memo'));

    // h01: a TLayout used as a card
    Card := TLayout.Create(nil);
    try
      Card.SetBounds(0, 0, 200, 100);
      Check('h01 before: the layout is not hit', Hit(Card, 100, 50) = nil);
      MakeClickable(Card, Sink.Clicked);
      Check('h01 MakeClickable: the layout is hit and has its OnClick',
        (Hit(Card, 100, 50) = Card) and Assigned(Card.OnClick));
    finally
      Card.Free;
    end;

    // h02: a card whose content took the click
    Box := TRectangle.Create(nil);
    try
      Box.SetBounds(0, 0, 200, 100);
      Title := TText.Create(Box);
      Title.Parent := Box;
      Title.SetBounds(10, 10, 180, 30);
      Inner := TLayout.Create(Box);
      Inner.Parent := Box;
      Inner.SetBounds(10, 50, 60, 40);
      Icon := TImage.Create(Inner);
      Icon.Parent := Inner;
      Icon.SetBounds(0, 0, 40, 40);
      Check('h02 before: the title takes the click', Hit(Box, 50, 20) = Title);
      Check('h02 before: the nested icon takes the click', Hit(Box, 20, 60) = Icon);
      LetClicksThrough(Box);
      Check('h02 after: a click on the title reaches the card', Hit(Box, 50, 20) = Box);
      Check('h02 after: a click on the nested icon reaches the card', Hit(Box, 20, 60) = Box);
    finally
      Box.Free;
    end;

    // h03: a label used as a link
    Lbl := TLabel.Create(nil);
    try
      Lbl.SetBounds(0, 0, 120, 20);
      Check('h03 before: the label is not hit', Hit(Lbl, 10, 10) = nil);
      MakeLink(Lbl, Sink.Clicked);
      Check('h03 MakeLink: the label is hit and has its OnClick',
        (Hit(Lbl, 10, 10) = Lbl) and Assigned(Lbl.OnClick));
    finally
      Lbl.Free;
    end;

    // h04: a transparent overlay over the controls
    Root := TRectangle.Create(nil);
    try
      Root.SetBounds(0, 0, 300, 200);
      Target := TRectangle.Create(Root);
      Target.Parent := Root;
      Target.SetBounds(20, 20, 100, 40);
      Overlay := TRectangle.Create(Root);
      Overlay.Parent := Root;
      Overlay.SetBounds(0, 0, 300, 200);
      Overlay.Opacity := 0;
      Check('h04 the transparent overlay takes the click meant for the control below',
        Hit(Root, 50, 30) = Overlay);
      ShowBusy(Overlay, False);
      Check('h04 ShowBusy(False): the click reaches the control below', Hit(Root, 50, 30) = Target);
      ShowBusy(Overlay, True);
      Check('h04 ShowBusy(True): the overlay blocks it again', Hit(Root, 50, 30) = Overlay);
    finally
      Root.Free;
    end;

    // r10, r12
    Outline := TRectangle.Create(nil);
    try
      MakeOutline(Outline);
      Check('r10 MakeOutline', (Outline.Fill.Kind = TBrushKind.None) and
        (Outline.Stroke.Kind = TBrushKind.Solid) and (Outline.Stroke.Thickness = 2));
    finally
      Outline.Free;
    end;
    Ctx := TRttiContext.Create;
    Check('r10 fact: TBrushKind lives in FMX.Graphics, None..Resource',
      (Ctx.GetType(TypeInfo(TBrushKind)).QualifiedName = 'FMX.Graphics.TBrushKind') and
      (GetEnumName(TypeInfo(TBrushKind), 0) = 'None') and (GetEnumName(TypeInfo(TBrushKind), 1) = 'Solid') and
      (GetEnumName(TypeInfo(TBrushKind), 2) = 'Gradient') and (GetEnumName(TypeInfo(TBrushKind), 3) = 'Bitmap') and
      (GetEnumName(TypeInfo(TBrushKind), 4) = 'Resource') and (Ord(High(TBrushKind)) = 4));
    Badge := NewBadge(nil);
    try
      Check('r12 NewBadge', (Badge.XRadius = 8) and (Badge.YRadius = 8));
    finally
      Badge.Free;
    end;
    Check('r12 fact: TRectangle in FMX.Objects, TComponent in System.Classes',
      (TRectangle.UnitName = 'FMX.Objects') and (TComponent.UnitName = 'System.Classes'));

    // u06: a card built in code
    Card2 := NewCard(nil, 'Orders');
    try
      Card2.SetBounds(0, 0, 200, 80);
      Check('u06 NewCard: one TText child with the title', (Card2.ChildrenCount = 1) and
        (Card2.Children[0] is TText) and (TText(Card2.Children[0]).Text = 'Orders'));
      Check('u06 NewCard: a click on the title reaches the card', Hit(Card2, 100, 40) = Card2);
    finally
      Card2.Free;
    end;
    Check('u06 fact: TAlignLayout in FMX.Types, TText in FMX.Objects',
      (Ctx.GetType(TypeInfo(TAlignLayout)).QualifiedName = 'FMX.Types.TAlignLayout') and
      (TText.UnitName = 'FMX.Objects'));

    // r19, u09
    Memo := TMemo.Create(nil);
    try
      AddLogLine(Memo, 'first');
      Check('r19 AddLogLine', (Memo.Lines.Count = 1) and (Memo.Lines[0] = 'first'));
    finally
      Memo.Free;
    end;
    VBox := TVertScrollBox.Create(nil);
    try
      FillList(VBox, ['a', 'b', 'c']);
      Check('u09 FillList: three labels, handed to the box''s Content', (VBox.Content.ChildrenCount = 3) and
        (VBox.Content.Children[0] is TLabel));
    finally
      VBox.Free;
    end;
    Check('r19 fact: TMemo lives in FMX.Memo, TVertScrollBox in FMX.Layouts',
      (TMemo.UnitName = 'FMX.Memo') and (TVertScrollBox.UnitName = 'FMX.Layouts'));

    // v6: r21, r22, u10, u11
    Bar := TToolBar.Create(nil);
    try
      DockAtTop(Bar);
      Check('r21 DockAtTop', Bar.Align = TAlignLayout.Top);
    finally
      Bar.Free;
    end;
    Combo := TComboBox.Create(nil);
    try
      FillSizes(Combo);
      Check('r22 FillSizes', (Combo.Items.Count = 3) and (Combo.Items[1] = 'Medium'));
    finally
      Combo.Free;
    end;
    Probe := TLayout.Create(nil);
    try
      Switch := AddSettingRow(Probe, 'Dark mode');
      Check('u10 AddSettingRow: one row in the parent, with the switch on the right and the caption',
        (Probe.ChildrenCount = 1) and (Switch.Parent is TLayout) and (Switch.Parent.Parent = Probe) and
        (Switch.Parent.ChildrenCount = 2) and (Switch.Align = TAlignLayout.Right) and not Switch.IsChecked and
        (Switch.Parent.Children[1] is TLabel) and (TLabel(Switch.Parent.Children[1]).Text = 'Dark mode'));
    finally
      Probe.Free;
    end;
    Tabs := TTabControl.Create(nil);
    try
      Page := AddPage(Tabs, 'General');
      Check('u11 AddPage', (Tabs.TabCount = 1) and (Tabs.Tabs[0] = Page) and (Page.Text = 'General'));
      Check('u11 fact: the page Add creates is owned by the tab control (freed with it), and sits in its content',
        (Page.Owner = Tabs) and (Page.Parent <> nil) and (Page.Parent.ClassName = 'TTabControlContent'));
    finally
      Tabs.Free;
    end;
    Check('fact: the unit of each FireMonkey class the v6 examples use',
      (TToolBar.UnitName = 'FMX.StdCtrls') and (TSwitch.UnitName = 'FMX.StdCtrls') and
      (TComboBox.UnitName = 'FMX.ListBox') and (TListBox.UnitName = 'FMX.ListBox') and
      (TControl.UnitName = 'FMX.Controls') and (TTabControl.UnitName = 'FMX.TabControl') and
      (TTabItem.UnitName = 'FMX.TabControl') and (TLayout.UnitName = 'FMX.Layouts') and
      (TFmxObject.UnitName = 'FMX.Types') and (Ctx.GetType(TSwitch).GetProperty('IsChecked') <> nil) and
      (Ctx.GetType(TSwitch).GetProperty('OnSwitch') <> nil) and
      (Ctx.GetType(TypeInfo(TAlignLayout)).QualifiedName = 'FMX.Types.TAlignLayout'));

    // h05: ask FireMonkey which control gets the click
    Probe := TLayout.Create(nil);
    try
      Probe.SetBounds(0, 0, 200, 100);
      Title := TText.Create(Probe);
      Title.Parent := Probe;
      Title.SetBounds(0, 0, 100, 100);
      Check('h05 ControlAt finds the control that gets the click', ControlAt(Probe, PointF(50, 50)) = Title);
      Check('h05 ControlAt says nil where nothing takes it', ControlAt(Probe, PointF(150, 50)) = nil);
    finally
      Probe.Free;
    end;
  finally
    Sink.Free;
  end;
end;

begin
  try
    RunFacts;
    RunExamples;
  except
    on E: Exception do
    begin
      Writeln('FAIL unexpected ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  Writeln(Failures, ' failure(s)');
  // The verdict is complete here. The controls above live without an application, a form or a
  // window, and FireMonkey's own unit finalization then ends now and then in an access violation
  // inside ntdll (Runtime error 217). Measured 12-nov, out of the examples' code (after the last
  // check): 0 of 8 runs with the v5 controls, up to 2 of 4 with TToolBar, TComboBox, TSwitch and
  // TTabControl as well; FMX.Forms in the uses does not change it; the cause is NOT measured.
  // So the judge leaves here, after flushing its output, without running that finalization.
  Flush(Output);
  ExitProcess(Cardinal(Failures));
end.
