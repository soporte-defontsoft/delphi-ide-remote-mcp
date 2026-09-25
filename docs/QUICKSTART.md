# Quickstart: from zero to the first call

Five steps. What you need: **one Windows machine with a licensed RAD Studio /
Delphi 11+ installed and working** (open the IDE once, build something). That
machine is the server. Nothing gets installed on the machines you work from.

## 1. Download the release

Take the zip from **[Releases](https://github.com/soporte-defontsoft/delphi-ide-remote-mcp/releases/latest)**,
check its SHA-256 against the one printed on the release page, and unzip it
into a folder of its own, for example `C:\Delphi-mcp-Server\`:

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
- Everything else is **off until you turn it on** (tests, remote execution,
  build scripts, git remotes...). The example file documents every key, one
  by one, when you want them.

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

## 4. Connect a client

Claude Code, from any machine (Linux and macOS included):

```bash
claude mcp add --transport http delphi http://WINDOWS-HOST:3000/mcp --header "Authorization: Bearer a-long-random-secret"
```

On the Windows machine itself use `localhost`. From another machine, open the
port in the Windows firewall for your LAN or VPN (or pin the listen address
with `BindIP=` under `[Server]`). Other clients (Claude Desktop, OpenCode,
your own agent): [CLIENTS.md](CLIENTS.md). MCP is a standard: it is
configuration, never client-side code.

## 5. The first call

Ask the agent for **`delphi_workspace`**. It answers with the roots it sees,
the active Delphi version and the server version: if that comes back, you are
connected and inside the jail. Then `delphi_projects` lists the projects under
`Roots`, and `delphi_build` compiles one. From there the agent's manual is
[../skills/cmcpdelphiide/SKILL.md](../skills/cmcpdelphiide/SKILL.md) and the
tool reference is [TOOLS.md](TOOLS.md).

## If it does not work

| You see | It means |
|---|---|
| `401` from the server | The Bearer is not the `Token=` of any `[Workspace.<name>]`. Check for a stray space or quote. |
| The tray refuses to start, port taken | The service, or another tray, is already listening on that port. One or the other. |
| `delphi_projects` finds nothing | `Roots=` does not point where the projects are (typo, wrong drive, forward slashes). |
| A project with installed components fails with `F2613 unit not found` | The server runs as a user that is not the IDE's. Same exe, other account: no library paths. |
| Only reading works, every write is refused | A local stdio process without a token is read-only by design. Give it the workspace token (`DELPHI_MCP_TOKEN`), or connect over HTTP with the Bearer. |
