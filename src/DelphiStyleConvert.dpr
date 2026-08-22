program DelphiStyleConvert;

{ Helper of the Delphi Remote MCP server: FMX style files, text <-> binary.
  Kept OUT of the server executable on purpose (FMX must not be linked into a
  Windows service). Invoked by delphi_styles.

    DelphiStyleConvert tobin   <in.style>  <out.bin.style>
    DelphiStyleConvert totext  <in.style>  <out.style>
    DelphiStyleConvert defaults <out.style>   the Windows platform default
                                              style (win10style) as text

  Exit codes: 0 ok, 1 error (message on stderr), 2 usage. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  FMX.Types,
  FMX.Styles,
  FMX.Controls.Win; // links the platform style resources (win10style...)

procedure Convert(const AIn, AOut: string; AFormat: TStyleFormat);
var
  Style: TFmxObject;
  FS: TFileStream;
begin
  Style := TStyleStreaming.LoadFromFile(AIn);
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
    else
    begin
      Writeln(ErrOutput, 'Uso: DelphiStyleConvert tobin|totext <in> <out> | defaults <out>');
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
