---
id: ho48-py-second-writer-thumb-key
family: every-place
language: python
framework: none
teaches: a bug report against a reader is often a second writer; the writer that drifted calls the one writer, and the reader stays its strict inverse - it is never taught a second shape
judge: python check.py (the premise on given/; both writers agree, the gallery key reads back, the reader still refuses the other shape on answer/); the key is composed once (once)
once: /w{
varies: p09-second-writer-bug-report p12-second-writer-file-name e05-second-writer-bug-report e08-second-writer-file-name
---

## user
Thumbnails rendered by the gallery are never cleaned up: `parse_thumb_key` returns None for their keys, like `thumb/1234/320px`. Fix this Python module.

{{code:given/thumbs.py}}

## assistant
`parse_thumb_key` is right; the bug is a second writer. `thumb_key` writes `thumb/1234/w320`, and `gallery_thumb_key` writes the same key as `thumb/1234/320px`. Teaching the reader a second shape would make every reader of the key carry both, and the next writer would invent a third. So `gallery_thumb_key` calls `thumb_key`: one writer, and the reader stays its strict inverse. Keys already stored in the other shape can be converted once, instead of loosening the everyday reader.

{{code:answer/thumbs.py}}
