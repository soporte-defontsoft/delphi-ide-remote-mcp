# Running and configuring the server

How to run `DelphiLspMcp.exe` (as a service, in a terminal or as a tray app), the account the
service needs, several Delphi versions on one machine, and every section and key of
`settings.ini`. The first five steps are in [QUICKSTART.md](../QUICKSTART.md); what the server is
and what each tool does, in the [README](../README.md) and [TOOLS.md](TOOLS.md).
## One executable, three ways to run it

| You want | Run | Notes |
|---|---|---|
| A local client to spawn it | `DelphiLspMcp.exe` | No switch: MCP over stdio. |
| The remote server, in a terminal | `DelphiLspMcp.exe --http 3000` | Ctrl+C stops it. Good for trying things out. |
| The remote server, permanently | `DelphiLspMcp.exe -install` | **How you should actually deploy it**: a Windows Service. Needs an elevated prompt; `-uninstall` removes it. It must then be told to **log on as the user who installed and uses RAD Studio** — see right below, this one is not optional. |
| An eye on it while you work | `DelphiLspMcp.exe -gui` | Tray app: starts iconized, double-click for the live log. The exe is a console program, so Windows flashes its console window for a moment when it starts (20-30 ms, measured 2026-09-30); a shortcut to `conhost.exe --headless DelphiLspMcp.exe -gui` starts it with no window at all. |

Each switch is accepted as `/x`, `-x` or `--x`. The service reads the same `settings.ini` next to the executable as every other mode — including its port, so the service and the tray cannot both run: it is one or the other.

### The service must log on as the user who owns the IDE

Not `LocalSystem`, and not a freshly created administrator either. RAD Studio keeps its configuration under **`HKEY_CURRENT_USER`**: the Library Search Path, the registered design packages, the platform SDKs, the PAServer profiles, the `$(BDS)` macro table. That is per user, by Embarcadero's design, and there is no way around it — even if this server read someone else's hive, the `msbuild` and `DelphiLSP.exe` processes it spawns are its children and would read their own.

Measured 2026-09-20 on one machine, same binary, only the service account changing:

| The service logs on as | Library roots it sees | Registered design packages |
|---|---|---|
| `LocalSystem` | 1 | 0 |
| a brand-new admin account | 2 | 0 |
| **the IDE's own user** | **11** | **all of them** |

What makes this worth a table is that the failure is *quiet*. The server starts, answers, reports `activeDelphi: 37.0` — the installation itself lives in `HKEY_LOCAL_MACHINE`, so it is found — and compiles anything that needs only the RTL. It breaks the first time a project uses an installed component, with `F2613 unit not found` and nothing anywhere pointing at the real cause.

So after `-install`: `services.msc` → the service → **Log On** → *This account*, and give it the IDE's user. Do it there rather than with `sc config`: that dialog also grants the account the "Log on as a service" right, and the password never travels on a command line. The SCM stores it, so changing that Windows password later stops the service from starting until you re-enter it.

### Letting an agent restart it by itself

Starting and stopping a service normally needs elevation, which an agent does not have. Grant one account start/stop rights on this one service, once, from an elevated prompt:

```
sc.exe sdshow DelphiLspMcp
sc.exe sdset  DelphiLspMcp "<what sdshow printed>(A;;CCLCSWRPWPDTLOCRRC;;;<your SID>)"
```

`whoami /user` gives the SID. After that `sc.exe stop` and `sc.exe start` work unelevated, so an agent can deploy a new build and bring the server back without anyone at the keyboard. It is a permission on one service, not a general privilege. One detail for a deploy script: `sc.exe query` reports STOPPED before the process has exited and released the exe - wait for the `DelphiLspMcp` process to be gone, not for the SCM state, before copying. (Up to 1.7.10 that gap was 30 s: the process never left by itself and the system ended it; since 1.7.11 it leaves as soon as it has stopped.)

And set the start type, or a reboot leaves you with no server:

```
sc.exe config DelphiLspMcp start= auto
```

Per-client configuration snippets (Claude Code, Claude Desktop, OpenCode, custom agents): see [docs/CLIENTS.md](CLIENTS.md).

**Getting the best out of the server from an AI agent** — the manual is [skills/SKILL.md](../skills/SKILL.md); [docs/AGENT.md](AGENT.md) is a short pointer to it.

## One server, one Delphi - several versions on one machine

A server works with **one** RAD Studio installation and nothing else: the build
(rsvars/msbuild), the DelphiLSP engine, the installed components, the designer tables, the
PAServer profiles and SDKs, `paclient`, `adb` and the readable library zone all come from it,
and no tool reaches into another installation. **Without its Delphi the server does not
start** - it is a Delphi MCP server.

**Which one**, at every start:

1. `[Server] DelphiVersion` in its `settings.ini` says it - and nothing else does.
2. The key is there and that version is installed (with DelphiLSP): that is the server's Delphi.
3. The key is there but that version is not installed (a typo, a Delphi uninstalled since): the
   server **does not start**. It says why and which keys would work on this machine - in its
   log, with exit code 1 in a terminal, in the Windows event log as a service, on the tray's
   icon - and it never falls back to another version.
4. There is no key: the server takes the newest installation that ships DelphiLSP and **writes
   it into its `settings.ini`** (`DelphiVersion=37.0`, one new line under `[Server]`; nothing
   else in the file changes, accents and line endings included). From then on the key rules:
   installing a newer RAD Studio later does not switch the server by itself, editing the key
   does. With no `settings.ini` at all (a client launching the exe over stdio) it is the newest,
   and no file is created. Two cases start with the newest but do NOT write it, and the log
   says why: `[Server]` written twice (or `DelphiVersion` twice in it - Windows reads only the
   first, and the version meant may be in the other), and a `[Workspace.<name>]` that still
   carries the `DelphiVersion=` of 1.13 (that workspace wanted a version: move it to `[Server]`).

A machine holds at most ONE installation per BDS version - its folders and registry keys are
named after the version, so a second one would land on the first - and that is why the number
alone picks it. The same version on several servers only happens on several machines.

**Which versions does this machine have?** The first lines of the server's log (the tray
window, `logs\actual.log` next to the exe, or the terminal) list them, each with the exact key
to copy into `settings.ini`:

