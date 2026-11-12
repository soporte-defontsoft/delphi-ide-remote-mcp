---
id: t07-sort-generic-list
family: task
language: delphi
framework: rtl
teaches: TList<T>.Sort with TComparer<T>.Construct and an anonymous function
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t07)
---

## system
You write Delphi (RAD Studio 13) code.

## user
I have a `TList<TPerson>`, where TPerson is a record with Name and Age. Sort the list by name, ignoring case.

## assistant
`TList<T>.Sort` takes an `IComparer<T>`, and `TComparer<T>.Construct` (System.Generics.Defaults) builds one from an anonymous function. `CompareText` compares two strings ignoring case.

{{code:PeopleSort.pas}}
