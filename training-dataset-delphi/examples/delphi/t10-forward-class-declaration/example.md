---
id: t10-forward-class-declaration
family: task
language: delphi
framework: rtl
teaches: two classes that need each other - a forward declaration, completed in the same type section; TObjectList owns its items
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t10)
---

## user
In Delphi, TOrder must point to its TCustomer and TCustomer must own a list of its orders. Declare both classes in one unit.

## assistant
Each class needs the other, so `TCustomer` is declared ahead with a forward declaration (`TCustomer = class;`). The forward declaration and the full one must be in the **same** `type` section. `TObjectList<TOrder>` owns the orders, so freeing the customer frees them too.

{{code:Shop.pas}}
