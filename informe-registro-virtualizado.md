# Claude Code on Windows: registry writes from the agent's shell never reach the real HKCU

**Environment**: Windows 11 IoT Enterprise LTSC 2024 (26100), Claude Code desktop app,
RDP session, single user (no elevation involved).

## What happens

Registry writes made from Claude Code's Bash/PowerShell tools — and from any process
launched by them — go to a view that the user's own processes never see. Reads from the
agent's side show that private view, so the agent sees a consistent (but wrong) picture
and believes its writes succeeded. **File writes are NOT affected**: they land on the real
filesystem normally, which makes the discrepancy easy to miss.

## Reproduction (10 minutes, measured 2026-09-19/20)

1. From Claude Code, create a key: `HKCU\Software\<anything>\ZZTEST` (Python `winreg`,
   PowerShell `New-Item`, or a native program launched from the agent's shell — all
   behave the same).
2. Read it back from Claude Code: **it is there**.
3. Look at the same path in `regedit` as the same user, refreshed (F5), or export the
   hive with `reg export`: **it is not there**.
4. Write a value to a key that DOES exist in the real hive: no exception is raised, and
   the key's last-write timestamp does not change in the real hive.

## What we ruled out

- **Different user / hive**: `WindowsIdentity.GetCurrent()` in the agent's shell reports
  the same account and the same SID as the interactive session, and reading through
  `HKEY_USERS\<that SID>` shows the agent's view, not the real one.
- **Elevation / UAC virtualisation**: the agent's shell, the user's `explorer.exe` and a
  user-launched service process all report `TokenVirtualizationEnabled = false`, same
  user, same SID.
- **The Bash tool's sandbox flag**: `dangerouslyDisableSandbox: true` changes nothing.
- **WOW64 redirection**: not applicable to `HKCU\Software`, and the values differ under a
  plain 64-bit read on both sides.
- **A hive file on disk**: a marked key written from the agent could not be found in any
  file modified in the previous 5 minutes under `%APPDATA%`, `%LOCALAPPDATA%`, `%TEMP%`,
  `C:\ProgramData` or the user profile (searched as ANSI and UTF-16).

## Why it matters

This makes a whole class of work silently unverifiable. In our case the agent spent an
evening "measuring" a feature that writes to `HKCU` — it read back its own writes,
concluded the feature worked, and every conclusion was wrong. The product code turned out
to be correct: only the test bench was lying, and nothing in the tooling hinted at it.

A warning would be enough — something like "registry writes in this environment are
isolated from the user's hive". Silent divergence between what the agent writes and what
the user sees is the part that costs hours.

## Suggestion

Either surface the isolation explicitly (documented, and ideally visible in the tool's
error/soft-warning surface), or make registry writes fail loudly instead of appearing to
succeed. Today they return success, and reads confirm them, which is the worst
combination for an agent trying to verify its own work.
