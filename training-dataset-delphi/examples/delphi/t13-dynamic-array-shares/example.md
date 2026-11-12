---
id: t13-dynamic-array-shares
family: task
language: delphi
framework: rtl
teaches: a dynamic array is a reference - assigning it shares it; Copy makes an independent array
judge: dcc64 37.0 Win64 + run (verify/DatasetSpecTest: t13, and the sharing fact)
---

## system
You write Delphi (RAD Studio 13) code.

## user
Write `WithBonus(const AScores: TArray<Integer>; const ABonus: Integer): TArray<Integer>`: the same scores with a bonus added to each one. The caller's array must not change.

## assistant
A dynamic array is a reference: after `B := A` both names point to the same array, and changing `B[0]` changes `A[0]` too. Start from `Copy(AScores)`, which makes an independent array, and add the bonus to that. (Strings look similar but are copy-on-write: changing one never changes the other.)

{{code:ScoreCopy.pas}}
