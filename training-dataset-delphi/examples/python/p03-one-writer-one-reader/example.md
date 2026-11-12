---
id: p03-one-writer-one-reader
family: every-place
language: python
framework: none
teaches: one function composes a format and its inverse reads it; two writers of the same name drift apart
judge: python check.py (the premise on given/, round trip on answer/); the name is composed once (once)
once: export-{year}-{number:04d}.csv
---

## system
You write Python code.

## user
Add a function to this module that reads the year and the number back from an export file name.

{{code:given/export_names.py}}

## assistant
There are already two writers of this name and they disagree: `export_file_name` pads the number to four digits (`export-2026-0007.csv`) and `archive_file_name` does not (`export-2026-7.csv`). A reader can only be the inverse of one writer. So: one function composes the name, the other caller uses it, and the reader is written as its inverse. It still reads the old unpadded names, since `int("7")` works.

{{code:answer/export_names.py}}
