program DumpMetaFmx;

{ Designer-metadata dumper, FMX side. Links the FMX control units and dumps
  every TPersistent class's published surface via RTTI into the generated
  unit the server's designer lint resolves against. Offline release tool -
  the server never runs this.

  Usage:  DumpMetaFmx.exe <output .pas path>
  e.g.    DumpMetaFmx.exe ..\..\src\Lsp.DesignerMeta.Fmx.pas

  STRONGLINKTYPES keeps the smart linker from stripping classes no code
  references - the whole point is covering ALL of them. The uses list below
  is SCOPE (which framework surfaces to dump), not knowledge: what each
  class publishes comes from the framework itself. }

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  FMX.Types,
  FMX.Graphics,
  FMX.Controls,
  FMX.Controls.Presentation,
  FMX.Forms,
  FMX.StdCtrls,
  FMX.Edit,
  FMX.ComboEdit,
  FMX.EditBox,
  FMX.SpinBox,
  FMX.NumberBox,
  FMX.Memo,
  FMX.ListBox,
  FMX.ListView,
  FMX.Layouts,
  FMX.Objects,
  FMX.TabControl,
  FMX.Menus,
  FMX.Grid,
  FMX.TreeView,
  FMX.DateTimeCtrls,
  FMX.Colors,
  FMX.MultiView,
  FMX.ScrollBox,
  FMX.SearchBox,
  FMX.Ani,
  FMX.Effects,
  FMX.ImgList,
  MetaDump in 'MetaDump.pas';

begin
  try
    if ParamStr(1) = '' then
    begin
      Writeln('uso: DumpMetaFmx.exe <ruta salida .pas>');
      Halt(1);
    end;
    DumpMeta('Lsp.DesignerMeta.Fmx', ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
