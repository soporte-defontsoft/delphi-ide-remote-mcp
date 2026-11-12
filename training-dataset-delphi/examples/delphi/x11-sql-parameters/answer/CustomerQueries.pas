unit CustomerQueries;

interface

uses
  FireDAC.Comp.Client;

function CountCustomersNamed(const AConn: TFDConnection; const AName: string): Integer;

implementation

function CountCustomersNamed(const AConn: TFDConnection; const AName: string): Integer;
begin
  // The name travels as a parameter, apart from the SQL text: no quoting by hand,
  // and nothing in it can change the query
  Result := AConn.ExecSQLScalar('select count(*) from customers where name = :name', [AName]);
end;

end.
