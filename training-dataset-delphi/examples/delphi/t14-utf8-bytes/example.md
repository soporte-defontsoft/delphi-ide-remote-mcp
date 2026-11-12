---
id: t14-utf8-bytes
family: task
language: delphi
framework: rtl
teaches: Length counts characters, not bytes; the size in bytes depends on the encoding - TEncoding (System.SysUtils)
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t14 - 'Café' is 4 characters and 5 UTF-8 bytes; the unit of TEncoding read from the class)
---

## user
A field of a file format holds at most 50 bytes of UTF-8. In Delphi, how many bytes does a string take in UTF-8? Write `Utf8ByteCount(const AText: string): Integer`.

## assistant
`Length` counts the characters of a Delphi string (UTF-16 code units), not bytes: `'Café'` has 4 characters but takes 5 bytes in UTF-8, because `é` needs two. Ask the encoding: `TEncoding.UTF8.GetByteCount`, from `System.SysUtils` (`TEncoding.UTF8.GetBytes` gives the bytes themselves).

{{code:Utf8Size.pas}}