```
RAD Studio on this machine: RAD Studio 13 37.0.59082.6021, Delphi 13 and C++Builder 13 Update 1  ->  [Server] DelphiVersion=37.0   <- this server
RAD Studio on this machine: RAD Studio 12 23.0.xxxxx.xxxx  ->  [Server] DelphiVersion=23.0
This server uses DelphiVersion=37.0 (RAD Studio 13, Delphi 13 and C++Builder 13 Update 1), pinned by [Server] DelphiVersion in settings.ini. One server, one Delphi: ...
Update declared in settings.ini: [Server] DelphiUpdate=13.1.
```

An agent sees the same list with `delphi_installs`, and its server's Delphi in
`delphi_workspace` (`activeDelphiName`, `activeDelphiBuild`, and `delphiUpdate` when one is
declared).

**Two versions = two servers.** To serve RAD Studio 12 and 13 from the same machine:

1. Copy the server folder (the exe with its `node\` folder, `DelphiStyleConvert.exe` and the two
   `DelphiFormRender*.exe` - what
   the release zip unpacks) to a second folder, e.g. `C:\Delphi-mcp-Server-12\`.
2. Give that copy its own `settings.ini`:

   ```ini
   [Server]
   Port=3132
   DelphiVersion=23.0

   [Workspace.Legacy]
   Token=another-long-random-secret
   Roots=D:\Projects\Delphi12
   ```

   - its own **port**;
   - its own **roots** - never the same roots as the other server: each process locks the
     files it writes only against its own threads, so two servers on one project would write
     the same files blind to each other. A project lives in one place;
   - its own workspaces and tokens.
3. Run it however you like. `-install` registers the one service called `DelphiLspMcp`, so it
   is for ONE server per machine; run the others with `-gui` (tray), with `--http` in a
   terminal, or under whatever keeps a program running for you. How you run it is yours to
   decide: the server only has to know which Delphi it is.
4. Open the firewall for the new port: `scripts\firewall-allow.ps1 -Port 3132` as
   Administrator. The rule is named after its port, so the first server's rule stays.
5. In the client, one MCP entry per server, named after its machine AND its version
   (`delphi-pc-13.1` on `:3131`, `delphi-pc-12` on `:3132`; see
   [docs/CLIENTS.md](CLIENTS.md)). The name is only a label - the same version can
   also run on several machines (13.1 here, 13.2 on a VM, 13.2 on another VM). What a server
   IS comes from `delphi_workspace` on it: `activeDelphiName`, `activeDelphiBuild`,
   `delphiUpdate` - the update its operator declares, since 13.1 and 13.2 are both "RAD Studio
   13" and BDS 37.0 - and `server.host`, the machine.

Everything else is already separate per folder: settings, logs, `__delphi-temp`, mailbox,
reports, and the presence mark that decides the startup purges. What two servers share is the
cache under `%LOCALAPPDATA%\DelphiLspMcp`: the engine configurations and the designer tables
carry the Delphi version in their file names, every cache file is written whole, and the
designer tables are generated under a lock shared by every process - so each server finds its
own version's files. One tool shares its converter on purpose: `delphi_styles` converts styles
with the one shipped with the server (`DelphiStyleConvert.exe`, built with RAD Studio 13's
FireMonkey), whatever the server's Delphi. The renderers of `delphi_designer preview` are built
with RAD Studio 13 too: they load its runtime packages (`rtl370.bpl`...) and the design
packages of the server's Delphi, and they are only tested against BDS 37.0. A preview runs
the constructors and property setters of the installed components, as the IDE does when it
opens a form, but inside a Windows container of its own with no capabilities, one per call:
without the container nothing is drawn (`DSGN-177`), so a form shows no live data from outside
it. What the agent writes - the form - is judged first (a value with the shape of a path outside
the roots is refused by its text before the renderer starts), and a component that waits (a
design-time connection with nothing to open) ends at the renderer's budget (`RENDER-007`, 60 s,
nothing left behind). The rest is in `src/Render/README.md`.

RAD Studio 13.1 and 13.2 are both BDS 37.0: one replaces the other, they never sit side by
side. For that, one machine (or VM) per version, each with its own server - the same model,
only further apart. The key stays `DelphiVersion=37.0`: the BDS number is what gives the
folders and registry keys of that Delphi, and on one machine it can only be one of them.
Which update it is, the operator may declare in `[Server] DelphiUpdate=13.1` (or `13.2`, and
tomorrow `14.1`). Today the server works the same with 13.1 and 13.2 - both are 37.0 - and
nothing reads that key to decide anything: it is there so that what a given update may need
one day has one place to hang from, and the server shows it in its startup log,
`delphi_installs` (`requestedUpdate`) and `delphi_workspace` (`delphiUpdate`). It is declared,
never deduced: the startup log and `delphi_installs` (`installedUpdate`) show the update each
installer recorded, the text the IDE's About box lists ("Delphi 13 and C++Builder 13 Update 1"
is 13.1, "... Update 2" is 13.2), as a hint for the operator, and the code never compares that
text. A value that is not `number.number` is ignored, with a warning in the log; GetIt patches
and hotfixes are something else and are not part of it.

Until 1.13 each workspace could pin its own version (`[Workspace.<name>] DelphiVersion`) and one
process kept engines and paths of several versions at once. That key is no longer read, and
the startup log says so.

## Configuration (`settings.ini` next to the exe, or environment variables)

The file is read **once, when the process starts**, and never reloaded live -
on purpose: the jail of a running agent must not change under it. After editing
it, restart the service (`sc.exe stop DelphiLspMcp` / `sc.exe start DelphiLspMcp`).
`delphi_workspace` says so (`settingsChangedNote`) whenever the file on disk is
newer than the running process.

The configuration is **four layers**, safest-by-default at every one:

**One principle above the layers (v0.98): NOTHING IS GLOBAL.** Every
permission, whitelist and capability belongs to ONE workspace, and a
workspace has exactly what its section declares — an absent switch is OFF,
an absent list is EMPTY. There is no `[Security]` section any more — and no generic `[Workspace]`
section either: only `[Workspace.<name>]` sections exist, because **an agent
either has a workspace token or has nothing**. A stale ini with either old
section is completely inert.

1. **The door** — credentials: **workspace or nothing** (v0.91, completed
   in v0.98). A caller authenticates *only* through a `[Workspace.<name>]`
   section — its own `Token`, optional `ReadOnlyToken`, its `Roots` and its
   configs. Tokenless HTTP is always **401**; a tokenless *local* stdio
   process may look, never touch (read-only) - unless it declares its
   own jail with `DELPHI_MCP_ROOTS` (see 2).
2. **The jail** — where each credential may touch disk: a world of its own
   per workspace token. (A locally launched process may declare a private
   jail with `DELPHI_MCP_ROOTS` and the other `DELPHI_MCP_*` variables —
   the harness/dev launch mode; they never touch a named workspace.)
3. **Capabilities** — what each workspace may *do* beyond compiling (run,
   test, remote-run, build scripts, reach git hosts or PAServer machines).
   All off until that workspace declares them.
4. **Surface** — what `tools/list` *advertises* (`[Tools]` profiles). Helps
   small models; never a permission.

```ini
; Comments go on their OWN line: Windows keeps a trailing "; ..." as part of
; the value, so "Port=3000 ; my port" is not port 3000 (measured 2026-10-05).
; Save the file as UTF-8 WITHOUT BOM (or ANSI): Windows does not see a section
; header with a BOM in front, so a BOM right before [Server] loses Port and
; BindIP - the server refuses to start and says so (a comment line first is fine).
; UTF-16 little endian is read too; UTF-16 big endian or UTF-32 stops the server at
; startup, and a file that exists but cannot be read puts nothing in force (said at startup).
[Server]
; HTTP port for --http and the tray (-gui)
Port=3000
; idle HTTP sessions expire after this (0 = never)
SessionTimeoutMinutes=720
; an LSP engine nobody uses for this long is stopped (0 = never)
EngineIdleMinutes=30
; at most this many LSP engines alive; past it, the least recently used one stops (0 = no cap)
MaxEngines=0
; the ONE RAD Studio this server uses; absent = the newest with DelphiLSP,
; which the server then writes here at its first start
DelphiVersion=37.0
; optional: which update of it you run (13.1, 13.2...); absent = none declared
DelphiUpdate=13.1

; Token-scoped sandboxes: the SECRET decides the jail. Hard boundary - other
; workspaces' roots are not even readable. Overlap is allowed and never
; subtracts (note Audit's root is a subfolder of Shop's). EACH SECTION IS
; COMPLETE IN ITSELF: absent switch = off, absent list = empty.
[Workspace.Shop]
; read-write, but only inside THESE roots
Token=shop-secret
; optional read-only twin, same roots
ReadOnlyToken=shop-reviewer-secret
Roots=D:\Projects\Shop;D:\Projects\Shared
; INSIDE the jail: read, never write
ReadOnlyPaths=vendor;third-party\libx
; OUTSIDE the jail: reference projects, read only, win over Roots
ReadOnlyRoots=D:\Projects\ReferenceERP
; Declare each place by a path with its DRIVE LETTER. An entry written as a network path (\\server\share\x)
; is NOT loaded, and the startup log says so: map the share to a letter with "reconnect at sign-in" - at
; startup the server tries to connect that letter for itself.
; ITS declaration - nothing is inherited
LibraryZone=1
; may build+run ITS test suites
AllowTests=1
; ITS persistent memory (vault_* tools)
VaultPath=D:\Vaults\TeamMemory
; ITS Android devices (absent = NONE)
AdbAllowedDevices=192.0.2.163
; optional: trims tools/list for this token
Profile=coder

[Workspace.Audit]
Token=audit-secret
; a SUBFOLDER of Shop - deliberate
Roots=D:\Projects\Shop\src\Forms
; navigation tools only in its listing (declares nothing else: it HAS nothing else)
Profile=reader

[Tools]
; global surface: full | coder | reader
Profile=full

[Log]
; log on disk (every mode): a block every N lines
LinesPerFile=2000
; rotation: keep the newest N block files
MaxFiles=10
```

Every key is documented in depth in [`settings.example.ini`](../settings.example.ini).

- **Port**: used by the service, the terminal `--http` mode and the tray app alike. A port given on the
  command line (`DelphiLspMcp --http 3900`) overrides the ini for that run.
- **BindIP** (`[Server] BindIP` or `DELPHI_MCP_BIND_IP`): listen on a single interface (e.g.
  your LAN/VPN address) instead of all of them — which also stops the firewall prompting
  twice (IPv4 + IPv6).
- **Firewall prompts every start?** Windows keys its prompts to the exe binary, so each
  rebuild looks new. Run `scripts/firewall-allow.ps1` **once as Administrator** to install a
  single durable rule keyed to the *port* (covers every rebuild) and clear the accumulated
  per-binary duplicates: `powershell -ExecutionPolicy Bypass -File scripts\firewall-allow.ps1 -Port 3000`.
- **Tokens (workspace or nothing, v0.91)**: every HTTP request must carry
  `Authorization: Bearer <token>` where the token is some workspace's `Token=` (read-write
  inside its roots) or `ReadOnlyToken=` (read-only inside the same roots: it can read,
  search, navigate symbols, get diagnostics, download, run query git commands and file
  reports — but `delphi_edit`, `delphi_create`, `delphi_build`,
  `delphi_package`, `delphi_upload` and git write commands are refused; `tools/list` does
  not even announce it the tools that only write, and `delphi_help` tells it so).
  Tokenless HTTP is **always 401** — the anonymous mode is gone in v0.98. A secret that appears in two sections (or a `Token=` equal to its `ReadOnlyToken=`), a key repeated inside a section, or a section written twice is a copy-paste the ini parser would swallow silently, so the server **closes the workspaces involved** (fail closed) and says which in the startup log. A token of a closed workspace - closed by that, by a protection that does not load or by roots that do not parse - is answered **403** `SYS-034` naming the workspace, not the 401 of a token that does not exist: the token is right, and the startup log says what to fix.
  The whole classification is enforced at a **single gate** in front of every
  `tools/call` — including the git argument filter, so no option can turn a "read" command
  into a write. **With NO workspace token configured at all, the server binds to
  `127.0.0.1` only** — an unconfigured server is never silently open to the network.
- **BREAKING — migrating from ≤ v0.97**: the `[Security]` section is GONE and completely
  inert — the server neither reads it, nor warns about it, nor knows it existed. Move every
  key you had there into each `[Workspace.<name>]` that deserves it — same names, same
  values, one decision per workspace. The generic `[Workspace]` section, the anonymous
  mode (`AnonymousReadOnly`) and the global `[Vault]`/`[Adb]` sections fell the same day:
  the vault is now each workspace's `VaultPath=`/`VaultReadOnly=`, the adb allowlist its
  `AdbAllowedDevices=` (absent = NO devices — the last fail-open default is gone). Old
  `AuthToken`/`ReadOnlyToken` values become a workspace's `Token=`/`ReadOnlyToken=` (true
  since v0.91). Fail safe is preserved the blunt way: a stale config authenticates
  nothing and earns a `127.0.0.1`-only bind.
- `--readonly` on the command line makes the entire process read-only, whatever the
  transport (useful for a stdio-registered reviewer).
- **`[Workspace.<name>]` token-scoped sandboxes**: each section defines its own credential(s)
  and its own jail. Whoever presents that `Token` works read-write inside *its* `Roots` and
  nowhere else — other workspaces' roots are not even **readable** (the library read zone
  below stays available to everyone). Workspaces may **overlap**: one can hold a whole tree
  and another just a subfolder of it; each token's jail is the union of its *own* roots and
  nothing is subtracted for belonging to another workspace too. A workspace whose `Roots`
  fail to parse admits nobody (fail closed). Inside a
  workspace section the credential key is `Token=`, and `AuthToken=` is accepted as an
  alias; the startup log lists every workspace it loaded and **warns** about misspelled
  sections (`[Workopenclaw]`…), tokenless workspaces, unparseable roots and retired keys that do nothing, so a config
  mistake never fails silently. And a workspace carries **everything else** too:
  `AllowTests`, `AllowRemoteRun`, `AllowBuildScripts`,
  `LibraryZone`,
  `AgentConfinement`, `SharedFolders`, `ReadOnlyPaths`, `ReadOnlyRoots`, `Profile` — and the reach lists `GitRemotes`,
  `RemoteHosts`, `RemoteRunProjects`. Nothing is inherited from anywhere: an absent switch
  is off, an absent list is empty — one workspace can be a CI space that executes and dials
  its build machine while every other space stays compile-only and offline.
- **Network shares are opt-in.** A share becomes part of the Delphi environment only when the
  operator maps it to a drive letter on the RAD Studio machine, with "reconnect at sign-in",
  and declares a place on that letter in a workspace; a share nobody mapped stays outside the
  boundary, on purpose. Windows decides which shares belong to the machine, and each workspace
  decides which folders of them its agents get - the rule of everything else here: what the
  operator did not declare does not exist.
  The server is not a client of the network at large: all it does there is connect, for its own
  session and passing no credentials, the letters the account already mapped. A path that names
  a share (`\\host\share\...`) is outside to every tool (`GUARD-002`), and the server answers
  without going to that host: measured 2026-10-01 with eight tools (list, read, search,
  textedit, delete, move, git, build) and a host that does not route, each answered in 0.02 s
  or less. Until 1.18.1 the pieces of `delphi_git args` were the door left: a share written
  there reached git, which opened SMB towards that host with the service's account (21 s
  against one that does not answer); since 1.19.0 `args` is gone, `remote` is the name of a
  remote of the repository, and its address is judged before git runs.
  The network path of a declared place is refused too (`GUARD-029`): a place is taken
  in the form it was declared in. One exception, by decision and for reading only: with
  `LibraryZone=1`, a folder of the IDE's Library Path that the IDE's owner wrote as a network
  path is read like the rest of that zone - the host is one the IDE already uses, not one an
  agent names. That one is read in the code, not measured.
- **Roots on a network drive.** Measured 2026-09-30 between two virtual machines of one local network:
  the server on one (RAD Studio 13.2, tray mode), its roots on a drive letter mapped to a share of
  the other. A call that reads a file answers in 3 ms from the server's own disk and in 9 ms from
  the share; on a copy of this server's own project in the share, the engine's first answer comes
  2.4 s after the request and 19 ms once warm; the 118 unit tests, built and run there, pass. What
  the machine that hosts the share writes in it is seen at the first read - new content (20 of 20),
  a new file in a listing (5 of 5) - with one exception: a file the server was just told does not
  exist, created then on the other machine, takes about 5 s to appear to a read (5 of 5). That
  matches the five seconds Windows documents for its share client's memory of a "not found"
  (`FileNotFoundCacheLifetime`); the cause itself was not measured. **git on such roots**: on
  that machine git refused a repository of the share ("detected dubious ownership") until the
  server's user told it to trust the share - `git config --global --add safe.directory
  '%(prefix)///host/share/*'`, run there, was enough for the repository measured - and
  `delphi_git` cannot do that for you (on a machine's own share git did not ask for it); since 1.13.1 its answer says so (`GIT-057`), also when the refusal comes before the command. Until
  1.8.2 `delphi_git` then answered `GIT-041` to every command that works on an existing
  repository, because git names it by its UNC; since 1.8.2 that answer is read in the form the
  root was declared in, and the paths git prints of those places (`init`, `worktree list`) leave
  with their virtual unit, which the agent can send back. **A Windows Service does not see the letters connected in the user's
  desktop session** (measured 2026-10-01: a program run by the service, under the same account,
  got "not connected" for such a letter and saw the local drives alone). Until 1.9.0 a root on
  such a letter did not work there - a write under it answered "the drive cannot be found" - and
  the startup log said nothing. **Since 1.9.0 the server connects those letters for itself.** At
  startup, for each drive letter of a root, a reference or a vault that its process does not
  see, it looks up the account's persistent mapping of that letter (`HKCU\Network\<letter>`:
  what Windows records for a drive mapped with "reconnect at sign-in"), connects the letter for
  its own session, passing no credentials, and checks that each declared place on it is a
  folder that opens. Each step is a line of the log; what does not work is a warning there: a
  letter with no persistent mapping, a connection Windows refused (with its error number), a
  place that does not open. A letter that has a mapping and did not connect because the network
  or the share was not there - a service started before the network, a NAS that was off - is
  tried again every 30 s in the background, and the log says when it connects; an error of
  credentials or of permission is said once and not retried (insisting would be two failed
  logons a minute against the share). Nothing of this goes in `settings.ini`. Measured 2026-10-01
  on this project's own production service, with a root on a letter of a NAS share whose
  credentials are not the account's: the log says the letter was connected in 16 ms and the
  root is reachable, and the write that failed went through. The startup waits 15 s at most for
  this check and then goes on, saying so; what the check finds afterwards goes to the log.
  Measured with a simulated share only (unit tests): a share that is down, the 15 s limit and
  the retry. Not measured: a connection Windows refuses, the tray mode started at sign-in
  before the network is up, a share that stalls later (an engine waiting on it could look like
  a hung one). The cleaning of the temporary folders of a root on a network drive, which walks its tree (2.6 ms per folder measured on that service), runs apart from the startup, and leaves what was written there in the last hour: a server on another machine may be using it.
- **A place is declared by a path with its drive letter** (`D:\...`), since 1.9.0. An entry of
  `Roots`, `ReadOnlyRoots`, `ReadOnlyPaths` or `VaultPath` - or of their `DELPHI_MCP_*`
  variables - that is not one (a network path `\\host\share\...`, a device path `\\?\...`) is
  not loaded, and the startup log names the key and the entry; until 1.8.2 a root written as a
  network path was accepted. Nor is an entry with a wildcard, one that starts with a single slash (`\vendor`: to Windows, the root of the drive the server runs from), a relative entry of `Roots`, `ReadOnlyRoots` or `VaultPath` (it would be relative to the folder of the process), or one relative to the current
  folder of a drive (`N:folder`); a bare drive (`N:`) is its root. The agent sees drive letters
  as virtual units (`srvd:`), and a place with no letter has none. A workspace left with no
  root admits nobody. An entry of
  `ReadOnlyRoots`, `ReadOnlyPaths` or `VaultPath` that is not loaded - also one that does not
  parse (a wildcard, a character Windows does not allow), which used to be dropped in silence -
  closes its workspace too: those keys say what must not be written, and with the entry left out
  it could be. In the local launch mode that closes the process (`GUARD-030`: no root, no vault, and the refusal comes before anything is looked up on disk), and so does
  starting it with the token of a workspace that is closed: it used to fall back to the trusted
  local mode, which reads the whole machine.
- **A root is a folder, and a whole drive is one more** (`Roots=N:\`), since 1.9.0. Until then
  it was not: the server took the final backslash off its places to compare and to show them,
  and `N:\` without it is `N:`, which to Windows is the CURRENT folder of the drive, not its
  root. It worked only while the server ran from another drive, and `delphi_workspace` showed
  such a root as `srvn:`, which sent back was refused (`GUARD-021`); it now shows `srvn:\`.
  Measured with test drives made with `subst` and the server running from the drive that is
  its root: list, read, write, move, delete, a reference and a vault that are whole drives, a
  project built there. Not measured there: git (to git a `subst` drive is the folder under
  it: `GIT-041`, as for any `subst` letter) and the root of a real volume.
- **ReadOnlyPaths**: folders INSIDE the jail that may be read but never written — a `vendor/`, a submodule, a reference clone. Semicolon-separated; a relative entry resolves against each root, an absolute one is a path with its drive letter; absent means none. An entry that is not loaded closes the workspace (see above). It is not the jail and the server says so differently: the jail is "you don't go in there", this is "you look, you don't touch". Third-party code often has to live inside the project — that is where whoever clones it will look for it — and when that folder is *another git repository*, a careless write does not even show up in the main repo's `git status`, so it can go a whole session unnoticed. This turns that into a rule the server enforces instead of one the agent has to remember. It holds for what an operation TOUCHES, not only for the path it was given: a move or a copy that would land on an entry is refused (`MOVE-020`), and so is a build whose output folder holds one, or that would rewrite one of the project's own `.res` files (`BUILD-029`, since 1.18.3). It opens nothing outside the roots: for an entry outside every root of its workspace and of its references (absolute, or relative with `..`), its agents get nothing - neither reading nor protection; to let them read a folder outside their roots without writing it, that is `ReadOnlyRoots`, below. An entry that contains a root is not outside (it makes the whole root read-only). Protection compares both the declared path and the real path through the same 8.3-aware location rule. An entry that contains a root by its declared path protects the whole root, even when that root is a junction to another folder; short and long names give the same result. On a local drive the startup checks both forms and gives no outside warning for that protection. On a network drive it is on the text, so that the startup never waits on a share. Such an entry is still loaded (no workspace may delete it), and since 1.9.1 the startup log says so, with the key and the entry: measured 2026-10-02 on a second machine, two workspaces declared `ReadOnlyPaths=L:\...` so that their agents could read our code, neither could, and the startup said nothing.
- **ReadOnlyRoots**: **reference projects** — folders OUTSIDE the jail that the workspace may read as if they were its own (read, search, symbols, definition, git query, fetch) and never write: no edit, no build (a build writes dcu and exe), no move, no temp files. To bring a unit or a folder in from one, `delphi_move copy=true`: the copy is yours, the original stays untouched, and a whole project or repository comes in like any folder (a repository with its git, when its git stays inside it). Same syntax as `Roots`, absolute. The idea: an agent works in its roots and can also *see other projects of the house to learn how things are done here*. Deliberately separate from `Roots`, so the write jail never sees them, and it **wins over `Roots`**: a folder in both lists, or a root inside a reference, is read-only. `delphi_workspace` lists them as `readOnlyRoots` and `delphi_projects` flags their projects with `readOnly:true`.
- **AgentConfinement**: *cooperative* subdivision inside one credential's
  jail — each agent (by its self-declared `clientInfo.name`) writes only under
  `<root>\<name>\`, plus any `SharedFolders`. Useful for teams sharing one token; for a
  boundary an agent cannot cross, use a workspace token instead (the name is self-declared,
  the secret is not).
- **AllowTests**: lets `delphi_test` build and run a workspace test project here — the only
  thing that ever executes on the server, and without it an agent can write code but never
  learn whether it works. The test runs in a Windows container (an AppContainer) of its
  own, created for that run and deleted with its answer, on a COPY of its output folder in
  the server's own temp: it reads and writes that copy and, besides it, only what Windows
  gives every container (its own temp folder, deleted with it, and the system files under
  Windows and Program Files) — no other file of the machine, no network, no network drive —
  and it is cut off at its timeout. It is a
  cage for tests of LOGIC: what a test reads must travel in its output folder, and a test
  project built with runtime packages is refused before building. Until 1.10 the run
  was confined by Windows' low-integrity label, which only holds on local disks: on a
  network folder a test wrote wherever the account reached (measured 2026-10-02).
  (`AllowRun` and `delphi_run`, arbitrary binaries on the server, were retired on
  2026-09-23: one execution path, `remote-run`; a left-over `AllowRun=1` in the ini does
  nothing, and the startup log names it as a retired key.)
- **AllowRemoteRun**: lets `delphi_paserver remote-run` execute, on a PAServer target, the
  binary *that project deployed there* — never anything else on that machine: the server
  derives the remote path itself and its launch script verifies the file's signature
  (ELF/Mach-O/PE), so only a native binary ever runs. The one execution path of the product (running on
  the target is not running here). It takes TWO declarations: this switch and
  `RemoteRunProjects` — an empty project list allows nothing (fail closed, v0.98). Its
  entries are the full paths of the projects' `.dproj` (a `.dpr`, or no extension, is the
  same project) or the wildcard: a bare name authorizes nothing (`RUN-022` says which path
  to write), because it matched any project with that name and a homonym in another folder
  could deploy over the allowed one. `delphi_build target=Deploy` through a profile asks
  the same list.
  `delphi_desktop` runs the server's own desktop node on the target, and seeing and
  typing on a desktop is a permission of its own: `McpDesktopNode` (or `all`) in
  `RemoteRunProjects` (`RUN-020` when it is missing). Looking leaves traces of the server on
  the target: it deploys or updates the node there, uploads and deletes a job file and its
  launcher, and the node writes the capture it hands back.
- **Reach lists (per workspace)**: `GitRemotes` limits which hosts git may reach - the URL
  written in a call and the network addresses of the repository's own remotes alike
  (clone/fetch/pull/push/ls-remote; a remote used by its name whose address is not listed gets `GIT-063`, naming the host), and the LFS endpoint of a tree a command materializes
  (`GIT-061`) — measured to close an SSRF/exfiltration primitive. The host is read from the
  address's authority alone, as every program reads it: an address that does not show its
  host plainly is refused (`GIT-062`), and `clone`'s address is judged whole, as git
  receives it. Profiles and SDKs created through the MCP appear in the
  IDE too: `add-profile`/`get-sdk` write the registry seats its managers actually read (they
  ignore the `.profile` folder), and the IDE loads that list **at startup** — so a profile
  created while it is running shows up at its next start. If one is on disk but missing from
  the list, `delphi_paserver command=reseat` writes the seats that are absent, reading each
  encrypted password from its own file: no PAServer, no password anyone has to know. An
  existing profile name is never overwritten, and duplicates by host get a warning. `RemoteHosts` does the same for every PAServer dial —
  hand-named hosts AND connection profiles: since v0.98 having a profile in the IDE is not
  permission (the profile says HOW to connect; the workspace says WHETHER) — measured to
  close a port-scanning primitive. In any of the four lists - `RemoteHosts`, `GitRemotes`,
  `RemoteRunProjects` and `AdbAllowedDevices` - an entry `*` (or `all`, or `0.0.0.0`) declares
  "anything" on purpose. Where each workspace may talk to is its own declaration, like
  everything else. A list of NAMES (`GitRemotes`, `RemoteHosts`, `AdbAllowedDevices`,
  `SharedFolders`, `[Tools] Only`) takes `;` or `,` between its entries; a list of PATHS
  (`Roots`, `ReadOnlyPaths`, `ReadOnlyRoots`, `RemoteRunProjects`) only `;`, since a path may
  hold a comma. Blanks and quotes around an entry are ignored in both.
- **`[Tools]` profiles**: `full` / `coder` / `reader` (or an explicit `Only=` allowlist) trim
  what `tools/list` advertises — ~15k tokens of schemas drown a small model. Listing only:
  hidden tools stay callable, permissions live in the layers above. A workspace can carry its
  own `Profile=`.
- **`VaultPath=` / `VaultReadOnly=` (per workspace)**: optional persistent memory for
  agents (a folder of Markdown notes) — each workspace declares its own, and two workspaces
  may remember in *different* vaults. Read-only by default; writes, when enabled, are
  append/create/anchored-replace only, always backed up first. `tools/list` announces a
  workspace only the vault tools its vault allows (none without one, no write tools while
  it is read-only). See `docs/VAULT.md`.
- **AllowBuildScripts**: `delphi_build` builds only what a compile-only build understands —
  the gate is a **whitelist** (since 1.21.2): under `<Project>` only PropertyGroup, ItemGroup,
  Import, ProjectExtensions and Target; inside a `<Target>` only Message, Warning, Error,
  CallTarget, OnError, PropertyGroup and ItemGroup. Anything else in the `.dproj` or in an
  imported `.targets` is refused by its name (`BUILD-017`): a task that *executes a program
  or plants/deletes files* (a planted `<Exec>`), an element the gate does not know, free text
  for the compiler's command line (`DCC_AdditionalSwitches`, `BRCC_UserSuppliedOptions`,
  `BRCC_ResponseFilename`), and an `<Import>` of a file outside the workspace, other than
  the IDE's own, even when harmless. An **inert** custom `<Target>` (a `<Message>`, a
  property) always builds. Independently of this switch, what the build **reads** through the
  project — the icon, the manifest, the search paths, a `.rc` and the files it names, a
  deployment file — has to lie where the session may read (the workspace, the IDE and its
  library zone), whether it exists or not (`BUILD-050` to `BUILD-053`; a hard link in the
  project's tree to a file outside is refused too). So has every unit the main source names
  with `in` (`uses X in '...'`, `contains` in a package: `BUILD-061`), and the `{$I}`/`{$R}`
  directives of every source the build reads from the workspace - the project's folder, a
  unit reached by such an `in`, the workspace folders of its search and include paths
  (`BUILD-028`). The fields of a deployment entry only take what a path takes, and in
  `RemoteDir` and `RemoteName` no macro but `$(PROJECTNAME)` (`BUILD-066`), and a project
  that goes to a PAServer target has a name of letters, digits, spaces and `_ - . ( ) +`
  (`PAS-071`). A `resinator.exe` in the project's folder is refused too (`BUILD-065`): the
  IDE's resource compiler would run it instead of its own. The server takes the current
  folder out of the library search of everything it starts. The project's **pre/post build events**
  (signing, copies, EurekaLog) are not
  refused either: the build runs with them emptied and says so (`buildEventsSkipped`) -
  the binary is for working and testing in the agent's workspace; the final, signed one is
  the operator's build, outside this server, where those events run. For a
  **trusted** project that must really execute its tasks, set `AllowBuildScripts=1` — this
  permits its build scripts and nothing else. Off by default.
  **To see the gate work from a client** (it judges the `.dproj` however it got there, and
  `delphi_upload` is the channel that writes one raw — `delphi_edit` and `delphi_textedit`
  refuse a project file): create a console project with `delphi_create`, then upload this
  minimal `.dproj` over its own (whole file, base64, `offset=0`) and build it — it compiles
  (the output folders are optional since 1.21.3: a `.dcu` folder the project leaves
  undeclared is supplied by the build, and `outputSupplied` says where):

  ```xml
  <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
      <MainSource>Probe.dpr</MainSource>
      <Config Condition="'$(Config)'==''">Debug</Config>
      <Platform Condition="'$(Platform)'==''">Win64</Platform>
      <AppType>Console</AppType>
      <FrameworkType>None</FrameworkType>
      <DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>
      <DCC_DcuOutput>.\$(Platform)\$(Config)\dcu</DCC_DcuOutput>
      <DCC_ConsoleTarget>true</DCC_ConsoleTarget>
    </PropertyGroup>
    <ItemGroup>
      <DelphiCompile Include="Probe.dpr"/>
    </ItemGroup>
    <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists('$(BDS)\Bin\CodeGear.Delphi.Targets')"/>
  </Project>
  ```

  Add `<Foo/>` before `</Project>` and the build answers `BUILD-017` naming
  "a <foo> element inside <project>"; put `<Icon_MainIcon>C:\Windows\win.ini</Icon_MainIcon>`
  in the PropertyGroup and it answers `BUILD-050` naming the element. Nothing is read or run
  either way. The copy of the original `.dproj` is in the `__delphi-patch` trash
  (`delphi_delete` the probe, then `delphi_move` the copy back).
- **`AdbAllowedDevices=` (per workspace)**: the `delphi_adb` device allowlist —
  `AdbAllowedDevices=192.0.2.163;SERIAL123` (a `;` or `,` list; an IP entry covers whatever
  port wifi debugging negotiates, a USB serial is listed as-is, and a device adb lists by its
  mDNS name is listed by that name, without the ` (2)` adb adds when it sees it twice). Devices outside the
  workspace's list are refused at **both** access levels, every device-addressing command
  must name its `device` explicitly (an implicit target could be an unlisted device that
  happens to be the only one attached) — and, like every list since v0.98, **absent means
  NO devices**, never unrestricted. A screenshot writes `/sdcard/delphi_mcp_screen.png` on
  the device and deletes it (a file of that name there would be overwritten).
- **`[Server] DelphiVersion`**: the ONE RAD Studio this server uses - the BDS version number
  (`37.0` = RAD Studio 13, `23.0` = 12 Athens, `22.0` = 11 Alexandria), and only from here.
  Absent = the newest with DelphiLSP, which the server then writes here at its first start. A
  version that is not installed stops the server from starting - it never uses another one.
  The startup list of installations with the key to copy, several versions on one machine
  (several servers) and what they share:
  [One server, one Delphi](#one-server-one-delphi---several-versions-on-one-machine).
- **`[Server] DelphiUpdate`** (optional): which update of that RAD Studio the server runs, as
  its operator declares it (`13.1`, `13.2`). Both are `37.0`, and today the server works the
  same with both: nothing reads the key to decide anything yet - it is there for what a given
  update may need one day. Declared, never deduced (the startup log shows the update each
  installer recorded, as a hint). A value that is not `number.number` is ignored with a
  warning; absent = none declared.
- **`[Server] SessionTimeoutMinutes`** (or `DELPHI_MCP_SESSION_TIMEOUT_MINUTES`): an HTTP
  session that sits idle longer than this (default 720 minutes; 0 = never) expires, and the
  next request on it answers 404 with the reason so the client re-initializes - the
  streamable-HTTP contract, and the same answer an id this process never issued gets
  (a server restart). Generous on purpose: every re-initialize costs an agent a whole
  `tools/list`. `delphi_workspace` reports the live `sessions` and the timeout in force.
- **`[Server] EngineIdleMinutes`** (or `DELPHI_MCP_ENGINE_IDLE_MINUTES`): an LSP engine
  (`DelphiLSP.exe`) nobody has used for this long (default 30 minutes; 0 = never) is stopped,
  and the next request of its project starts another. Measured: an engine at rest keeps
  about 125 MB (a 60-unit project), and the first answer of the one that replaces it came
  2.1 s after the request (a small project). The same time closes a document an engine
  has open and nobody asks about. Apart from this, and with no setting: an engine with a
  request in flight that shows no sign of life for 20 s - no message, no CPU, no I/O -
  and does not answer when the server asks it is taken for hung and stopped; whoever
  waited gets `LSP-033` ("repeat"), and the repeat starts another engine.
- **`[Server] MaxEngines`** (or `DELPHI_MCP_MAX_ENGINES`): how many LSP engines may be alive at
  once. An engine that would pass the cap stops the least recently used one that is not
  working - never one with a request in flight; if every engine is busy the cap is passed
  rather than throwing an answer away - and the log says which one and why. Its project's
  next request starts it again (a few seconds). Default 0: no cap, only `EngineIdleMinutes`
  stops engines. Worth setting on a machine with little memory or many projects at once.
- **`[Log]`** — the server's log on disk, the **same in every mode** (service, terminal and
  tray), in `logs\` next to the exe. `logs\actual.log` is the live tail, appended every half
  second, so a process killed from outside loses half a second, not hours. Every
  `LinesPerFile` lines it is *renamed* to `logs\yyyymmdd-hhnnss.log` (a block) and rotation
  keeps the newest `MaxFiles` blocks; a `.log` of another name is never touched. A clean
  stop logs `stopped` and flushes the tail. Several processes with the same exe (a local stdio
  client next to the service) share the file safely, and nothing is ever written or pruned
  through a link planted at `logs\`. Passwords and tokens in a request are masked before
  they reach it, and a base64 run (an inline capture inside a response, an upload, a
  `delphi_fetch` chunk) is not kept: a mark with its size stays, the rest of the line whole.
  The tray's window shows the latest `LinesPerFile` lines on top. Memory is
  bounded end to end: the buffers cap at 5000 lines (beyond that, lines are counted and
  reported as dropped, never accumulated). Until 1.5.0 only the tray wrote this log: the
  service and the terminal had none.
- **Roots** are both discovery (`delphi_projects`) and a **jail**: with roots configured, every
  disk-touching tool (read/edit/create/build/lint/search/list/git/LSP) refuses paths outside
  them — including `..\` escapes and prefix cousins. Paths with spaces need no quoting (the
  separator is `;`); quotes around a root are tolerated and stripped. If Roots is configured
  but no root parses valid, the server **fails closed** (everything refused) rather than
  silently running unrestricted. No roots = unrestricted (local trusted mode). For remote
  exposure configure BOTH, and expose over VPN/LAN only.
- **`__delphi-temp`: the server's temporaries, and they are disposable.** One home, next to
  the executable, like `reports\`: a git message file, an SDK probe, the script sent to a
  target, and the captures the server makes to hand back (`delphi_desktop`, `delphi_adb`,
  `delphi_designer preview` without `out=`), in `__delphi-temp\captures\<workspace>\<agent>\`.
  A capture is the server's own work: it travels in the answer, or with `inline=false` as a
  download link that asks for it by name (`/files?capture=<name>`), and is deleted once
  delivered; a workspace is only ever handed its own. No answer names this folder, and
  `delphi_fetch` is for the agent's own files (over stdio there is no link: `out=` keeps one).
  None of it goes through the jail and none of it lands in a workspace - the jail judges what
  the agent names (`out=` included), not what the server does to serve it. **The folder is
  emptied whole every time the server starts**, and only by the FIRST live instance of that
  exe (a stdio launch of the service's own binary shares the folder, and purging it would
  delete files in flight): nothing there survives a restart, so never leave anything of your
  own in it - writing inside is refused. Skipped by every listing and search, `includetrash`
  included: it is not trash, nothing is restored from it. Before 1.0.12 these files went to
  the MACHINE's `%TEMP%` (56.4 MB measured, forgotten there for two days); from 1.0.12 to
  1.18.1 the captures went to `<root>\__delphi-temp\<agent>\`, inside the workspace, because
  `delphi_fetch` checked the jail - and the jail then judged the server's own work. Since
  1.23 the server no longer empties at startup the `__delphi-temp` those versions left in a
  workspace root: that was the server deleting inside a workspace, which is not its home.
  What is left there is the operator's to delete - hidden from every listing, refused for
  writing.
  THIS SERVER declares it in the tool's own source (`[RutaDelServidor]`), and since 1.0.14 the
  gate in front of every `tools/call` READS that declaration: an absolute path in a marked
  argument must fall inside what the workspace may read, before the tool even starts. It is a
  floor, not a replacement - each tool still makes its own, stricter check (reading versus
  writing is something only the tool knows) - and `delphi_workspace` reports how many
  parameters the floor watches (`jailedParams`), so an empty floor can be seen. The two
  exceptions are paths on the TARGET machine - `delphi_paserver`'s `exe` and `delphi_config`'s
  `remotedir` - where this server's jail has nothing to say.
- **A root is also where project discovery STOPS.** Looking for the `.dproj` that serves a unit
  (the IDE's `.delphilsp.json` is not read since 1.20.2), the server walks up from the file — but never past the edge of what this workspace
  may read. A project file sitting ABOVE the root is not adopted (since 1.0.11): if your layout
  puts the root at `src\` and the `.dproj` one level up, point the root at the project folder.
  Measured on 2026-09-21: without that stop, a stray 10-byte `.dproj` left in `%TEMP%` became
  the "project" of every unit below it, which made `delphi_references` scan **168 sources
  across other workspaces** and publish their paths in the refusal.
- **Virtual drive units**: the server's real drive letters never travel to the client — paths
  leave as `srvd:\...`, `srvc:\...` and are accepted back in the same form (real paths still
  work), so an agent can never mistake server paths for its own local disks. One generic rule
  at the dispatch gate covers every tool's output, compiler/git messages and 8.3 short forms
  included. Exception: file CONTENT is byte-exact by design and travels verbatim
  (`delphi_read`, `delphi_fetch`, search hits, the vault readers, the lines of content of a `delphi_git` diff, the verification echo of
  the editors - see "Byte fidelity beats the drive mask" in [ARCHITECTURE.md](ARCHITECTURE.md#design-points)). On the way in it is the same
  rule: what goes INSIDE a file (the `old`/`new` of an edit, a note's text, a commit message)
  is content and is written as sent - the parameters carry a mark, `[Contenido]` -, except a
  value of `delphi_designer` (`value`, `props`, `state`), whose text is expanded when it starts
  with a virtual unit, because a path in a form has to work when it runs. A path on a drive this
  server does not serve leaves as `srv0:` - it says there is a path and not where - and
  is refused by name if it comes back. The letters served are those of each workspace's own places (until 1.9.0 they were worked out once, with the workspace of the first call). (It was `srvx:` until 1.0.13, which is exactly what
  a genuinely served `X:` drive masks to.)
- **Library read zone** (off unless the workspace declares `LibraryZone=1`; re-read when the IDE's Library Path or its Environment Variables change - the server asks Windows to signal those registry keys - so a component registered while the server runs is readable from the next call, no restart (since 1.21.4); absent, reads are confined to the roots exactly
  like writes): READING tools (read/search/list/fetch/LSP navigation) additionally
  accept, for **every installed Delphi**, its installation directory, the Library Search Path
  of **every registered platform** (Win, Linux64, macOS, Android, iOS…) and the **GetIt
  catalog repositories** — so an agent can follow a definition into `System.SysUtils.pas`,
  read the source of an installed component (FMXLinux, LockBox…) or inspect the Android SDK.
  Macros like `$(BDSCatalogRepositoryAllUsers)` are expanded from the IDE's own registry
  table, never hardcoded. Writing tools can never touch that zone, and `delphi_workspace`
  reports it as `readableExtra`. The Config Fabricator also merges the IDE Library Search
  Path, so symbols of installed (third-party) components resolve.

