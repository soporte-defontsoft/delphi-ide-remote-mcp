---
id: x08-rtl-file-extension
family: landscape
language: delphi
framework: rtl
teaches: look before you write includes the RTL - ExtractFileExt takes the extension of the FILE name; searching the whole path for a dot finds the dot of a folder
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x08 - a dot in a folder name, a double extension, a name that starts with a dot; TPath.GetExtension and the Pos version measured on the same paths); the answer calls the RTL (must_contain)
must_contain: ExtractFileExt(APath)
---

## user
Write `ExtensionOf(const APath: string): string` in Delphi: the extension of the file a path names, with its dot (`.pdf`), or an empty string when it has none.

## assistant
`System.SysUtils` already has it: `ExtractFileExt`, which only looks at the file name. Searching the whole path for a dot goes wrong as soon as a folder has one: for `C:\v1.2\readme`, `Copy(APath, Pos('.', APath), MaxInt)` gives `.2\readme`, while `ExtractFileExt` gives the right answer, an empty string. It also gives `.gz` for `archive.tar.gz` (only the last extension) and `.gitignore` for `.gitignore`. (`TPath.GetExtension`, in `System.IOUtils`, gives the same on these paths.)

{{code:FileKinds.pas}}
