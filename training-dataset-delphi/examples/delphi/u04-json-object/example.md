---
id: u04-json-object
family: task
language: delphi
framework: rtl
teaches: TJSONObject lives in System.JSON; it owns the values added with AddPair, so freeing it frees them
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: u04, and the unit of TJSONObject read from the class)
---

## user
Delphi: given a name and an age, return the JSON text `{"name":"Ann","age":30}`. Write `PersonToJson(const AName: string; const AAge: Integer): string`.

## assistant
`TJSONObject` lives in `System.JSON`. It owns the values added with `AddPair` (here the `TJSONNumber`), so freeing the object frees them too; `ToJSON` returns the compact text.

{{code:PersonJson.pas}}
