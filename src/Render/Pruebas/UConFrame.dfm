object FormConFrame: TFormConFrame
  Left = 0
  Top = 0
  Caption = 'Con frames'
  ClientHeight = 300
  ClientWidth = 340
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  PixelsPerInch = 96
  TextHeight = 15
  object EtiquetaForm: TLabel
    Left = 16
    Top = 8
    Width = 120
    Height = 15
    Caption = 'Dos frames inline:'
  end
  inline FrameX1: TFrameX
    Left = 16
    Top = 32
    Width = 300
    Height = 120
    TabOrder = 0
    inherited EditFrame: TEdit
      Text = 'cambiado en el primero'
    end
  end
  inline FrameX2: TFrameX
    Left = 16
    Top = 168
    Width = 300
    Height = 120
    TabOrder = 1
    inherited PanelFrame: TPanel
      Caption = 'Panel cambiado en el segundo'
      Color = clYellow
    end
  end
end
