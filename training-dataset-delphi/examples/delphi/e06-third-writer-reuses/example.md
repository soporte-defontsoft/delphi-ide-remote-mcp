---
id: e06-third-writer-reuses
family: every-place
language: delphi
framework: rtl
teaches: a new place that needs an existing format calls its one writer - it does not write the format again
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: e06 - the subject, and the reference inside it reads back); the format is written once (once) and the new function calls the writer (must_contain)
once: Format('INV-%d-%.5d'
must_contain: 'Payment reminder: ' + InvoiceRef(AYear, ANumber)
---

## user
Add to this Delphi unit a function `ReminderSubject(const AYear, ANumber: Integer): string` for the subject of a payment reminder e-mail: `Payment reminder: ` followed by the invoice reference.

{{code:given/InvoiceRefs.pas}}

## assistant
The unit already has the one writer of an invoice reference, `InvoiceRef`, and `TryParseInvoiceRef` reads exactly what it writes. The subject calls it instead of writing `INV-...` a second time: if the format ever changes, it changes in one place, and the reference in the subject is always one the reader understands.

{{code:answer/InvoiceRefs.pas}}
