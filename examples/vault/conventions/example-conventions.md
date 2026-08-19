# Example conventions

> Example note — it shows the shape of a convention note. Replace with your own.

## Rule

Every unit that talks to the outside world (files, HTTP, database) returns its
errors; it never shows them. UI is the only layer allowed to display anything.

## Why

A helper unit popped up a message box during a nightly unattended run and the
whole import hung until someone came in the next morning and clicked OK
(2024-01-22). The rule exists because of that morning.

## Exceptions

None. If a helper "needs" to ask the user something, the design is wrong: pass
the decision back to the caller.

---

## Rule

Anything that can fail gets a timeout, and the timeout is a parameter with a
default — never a hardcoded constant buried in the call.

## Why

Two different suppliers needed 5 s and 90 s. With a constant, the second one
could only work by making everyone wait.

## Exceptions

Local file reads. Add one the day a network drive proves otherwise.
