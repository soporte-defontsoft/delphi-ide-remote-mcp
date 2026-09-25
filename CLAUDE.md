# This repository is worked THROUGH its own MCP server

**Hard rule (David, 2026-09-20).** When working on this repo, an agent reads,
searches, edits, configures, builds and versions **through the `delphi_*` MCP
tools** — not through the generic file/shell tools — even when it happens to be
running on the very Windows machine that hosts Delphi and the server.

**Why.** The only real test of this product is being used as a client. On
2026-09-20 v1.0.0-beta shipped with `delphi_read` (the most used tool here),
`delphi_help` (the first call the manual tells an agent to make) and
`delphi_git status` answering `{"ok": true}` and **not one line of content** to
any MCP client that understands `structuredContent`. The suite was green: 51
batteries, 1293 checks, 0 failures — they speak the raw protocol and read
`content`, so not one of them could see it. Using the server as an agent found
it in the first call.

## Survey the landscape first (David, 2026-09-20)

One act, four questions. You look at the landscape once - the one there is
today AND the one this code will have tomorrow - and while you are
there you ask all four:

**1. Landscape before TOUCHING** — where else does this live? You do not fix
where you happen to be looking; you fix where the rule lives. If there is a
single central point, patching an edge *hides* the bug: the symptom goes and
the cause stays, now with nobody looking for it.

**2. Landscape to see if it ALREADY EXISTS** — is there something similar,
usable or adaptable? Often the answer is a *parameter* on what exists, not a
sibling. That reduces code and centralises the problems.

**3. Landscape to COUNT** - how many times is this already written? Twice
is a helper with parameters: reusable, extendable, central, and a bug fixed
there is fixed in every caller at once. For configuration and jail
decisions, ONE reader from the very first copy: several readers of the same
setting are several doors. Measured 2026-09-25: 18 hand-written copies of
"the active workspace's field, else the global" - a new key with its
workspace half forgotten would have fallen back to the global SILENTLY.

**4. The FUTURE landscape** - who will need this next? Design it so the
next caller is one line, not a copy: the next tool that captures, the next
key of a workspace, the next format. Measured 2026-09-25, three times in one
afternoon: the inline screenshot first went into `delphi_desktop`'s own
`Execute` while `delphi_adb` also captures; base64 was validated inside
`delphi_upload` while `delphi_fetch` encoded on its own; the capture
recognizer knew `desktop` and Android captures kept piling up. Each became
one helper (`DeliverCapture` / `AttachImage`, `Lsp.Base64`,
`CAPTURE_SUB_*` shared by namer and reader), and the next tool that
captures now calls it.

In David's words: *"una cosa es saber escribir codigo y otra distinta es
saber programar"* - writing code solves today's line; programming leaves
tomorrow's line somewhere to land.

The practical part: **the same search answers all four.** Search for what the
function DOES, not for what you would call it, and that one pass turns up the
other places the rule lives AND the function you were about to duplicate.
Measured: searching for where paths were canonicalised turned up
`LongCanonical` — exactly what was being rewritten from scratch 800 lines
below it, in the same unit.

They are not style. Measured here on 2026-09-20, all three the same shape:

- A drive-letter leak was patched at ONE emitter instead of at the single
  outbound masker. It stayed alive in eight other tools and an auditor found
  it hours later.
- A jail fix changed how roots are canonicalised without checking the other
  sites that canonicalise. Two forms then coexisted, the "is this the root?"
  comparison stopped matching, and the workspace root became **deletable**.
- The `occurrence` bug lived in two twins (`delphi_edit` / `delphi_textedit`)
  and a third door (block anchors). Fixing one left two.

And the counterpart, which is what the rules buy: of the 32 sites of one
directory-creation race, only ONE had ever shown up in a battery. The other 31
were waiting for two agents to coincide. Asking "where else does this live?"
is how you fix the bugs that have not happened yet.

The corollary: **a shared helper is also where the NEXT feature of the same
family lands.** `AplicaTanda` is the example — the two things still pending
for batches now have one place to be written instead of two.

## Nothing outside the workspace is ever written (David, 2026-09-25)

**Hard rule.** No tool creates, modifies, moves, renames, overwrites or
deletes anything outside the session's write roots - not directly, not
through a junction or a symlink, not as a side effect of an RTL call.
`ReadOnlyRoots` and everything outside `Roots` are read-only, full stop.
To bring something in from outside there is ONE way: `copy`, which copies
only what the session can read. `move` only moves inside the workspace.

**The proof that it needs a hard rule.** From v0.16 to 2026-09-25,
`delphi_move` of a folder called `TDirectory.Move`. The gate checked the two
paths it was given; the RTL then walked every junction inside the folder,
copied the files behind it into the jail and deleted the originals.
Reproduced live: a victim folder outside every root came out EMPTY. A gate
on the argument plus an operation on the tree is a hole: the gate has to
hold for every path the operation TOUCHES, not the one it was GIVEN.

