object FrameX: TFrameX
  Left = 0
  Top = 0
  Width = 300
  Height = 120
  TabOrder = 0
  object EtiquetaFrame: TLabel
    Left = 8
    Top = 8
    Width = 100
    Height = 15
    Caption = 'Etiqueta del frame'
  end
  object EditFrame: TEdit
    Left = 8
    Top = 32
    Width = 200
    Height = 23
    TabOrder = 0
    Text = 'texto del frame'
  end
  object PanelFrame: TPanel
    Left = 8
    Top = 64
    Width = 280
    Height = 41
    Caption = 'Panel del FRAME'
    Color = clInfoBk
    ParentBackground = False
    TabOrder = 1
  end
end
