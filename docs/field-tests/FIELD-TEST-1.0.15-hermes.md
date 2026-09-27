# Field test of v1.0.15-beta — assignment for the Hermes agent

> **Note (2026-09-22)**: written for 1.0.15; since 1.0.16 the desktop tool is `delphi_desktop profile=<PAServer profile>` for Linux and Windows, and `delphi_adb_linux` is only an alias. Kept as history.

You are an EXTERNAL tester of this MCP server. You work with your own token
(`[Workspace.Hermes]`), inside your own jail, on a real project:
**GalateaFMX**, which is in your sandbox. You do not know the server's code and
you do not need to: what is being tested is **what the tools tell you and let you do**.

A bug you find is worth more than ten green batteries: the batteries were
written by whoever wrote the code.

## How to work

1. **Everything through the `delphi_*` tools.** If a tool makes something harder
   than doing it by hand, THAT is a finding: report it, do not go around it.
2. **First call: `delphi_workspace`.** Write down what it answers: `roots`
   (your jail), `access`, and the `server` block — it has to say
   `version: 1.0.15-beta`, `mode`, `transport` and `account`. If it says another
   version, stop and report it: you would be testing another server.
3. **The server's paths are virtual units** (`srvd:\...`). Use them exactly as
   you get them; they are not your disks.
4. **Every phase ends with a report** through `delphi_report` (format below),
   also when everything went fine. Do not wait until the end to report.
5. **If a tool refuses**, read the whole message: it almost always says what to do.
   If the message does not help you, that is a finding too.

## What is NOT done (hard rules)

- **Do not leave your jail** or try to get around it "to test it". If you think
  a jail refusal is unfair, report it and carry on.
- **On a remote desktop, type ONLY into something you have just opened and that
  starts empty**: the start menu search box, the calculator, a field of the
  GalateaFMX app itself. **Never into a terminal, never into a text editor that
  already had a document, never into a browser with an open session.**
  Take a screenshot BEFORE typing to see where the focus is.
- **Do not open, read or copy credential files**, neither on the remote desktop
  nor on the server. If GalateaFMX asks for a user and password, **stop
  and ask David for them**; do not look for them.
- **Do not press "save", "discard", "delete" or "send"** on anything you have
  not created yourself in this test.
- **Do not publish anything**: no `git push`, no tags. `git status`/`diff`/`log` yes.
- If a call answers "session expired" or does not answer, **check whether it
  ran before repeating it** (a screenshot, a `delphi_read`): it may have
  run anyway.

## Phase 0 — Orientation (5 minutes)

- `delphi_workspace` (see above).
- `delphi_help` — read it: it is what the server says about itself. Write down
  anything it promises and then does not deliver.
- `delphi_projects` on your root: find GalateaFMX's `.dproj`.
- `delphi_config` `command=view` on that `.dproj`: active platforms, SDK
  and the project's profile.
- `delphi_paserver` `command=profiles`: which profiles and SDKs exist, with their glibc.

**Report:** after five calls, is it clear what you can do and where?
What did you miss knowing?

## Phase 1 — Build GalateaFMX

1. `delphi_build` for **Win64** (Debug). Write down the time, the errors, and whether
   the answer tells you where the binary ended up.
2. `delphi_build` for **Linux64**. Look at the `sdk` and `sdkNote` fields:
   they have to say which SDK it linked with and who decided it (the project or
   the IDE).
3. If it fails on a unit not found, do NOT edit search paths blindly:
   `delphi_config command=view section=searchpaths` and report what you see.
4. Repeat one build with `verbosity=normal` and another with `quiet`: is the
   short version enough to know whether it compiles? Does the long one bring what is missing?

## Phase 2 — Deploy and run on Linux

1. `delphi_paserver command=test-connection name=<profile>` against the Linux
   profile you use (ask David which one if there are several).
2. `delphi_build target=Deploy platform=Linux64 profile=<profile>`.
3. `delphi_paserver command=remote-run project=<dproj> name=<profile>`: the app
   has a window, so the normal outcome is `stillRunning=true` with partial output.
   Write down whether the answer explains it well.
4. **NEW in 1.0.15 — repeat `get-sdk`**: `delphi_paserver command=get-sdk
   name=<profile>` on an SDK that ALREADY exists. It has to answer fine, with
   pulls `already up to date` and an `incremental` note. Before this
   version it ended in RECHAZADO (refused). Report what you see.

## Phase 3 — See and drive the app (the remote desktop)

With `delphi_adb_linux profile=<profile>`:

1. `command=status` and then `command=screenshot`. Download the capture with
   `delphi_fetch` and LOOK at it. Can you see GalateaFMX?
2. `command=windows` if the window is covered.
3. **Get into the app** as far as you can without credentials. If it asks for a login,
   stop and ask David for it (hard rule).
