program OraculoXml;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  UOraculo in 'UOraculo.pas';

begin
  try
    // las carpetas a recorrer, una por argumento (tests/test_oraculo_xml.py);
    // --crudo delante, el mutante del oraculo
    var Carpetas: TArray<string> := [];
    var ConCrudo := False;
    for var I := 1 to ParamCount do
      if ParamStr(I) = '--crudo' then
        ConCrudo := True
      else
        Carpetas := Carpetas + [ParamStr(I)];
    Corre(Carpetas, ConCrudo);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
