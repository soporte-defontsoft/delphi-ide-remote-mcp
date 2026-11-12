---
id: p05-measure-what-already-worked
family: landscape
language: python
framework: none
teaches: before changing a shared helper, pin what its callers already do with tests, then change it and run them again
judge: python check.py (the two old tests pass on given/ and the new one fails there; all three pass on answer/)
---

## system
You write Python code.

## user
In this Python module, make `slugify` turn accented letters into their plain letter ("Café con leche" -> "cafe-con-leche") instead of dropping them.

{{code:given/slugs.py}}

## assistant
`slugify` is shared: `article_url` and `tag_url` both depend on it. Before changing a shared helper, pin down what its callers already do with tests and run them on the current code; then make the change and run them again - the new rule must not move anything that already worked.

First the tests. The first two pass on the current code; the third is the new behaviour:

{{code:answer/test_slugs.py}}

Then the change:

{{code:answer/slugs.py}}
