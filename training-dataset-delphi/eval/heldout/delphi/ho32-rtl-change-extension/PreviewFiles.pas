unit PreviewFiles;

interface

// The file name with the extension .pdf instead of the one it had, or added when it had none
function PreviewName(const AFileName: string): string;

implementation

uses
  System.SysUtils;

function PreviewName(const AFileName: string): string;
begin
  // ChangeFileExt looks for the dot only after the last folder separator
  Result := ChangeFileExt(AFileName, '.pdf');
end;

end.
