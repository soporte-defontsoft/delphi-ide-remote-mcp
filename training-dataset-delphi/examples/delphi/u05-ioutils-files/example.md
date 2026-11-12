---
id: u05-ioutils-files
family: task
language: delphi
framework: rtl
teaches: TDirectory, TFile and TPath are records in System.IOUtils; GetFiles with a mask searches one folder unless told otherwise
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u05 on a real folder, and the unit of TDirectory read through RTTI)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Count the .txt files in a folder, not in its subfolders. Write `CountTextFiles(const AFolder: string): Integer`.

## assistant
`TDirectory`, `TFile` and `TPath` are records in `System.IOUtils`. `TDirectory.GetFiles(Folder, '*.txt')` returns the matching files of that folder only; an overload with a `TSearchOption` takes the subfolders too.

{{code:TextFiles.pas}}
