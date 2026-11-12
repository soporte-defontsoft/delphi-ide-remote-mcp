unit TextFiles;

interface

function CountTextFiles(const AFolder: string): Integer;

implementation

uses
  System.IOUtils;

function CountTextFiles(const AFolder: string): Integer;
begin
  Result := Length(TDirectory.GetFiles(AFolder, '*.txt'));
end;

end.
