program DelphiStyleConvert;

{ Helper of the Delphi Remote MCP server: FMX style files, text <-> binary.
  Kept OUT of the server executable on purpose (FMX must not be linked into a
  Windows service). Invoked by delphi_styles.

    DelphiStyleConvert tobin   <in.style>  <out.bin.style>
    DelphiStyleConvert totext  <in.style>  <out.style>
    DelphiStyleConvert defaults <out.style>   the Windows platform default
                                              style (win10style) as text
    DelphiStyleConvert check   <in.style>    what FMX IGNORES when it loads
                                              that text style: one line
                                              IGNORED<tab>message each (the
                                              RTL's, with class and property)

  Exit codes: 0 ok, 1 error (message on stderr), 2 usage. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  FMX.Types,
  FMX.Styles,
  FMX.Consts, // SCannotLoadStyleFromFile: la negativa de TStyleStreaming.LoadFromFile
  FMX.Controls.Win, // links the platform style resources (win10style...)
  Lsp.DesignerForma in '..\Server\Lsp.DesignerForma.pas', // DesignerAFlujo, como los renderizadores
  Lsp.Pascal in '..\Server\Lsp.Pascal.pas'; // la usa Lsp.DesignerForma (GrupoDeClasesDe), como en los renderizadores

{ LA lectura del conversor: la entrada que el servidor ya paso por su puerta,
  abierta como la abre TStyleStreaming.LoadFromFile. }
function Entrada(const AIn: string): TStream;
begin
  Result := TFileStream.Create(AIn, fmOpenRead or fmShareDenyWrite);
end;

procedure Convert(const AIn, AOut: string; AFormat: TStyleFormat);
var
  Style: TFmxObject;
  S: TStream;
  FS: TFileStream;
begin
  // lo que hace TStyleStreaming.LoadFromFile, sobre Entrada
  S := Entrada(AIn);
  try
    if not TStyleStreaming.CanLoadFromStream(S) then
      raise EStyleException.CreateResFmt(@SCannotLoadStyleFromFile, [AIn]);
    Style := TStyleStreaming.LoadFromStream(S);
  finally
    S.Free;
  end;
  try
    FS := TFileStream.Create(AOut, fmCreate);
    try
      TStyleStreaming.SaveToStream(Style, FS, AFormat);
    finally
      FS.Free;
    end;
  finally
    Style.Free;
  end;
end;

type
  { El lector de estilos de FMX (TStyleReader, privado en la implementation de
    FMX.Styles) con su MISMA tolerancia - Error devuelve True: lo que no sabe
    leer se salta, una propiedad que la clase no publica, un valor que no lee,
    una clase que no conoce con todo lo de dentro - pero apuntando cada error
    (el mensaje del RTL ya dice clase y propiedad: "Error reading
    TLayout.Fill.Color: Property Fill.Color does not exist"). Solo diagnostica: el binario
    lo sigue haciendo TStyleStreaming (tobin). Lo que se tragaba en silencio
    salia del .bin.style con ok:true (Hermes, completo de la 1.20.1). }
  TLectorQueApunta = class(TReader)
  protected
    procedure SetName(Component: TComponent; var Name: string); override;
    function Error(const Message: string): Boolean; override;
  public
    Ignorado: TStringList;
    constructor Create(Stream: TStream; BufSize: Integer);
    destructor Destroy; override;
  end;

constructor TLectorQueApunta.Create(Stream: TStream; BufSize: Integer);
begin
  inherited Create(Stream, BufSize);
  Ignorado := TStringList.Create;
end;

destructor TLectorQueApunta.Destroy;
begin
  Ignorado.Free;
  inherited;
end;


procedure TLectorQueApunta.SetName(Component: TComponent; var Name: string);
begin
  Name := ''; // como TStyleReader: un estilo no tiene nombres
end;

function TLectorQueApunta.Error(const Message: string): Boolean;
begin
  Ignorado.Add(Message);
  Result := True;
end;

{ Lo que FMX ignora al cargar el .style de texto AIn: los mismos pasos que
  TStyleStreaming.LoadFromStream para un texto (el texto a binario con el
  parser del RTL - DesignerAFlujo, la casa de esa conversion - y ese binario
  por el lector), con el lector que apunta. }
procedure Check(const AIn: string);
var
  FS: TStream;
  Bin: TMemoryStream;
  R: TLectorQueApunta;
  Raiz: TComponent;
  L: string;
begin
  FS := Entrada(AIn);
  Bin := TMemoryStream.Create;
  try
    DesignerAFlujo(FS, Bin);
    Bin.Position := 0;
    ActivateClassGroup(TFmxObject);
    R := TLectorQueApunta.Create(Bin, 4096);
    try
      BeginGlobalLoading;
      try
        Raiz := R.ReadRootComponent(nil);
        NotifyGlobalLoading;
      finally
        EndGlobalLoading;
      end;
      Raiz.Free;
      for L in R.Ignorado do
        Writeln('IGNORED'#9 + L);
    finally
      R.Free;
    end;
  finally
    Bin.Free;
    FS.Free;
  end;
end;

procedure Defaults(const AOut: string);
var
  Style: TFmxObject;
  FS: TFileStream;
begin
  Style := TStyleStreaming.LoadFromResource(HInstance, 'win10style', RT_RCDATA);
  try
    FS := TFileStream.Create(AOut, fmCreate);
    try
      TStyleStreaming.SaveToStream(Style, FS, TStyleFormat.Text);
    finally
      FS.Free;
    end;
  finally
    Style.Free;
  end;
end;

var
  Cmd: string;
begin
  try
    Cmd := LowerCase(ParamStr(1));
    if (Cmd = 'tobin') and (ParamCount >= 3) then
      Convert(ParamStr(2), ParamStr(3), TStyleFormat.Binary)
    else if (Cmd = 'totext') and (ParamCount >= 3) then
      Convert(ParamStr(2), ParamStr(3), TStyleFormat.Text)
    else if (Cmd = 'defaults') and (ParamCount >= 2) then
      Defaults(ParamStr(2))
    else if (Cmd = 'check') and (ParamCount >= 2) then
      Check(ParamStr(2))
    else
    begin
      Writeln(ErrOutput, 'Usage: DelphiStyleConvert tobin|totext <in> <out> | defaults <out> | check <in>');
      Halt(2);
    end;
    Writeln('OK');
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'ERROR: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
