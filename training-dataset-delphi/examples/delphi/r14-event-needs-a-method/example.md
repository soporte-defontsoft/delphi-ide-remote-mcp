---
id: r14-event-needs-a-method
family: repair
language: delphi
framework: rtl
teaches: E2009 - an event (TNotifyEvent and the rest) needs a method of an object, not a standalone procedure
judge: dcc64 37.0 Win64 - broken gives exactly dcc.txt (compiled from a short path); fixed compiles and runs (verify/DatasetSpecTest: r14)
---

## user
Delphi: I want to count the changes of a TStringList, but assigning the handler does not compile:

{{text:dcc.txt}}

{{code:broken/ChangeWatch.pas}}

## assistant
`OnChange` is a `TNotifyEvent`, declared as `procedure(Sender: TObject) of object`: a method pointer, which carries the method and the object it belongs to. A standalone procedure is not a method, hence E2009 ("method pointer and regular procedure"). Put the handler in a class and assign the method of an instance; the counter becomes a field of that object instead of a global variable.

{{code:fixed/ChangeWatch.pas}}
