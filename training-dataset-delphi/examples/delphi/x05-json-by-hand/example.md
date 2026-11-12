---
id: x05-json-by-hand
family: landscape
language: delphi
framework: rtl
teaches: look before you write includes the RTL - JSON is written with System.JSON (TJSONObject), never by concatenation: escaping one character by hand fixes one name and leaves the next
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x05 - a quote, a backslash, a tab and a line break survive the round trip, and #1 leaves no raw control character; the concatenated version does not parse; Delphi's parser accepts a raw #1); the answer uses TJSONObject (must_contain)
must_contain: TJSONObject.Create
---

## user
The JSON this Delphi function writes is rejected when a customer's name has a quote in it, like `Ann "the boss"`. Fix it.

{{code:given/CustomerJson.pas}}

## assistant
Replacing the quote by hand would fix this name and break on the next one. JSON escapes the quote, the backslash and EVERY control character (U+0000 to U+001F), not only the tab and the line break - and a hand-made list of replacements always stops short of that. It is also hard to notice: Delphi's own parser accepts a raw control character inside a string, so a test that only parses the output does not catch it. `System.JSON` already writes it correctly: build a `TJSONObject`, add the pairs, and let `ToJSON` do the escaping. The same goes for reading it back: `TJSONObject.ParseJSONValue`, not `Pos` and `Copy`.

{{code:answer/CustomerJson.pas}}
