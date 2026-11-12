---
id: x04-rtl-path-combine
family: landscape
language: delphi
framework: rtl
teaches: TPath.Combine already joins paths (separator only when missing, the platform's own); a hand-written '\' is a copy of it that breaks off Windows
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x04 - with and without the trailing separator); the answer calls TPath.Combine (must_contain)
must_contain: TPath.Combine(AFolder, 'config.ini')
---

## user
In Delphi, build the path of `config.ini` inside a folder. The folder may or may not end with a separator, and the code also has to run on Linux and Android. Write `ConfigFileIn(const AFolder: string): string`.

## assistant
`TPath.Combine`, in System.IOUtils, already does it: it adds the separator only when it is missing, and it uses the platform's own (`PathDelim`). `AFolder + '\config.ini'` is a hand-written copy of it that doubles the separator when the folder already ends with one, and breaks on Linux and Android, where the separator is `/`.

{{code:ConfigPath.pas}}
