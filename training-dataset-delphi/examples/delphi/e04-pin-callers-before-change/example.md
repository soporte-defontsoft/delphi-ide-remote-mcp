---
id: e04-pin-callers-before-change
family: landscape
language: delphi
framework: rtl
teaches: before changing a shared helper, pin what its callers already do with tests (DUnitX), then change it and run them again
judge: dcc64 37.0 Win64 + DUnitX through delphi_test (verify/DatasetPinTest: 3/3); the premise measured once - on the given unit the two pinning tests pass and the new one fails
---

## user
Codes now also arrive with spaces inside (`k - 100`). Change `NormalizeCode` in this Delphi unit so that it ignores every space.

{{code:given/CodeRules.pas}}

## assistant
`NormalizeCode` is shared: `IsDiscontinued` and `IsSeasonal` both depend on it. Before changing a shared helper, pin down what its callers already do with tests and run them on the current code - they pass. Then add a test for the new rule (it fails on the current code), make the change, and run them all again: the new rule must not move anything that already worked.

First the tests, with DUnitX:

{{code:answer/CodeRulesTests.pas}}

Then the change:

{{code:answer/CodeRules.pas}}
