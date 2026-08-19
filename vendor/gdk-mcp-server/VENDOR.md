Vendored from https://github.com/gdksoftware/delphi-mcp-server
Upstream commit: 4e98e3b032d5df57cd8f78450f4442e9189e26df
License: MIT (see LICENSE)
Local changes:
- Example .dpr/.dproj removed; example tools not referenced by our server.
- MCPServer.IdHTTPServer.pas: USE_TAURUS_TLS define disabled (standard Indy
  SSL - no TaurusTLS dependency; SSL remains off by default), and an optional
  AuthToken property added: when set, every non-OPTIONS request must carry
  "Authorization: Bearer <token>" or gets 401. An OnParseAuthentication
  handler accepts the Bearer scheme (stock Indy answers 401 "Unsupported
  authorization scheme" on its own otherwise). All marked "[local change]".
