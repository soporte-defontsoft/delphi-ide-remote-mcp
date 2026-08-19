# Example project — log

> History: dated entries, newest first, append only. Never rewritten — the
> value of a log is that you can trust it.
>
> Example note — replace all of it.

- **2024-06-05** — Added the XLSX adapter for the new supplier. Their header
  spans two merged rows, so the sheet reader had to look for the first row with
  a numeric price cell instead of assuming row 1. Import of their catalogue:
  4 812 rows in 38 s. The unit column is free text ("box of 12", "cx12", "12u")
  and the normalizer rejects all of it — needs a lookup table, not a parser.

- **2024-05-19** — One adapter was doing its own VAT maths and had drifted 0,3 %
  from the rest since March. Moved all conversion into the normalizer and
  removed the duplicate logic. Lesson: adapters read, they never interpret.

- **2024-03-02** — A malformed import reached live prices (a decimal comma read
  as a thousands separator, 1 240 € instead of 1,24 €). Introduced staging
  tables plus a diff review before publish. Caught two similar cases since.

- **2024-02-11** — Chose a nightly run over on demand: two suppliers only
  refresh once a day and a third rate-limits at 60 requests/hour, so on-demand
  meant waiting without fresher data.
