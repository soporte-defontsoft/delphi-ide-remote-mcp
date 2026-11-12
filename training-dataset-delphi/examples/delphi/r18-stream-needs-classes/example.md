---
id: r18-stream-needs-classes
family: repair
language: delphi
framework: rtl
teaches: the streams (TStringStream, TMemoryStream, TFileStream) live in System.Classes and TEncoding in System.SysUtils; one missing unit breeds a cascade of E2066 - fix the first error
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r18, and the unit of each class read through RTTI)
---

## user
This Delphi unit does not compile:

{{text:dcc.txt}}

{{code:broken/TextBlob.pas}}

## assistant
Only the first error matters: `TStringStream` is declared in `System.Classes`, with the other streams (`TMemoryStream`, `TFileStream`), and the unit only uses `System.SysUtils`, where `TEncoding` lives. Without the type, every line that uses `Stream` is noise to the compiler - that is where the three E2066 come from, and they go away with the first error. Add `System.Classes` to the implementation `uses` clause (only the implementation needs the type).

{{code:fixed/TextBlob.pas}}
