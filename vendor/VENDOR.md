Vendored from https://github.com/gdksoftware/delphi-mcp-server
Upstream commit: 4e98e3b032d5df57cd8f78450f4442e9189e26df
License: MIT (see LICENSE)
Local changes:
- Example .dpr/.dproj removed; example tools not referenced by our server.
- MCPServer.IdHTTPServer.pas: USE_TAURUS_TLS define disabled (standard Indy
  SSL - no TaurusTLS dependency; SSL remains off by default), and two-tier
  Bearer auth added: AuthToken (full read-write), ReadOnlyToken (read-only)
  and AnonymousReadOnly (tokenless requests get read-only). When any token is
  configured, everything else gets 401. An OnAccessLevel callback fires on
  every accepted request so the host can flag the worker thread's access
  level (Indy reuses threads). An OnParseAuthentication handler accepts the
  Bearer scheme (stock Indy answers 401 "Unsupported authorization scheme"
  on its own otherwise). All marked "[local change]".
- MCPServer.ToolsManager.pas: optional class-var ToolGate callback consulted
  before ANY tool executes (single entry gate); when it returns a non-empty
  string, that message is returned to the client instead of running the tool.
  The access policy itself lives host-side (Lsp.Guard). Marked
  "[local change]".
