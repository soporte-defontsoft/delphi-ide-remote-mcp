---
id: r05-declaration-differs
family: repair
language: delphi
framework: rtl
teaches: E2037 - the implementation's signature must match the declaration; one mismatch breeds E2003 and E2065
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (verify/DatasetBrokenProbe); fixed compiles and runs (verify/DatasetSpecTest: r05)
---

## user
I added a tax parameter to `Gross` and now this Delphi unit does not compile:

{{text:dcc.txt}}

{{code:broken/InvoiceMath.pas}}

Fix it so `Gross` adds the tax percentage to the base amount.

## assistant
Start with the first error; the other two follow from it. The class declares `Gross(const ATaxPercent: Currency)`, but the implementation still says `function TInvoice.Gross: Currency` (E2037). A method's signature lives in two places and both must match. Because they do not, the compiler does not take that body as the method: there `FBase` is unknown (E2003), and the declared method is left without a body (E2065). Make the implementation's signature match the declaration:

{{code:fixed/InvoiceMath.pas}}
