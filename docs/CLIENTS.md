# Connecting MCP clients

MCP is a standard: **no client-side code is needed**, only configuration. Any
MCP-capable agent can use this server. Two transports:

- **stdio** — the client spawns `DelphiLspMcp.exe` on the same Windows machine.
- **Streamable HTTP** — the server runs resident on the Windows machine
  (as a Windows Service, `DelphiLspMcp --http 3000`, or `DelphiLspMcp -gui`) and clients
  connect from anywhere (Linux included) with the Bearer token.

For remote use, configure a `[Workspace.<name>]` section in `settings.ini`
next to the exe (see README): its `Token=` is the credential and its `Roots=`
the jail - nothing is global since v0.98. The listen
port is `[Server] Port` in the same file (default 3000; a `--http <port>`
argument overrides it for that run) — the `3000` in the examples below is
whatever you configured.

Reviewer agents (read but never modify) can be given the workspace's
`ReadOnlyToken=` instead of its full token — same configuration snippets,
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

Every `delphi_fetch` answer carries a `download` link (`GET /files?path=...`
on the same host, with the same Bearer token) and the response comes with an
`X-File-SHA256` header to verify the bytes. A big file is one `curl`, however
large — use the `download` value verbatim:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" -o C:/dest/file.zip "<download link>"
```

The base64 chunks inline in the tool result remain for small files, or for
clients that have no shell to run `curl` from. Files over 1 MB answer with the
link only, unless `maxbytes<=1048576` is passed to force chunks.

Recommended flow for binaries: `delphi_build` (the result names the artifact
in `output`) → `delphi_package` (zip, compressed, dcu excluded) →
`delphi_fetch` the zip → `curl` its `download` link.

## Several Delphi servers: one entry per server

A server works with ONE RAD Studio (README: *One server, one Delphi*). Two
versions on one Windows machine are two servers, each one on its own port with
its own tokens - and the same version can also run on SEVERAL machines (13.1 on
the workstation, 13.2 on a VM, 13.2 again on a second VM). The client gets one
entry per server; name each one after its MACHINE and its version, never after
the version alone:

```bash
claude mcp add --transport http delphi-pc-13.1 http://WORKSTATION:3131/mcp \
  --header "Authorization: Bearer TOKEN_OF_THAT_SERVER"
claude mcp add --transport http delphi-pc-12 http://WORKSTATION:3132/mcp \
  --header "Authorization: Bearer TOKEN_OF_THAT_SERVER"
claude mcp add --transport http delphi-vm1-13.2 http://VM1:3131/mcp \
  --header "Authorization: Bearer TOKEN_OF_THAT_SERVER"
```

The entry name is only your label. What each server IS comes from
`delphi_workspace` on it: `activeDelphiName` ("RAD Studio 13"),
`activeDelphiBuild`, `delphiUpdate` and `server.host` (the machine). RAD
Studio 13.1 and 13.2 are both "RAD Studio 13" and BDS 37.0; `delphiUpdate`
is the update the server's operator declares (`[Server] DelphiUpdate=13.2`),
and the build is the exact one (37.0.59082.x here, 37.0.60952.x on the 13.2
VM).

## Any other MCP client (Hermes, custom agents, SDKs)

- **stdio**: spawn `DelphiLspMcp.exe`; JSON-RPC 2.0, one message per line,
  MCP protocol `2025-06-18`. Logs go to stderr, protocol to stdout.
- **HTTP**: POST JSON-RPC to `http://HOST:PORT/mcp` with
  `Authorization: Bearer <token>` and `Accept: application/json`.
  `initialize` → `notifications/initialized` → `tools/list` / `tools/call`.

The test batteries under `tests/` are minimal working MCP clients in plain
Python stdlib — use them as reference implementations for both transports.
