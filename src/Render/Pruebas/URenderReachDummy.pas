unit URenderReachDummy;

{ Cobaya para una COPIA de prueba del renderizador. No se enlaza en las
  builds del producto ni se instala en el IDE. Todos los efectos apuntan
  a datos y endpoints DUMMY que prepara el arnes. }

interface

uses
  System.Classes;

type
  TDummyReach = class(TComponent)
  private
    FRuta, FAccion: string;
    procedure SetAccion(const AValor: string);
  published
    property Ruta: string read FRuta write FRuta;
    property Accion: string read FAccion write SetAccion;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Net.HttpClient;

procedure TDummyReach.SetAccion(const AValor: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  FAccion := AValor;
  if AValor = 'espera' then
  begin
    TFile.WriteAllText('DUMMY-parent.pid', IntToStr(GetCurrentProcessId));
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    Cmd := '"' + ParamStr(0) + '" --dummy-counter';
    UniqueString(Cmd);
    if not CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW,
      nil, nil, SI, PI) then
      RaiseLastOSError;
    TFile.WriteAllText('DUMMY-child.pid', IntToStr(PI.dwProcessId));
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
    for var I := 1 to 1800 do
      Sleep(100); // fin propio a tres minutos aun si el arnes falla
  end
  else if AValor = 'lee' then
    TFile.WriteAllBytes('DUMMY-read.bin', TFile.ReadAllBytes(FRuta))
  else if AValor = 'escribe' then
    TFile.WriteAllText(FRuta, 'DUMMY')
  else if AValor = 'red' then
  begin
    var Cliente := THTTPClient.Create;
    try
      Cliente.ConnectionTimeout := 2000;
      Cliente.ResponseTimeout := 2000;
      Cliente.Get(FRuta); // el arnes solo proporciona su HTTP local
    finally
      Cliente.Free;
    end;
  end;
end;

initialization
  if ParamStr(1) = '--dummy-counter' then
  begin
    for var I := 1 to 1800 do
    begin
      TFile.WriteAllText('DUMMY-counter.txt', IntToStr(I));
      Sleep(100);
    end;
    Halt(0);
  end;
  System.Classes.RegisterClass(TDummyReach);

end.
