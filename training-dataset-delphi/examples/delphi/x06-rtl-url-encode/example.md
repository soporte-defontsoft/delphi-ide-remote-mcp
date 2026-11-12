---
id: x06-rtl-url-encode
family: landscape
language: delphi
framework: rtl
teaches: look before you write includes the RTL - a value that goes into a URL is encoded with TNetEncoding.URL (System.NetEncoding), never appended as it comes
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x06 - 'a b&c=d/e' gives q=a+b%26c%3Dd%2Fe, and '?' gives %3F); the answer encodes with the RTL (must_contain)
must_contain: TNetEncoding.URL.Encode(ATerm)
---

## user
Write `SearchUrlFor(const ATerm: string): string` in Delphi: it returns `https://example.com/search?q=` followed by the search term.

## assistant
The term cannot be appended as it comes: a `&` in it would start a new parameter, and a space is not allowed in a URL at all. `System.NetEncoding` already encodes it: `TNetEncoding.URL.Encode`. For `a b&c=d/e` it gives `a+b%26c%3Dd%2Fe`.

{{code:SearchUrl.pas}}
