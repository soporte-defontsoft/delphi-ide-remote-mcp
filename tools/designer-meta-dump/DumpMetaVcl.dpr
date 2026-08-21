program DumpMetaVcl;

{ Designer-metadata dumper, VCL side - see DumpMetaFmx.dpr for the story.

  Usage:  DumpMetaVcl.exe <output .pas path>
  e.g.    DumpMetaVcl.exe ..\..\src\Lsp.DesignerMeta.Vcl.pas }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.Grids,
  Vcl.CheckLst,
  Vcl.Mask,
  Vcl.Samples.Spin,
  Vcl.ImgList,
  Vcl.ActnList,
  Vcl.ToolWin,
  Vcl.Tabs,
  MetaDump in 'MetaDump.pas';

begin
  try
    if ParamStr(1) = '' then
    begin
      Writeln('uso: DumpMetaVcl.exe <ruta salida .pas>');
      Halt(1);
    end;
    DumpMeta('Lsp.DesignerMeta.Vcl', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
