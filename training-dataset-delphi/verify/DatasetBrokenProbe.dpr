program DatasetBrokenProbe;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils;

begin
  try
    Writeln('DatasetBrokenProbe running');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
