---
id: p09-second-writer-bug-report
family: every-place
language: python
framework: none
teaches: a bug report against a reader is often a second writer; the writer that drifted calls the one writer, and the reader stays its strict inverse - it is never taught a second shape
judge: python check.py (the premise on given/; both writers agree, the log key reads back, the reader still refuses the other shape on answer/); the format is written once (once)
once: "%Y%m%d"
---

## user
Session keys copied from the logs, like `7:2026-03-07`, are refused by `parse_session_key` in this Python module. Fix it.

{{code:given/session_keys.py}}

## assistant
The reader is right; the bug is a second writer. `session_key` writes `7:20260307`, and `session_key_for_log` writes the same key as `7:2026-03-07`. Teaching the reader a second shape would make every reader of the key carry both, and the next writer would invent a third. So `session_key_for_log` calls `session_key`, the day format lives in one constant, and `parse_session_key` stays the strict inverse of the one writer. If keys in the other shape were already stored, convert them once instead of loosening the everyday reader.

{{code:answer/session_keys.py}}
