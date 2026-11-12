---
id: p12-second-writer-file-name
family: every-place
language: python
framework: none
teaches: a bug report against a reader is often a second writer; the writer that drifted calls the one writer, and the reader stays its strict inverse - it is never taught a second shape
judge: python check.py (the premise on given/; both writers agree, the e-mailed name reads back, the reader still refuses the other shape and a day that does not exist on answer/); the format is written once (once)
once: "%Y-%m-%d"
---

## user
Our archiver sorts reports by day with `day_of_report`, but the reports that were e-mailed are always left out. Fix this Python module.

{{code:given/report_paths.py}}

## assistant
`day_of_report` is right; the bug is a second writer. `report_name` writes `report-2026-03-07.txt`, and `emailed_report_name` writes the same day as `report-7.3.2026.txt`. Teaching the reader a second shape would make every reader of the name carry both, and the next writer would invent a third. So `emailed_report_name` calls `report_name`, the day format lives in one constant, and `day_of_report` stays the strict inverse of the one writer. Reports already sent with the other name can be renamed once.

{{code:answer/report_paths.py}}
