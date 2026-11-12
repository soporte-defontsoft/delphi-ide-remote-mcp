---
id: x09-rtl-html-encode
family: landscape
language: delphi
framework: rtl
teaches: look before you write includes the RTL - TNetEncoding.HTML encodes '&', '<', '>' and '"' in one pass; replacing by hand in the wrong order encodes twice
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: x09 - a tag and an ampersand, a double quote; facts: the apostrophe is left as it is, the hand-made order encodes twice); the answer calls the RTL (must_contain)
must_contain: TNetEncoding.HTML.Encode(AText)
---

## user
When a user writes `<b>` in a comment, the page shows `&lt;b&gt;` instead of `<b>`. This Delphi function puts the text into the HTML. Fix it.

{{code:given/PageText.pas}}

## assistant
The replacements run in the wrong order: `<` becomes `&lt;` first, then the `&` of that `&lt;` becomes `&amp;`, and the browser shows `&lt;b&gt;`. Moving `&` to the front would fix this case and still leave the double quote, which breaks an attribute. `System.NetEncoding` already does it right, in one pass: `TNetEncoding.HTML.Encode`. It encodes `&`, `<`, `>` and `"`; it leaves the apostrophe as it is, so attribute values go between double quotes.

{{code:answer/PageText.pas}}
