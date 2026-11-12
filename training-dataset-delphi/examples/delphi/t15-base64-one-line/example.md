---
id: t15-base64-one-line
family: task
language: delphi
framework: rtl
teaches: TNetEncoding.Base64 breaks long output into lines; Base64String gives one line (System.NetEncoding)
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t15 - one line, decodes back; and Base64 breaking the same text into lines)
---

## user
In Delphi, encode a text as Base64 to put it in a JSON field. Write `ToBase64(const AText: string): string`.

## assistant
Use `TNetEncoding.Base64String`, from `System.NetEncoding`. `TNetEncoding.Base64` breaks long output into lines (the MIME style of e-mail), and line breaks inside a JSON value or a URL are a bug waiting to happen. `Base64String` returns one single line, and `TNetEncoding.Base64String.Decode` reads it back.

{{code:Base64Text.pas}}
