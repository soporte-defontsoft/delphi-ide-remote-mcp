---
id: ho32-rtl-change-extension
family: landscape
language: delphi
framework: rtl
teaches: ChangeFileExt replaces or adds an extension, looking for the dot only in the file name; TPath has no ChangeExtension (the .NET name - measured: E2003)
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho32 - a dot in a folder, two dots, no extension); TPath.ChangeExtension measured as E2003; the RTL is used (must_contain)
must_contain: ChangeFileExt(
varies: x08-rtl-file-extension x04-rtl-path-combine r09-invented-rtl-function
---

## user
Delphi: write the unit `PreviewFiles` with `function PreviewName(const AFileName: string): string;`. It gives the same file name with the extension `.pdf` instead of the one it had, or with `.pdf` added when it had none: `report.final.docx` gives `report.final.pdf`, and `C:\my.docs\notes` gives `C:\my.docs\notes.pdf`.

## assistant
`ChangeFileExt` (`System.SysUtils`) does it: it replaces what follows the last dot of the file name, and adds the extension when there is none. It looks for that dot only after the last folder separator, so the dot of `my.docs` is left alone. `TPath` has no `ChangeExtension` in Delphi - that is the .NET name, and the compiler answers it with E2003.

{{code:PreviewFiles.pas}}
