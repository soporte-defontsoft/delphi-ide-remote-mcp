unit PageText;

interface

function HtmlText(const AText: string): string;

implementation

uses
  System.NetEncoding;

function HtmlText(const AText: string): string;
begin
  // TNetEncoding.HTML encodes '&' together with '<', '>' and '"', in one pass: nothing is encoded twice
  Result := TNetEncoding.HTML.Encode(AText);
end;

end.
