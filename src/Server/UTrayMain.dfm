object FormTray: TFormTray
  Left = 0
  Top = 0
  Caption = 'DelphiLSP MCP Service'
  ClientHeight = 420
  ClientWidth = 720
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  TextHeight = 15
  object MemoLog: TMemo
    Left = 0
    Top = 0
    Width = 720
    Height = 420
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object TrayIcon: TTrayIcon
    PopupMenu = PopupMenu
    Visible = True
    OnDblClick = MiShowClick
    Left = 48
    Top = 48
  end
  object PopupMenu: TPopupMenu
    Left = 144
    Top = 48
    object MiShow: TMenuItem
      Caption = 'Status / Log'
      Default = True
      OnClick = MiShowClick
    end
    object MiCopy: TMenuItem
      Caption = 'Copy server URL'
      OnClick = MiCopyClick
    end
    object MiSep: TMenuItem
      Caption = '-'
    end
    object MiExit: TMenuItem
      Caption = 'Exit (stop the server)'
      OnClick = MiExitClick
    end
  end
end
