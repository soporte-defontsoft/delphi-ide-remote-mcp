unit LspTests.Comun;

{ Lo comun de la suite. Un test que en ESTA maquina no puede medir lo suyo (sin la
  ayuda instalada, sin forma 8.3...) lo DICE en una linea NOTA y
  pasa: un Assert.Pass a secas contaba como pasado y no se veia, y la suite salia
  "todos pasados" sin haber medido esos. test_engine_dunitx reimprime las NOTA, y
  run_all las lista entre lo que no se midio (revisor de baterias de la 1.27). }

interface

procedure NoSeMide(const AMotivo: string);

implementation

uses
  DUnitX.TestFramework;

procedure NoSeMide(const AMotivo: string);
begin
  // en su linea: el registrador de consola de DUnitX escribe sus puntos sin salto
  WriteLn;
  WriteLn('NOTA no se mide: ' + AMotivo);
  Assert.Pass(AMotivo);
end;

end.
