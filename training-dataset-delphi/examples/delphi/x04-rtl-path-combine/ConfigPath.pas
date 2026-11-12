unit ConfigPath;

interface

function ConfigFileIn(const AFolder: string): string;

implementation

uses
  System.IOUtils;

function ConfigFileIn(const AFolder: string): string;
begin
  // TPath.Combine adds the separator only when it is missing, and uses the
  // platform's own (PathDelim): no hand-written '\' that breaks on Linux or Android
  Result := TPath.Combine(AFolder, 'config.ini');
end;

end.
