---
id: p01-reuse-existing-helper
family: landscape
language: python
framework: none
teaches: look at what the module already has before writing; call the helper instead of writing its twin
judge: python check.py (behaviour); the answer calls full_name (must_contain)
must_contain: full_name(first, last)
---

## system
You write Python code.

## user
Add a function `customer_label(first, last)` to this Python module. It returns `Customer: ` followed by the customer's full name.

{{code:given/names.py}}

## assistant
Look at what the module already has first: `full_name` builds exactly that name, trimming both parts and leaving no stray space when one of them is empty. `customer_label` calls it instead of building the name a second time - a copy would give a different answer the first time someone changes how names are built.

{{code:answer/names.py}}
