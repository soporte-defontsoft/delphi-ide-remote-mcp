---
id: p06-pin-callers-before-change
family: landscape
language: python
framework: none
teaches: before changing a shared helper, pin what its callers already do with tests, then change it and run them again
judge: python check.py (the two old tests pass on given/ and the new one fails there; all three pass on answer/)
---

## system
You write Python code.

## user
`round_price` must round halves up (0.125 -> 0.13), but Python's `round()` rounds them to even (0.12). Change it in this module.

{{code:given/prices.py}}

## assistant
`round_price` is shared: `line_total` and `with_tax` both depend on it. Before changing a shared helper, pin down what its callers already do with tests and run them on the current code; then make the change and run them again - the new rule must not move anything that already worked.

First the tests. The first two pass on the current code; the third is the new behaviour:

{{code:answer/test_prices.py}}

Then the change:

{{code:answer/prices.py}}