4. **NEW in 1.0.15 — the keyboard.** In a text field of the app (or in the
   start menu search box), type with `command=type`:
   `Test 1015-14/2 Año @ (x); ¿ok?` (the ñ and the ¿ are there on purpose)
   Take a screenshot and compare it character by character. The answer has to say
   which keyboard it typed with (`teclado: el del escritorio (...)`, "keyboard:
   the desktop's"). Report ANY character that comes out different, and which layout it is.
5. **NEW in 1.0.15 — the text is typed, not executed.** Type into that
   same field: `hello; echo INJECTION $(id) 'q'`. It has to appear
   LITERALLY. If you see that something was executed, or the call fails with a
   shell syntax error, it is a SERIOUS bug: report it as `kind=bug` with the
   exact text of the answer.
6. Ask for a character that keyboard does not have (an emoji, for example): it has
   to be refused BY ITS NAME, without typing something else.
7. Walk through the app: open two or three screens, go back, close it with its
   button. Do the capture's coordinates land where you click? Does every answer
   bring its new capture?

If your server has a desktop session open, repeat 1–2 with
`delphi_desktop` (the Windows machine's own desktop). Without an open session it does not
work **on purpose** (the user has to be able to see what you do): write down
whether the message explains it.

## Phase 4 — Edit the way an agent would (on a COPY)

Do not touch the good GalateaFMX. Create a toy project in your jail:

1. `delphi_create kind=project-fmx name=HermesTest dir=<your root>\HermesTest`.
2. **NEW — subfolders**: `delphi_create kind=unit name=UModel
   project=<dpr> dir=Domain\Models` and a `kind=form-fmx ... dir=Views`.
   Check with `delphi_read` of the `.dpr` that they are registered with their
   relative path, and `delphi_build`.
3. Try what must NOT get through in `dir`: an absolute path, `..\outside`, a
   name with quotes. All three have to be refused.
4. **NEW — moving and deleting folders**: `delphi_move` from `Domain` to `Core`
   and `delphi_build` (it has to keep compiling); `delphi_delete` of the
   folder and `delphi_build` again.
5. **NEW — fragment mode**: create a `.md` with a paragraph of one single, very
   long line (500+ characters) that contains a number twice. With
   `delphi_textedit`:
   - `fragment` + `atline` + `new` on a unique piece → it has to change
     ONLY that.
   - the repeated number → it has to be refused, saying how many times it appears and
     showing the line.
   - without `atline` → refused.
   - inside `edits`: `[{"fragment":"...","new":"...","atline":N}]`.
   Repeat one with `delphi_edit` on a `.pas`. Is the refusal message enough
   to get it right the first time?
6. `delphi_changeset`: a change that touches the `.pas` and the `.md` at once,
   with `preview` and `commit`.
7. `delphi_symbols` on a unit with a `{$IFDEF LINUX}` block: the routine
   inside does NOT show up, and the tool's description has to warn about it.
8. `delphi_package` of the **Linux64** output folder: the answer has
   to bring `linuxNote` (the `chmod +x`).

## Phase 5 — Whatever you see

Half an hour free, using the server for something that feels natural to you in
GalateaFMX (finding where a class is used with `delphi_references`, a
`delphi_rename_symbol` in preview, `delphi_diagnostics` of a large unit,
`delphi_styles lint`). Write down frictions: parameters you do not guess the
first time, answers that are too long or too short, messages that do not
say what to do, times that get out of hand.

## How to report

One `delphi_report` call per finding (or per phase, if it went fine):

```json
{
  "agent": "hermes",
  "from": "Hermes - field test 1.0.15",
  "kind": "bug | limitation | suggestion | question",
  "title": "Phase 3.4 - the @ comes out as 2 on keyboard X",
  "message": "WHAT I DID (the exact call, with its parameters)\nWHAT HAPPENED (the LITERAL answer, pasted)\nWHAT I EXPECTED\nSEVERITY: blocking | annoying | cosmetic\nREPRODUCIBLE: always | sometimes | once"
}
```

Reporting rules:

- **Paste the literal answer**, do not summarize it: the bug is usually in one
  word.
- **One thing per report.** Three bugs = three reports.
- Tell **what you measured** apart from what you assume. "I think" is marked as such.
- If something surprised you for the better, say so too: it tells us what not to touch.
- When you finish, one last report `title: "SUMMARY field test 1.0.15"`
  with: the phases done, the phases you could not do and why, and your three
  most important findings in order.

## What is new in this version (so you know where to look)

- Fragment mode in the whole editing family.
- Project subfolders: `delphi_create dir=`, moving and deleting folders.
- `delphi_adb_linux type`: types with the real keyboard of the target desktop,
  and the text travels as text, never as a shell command (a SECURITY
  fix).
- A repeated `get-sdk` is no longer refused.
- Files in CP1252 no longer break `delphi_styles lint` nor hide notes of the
  vault.
- `delphi_workspace` says which Windows account the server runs as.

The details are in `CHANGELOG.md`, entry `[1.0.15-beta]`.
