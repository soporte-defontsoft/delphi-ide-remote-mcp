# Connecting MCP clients

MCP is a standard: **no client-side code is needed**, only configuration. Any
MCP-capable agent can use this server. Two transports:

- **stdio** — the client spawns `DelphiLspMcp.exe` on the same Windows machine.
- **Streamable HTTP** — the server runs resident on the Windows machine
  (`DelphiLspMcp --http 3000` or the `DelphiLspMcpTray` tray app) and clients
  connect from anywhere (Linux included) with the Bearer token.

For remote use, configure BOTH security knobs in `settings.ini` next to the
exe (see README): `[Security] AuthToken` and `[Workspace] Roots`. The listen
port is `[Server] Port` in the same file (default 3000; a `--http <port>`
argument overrides it for that run) — the `3000` in the examples below is
whatever you configured.

Reviewer agents (read but never modify) can be given `[Security]
ReadOnlyToken` instead of the full token — same configuration snippets,
different Bearer value. See the README's Configuration section.

## Claude Code

```bash
# local (stdio), on the Windows machine:
claude mcp add delphi -- C:/path/to/DelphiLspMcp.exe

# remote (HTTP), from any machine:
claude mcp add --transport http delphi http://WINDOWS-HOST:3000/mcp \
  --header "Authorization: Bearer YOUR_TOKEN"
```

## Claude Desktop

`claude_desktop_config.json` (Settings > Developer > Edit Config):

```json
{
  "mcpServers": {
    "delphi": {
      "command": "C:\\path\\to\\DelphiLspMcp.exe"
    }
  }
}
```

For remote HTTP, add the server from Settings > Connectors with the URL
`http://WINDOWS-HOST:3000/mcp` (send the Bearer token as a custom header if
your version supports it, or front the server with a reverse proxy that
injects it).

## OpenCode

`opencode.json` (or the global config):

```json
{
  "mcp": {
    "delphi-local": {
      "type": "local",
      "command": ["C:/path/to/DelphiLspMcp.exe"],
      "enabled": true
    },
    "delphi-remote": {
      "type": "remote",
      "url": "http://WINDOWS-HOST:3000/mcp",
      "headers": { "Authorization": "Bearer YOUR_TOKEN" },
      "enabled": true
    }
  }
}
```

(Exact schema may vary between OpenCode versions — check `opencode mcp` docs.)

### Downloading build output through OpenCode (`delphi_fetch`)

`delphi_fetch` returns each chunk as base64 inside the tool result — an 8 MB
chunk is ~11 MB of JSON text. OpenCode truncates tool output that large in
the conversation, but **saves the full result to a local file** and prints
its path (`Full output saved to: ...\tool-output\tool_...`). That spool file
IS the transport — parse it instead of re-fetching with smaller chunks:

```powershell
$json = Get-Content -Raw "C:\Users\YOU\.local\share\opencode\tool-output\tool_XXXX" | ConvertFrom-Json
[IO.File]::WriteAllBytes("C:\dest\file.zip", [Convert]::FromBase64String($json.chunkBase64))
(Get-FileHash -Algorithm SHA256 "C:\dest\file.zip").Hash  # compare with $json.sha256
```

Recommended flow for binaries: `delphi_build` (the result names the artifact
in `output`) → `delphi_package` (zip, compressed, dcu excluded) →
`delphi_fetch` the zip — it is usually a single chunk. Loop `offset` until
`eof:true` for anything bigger, appending each decoded chunk.

## Any other MCP client (Hermes, custom agents, SDKs)

- **stdio**: spawn `DelphiLspMcp.exe`; JSON-RPC 2.0, one message per line,
  MCP protocol `2025-06-18`. Logs go to stderr, protocol to stdout.
- **HTTP**: POST JSON-RPC to `http://HOST:PORT/mcp` with
  `Authorization: Bearer <token>` and `Accept: application/json`.
  `initialize` → `notifications/initialized` → `tools/list` / `tools/call`.

The test batteries under `tests/` are minimal working MCP clients in plain
Python stdlib — use them as reference implementations for both transports.
