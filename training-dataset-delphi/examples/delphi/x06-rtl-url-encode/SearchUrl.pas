unit SearchUrl;

interface

function SearchUrlFor(const ATerm: string): string;

implementation

uses
  System.NetEncoding;

function SearchUrlFor(const ATerm: string): string;
begin
  // TNetEncoding.URL encodes every character that means something in a URL
  // ('&', '=', '/', '?'...), and a space as '+'
  Result := 'https://example.com/search?q=' + TNetEncoding.URL.Encode(ATerm);
end;

end.
