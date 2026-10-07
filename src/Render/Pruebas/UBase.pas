unit UBase;
interface
uses Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, System.Classes, Vcl.Controls;
type
  TFormBase = class(TForm)
    PanelCabecera: TPanel;
    BotonAceptar: TButton;
    EtiquetaBase: TLabel;
  end;
implementation
{$R *.dfm}
end.
