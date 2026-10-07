program DelphiFormRenderVcl;

{ Helper of the Delphi Remote MCP server: renders a VCL .dfm to a PNG of what
  the IDE designer shows, without showing anything on the server's desktop.
  Kept OUT of the server executable on purpose (the IDE's design packages are
  loaded into this process; if one of them crashes, this process dies and the
  server answers with the error). Invoked by delphi_designer command=preview.
  Arguments and output: FormRender.Comun / FormRenderProtocolo.inc.
  Exit codes: 0 ok, 1 error (ERROR= line), 2 usage, 3 timeout. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FormRender.Comun in 'FormRender.Comun.pas',
  FormRender.Vcl in 'FormRender.Vcl.pas',
  FormRender.Textos in 'FormRender.Textos.pas',
  Lsp.DesignerForma in '..\Server\Lsp.DesignerForma.pas',
  Lsp.Pascal in '..\Server\Lsp.Pascal.pas';

begin
  ExitCode := Main;
end.
