program DatasetCompileFmx;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  StatusLabel in '..\examples\delphi\t02-fmx-label-text\StatusLabel.pas',
  PayButton in '..\examples\delphi\r03-fmx-has-no-caption\fixed\PayButton.pas';

begin
  try
    Writeln('DatasetCompileFmx running');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
