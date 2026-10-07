inherited FormHija: TFormHija
  Caption = 'Hija'
  ClientHeight = 300
  inherited PanelCabecera: TPanel
    Caption = 'Cabecera cambiada por la HIJA'
    Color = clMoneyGreen
  end
  inherited BotonAceptar: TButton
    Top = 260
    Caption = 'Aceptar (hija)'
  end
  object EditHija: TEdit
    Left = 16
    Top = 96
    Width = 200
    Height = 23
    TabOrder = 2
    Text = 'solo en la hija'
  end
end
