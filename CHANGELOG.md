# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/): MAJOR.MINOR.PATCH, where MINOR
adds tools/capabilities and PATCH fixes. The server reports its version in
the MCP `initialize` response (`serverInfo.version`).

## [0.29.0-beta] - 2026-08-20

Field lesson from the first remote deploy (OpenCode agent bringing a freshly
built exe to its own machine): the build succeeded in seconds, then the agent
spent ~20 calls hunting the exe, because `delphi_list` hid the build-output
folders it had every reason to look in. A stateless protocol means the agent
only knows what each result tells it - so results must leave it ready for the
next step, the same way a rejection offers the legitimate path.

### Changed
- **`delphi_list` filters IDE artifacts RELATIVE to the requested root.**
  Naming a build-output folder (`Compiled\Win32\Release`...) as `root` is
  explicit consent to see inside it: its files and subdirectories are now
  listed. Listings from above still hide build output, but the result now
  carries `hidden` (how many entries the artifact filter removed) and a
  `note` telling the agent how to see them - before, the folder simply
  answered empty while `delphi_fetch` served the same path, and the
  contradiction cost the field agent four minutes of blind guessing.
- **`delphi_build` declares the artifact it produced.** On success the result
  now carries `output` (the built .exe/.dll/.bpl, resolved from the .dproj's
  `DCC_ExeOutput`/`DCC_BplOutput` or the IDE default and verified ON DISK),
  `outputSize`, and an `outputNote` pointing at `delphi_package` +
  `delphi_fetch` for retrieval.
- **The tray host announces its version** in the startup log line, the window
  caption and the tray icon hint (before, no way to tell WHICH build was
  serving without calling `initialize`).

### Docs
- `docs/CLIENTS.md`: how to receive `delphi_fetch` chunks through OpenCode,
  whose client truncates oversized tool output to a local spool file - the
  spool IS the transport (one-line PowerShell decode included), plus the
  recommended `build` -> `package` -> `fetch` flow for binaries.

8 E2E batteries, **423 checks** (new: relative artifact filtering with
`hidden`+`note`, explicit root inside build output, `delphi_build`
`output`/`outputSize`/`outputNote`).

## [0.28.0-beta] - 2026-08-20

Field round 9, second pass. One confirmed data-loss bug (concurrency) fixed, and
the build hazard scanner narrowed so it stops rejecting legitimate projects - the
tester's "a false positive is as serious as a hole".

### Security
- **CONCURRENT vault writes lost data, silently.** A knowledge vault is shared by
  several remote agents, so two of them appending to the same note at once is
  normal - but the read -> backup -> write cycle of `vault_append`/`vault_patch`
  was not serialized. Both read the same base and the last save erased the
  other's addition, while BOTH callers got an "ANADIDO ... copia previa" success;
  and two backups of one note in the same second collided at the copy step. The
  whole cycle now runs under one process-wide lock (`vault_create` too), so every
  reported success is really on disk. The append and patch write paths were
  unified into a single locked helper so the fix lives in one place.
