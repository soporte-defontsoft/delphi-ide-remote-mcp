# Quickstart: from zero to the first call

Five steps. What you need: **one Windows machine with a licensed RAD Studio /
Delphi 11+ installed and working** (open the IDE once, build something). That
machine is the server: **everything below happens on that PC**, the one with
Delphi. Nothing gets installed on the machines you work from.

## 1. Download the release

Take the zip from **[Releases](https://github.com/soporte-defontsoft/delphi-ide-remote-mcp/releases/latest)**,
check its SHA-256 against the one printed on the release page, and unzip it
**on the Delphi PC**, into a folder of its own, for example `C:\Delphi-mcp-Server\`:

```
certutil -hashfile DelphiLspMcp-*.zip SHA256
```

Inside: `DelphiLspMcp.exe` (the server), `DelphiStyleConvert.exe` (its style
companion), `settings.example.ini`, `node\` (the desktop node and the launcher,
used later for Linux targets) and `docs\`.

## 2. A five-line `settings.ini`

Copy `settings.example.ini` to **`settings.ini`, next to the exe**, and keep
just this:

```ini
[Server]
Port=3000

[Workspace.Main]
Token=a-long-random-secret
Roots=D:\Projects
```

- `Token=` is the credential: whoever presents it works **read-write inside
  `Roots`** and nowhere else. Make it long and random, for example:
  `powershell -c "[guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')"`.
- `Roots=` is the jail: the folder (or folders, `;`-separated) that hold the
  projects the agent may touch. Backslashes, a real drive.
- To let the agent **read** code it must not touch - your other projects, to
  learn how things are done - add `ReadOnlyRoots=` with those folders, wherever
  they are: `Roots=D:\Sandbox` and `ReadOnlyRoots=D:\Projects` is an agent
  that writes in its sandbox and reads your projects. Its sibling
  `ReadOnlyPaths=` is another thing: folders INSIDE the roots that are read and
  never written (a `vendor\`); it opens nothing outside them.
- Everything else is **off until you turn it on** (tests, remote execution,
  build scripts, git remotes...). The example file documents every key, one
  by one, when you want them.
- Which RAD Studio? At its first start the server takes the newest and writes
  it into this file (`DelphiVersion=37.0` under `[Server]`); from then on the
  key rules. The first lines of its log list every installation, each with the
  line that pins it (`[Server] DelphiVersion=23.0`). Two versions = two
  servers, each in its own folder with its own port: README, *One server, one
  Delphi*.

## 3. Run it

```
DelphiLspMcp.exe -gui
```

A tray icon appears; double-click it for the live log. It listens on the port
above. Run it **as the Windows user who owns RAD Studio**: the IDE keeps its
library paths, packages and SDKs per user, and another account sees none of
them. When you want it permanent, make it a Windows Service (`-install`, see
the README's Quickstart): same `settings.ini`, same port, so it is the service
*or* the tray, never both.

The tray's **Copy server URL** copies `http://localhost:3000/mcp`. That URL
alone - pasted in a browser, say - answers `401`: every request has to carry
the token, which is what step 4 sets up.

## 4. Connect a client

Claude Code, from any machine (Linux and macOS included):

```bash
claude mcp add --transport http delphi http://WINDOWS-HOST:3000/mcp --header "Authorization: Bearer a-long-random-secret"
```

On the Windows machine itself use `localhost`. From another machine, open the
port in the Windows firewall for your LAN or VPN (or pin the listen address
with `BindIP=` under `[Server]`). Other clients (Claude Desktop, OpenCode,
your own agent): [docs/CLIENTS.md](docs/CLIENTS.md). MCP is a standard: it is
configuration, never client-side code.

## 5. The first call

Ask the agent for **`delphi_workspace`**. It answers with the roots it sees,
the active Delphi version and the server version: if that comes back, you are
connected and inside the jail. Then `delphi_projects` lists the projects under
`Roots`, and `delphi_build` compiles one. From there the agent's manual is
[skills/SKILL.md](skills/SKILL.md) and the
tool reference is [docs/TOOLS.md](docs/TOOLS.md).

## If it does not work

| You see | It means |
|---|---|
| `401` from the server | The request carries no `Authorization: Bearer <token>` header (a browser never does), or the Bearer is not the `Token=` of any `[Workspace.<name>]` - check for a stray space or quote. The 401's JSON `hint` says the same. |
| The tray refuses to start, port taken | The service, or another tray, is already listening on that port: one or the other. Or Windows reserves that port (Hyper-V and WSL take ranges; `netsh interface ipv4 show excludedportrange protocol=tcp` lists them): change `[Server] Port=`. The message names the port and the socket error. |
| `delphi_projects` finds nothing | `Roots=` does not point where the projects are (typo, wrong drive, forward slashes). |
| `401` with the right token, and the startup log says an entry is "NOT loaded" | A place is declared by a path with its drive letter (`D:\...`, also on a share: map it to a letter). A root written as a network path (`\\server\share\x`), or as a relative one (`projects`, `\projects`), is not loaded, and a workspace with no root, or with a `ReadOnlyRoots` / `ReadOnlyPaths` / `VaultPath` entry that could not be loaded, admits nobody. The warning names the key and the entry. |
| A root on a network drive letter fails under the service ("the drive cannot be found") | The service does not see the letters of the desktop session; at startup the server connects the ones the account has mapped with "reconnect at sign-in", and its log says what happened with each. |
| The agent answers `GUARD-002` for a folder you listed in `ReadOnlyPaths`, and the startup log says it is "outside every root" | `ReadOnlyPaths` only marks folders INSIDE the roots. To let the agent read a folder outside them, without writing it, list it in `ReadOnlyRoots`. |
| Every call answers `GUARD-030` | A local (stdio) process that is closed: it was started with the token of a workspace that is closed, or one of its `DELPHI_MCP_READONLY_*` / `DELPHI_MCP_VAULT_PATH` entries could not be loaded. Its startup log names which. |
| `delphi_git` answers `GIT-050` | There is no git on the server PC, or it is not in the `PATH` the server was started with. Only `delphi_git` needs it: everything else works without. |
| A project with installed components fails with `F2613 unit not found` | The server runs as a user that is not the IDE's. Same exe, other account: no library paths. |
| Only reading works, every write is refused | A local stdio process without a token is read-only by design (unless it was launched with `DELPHI_MCP_ROOTS`, the harness/dev mode). Give it the workspace token (`DELPHI_MCP_TOKEN`), or connect over HTTP with the Bearer. |
