# Example project — context

> Example note. It shows the *shape* of a context note: the stable "why" of a
> project, the part that does not change week to week. Replace all of it.

## What it is

A small service that imports supplier price lists and publishes them to the
main application. Runs unattended, nightly.

## Why it exists

Prices used to be pasted by hand into the application, which meant a day of lag
and regular typos in the decimals. The importer removed both.

## Shape

- **Reader** — one adapter per supplier format (CSV, XLSX, a SOAP endpoint).
- **Normalizer** — currency, VAT and unit conversion. All the business rules
  live here; the adapters stay dumb on purpose.
- **Publisher** — writes to the application's staging tables, never to the live
  ones directly.

## Decisions that stuck

- **Nightly, not on demand** — the supplier endpoints rate-limit hard and two
  of them only refresh once a day, so on-demand added latency and no freshness
  (2024-02-11).
- **Staging tables instead of direct writes** — one bad import in the first
  month reached production prices; staging plus a diff review made that
  impossible (2024-03-02).
- **Adapters never convert** — an early adapter did its own VAT maths and
  drifted from the others. Conversion belongs in one place (2024-05-19).

See also [[Example conventions]].
