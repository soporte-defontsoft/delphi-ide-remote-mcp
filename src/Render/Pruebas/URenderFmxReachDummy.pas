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
  if M is TMediaPlayer then
    TFile.WriteAllText('DUMMY-media.txt',
      BoolToStr(TMediaPlayer(M).Media <> nil, True) + ':' +
      IntToStr(TMediaPlayer(M).Duration));
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
