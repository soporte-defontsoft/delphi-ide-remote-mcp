---
id: p11-csv-module
family: landscape
language: python
framework: none
teaches: look before you write includes the standard library - CSV is written with the csv module, never joined by hand: quoting by hand fixes the comma and leaves the quote
judge: python check.py (the premise on given/; the exact line, and the fields read back with csv.reader on answer/); the answer uses the module (must_contain)
must_contain: csv.writer(
---

## user
A name like `Smith, John` ends up split into two columns by this Python function. Fix it.

{{code:given/csv_lines.py}}

## assistant
Wrapping every field in quotes by hand would fix the comma and break on the next field with a quote inside, which CSV doubles (`"say ""hi"""`). The `csv` module already knows the rules: it quotes a field only when it needs to and doubles the quotes inside. Reading the line back is the same module, `csv.reader`.

{{code:answer/csv_lines.py}}
