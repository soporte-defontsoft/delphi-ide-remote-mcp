---
id: t11-case-needs-ordinal
family: task
language: delphi
framework: rtl
teaches: case only takes ordinal values; look a string up with IndexText and branch on the index
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t11)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Map the colour names red, green and blue (any case) to the codes $0000FF, $00FF00 and $FF0000 with a case statement; any other name returns -1.

## assistant
`case` only accepts ordinal values (integers, characters, enumerations), and a string is not one. Turn the name into an index first: `IndexText` (System.StrUtils) returns its position in the list ignoring case, or -1, and the `case` branches on that integer.

{{code:ColorCodes.pas}}
