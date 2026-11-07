unit URenderFmxReachDummy;

{ Solo para la copia DUMMY del ayudante FMX; nunca en el producto. }

interface

uses System.Classes;

type
  TDummyFmxMeasure = class(TComponent)
  protected
    procedure Loaded; override;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, System.SysUtils, System.IOUtils,
  FMX.Forms, FMX.Media;

procedure TDummyFmxMeasure.Loaded;
var
  M: TComponent;
begin
  inherited;
  M := Owner.FindComponent('Player1');
  // el estado en que el renderizador cargo el componente del agente: en
  // diseno (PonEnDiseno) o, en la variante de control, en ejecucion. Por su
  // efecto ya no se ve: el fichero que nombre o lo niega la puerta del
  // servidor (DSGN-115) o su contenedor no lo lee (medido el 7-nov-2026)
  if M is TMediaPlayer then
    TFile.WriteAllText('DUMMY-media.txt', 'diseno=' + BoolToStr(csDesigning in M.ComponentState, True));
  if not (csDesigning in ComponentState) and (Owner is TForm) then
  begin
    // Fuerza un HWND oculto para el control de navegacion en ejecucion.
    var H := TForm(Owner).Handle;
    if H = nil then Exit;
  end;
  for var I := 1 to 30 do
  begin
    Application.ProcessMessages;
    Sleep(100);
  end;
end;

initialization
  CoInitialize(nil); // el control positivo de DirectShow necesita COM
  System.Classes.RegisterClass(TDummyFmxMeasure);

end.
