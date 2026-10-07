object FormPrueba: TFormPrueba
  Left = 0
  Top = 0
  Caption = 'Prueba'
  ClientHeight = 200
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  PixelsPerInch = 96
  TextHeight = 15
  object Label1: TLabel
    Left = 16
    Top = 16
    Width = 60
    Height = 15
    Caption = 'Nombre'
  end
  object Edit1: TEdit
    Left = 16
    Top = 36
    Width = 200
    Height = 23
    TabOrder = 0
    Text = 'Texto de prueba'
  end
  object ComboBox1: TComboBox
    Left = 16
    Top = 72
    Width = 200
    Height = 23
    Style = csDropDownList
    TabOrder = 1
    Items.Strings = (
      'Opcion A'
      'Opcion B')
    ItemIndex = 0
    Text = 'Opcion A'
  end
  object CheckBox1: TCheckBox
    Left = 16
    Top = 108
    Width = 150
    Height = 17
    Caption = 'Activo'
    Checked = True
    State = cbChecked
    TabOrder = 2
  end
  object Button1: TButton
    Left = 240
    Top = 36
    Width = 120
    Height = 25
    Caption = 'Aceptar'
    TabOrder = 3
  end
  object Panel1: TPanel
    Left = 16
    Top = 140
    Width = 344
    Height = 41
    Caption = 'Panel'
    Color = clSkyBlue
    ParentBackground = False
    TabOrder = 4
  end
end