**How it is kept.**
- One question, one helper: "may this session write HERE?" is answered by
  `EscrituraDenegada` in `Lsp.Guard` (the write gate on the REAL path plus
  the read-only mode). No tool decides read-only-ness on its own and no
  tool rebuilds the answer. The WRITERS ask it themselves (`AtomicWrite`,
  `BackupFile`): a caller that forgets - or writes a file it found inside
  a .dpr instead of one it was given - cannot open anything (audit,
  2026-09-25: a unit rename rewrote a file outside the roots).
- Trees are walked only by the guard's walkers, which never cross a link
  (`BorraArbol` deletes, `CopiaArbol` copies). A folder moves only by a
  rename of the folder itself, where a link travels as a link and what is
  behind it is never touched.
- The RTL tree functions (`TDirectory.Move`, `TDirectory.Copy`, recursive
  `TDirectory.Delete`) do not belong in the server. A raw primitive
  (`TFile.Move/Copy/Delete`, `MoveFile`, `DeleteFile`, `RemoveDir`) runs
  only on a path the gate has just approved. Measured 2026-09-25: about 35
  raw write calls spread across the units - every one is a door until it is
  audited behind the gate.
- Every tool that writes a folder gets a battery that plants a junction to
  a victim outside the roots; the victim must come out untouched.

## One namer (David, 2026-09-20)

The strong form of the rule, and his own words: *"si siempre pasan por el
mismo nombrador se te acaban los problemas"*. When something has a FORMAT —
a file name, a path, a key, an id, a wire format — there is **one function
that composes it and one that reads it, and the reader is the inverse of the
writer**. Nobody builds one by hand, anywhere.

Why it is not the same as the two questions above: you can pass both of them
and still fail here. v1.0.8 unified the READER of the trash file names and
left the three WRITERS alone — so the copy taken before a `restore`, named by
hand in a third shape, was invisible to the listing and could not be
restored. The edge was fixed and the point was left. **It took David one
question to find it**, the day it shipped.

The test is mechanical: grep for the format, not for the function name. If
two places build the same kind of string, one of them will drift, and the
reader will only understand one of them. A repeated *constant* is the same
smell one size down.

And the design cue that falls out of it: when two copies need to be told
apart, put the difference in the **folder, the prefix, the field** — never in
a variant of the name itself. The name stays one shape, so the reader keeps
working for all of them.

Full version, with the criteria for when a boolean is *not* the right answer:
`conventions/paisaje-antes-de-tocar.md` in the vault.

## What it means in practice

| Job | Tool |
| --- | --- |
| Read a source, its symbols, find text, list a folder | `delphi_read`, `delphi_symbols`, `delphi_search`, `delphi_list` |
| Edit Pascal / other text / several files at once | `delphi_edit`, `delphi_textedit`, `delphi_changeset` |
| Create a unit, form, project | `delphi_create` |
| Project settings, platforms, SDK, PAServer profile | `delphi_config` |
| Compile, run the tests of a project | `delphi_build`, `delphi_test` |
| Branches, diff, commit, tag, push | `delphi_git` |
| Linux / Android targets | `delphi_paserver`, `delphi_adb` |

If a tool makes a job harder than the shell would, **that is the bug to fix**,
not a reason to go around it: write it down or send it with `delphi_report`.

## The exceptions, and they are few

- **The whole project group** (`BuildGroup.bat`) and the **python batteries**
  (`tests/run_all.py`, `tests/release_check.py`) — the server builds projects,
  not its own group, and the batteries are the harness, not a client.
- **The release ritual** — it reads a credential file, and a credential never
  travels through a tool.
- **What is not Delphi work**: the knowledge vault and the server's own
  `settings.ini` (which lives outside the workspace roots). Neither belongs to
  these tools and neither counts as a gap.
- **Deploying the exe** to `C:\Delphi-mcp-Server\`. Since 2026-09-20 the
  agent does the whole thing: production is a **Windows Service**, and
  `sc.exe stop` / `sc.exe start DelphiLspMcp` work unelevated because that one
  account was granted start/stop rights on that one service (see the README).
  The MSIX constraint that used to make this David's job no longer applies -
  the SCM launches the service, so it never inherits the package's private
  registry hive.

  **But the service has to log on as the user who owns RAD Studio.** Not
  LocalSystem, not a fresh admin account: the IDE keeps its Library Search
  Path, its registered packages, its SDKs and its profiles in `HKCU`, and a
  server without them starts, answers, says `activeDelphi: 37.0` and then
  fails with `F2613 unit not found` the first time a project touches an
  installed component. Measured: 11 library roots as the IDE's user, 1 as
  LocalSystem, 2 as a new admin.
- **A wall.** If a tool genuinely cannot do the job, fix it the conventional
  way as a last resort and go straight back to the MCP — but **the wall IS the
  finding**: write down what you were doing, which tool you expected to do it,
  and what you did instead. That list is the roadmap.
- **Production being down.** The agent talks to production over HTTP
  (127.0.0.1:3131), so with nothing listening there are no tools — getting it
  back is then the only job. Normally that is `sc.exe start DelphiLspMcp` and
  the agent does it alone. The tray (`-gui`) is the fallback and reads the
  same port from `settings.ini`, so the two can never run at once: it is the
  service or the tray, never both.
