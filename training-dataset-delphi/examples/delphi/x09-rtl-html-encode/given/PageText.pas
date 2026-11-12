unit PageText;

interface

function HtmlText(const AText: string): string;

implementation

uses
  System.SysUtils;

function HtmlText(const AText: string): string;
begin
  Result := StringReplace(AText, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
end;

end.
