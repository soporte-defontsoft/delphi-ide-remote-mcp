---
id: t03-char-code-outside-quotes
family: task
language: delphi
framework: rtl
teaches: a character code (#$2714) goes outside the quotes; Delphi string literals have no escape sequences
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t03 and the six-characters fact)
---

## system
You write Delphi (RAD Studio 13) code. Keep the source file plain ASCII.

## user
Write a function that returns the text "Sent" followed by a space and a check mark (U+2714).

## assistant
Delphi string literals have no escape sequences: inside the quotes, `'#$2714'` is six ordinary characters. A character code goes **outside** the quotes, concatenated to the literal: `'Sent ' + #$2714`. The source stays plain ASCII and the string holds the real character.

{{code:SendStatus.pas}}
