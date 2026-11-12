---
id: e08-second-writer-file-name
family: every-place
language: delphi
framework: rtl
teaches: a bug report against a reader is often a second writer; the writer that drifted calls the one writer, and the reader stays its strict inverse - it is never taught a second shape
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: e08 - the nightly name reads back, both writers agree, the reader still refuses the other shape and a day that does not exist); the format is written once (once)
once: FormatDateTime('yyyy-mm-dd'
---

## user
Our cleanup job finds old backups by their date with `TryBackupDay`, but it never finds the ones the nightly job writes. Fix this Delphi unit.

{{code:given/BackupFiles.pas}}

## assistant
`TryBackupDay` is right; the bug is a second writer. `BackupFileName` writes `backup_2026-03-07.zip`, and `NightlyBackupFileName` writes the same day as `backup_20260307.zip`. Teaching the reader a second shape would make every reader of the name carry both, and the next writer would invent a third. So `NightlyBackupFileName` calls `BackupFileName`: one writer, and `TryBackupDay` stays its strict inverse. The nightly backups already on disk can be renamed once to the real shape.

{{code:answer/BackupFiles.pas}}
