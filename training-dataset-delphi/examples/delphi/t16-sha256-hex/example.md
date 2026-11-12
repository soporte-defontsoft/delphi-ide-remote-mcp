---
id: t16-sha256-hex
family: task
language: delphi
framework: rtl
teaches: THashSHA2 (System.Hash) - SHA-256 by default, lowercase hex
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t16 against the standard test vector of 'abc'; the unit of THashSHA2 read through RTTI)
---

## user
Delphi: I need the SHA-256 of a text as a hex string. Write `Sha256Hex(const AText: string): string`.

## assistant
`THashSHA2`, in `System.Hash`, hashes with SHA-256 unless told otherwise, and `GetHashString` returns the digest in lowercase hex.

{{code:Fingerprint.pas}}
