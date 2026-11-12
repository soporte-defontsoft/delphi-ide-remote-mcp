---
id: ho20-lap-time-format
family: task
language: delphi
framework: rtl
teaches: in FormatDateTime nn is the minutes, and mm is the month unless it follows an hour; milliseconds become a TDateTime as a fraction of a day
judge: dcc64 37.0 Win64 + run (verify/HeldoutSpecTest: ho20 - the examples, and every 997 ms of the hour against integer arithmetic; mm:ss.zzz of 83250 measured as 12:23.250)
varies: t01-minute-second
---

## user
Write a Delphi unit `LapTimes` with `function LapText(const AMilliseconds: Integer): string;`. It shows a lap time under one hour as minutes, seconds and milliseconds: 83250 gives `01:23.250`, and 500 gives `00:00.500`.

## assistant
`FormatDateTime` does it once the milliseconds are a `TDateTime`, which is a fraction of a day: `AMilliseconds / MSecsPerDay`. The trap is the minutes. In a format, `nn` is always the minutes, while `mm` is the month unless it comes right after an hour: `mm:ss.zzz` gives `12:23.250` for 83250, the 12 being the month of day zero. So the format is `nn:ss.zzz`.

{{code:LapTimes.pas}}