- **git `clone` now inserts `--` before the URL**, so the URL can never be parsed
  as an option whatever it contains (defence in depth over the existing
  leading-`-` check and the gate's dangerous-flag filter). User options still
  apply - they go before the `--`.

### Changed
- **The build hazard scanner no longer refuses an INERT custom `<Target>`.**
  Rejecting *every* `<Target>`/`<Exec>` was a false positive as serious as a
  hole: it broke real projects with a post-build copy or Authenticode signing.
  The scanner now refuses only tasks that **execute a program or plant/delete
  files** (`Exec`, `UsingTask`, inline `Code`, `Copy`/`Move`/`Delete`/`MakeDir`/
  `WriteLinesToFile`/`WriteCodeFragment`/`DownloadFile`, compilers...). A target
  that only prints a `<Message>` or sets a property now builds.
- **New opt-in `[Security] AllowBuildScripts` (env `DELPHI_MCP_ALLOW_BUILD_SCRIPTS`).**
  A *trusted* project that signs or copies at build time can be enabled WITHOUT
  turning on `delphi_run` (which `AllowRun` would). `AllowRun` still implies it.
  Untrusted uploads with no opt-in still hit the scanner. Both default to off.

8 E2E batteries, **416 checks** (new: R9 concurrency burst over HTTP; scanner
false-positive / opt-in cases).

## [0.27.0-beta] - 2026-08-20

Field round 9 (Fable), first findings - plus the vault bootstrap redesigned to
match how the same vault is read locally.

### Security
- **CRITICAL: the vault's governance files could be written through a trailing
  space.** `vault_append` with `"MEMORY.md "` reached the real file: Windows
  trims the space when opening, while the governance check compared the raw
  string and saw a different name. The check now decides on the **resolved**
  path, and the Windows name rule (segment ending in a dot or space, or
  carrying an ADS) is enforced by **one shared helper** - the same one the
  workspace jail uses, now covering every path segment rather than only the
  last. The same trick had defeated `delphi_textedit` in an earlier round; it
  is now a single rule in a single place instead of one per toolset.
- **`vault_patch` could empty a note** (`old_text` = the whole content,
  `new_text` = `""`). Deleting knowledge is not an operation this server
  offers, so a replacement that would leave the note blank is refused - the
  automatic backup is there for accidents, not as a licence.

### Changed
- **The vault bootstrap serves WHOLE FILES again.** Concatenating rules + index
  into one 85 KB result overflowed a client, and paging it by line meant
  reading documentation in fragments - which is not how the vault is read
  locally. Now each file arrives complete, and when the two do not fit
  together the second is fetched by name (`vault_read {path: "MEMORY.md"}`):
  the split happens between files, never inside one. Measured on a real vault:
  22 KB then 63 KB, two calls, both whole.

### Fixed
- Removed a duplicated implementation of the Low-integrity labelling helper in
  `Lsp.Sandbox` (the same function body under two names).

7 E2E batteries, **401 checks**.

## [0.26.2-beta] - 2026-08-20

### Changed
- **All build output now lands under `Compiled/`** (`Compiled/<Platform>/<Config>`
  for binaries, `Compiled/Dcu/...` for units) instead of scattering
  `Win32/`/`Win64/` folders through the source tree - the layout `delphi_config
  set-output` produces, now applied to this project itself. `Compiled/` added to
  `.gitignore` (binaries and `settings.ini` were already ignored by name).

### Fixed
- **`DELPHI_MCP_VAULT_READONLY` only overrode the ini when set to `0`.** Setting
  it to `1` fell through to `settings.ini`, so a writable vault could not be
  forced back to read-only from the environment. The variable now wins in both
  directions.
- The test batteries defaulted to the **Debug** executable, which sits next to
  the operator's production `settings.ini` and so inherited its jail and vault.
  They now default to the **Release** build, which carries no configuration -
  the convention that was already in use, now the default so the batteries run
  with no arguments.

7 E2E batteries, **390 checks**.

## [0.26.1-beta] - 2026-08-20

### Security
- **The knowledge vault now belongs to the `vault_*` tools alone, wherever it
  sits.** Putting a vault *inside* a workspace root used to expose it to the
  code tools: `delphi_edit` could rewrite a note behind the vault's back -
  skipping the automatic backup and the protection of the governance files -
  and `delphi_list` served the notes as if they were source. Any path inside
  the vault is now refused by the code tools with a message pointing at
  `vault_read`/`vault_append`, and the vault is skipped in the `delphi_list`,
  `delphi_search` and `delphi_projects` walks. The isolation no longer depends
  on where the operator happens to put the folder.

7 E2E batteries, **390 checks**.

## [0.26.0-beta] - 2026-08-20

Field round 8 (Fable): the vault passed its security review untouched, but the
round broke the compile-only guard again and found the bootstrap unusable.

### Security
- **CRITICAL: the build guard was evadable through a macro-based `<Import>`.**
  0.25.1 trusted any import written with an MSBuild macro, but
  `$(MSBuildProjectDirectory)\payload.targets` is *both* macro-based and
  resolves right next to the project - so uploading a `.targets` there and
  importing it ran its `<Exec>` at build time. Confirmed end to end.
  Imports are now **followed and scanned recursively** (depth-capped): only the
  IDE's own targets are trusted without being read, anything else must resolve
  to a readable file that passes the same scan, and what cannot be resolved is
  refused. `<Target>`/`<Exec>` are also matched with an XML namespace prefix
  (`<msb:Target>` slipped past a literal match; MSBuild happened to reject it,
  which is not a guarantee to rely on). A traversal now disqualifies an import
  outright - `$(BDS)\..\..\evil.targets` was macro-based and ended in
  `.targets`, and the previous whitelist trusted it.

### Fixed
- **The vault bootstrap did not fit in one answer.** `vault_read` with no path
  returned rules + index whole - 85 KB against a real vault, past a client's
  per-result cap, forcing it to spill to disk and read the result back in
  pieces. Reads are now **paged by line** with a per-result budget, and every
  truncated answer states the exact continuation offset
  (`Mostradas las lineas 1..271 de 379. Pide el resto con {offset: 272}`).
  Verified against the real vault: 40 KB first page, continuation works.
- **A rejected path came back rewritten.** Asking for `C:/Windows/win.ini` was
  refused with `"srvc:/Windows/win.ini"` - the outbound drive filter rewriting
  an echo of the caller's own text, confusing to debug. The rejection no longer
  echoes the path; it states the rule.

7 E2E batteries, **383 checks**.

## [0.25.1-beta] - 2026-08-20

### Security
- **Hardened the compile-only scan against evasions** (found while writing the
  next field-test brief, before it shipped). The 0.24.0 guard matched element
  names case-sensitively and let an `<Import>` name any relative file, so three
  routes remained: odd casing (`<prebuildevent>`), and — the real one — a
  *clean-looking* `.dproj` importing an evil `.targets` dropped beside it, which
  moved the payload one file away from the scan. The whole scan is now
  case-insensitive, and an `<Import>` is refused unless it is macro-based
  (`$(BDS)\...`, as every real project's imports are): no UNC, no absolute, no
  `..`, no bare relative file. Verified: 7 evasion variants refused, and an
  untouched project still builds.

## [0.25.0-beta] - 2026-08-19

### Added
- **Knowledge vault: persistent memory for agents (optional, off by default).**
  Point `[Vault] Path` at a folder of Markdown notes (an Obsidian vault) and the
  server exposes it, so an agent working remotely can consult accumulated
  knowledge — decisions, conventions, project context — and not just source
  code. Nothing registers unless configured.
  - `vault_read` — a note by relative path, with line numbers and
    `offset`/`limit`. **With no path it returns the vault's own rules
    (`AGENTS-VAULT.md`) plus its index (`MEMORY.md`)**: the bootstrap, because
    those filenames are a vault convention a remote agent should not have to
    know. Lazy loading is the protocol — the vault is never read in bulk.
  - `vault_search` — `target=files` (glob over note names) or `target=content`
    (regex inside notes → path, line number, line), optionally scoped to a
    `subfolder`.
  - **Writing (opt-in, `[Vault] ReadOnly=0`, read-write credential only):**
    `vault_append` (a dated log entry or progress line, optionally after a
    unique `anchor`), `vault_create` (new note, **never** overwrites) and
    `vault_patch` (replace a fragment that appears exactly once). There is
    deliberately no wholesale rewrite, no delete, no move and no git.
  - **The rules that can be enforced by code are enforced by the server:** the
    original of any modified note is copied to `backups/mcp/<timestamp>/` first
    (no parameter disables it); the governance files (`AGENTS-VAULT.md`,
    `AGENTS-VAULT-WRITE.md`, `MEMORY.md`) are never writable; a strict jail
    (relative paths only, no `..`, `.md` only, `backups/`/`.git/`/`.obsidian/`
    excluded); UTF-8 in and UTF-8 without BOM out; and notes over 100 000
    characters are truncated with a pointer to `offset`/`limit`.
  - The *doctrine* stays in the vault itself, not in the code — so two people
    can point this at two different vaults and each gets their own rules.
    See **docs/VAULT.md**, which also shows how to start a vault from scratch.

  - **Session wiring, so no agent has to be taught any of this:** when a vault
    is configured the MCP `initialize` response carries `instructions` (there
    is a vault, start with `vault_read` and no path — short on purpose, since
    instructions ride in every prompt), and a `vault` prompt is exposed, which
    clients surface as an invocable command (`/vault` in Claude Code) to reload
    rules + index mid-session. A vault can replace that text with its own by
    placing `VAULT-INSTRUCTIONS.md` at its root — its "skill".
  - **First run seeds itself:** point `[Vault] Path` at a folder that does not
    exist or holds no notes and the server creates a working starter vault
    there (rules, index, write guide, example project). A vault that already
    has notes is never touched. The same starter kit ships in
    `examples/vault/` — generic on purpose: the shape, not anyone's content.
  - The vault is an **independent jail**: it lives outside the workspace roots,
    the code tools cannot read it and the vault tools cannot serve code.
  - Vault text is exempt from drive-letter masking, like `delphi_read`: an
    agent copies fragments of a note verbatim to build the `anchor`/`old_text`
    of a later write, so the text must match the file on disk byte for byte.

7 E2E batteries, **371 checks** (the vault battery adds 83).

## [0.24.0-beta] - 2026-08-19

Field round 7 (Fable): the sandbox held again, but the round found the real
hole — the "compile-only, never execute" posture had a build-time escape.

### Security
- **CRITICAL: code execution via `delphi_upload` + `delphi_build`.** `delphi_upload`
  writes any path with no extension filter, so a `.dproj` could be planted whose
  MSBuild `<Target><Exec>` ran an arbitrary shell command on the next
  `delphi_build` — at normal integrity, defeating "this server only compiles".
  The narrow, documented pre/post-build vector turned out to be trivial to reach.
  Fixed at the point of execution: before running MSBuild, the project is scanned
  and a build that would **execute a shell** — a custom `<Target>`/`<Exec>`, a
  non-empty Pre/PostBuild/Link event, or an `<Import>` of a foreign (UNC or
  absolute non-macro) targets file — is **refused**, unless the operator opted
  into execution with `[Security] AllowRun=1` (the same switch that gates
  `delphi_run`). The scan holds however the `.dproj` arrived (upload, edit, or
  pre-existing). A stock RAD Studio project has none of these and builds normally.
- **HIGH: `delphi_upload` overwrote with no undo.** A fresh upload (offset 0)
  truncates the target; it was the only writer that could destroy a file with no
  backup (a 1-byte upload wiped a real `.dproj` in testing). Upload now copies
  the existing file to the recoverable trash (`__delphi-patch`) before truncating.

6 E2E batteries, **280 checks** (adds the upload+build exploit, now blocked, and
the upload backup).

## [0.23.0-beta] - 2026-08-19

Field round 6 (Fable): the filesystem sandbox held against every attack; the
three findings left are behaviour/UX papercuts, none a security hole.

### Fixed
- **R6-A: `delphi_config view` reported the wrong enabled/disabled per platform.**
  The `.dproj` platform list was parsed with a separate attribute list (`value`)
  and value list (inner text); the file's `<Platform Condition="…">Win64</Platform>`
  selector — inner text but no `value` — shifted the value list by one, so every
  platform's `enabled` flag was mislabelled. Each `<Platform value="X">V</Platform>`
  is now parsed as a unit, so name and enabled always come from the same element.
- **R6-C: a low-integrity `delphi_run` could not overwrite a pre-existing file**
  in its own working folder (a log/csv/ini created earlier at Medium integrity)
  — an unexplained "Acceso denegado". The inherited Low label only reached new
  children; existing entries are now relabelled too, so the confined run can
  update its own outputs and nothing else. (Only reachable with `AllowRun=1`.)

### Added
- **R6-B: `delphi_list includeTrash=true`** surfaces the recoverable trash
  (`__delphi-patch`, where `delphi_delete` moves files) so a deleted file can be
  found and restored with `delphi_move`. Hidden by default, as before.

6 E2E batteries, **276 checks**.

## [0.22.0-beta] - 2026-08-19

### Added
- **`delphi_config set-output`: put every binary under one folder.** A curated
  edit of the `.dproj` (same pipeline as `add-platform`: shared `Lsp.Dproj`
  read, encoding-preserving write, automatic `__delphi-patch` backup) that sets
  `DCC_ExeOutput` to `.\<folder>\$(Platform)\$(Config)` and `DCC_DcuOutput` to
  `.\<folder>\Dcu\$(Platform)\$(Config)` — the common RAD Studio convention,
  keeping the per-platform/config subfolders so Win32 and Win64 never collide.
  Default folder `Compiled`; `output=default` restores the stock layout. The
  folder name is validated (simple relative token only — no XML metacharacters,
  no absolute path, no `..`), so it cannot inject into the project the way the
  0.19.0 platform name could. A write op: refused for read-only credentials.
  Verified end-to-end: after `set-output Compiled`, a real build lands its
  `.exe` in `Compiled\Win64\Debug\`. 6 batteries, **271 checks**.

## [0.21.0-beta] - 2026-08-19

This release settles the server's posture: it is a **pure development/compile
server**. It compiles; it does not execute. Testing a binary belongs on the
client's own machine (or a real target device), not on the build box.

### Changed
- **`delphi_run` is now OFF by default.** Executing a compiled program on the
  build server is both pointless (nobody sees the process there) and the main
  way a runaway agent could do damage, so it is refused for **every**
  credential — read-write tokens included — enforced in the single entry gate.
  The rejection points the agent at the intended path instead: download the
  artifact (`delphi_package` + `delphi_fetch`) and run it on your machine, or
  deploy to a real target (PAServer on Linux/macOS, or Android) where it runs
  on the client, not the server. An operator who genuinely needs server-side
  execution (e.g. a console test runner in CI) can opt in with `[Security]
  AllowRun=1` (env `DELPHI_MCP_ALLOW_RUN=1`); the low-integrity sandbox and Job
  Object still apply in that case.

### Added
- **Startup log now announces the workspace jail (roots).** The single most
  important operational fact — what the agents can and cannot touch on disk —
  was absent from the banner. It now prints `Workspace jail (roots, N): …`, or
  a warning when there is no jail (unrestricted) or the roots are invalid
  (fail-closed). Same summary in the console and tray hosts.
- **`docs/AGENT.md`** — a model-facing guide (prefer semantic tools over text
  search, virtual paths, 0-based positions, safe editing, recoverable trash)
  to paste into an agent's `CLAUDE.md` / `AGENTS.md`.

6 E2E batteries, **264 checks** (adds a check that `delphi_run` is refused by
default). See below for the 0.20.0 sandbox this builds on.

## [0.20.0-beta] - 2026-08-19

### Security
- **Real filesystem sandbox for `delphi_run` (closes the B0b write vector).**
  A program launched by `delphi_run` now runs at **Low integrity** (Windows
  Mandatory Integrity Control), so it **cannot write** to any object at the
  normal (Medium) integrity level — the user profile, other projects,
  `C:\Windows`, anywhere on the system. Its own working directory is labelled
  Low so it can still write its output there, and there only. Reads are
  unaffected (read-down is allowed) and stdout is still captured. The response
  states `sandbox=low-integrity`; if the OS ever refuses the confined launch
  it says `sandbox=NO` instead of pretending. Verified: a compiled program
  that tries to write to `C:\Users\Public` is blocked while its local write
  succeeds. This plus the 0.17.0 Job Object (lifetime/resources) sandboxes
  run along both axes.
  *Scope: `delphi_run` only. `delphi_build` still runs the trusted toolchain
  at normal integrity (it must write .dcu/.exe and read the SDK/registry); a
  malicious `.dproj` pre/post-build step remains a narrower, documented
  vector.*

## [0.19.0-beta] - 2026-08-19

Field round 5 (Fable): one critical injection and two recovery gaps.

### Security
- **R5-B (critical): XML injection through `delphi_config add-platform`.** The
  platform name was interpolated raw into `<Platform value="…">` in the
  `.dproj`, with no validation or escaping. A crafted name closed the tag and
  injected a live `<Import Project="\\attacker\share\x.targets"/>` — which
  MSBuild would execute on the next `delphi_build` (build-time RCE). The name
  is now validated against the canonical platform whitelist (Win32, Win64,
  Win64x, WinARM64EC, OSX64, OSXARM64, Linux64, Android(64), iOS…); anything
  else is refused, so no metacharacter can reach the file. It really is a
  curated edit now.

### Added
- **`delphi_config remove-platform`**: the reversible inverse of
  add-platform (disables a platform), backing the `.dproj` up first — the
  symmetry that was missing for recovery.

### Fixed
- **R5-A: the trash was unrecoverable by the route its own message named.**
  `delphi_delete` said "recover with `delphi_move` from that path", but
  `delphi_move` refused any path under the trash. Restoring an item OUT of the
  trash is now allowed (moving the trash folder itself, or moving items INTO
  it by hand, stays refused), and the delete message spells out the exact
  call.
- **R5-C: `.dproj` edits now leave a backup.** `add-platform`/`remove-platform`
  write through the same backup-first path as `delphi_edit`, so a bad edit is
  recoverable from `__delphi-patch\`.

## [0.18.0-beta] - 2026-08-19

Four issues from an external code review, all fixed and regression-tested.

### Security
- **No-credential server binds to localhost only.** With NO token and no
  `AnonymousReadOnly`, the HTTP host would listen on every interface — an
  unconfigured server silently open to the network. It now binds `127.0.0.1`
  only in that case; remote access requires a token (or an explicit
  `AnonymousReadOnly=1`).
- **More git options refused at the gate.** `--config` is `-c`'s long form on
  `clone` and slipped through (`git clone --config core.sshCommand=… ` →
  RCE); also `--separate-git-dir`, `--template`, `--git-dir` and `--work-tree`
  redirect where git writes/reads and could escape the jail. All now refused
  alongside the existing `-c`/`--output`/`--no-index` set.

### Fixed
- **Build/run no longer hangs on a silent process.** The output pipe was
  drained with a blocking `ReadFile`, so a child that produced no output
  blocked forever and the timeout never fired. It now polls with
  `PeekNamedPipe`, honouring the deadline even on a silent hang (verified: a
  mute 60 s process with a 3 s timeout returns in ~3 s).
- **The tray app now registers all 27 tools.** Five units added in 0.15–0.16
  (`delphi_config`, `delphi_paserver`, `delphi_delete`, `delphi_move`,
  `delphi_report`) were linked into the console host but not the tray, so the
  tray silently exposed fewer tools. Both host unit-lists are now kept in
  sync (with a comment on each to keep it that way).

### Docs
- README no longer claims a Windows Service, LRU eviction or idle-shutdown as
  shipped — they are marked roadmap. What runs today (console + tray, warm
  DelphiLSP per workspace) is described as it is.

## [0.17.0-beta] - 2026-08-19

### Security
- **Build/run processes are confined in a Windows Job Object** (B0b): the
  whole spawned tree (cmd → msbuild → dcc, or a launched exe) is now
  **killed on job close**, so a timeout or the server shutting down never
  leaves orphaned compiler/child processes behind; a process-count cap guards
  against fork bombs and a per-process memory cap against runaways; UI
  restrictions block the tree from exiting Windows or changing system
  settings. Applied at the single process-launch point, so it covers build,
  run and git. **Honest scope**: this bounds process lifetime and resources,
  not filesystem access — a compiled program can still write where the
  service account can. Full per-directory confinement (AppContainer / a
  restricted token) remains future work; the workspace jail plus this Job
  Object bound the damage.

## [0.16.0-beta] - 2026-08-19

### Added
- **`delphi_delete` (tool 26)**: remove a file or folder inside the workspace
  — NOT a hard delete: the target is moved to a recoverable trash
  (`__delphi-patch\<date>\deleted\` next to it), so a mistake can be undone.
  Refuses to delete the trash folder itself. Jailed, read-write only. Cleans
  up stray files and build leftovers.
- **`delphi_move` (tool 27)**: move or rename a file/folder inside the
  workspace; the source is copied to the trash first, destination parents are
  created, an existing destination is never overwritten. Jailed, read-write.
- **`[Server] BindIP`** (env `DELPHI_MCP_BIND_IP`): bind the HTTP listener to
  one interface (e.g. a LAN/VPN address) instead of all interfaces — which
  also removes the duplicate IPv4+IPv6 firewall prompt.

## [0.15.0-beta] - 2026-08-19

Cross-platform groundwork: see and manage a project's build configurations,
and discover the Platform Assistant so an agent can target Linux/macOS.

### Added
- **`delphi_config` (tool 24)**: see and manage a project's build
  configurations and target platforms. `view` (read-only) reports the
  framework, the configurations (Debug/Release/custom) and every platform
  with whether it is enabled, whether the project **can** target it, and
  whether it needs a remote profile. `add-platform` (read-write) enables a
  platform in the `.dproj` — a **curated** edit of the `<Platforms>` block
  only. It refuses a platform the framework cannot target: **VCL is Windows
  only** (`Vcl.Forms` does not exist on Linux/macOS/mobile); FMX and console
  cross platforms.
- **`delphi_paserver` (tool 25, read-only)**: the bridge for building on
  other platforms via the Platform Assistant. `platforms` lists what this
  server can target and each platform's profile/SDK status; `packages` lists
  the PAServer installers that ship with each Delphi install (download with
  `delphi_fetch`, run on the Linux/Mac target); `profiles` lists the
  registered connection profiles and SDKs. The write/network half (create a
  profile against the target, deploy+run remotely) builds on this once a live
  PAServer target exists.
- **`Lsp.Dproj`**: the single tolerant `.dproj` parser, now shared by the LSP
  config fabricator and these tools — no second parser (house rule).
- `delphi_build` accepts any declared platform, not just Win32/Win64.

## [0.14.0-beta] - 2026-08-19

The library read zone finally covers what it always promised, plus the
fourth field round's findings.

### Fixed
- **The read zone was missing most of the machine's Delphi material**, a gap
  in a feature shipped back in 0.6.0:
  - it walked only `Win32`/`Win64`, while an install registers a Library
    Search Path for **every** platform (13 here: Linux64, OSX64, OSXARM64,
    Android ×2, iOS ×4, Win64x, WinARM64EC…);
  - it expanded a hardcoded handful of macros, so every entry using
    `$(BDSCatalogRepository…)` was silently dropped — i.e. **every GetIt
    package** (FmxLinux, LockBox…) and the Android SDKs.
  Macros are now expanded against the IDE's own authoritative table
  (`HKCU\…\BDS\<ver>\Environment Variables`), all registered platforms are
  walked, the catalog repositories are included whole (the search path points
  at compiled `Lib\`, while the useful material is the sibling `source\`),
  and it is done **per installation** — each Delphi owns its packages.
- **`delphi_list` aborted entirely on one unreadable subdirectory**
  (`TDirectory.GetFiles` recursive is all-or-nothing) and again when asking
  size/date of a file whose path exceeds the classic length limit. Measured
  on the Android NDK, which killed a whole listing; it now walks tolerantly
  and lists 19,436 files there.
- **R4-A**: `delphi_fetch` returned the server's real path. The byte-fidelity
  exemption was wrong for it: its payload is base64, an alphabet with neither
  `:` nor `%`, so masking cannot corrupt it. Only `delphi_read` stays exempt
  (its payload is file text an edit anchor must match).
- **R4-C**: `delphi_list` echoed `..\` segments back in every returned path;
  the root is canonicalized first.
- Paths whose last segment is `.` or `..` are no longer refused as
  "name ending in a dot": they are ordinary navigation, and the jail already
  canonicalizes before deciding (escape attempts through `..` remain caught —
  verified in the field round).

### Added
- **R4-B**: `delphi_workspace` publishes `readableExtra` — the read-only
  library zone (installations, library paths, catalog repositories), so the
  agent knows what it may read besides the roots instead of being told
  "anything outside is refused".

## [0.13.0-beta] - 2026-08-19

Read-only becomes airtight, a feedback channel for the agents that use the
server, and the third field round's findings.

### Added
- **`delphi_report` (tool 23)**: agents report bugs, limitations or
  suggestions **directly to the server**, which stores each one as its own
  timestamped markdown file (version, date, kind, origin, message) in a
  `reports/` folder next to the executable — a history that can be read and
  worked through later. Deliberately **available at every access level,
  read-only included**: the restricted agents are the ones most likely to hit
  a wall. Safe by construction — the client never supplies a path: the folder
  is fixed and the file name is generated server-side.
- **`Lsp.Texts`**: every model-facing text (tool/parameter descriptions,
  rejections, notices) and the version string now live in ONE unit. These
  texts are the server's real user interface; scattered they drift and
  contradict each other. Pure ASCII by convention — the encoding rule that
  produced the mojibake bug is now a property of the file.

### Security
- **Read-only is now airtight** (found by an internal audit that ran the
  server anonymously and tried to escape):
  - `delphi_git diff|show --output=<path>` let ANY client — including
    anonymous/read-only — write files anywhere on disk, **outside the
    workspace roots included** (an absolute `--output` ignores `-C <repo>`).
    Dangerous git options (`--output`, `--no-index`, `--exec`,
    `--upload-pack`, `--receive-pack`, `--ext-diff`, `--textconv`,
    `--config-env`, `-c`, `-o`) are now refused **at the single gate**, so the
    rule applies to every git call at BOTH access levels.
  - `delphi_git tag` with a `message` (annotated tag = a write) passed the
    read-only gate when `args` was empty: the gate only looked at `args`.
- Verified in the same audit and left unchanged (they were already correct):
  401 for a missing token when one is configured, and the per-request
  read-only flag being re-set on every request (no leakage between pooled
  Indy threads).

### Fixed
- **C1-bis**: `insert:"metodo"` with `visibility:"published"` placed the
  declaration right after the class header — i.e. BEFORE the component
  fields, which is E2169 ("field definition not allowed after methods").
  It now lands after the last member of the implicit published section.
- **B5** (root cause found by measuring the live JSON): `definition` answers a
  bare Location **object**, not an array, so the chaining added in 0.12.0
  never triggered and `kind=declaration` still returned the enclosing scope.
  The parser now accepts object/array/LocationLink and aims the second lookup
  at the routine's identifier column.
- **R3-1**: LSP tools leaked the real drive in their URIs
  (`file:///D%3A/...`) because the percent-encoded colon dodged the mask.
  Virtual drive units now cover that form too.
- `delphi_git log` regression test no longer asserts on a specific old commit
  message (it scrolled out of the 20-line window).

## [0.12.0-beta] - 2026-08-19

Virtual drive units — server paths stop looking like the client's own disks —
plus every finding from the second field round (the "Agenda" end-to-end run:
2 projects, 7 commits, 16/16 tests, ~86 MCP calls).

### Added
- **Virtual drive units (`srvd:`, `srvc:`, ...)**: the server's real drive
  letters never travel to the client. One generic prefix rule at the single
  dispatch gate handles both directions — arguments are expanded on the way
  in (`srvd:\x` → `D:\x`; real paths still accepted), and every textual
  result is masked on the way out, INCLUDING compiler/git/LSP output and 8.3
  short forms (`D:\PROYEC~1`). Byte-fidelity exemption: successful
  `delphi_read`/`delphi_fetch` content travels verbatim (an edit anchor
  built from masked text would not match the disk); their rejections are
  masked like everything else. Measured origin: remote agents mistaking
  server paths for their own local disks.
- **`delphi_edit delete:true`**: removes the anchored line ENTIRELY
  (`new:""` only blanks it — and now says so: `BLANQUEADA la linea N ...
  para eliminarla del todo usa delete:true`).
- **IDE settings read at runtime** (`IdeConfigValue`, generic HKCU reader —
  the building block for future Android/macOS/SDK configuration): new
  units/forms/projects are created with the encoding the IDE is configured
  to use (`Editor\DefaultFileFilter`: UTF-8 → utf8-bom, ANSI → cp1252), and
  BOM-less pure-ASCII files get their first accents written in that same
  standard.

### Fixed
- **B3 (blocker): `insert:"rutina-global"` in a `.dpr`** placed the routine
  before `end.` — legal in a unit, E2070 + 2×E2029 in a program. In a `.dpr`
  the routine now lands between the `uses` clause and the main `begin`;
  `insert:"metodo"` on a `.dpr` is refused with guidance.
- **C1: `insert:"metodo"` with `visibility:"published"`** now works on form
  classes with no explicit section keyword: the declaration lands in the
  implicit published section right after the class header — the event
  handler case, the most common VCL edit.
- **B1: `delphi_git commit`/`tag` messages** now reach git via `-F <file>`
  (byte-exact): embedding them in the command line turned every `"` into
  `''`.
- **B5: `delphi_definition kind=declaration` on a call site** returned the
  declaration of the ENCLOSING method; the tool now chains
  definition→declaration at the target's own position, so it answers the
  callee.
- **B2: `acentos=` counted the UTF-8 BOM** as 3 phantom high bytes.
- **B4: mojibake in `delphi_create form-vcl` response messages**: a handful
  of message literals carried non-ASCII bytes that the compiler mangles when
  the IDE's default encoding disagrees with the file; all server messages
  are now pure ASCII by construction.
- Scaffolded `.gitignore` no longer carries a UTF-8 BOM (git does not strip
  it, which silently broke the first ignore rule).

### Security
- **`[Workspace] Roots` parsing fails CLOSED**: quotes around a root are
  tolerated and stripped (paths with spaces need no quoting — the separator
  is `;`), and if Roots is configured but NO root parses valid, every path
  is refused instead of silently running unrestricted.

## [0.11.0-beta] - 2026-08-19

The transfer batch, plus the addendum findings from the replication run.
Bringing a repository in no longer means recreating it file by file.

### Added
- **`delphi_git clone` / `pull` / `fetch`**: a whole repository onto the
  server in ONE call, jailed to the workspace roots (URL in `message`,
  destination in `repo`; only http/https/git/ssh URLs; refuses to clone
  over an existing repo). Measured: the full public repo cloned in 1.2 s
  versus ~200 MCP calls to recreate it.
- **`delphi_upload` (tool 22)**: the mirror of `delphi_fetch` — chunked
  base64 upload with whole-file SHA-256 verification, for material that
  cannot be recreated by editing (`.res`, icons, binary designer files).
  Jailed, creates parent directories, refuses out-of-order offsets.
- **Create-with-content**: `delphi_edit createunit` accepts `content` (the
  whole unit in one call instead of create + N anchored patches — the
  measured friction #1: 6 calls per file down to 1), both it and
  `delphi_textedit` accept `eol` (`crlf` default / `lf`), because the JSON
  channel usually delivers LF-only text.

### Security
- **Windows name-normalization bypass closed** (found in the field): a path
  ending in a dot or space ("X.pas.") passes any literal extension check
  while Windows creates "X.pas" — it defeated the `.pas` guard of
  `delphi_textedit`. Alternate Data Streams ("X.pas::$DATA") did the same.
  Both are now refused at the single write gate, so the fix covers EVERY
  writing tool, not just the one where it was found.
- `delphi_upload` validates the base64 alphabet itself: Delphi's decoder
  skips invalid characters instead of failing, which would have written a
  silently corrupt file.

### Fixed
- `delphi_textedit` create reported `encoding=utf8` for pure-ASCII content
  that a later `delphi_read` detects as cp1252; it now says what detection
  will say.

## [0.10.0-beta] - 2026-08-19

More field-test findings from the full-repo replication run. Two were real
bugs (one an outright blocker), one a new tool, one a security hardening.

### Fixed
- **Dotted unit names** (blocker): `delphi_edit createunit` and scaffolded
  form units rejected names like `Lsp.BuildRunner` — the tool could not
  create the very units of the project it is part of. Namespaced names
  (`Ident(.Ident)*`) are now accepted.
- **Access Violation on `delphi_edit` with `new=""`**: blanking a line
  crashed the handler (indexing an empty split). Empty replacement now
  blanks the line cleanly.

### Added
- **`delphi_workspace` (tool 21)**: the server's lay of the land — the
  configured workspace roots (made explicit so a remote agent never
  confuses SERVER paths with its own local disk), the access level
  (read-write / read-only) and the active Delphi. Read-only; call it first.

### Security
- Every `delphi_run` (arbitrary execution by design) and `delphi_build`
  (can run pre/post-build steps from the .dproj) now writes an audit line
  to the log — for run, the executed binary's SHA-256. (Build and run
  remain refused under a read-only credential.) OS-level sandboxing of the
  spawned process is tracked as future work.

## [0.9.1-beta] - 2026-08-19

### Fixed
- **Mojibake in delphi_git output** (second field-test round): git emits
  UTF-8 but captured console output was decoded as ANSI ("AÃ±ade" for
  "Añade"). The capture now runs a strict UTF-8 scan over the bytes:
  well-formed UTF-8 with high bytes decodes as UTF-8, everything else keeps
  the ANSI fallback (compilers and console programs emit ANSI/OEM). Applies
  to delphi_git, delphi_run and delphi_build alike. 142 checks.

## [0.9.0-beta] - 2026-08-19

Everything in this release comes from the first real remote field test: a
Claude Desktop agent on another machine drove the full cycle over HTTP and
its report exposed four issues. All four are fixed and test-locked.

### Fixed
- **Stale LSP buffer** (the big one): the language server saw each file as
  it was when first opened; edits made afterwards (delphi_edit, scaffolding,
  external editors) were invisible to completion/signature/definition. Now
  every acquire compares a disk fingerprint (mtime+size) and refreshes the
  buffer via didChange - the LSP always answers about the CURRENT source.
- **BOM false positive in the delphi_edit audit**: on UTF-8+BOM files the
  high-byte accounting smuggled 3 phantom bytes (the BOM) into the "leaving"
  side, producing "ACENTOS FUERA DE CUADRO: esperaba 0 y hay 3" on perfectly
  healthy writes (and scaring agents into restoring). Text fragments are now
  encoded BOM-less for accounting.

### Changed
- **delphi_git `message`**: normal punctuation is welcome (the message never
  goes through a shell - git is spawned with a direct command line); only
  line breaks are refused. Shell-metacharacter screening stays on `args`.
- **delphi_git `config`** added to the whitelist, restricted to `user.name`
  / `user.email` (value in `message`), so a remote agent can commit on a
  fresh repo/machine. Refused in read-only mode like every write.
- **delphi_create** ships a basic `.gitignore` with every new project
  (build artifacts, tool backups, `.delphilsp.json`); the agent may edit it
  later with delphi_textedit.

### Tests
- 141 checks across the 5 batteries (stale-buffer refresh, BOM accounting
  on utf8-bom, git config identity + free punctuation, scaffold .gitignore).

## [0.8.0-beta] - 2026-08-19

Closes the gap found by the full capability inventory of DelphiLSP 37.0
(docs/DELPHILSP-NOTES.md): the engine announced signatureHelp and
declaration/implementation providers that no tool exposed.

### Added
- **`delphi_signature` (tool 20)**: signature help for the call under a
  position — routine signatures with parameter names/types, the IDE's
  Ctrl+Shift+Space. Position must be inside the call parentheses.
- **`delphi_definition` `kind` parameter**: `definition` (default) = the
  body in the implementation section; `declaration` = the interface
  declaration — the two halves of a Delphi unit. (`implementation` is
  accepted but the engine answers it like declaration — measured.)

### Docs
- DELPHILSP-NOTES: measured navigation semantics (definition=body,
  declaration=interface, implementation≡declaration), LSIF conditions and
  kill-switch, `$Y` requirement, DelphiLSPLog registry logging.

## [0.7.0-beta] - 2026-08-19

### Added
- **`delphi_installs` (tool 19)**: list every RAD Studio/Delphi installation
  discovered on the machine (side-by-side versions are common), with root
  directory, DelphiLSP/msbuild availability, and which one is ACTIVE for the
  LSP engine (the newest shipping DelphiLSP.exe). Installs without DelphiLSP
  are listed too: they still build via msbuild.

### Fixed
- **No composed branding paths**: `$(BDSUSERDIR)`/`$(BDSCOMMONDIR)` are now
  resolved from the authoritative `rsvars.bat` written by the installer
  (Embarcadero renames its Documents folder between eras — e.g. "RAD
  Studio" vs "Embarcadero\Studio"), never composed by hand. Entries that
  cannot be resolved are dropped instead of guessed.

## [0.6.0-beta] - 2026-08-19

Born from a dogfooding audit: "could this MCP have built its own project?"
The Delphi cycle could; docs, tests and release engineering could not. Now
they can.

### Added
- **`delphi_textedit` (tool 18)**: safe editing of plain-text NON-Delphi
  files (.md .html .js .css .sql .py .bat .ini .json ... any plain text,
  denylist not whitelist) with the same discipline as `delphi_edit` —
  one-full-line unique anchor with hints and atline tie-break, encoding and
  EOL preserved, automatic backup, atomic write, no whole-file rewrites —
  plus a CREATE mode that never overwrites. Delphi sources/designers/.dproj
  and binaries are refused.
- **`delphi_git`: `init`, `push`, `tag`** added to the whitelist (push uses
  the credentials/remotes stored on the server — consistent with the
  centralized model; tag is annotated when "message" is given). In read-only
  mode `tag`/`branch` without arguments (pure listing) pass; everything else
  that writes stays refused.
- **Library read zone**: with a jail configured, READING tools (read /
  search / list / fetch / LSP navigation) also accept the RAD Studio
  installation and the IDE Library Search Path directories, so agents can
  follow definitions into RTL/VCL sources and read installed components'
  code. Writing tools can never touch that zone.
- **Config Fabricator**: merges the IDE's global Library Search Path
  (registry) into fabricated settings, so symbols of installed third-party
  components resolve without the project repeating their paths.

### Tests
- 124 checks across the same five batteries (textedit lifecycle including
  .html, git init/tag/push against a throwaway repo, library-zone
  read-vs-write, read-only classification of the new tools).

## [0.5.0-beta] - 2026-08-19

### Added
- **Read-only access level**, enforced at a single gate in front of every
  `tools/call`: `[Security] ReadOnlyToken` (second Bearer credential),
  `AnonymousReadOnly=1` (tokenless requests get read-only), and a
  `--readonly` flag (whole process read-only, any transport). Read-only
  clients can read, search, navigate symbols, get diagnostics, download and
  run query git commands; `delphi_edit`, `delphi_create`, `delphi_build`,
  `delphi_run`, `delphi_package` and git write commands are refused. Made
  for reviewer agents (e.g. a wiki agent cross-checking the sources).
- `settings.example.ini` configuration template.

### Changed
- Documented that the HTTP listen port is configurable via
  `settings.ini [Server] Port` (default 3000; `--http <port>` overrides),
  and locked the behavior with a test.
- Token/credential reading centralized in one unit (was duplicated in the
  console and tray hosts).

## [0.4.0-beta] - 2026-08-19

The project is now explicitly labeled **beta**: functional and test-covered,
but young — expect rough edges and breaking changes between minor versions.

### Added
- `delphi_package` (tool 17): zip a build-output directory on the server
  into a single deploy artifact (recursive, `.dcu` intermediates excluded),
  ready to download with one `delphi_fetch`. The standard route to run GUI
  apps on the client machine: `delphi_build` → `delphi_package` →
  `delphi_fetch`.

## [0.3.0] - 2026-08-19

First complete release: total control of Delphi and its projects from a
remote machine. Built and validated in a single day against DelphiLSP 37.0
(RAD Studio 13 "Florence").

### Added
- **16 MCP tools**: `delphi_symbols`, `delphi_definition`, `delphi_hover`,
  `delphi_completion` (official DelphiLSP engine); `delphi_diagnostics`
  (Error Insight on demand, no build); `delphi_references` (hybrid text scan
  + compiler validation, homonyms rejected); `delphi_read` / `delphi_edit`
  (safe editing: one-line anchors, byte-exact encoding preservation, atomic
  writes, backups + 2-step restore, semantic INSERT, TPF0 hard-reject);
  `delphi_create` (scaffold console/VCL/FMX projects and VCL/FMX forms,
  buildable immediately); `delphi_build` (real MSBuild); `delphi_run`
  (jailed execution with output capture); `delphi_fetch` (chunked artifact
  download with SHA-256); `delphi_search`, `delphi_list` (files and
  explorer-style dirs), `delphi_projects` (locator), `delphi_git`
  (whitelisted operations).
- **Three hosts**: stdio (local MCP clients), console `--http [port]`
  (Streamable HTTP), and `DelphiLspMcpTray` (starts minimized to tray).
- **Security**: Bearer token auth (`[Security] AuthToken` /
  `DELPHI_MCP_TOKEN`) and workspace jail (`[Workspace] Roots` /
  `DELPHI_MCP_ROOTS`) enforced on every disk-touching tool, with
  canonicalized paths (no `..\` escapes, no prefix cousins).
- **Config Fabricator**: project settings generated from the `.dproj` when
  no fresh `.delphilsp.json` exists (stale ones detected and ignored);
  RAD Studio located via the Windows registry (11/12/13+, no hardcoded paths).
- **Tests**: five end-to-end batteries speaking real MCP over stdio/HTTP,
  86 checks total, including byte-level encoding verification and building
  freshly scaffolded projects for real.

### Notes
- Requires a licensed RAD Studio / Delphi 11+ installation on the server
  machine (`DelphiLSP.exe` is not redistributed).
- MCP plumbing vendored from gdksoftware/delphi-mcp-server (MIT) with two
  documented local changes (see `vendor/gdk-mcp-server/VENDOR.md`).
