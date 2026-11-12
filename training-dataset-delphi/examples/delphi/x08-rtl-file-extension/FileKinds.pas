unit FileKinds;

interface

function ExtensionOf(const APath: string): string;

implementation

uses
  System.SysUtils;

function ExtensionOf(const APath: string): string;
begin
  // the extension of the FILE name: a dot in a folder name does not count
  Result := ExtractFileExt(APath);
end;

end.
