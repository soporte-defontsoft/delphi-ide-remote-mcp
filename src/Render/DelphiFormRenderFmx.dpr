program DelphiFormRenderFmx;

{ Helper of the Delphi Remote MCP server: renders an FMX .fmx (form or frame)
  to a PNG of what the IDE designer shows, with the style the form carries, a
  .style file or one of the IDE's platform preview styles. No window, no
  dialog can reach the server's desktop. Kept OUT of the server executable
  (FMX must not be linked into a Windows service, and a third-party package
  that crashes kills only this process). Invoked by delphi_designer
  command=preview. Arguments and output: FormRender.Comun /
  FormRenderProtocolo.inc. Exit codes: 0 ok, 1 error, 2 usage, 3 timeout. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FormRender.Comun in 'FormRender.Comun.pas',
  FormRender.Fmx in 'FormRender.Fmx.pas',
  FormRender.Textos in 'FormRender.Textos.pas',
  Lsp.DesignerForma in '..\Server\Lsp.DesignerForma.pas',
  Lsp.Pascal in '..\Server\Lsp.Pascal.pas';

begin
  ExitCode := Main;
end.
