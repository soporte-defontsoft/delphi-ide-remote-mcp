object FormBase: TFormBase
  Left = 0
  Top = 0
  Caption = 'Base'
  ClientHeight = 240
  ClientWidth = 420
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  PixelsPerInch = 96
  TextHeight = 15
  object EtiquetaBase: TLabel
    Left = 16
    Top = 56
    Width = 120
    Height = 15
    Caption = 'Etiqueta de la base'
  end
  object PanelCabecera: TPanel
    Left = 0
    Top = 0
    Width = 420
    Height = 41
    Align = alTop
    Caption = 'Cabecera de la BASE'
    Color = clSkyBlue
    ParentBackground = False
    TabOrder = 0
  end
  object BotonAceptar: TButton
    Left = 320
    Top = 200
    Width = 90
    Height = 25
    Caption = 'Aceptar'
    TabOrder = 1
  end
end
