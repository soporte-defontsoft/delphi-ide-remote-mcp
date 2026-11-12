---
id: t05-signature-in-both-places
family: task
language: delphi
framework: rtl
teaches: a method's signature lives in the class declaration and in the implementation; both change together
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t05); the E2037 text is dcc's own (r05)
---

## user
In this Delphi unit, change `TOrder.Total` so it takes a discount percentage `ADiscountPercent: Currency` and returns the amount minus that percentage.

{{code:given/OrderMath.pas}}

## assistant
A method's signature is written twice in Delphi: in the class declaration and in the implementation. Both change together; if only one does, the unit stops compiling with E2037 ("Declaration of 'Total' differs from previous declaration").

{{code:answer/OrderMath.pas}}
