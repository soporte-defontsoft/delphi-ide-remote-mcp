---
id: r09-invented-rtl-function
family: repair
language: delphi
framework: rtl
teaches: E2003 on an RTL function that does not exist - ChangeExt is invented; ChangeFileExt(Name, '') drops the extension
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs, TPath.GetFileNameWithoutExtension included (verify/DatasetSpecTest: r09)
---

## user
Delphi: this should turn `C:\data\sales.csv` into `sales-report.txt`, but it does not compile:

{{text:dcc.txt}}

{{code:broken/FileStem.pas}}

## assistant
There is no `ChangeExt` in the RTL: the name is invented. The function is `ChangeFileExt(FileName, NewExt)` in System.SysUtils, and with an empty extension it drops the old one. Its neighbours: `ExtractFileName` (the name with its extension) and `ExtractFileExt`, and in System.IOUtils `TPath.GetFileNameWithoutExtension`.

{{code:fixed/FileStem.pas}}
