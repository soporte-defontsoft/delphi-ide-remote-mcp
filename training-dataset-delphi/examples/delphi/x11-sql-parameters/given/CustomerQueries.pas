unit CustomerQueries;

interface

uses
  FireDAC.Comp.Client;

function CountCustomersNamed(const AConn: TFDConnection; const AName: string): Integer;

implementation

function CountCustomersNamed(const AConn: TFDConnection; const AName: string): Integer;
begin
  Result := AConn.ExecSQLScalar('select count(*) from customers where name = ''' + AName + '''');
end;

end.
