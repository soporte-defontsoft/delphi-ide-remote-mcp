Vendored from https://github.com/gdksoftware/delphi-mcp-server
Upstream commit: 4e98e3b032d5df57cd8f78450f4442e9189e26df
License: MIT (see LICENSE)
Local changes (each marked "[local change]" in the code, most with its date):
- Example .dpr/.dproj removed; example tools not referenced by our server.
- src/Core/MCPServer.Logger.pas: secret values ("password", "passkey",
  "passfile", "token") masked in logged request bodies (MaskSecretValues);
  console output that fails (stderr closed, no console) switches console
  logging off instead of crashing; the log file is flushed after every line.
- src/Core/MCPServer.Registration.pas: an unknown resource URI raises
  ERecursoNoExiste (-32002); messages from the host's catalog (Lsp.Texts).
- src/Core/MCPServer.Settings.pas: MachineName, reported as serverInfo.host.
- src/Managers/MCPServer.CoreManager.pas: hooks for the host's
  "instructions" and "prompts" capability; the session id is local to each
  initialize (a shared field gave two concurrent clients the same id);
  clientInfo read only as an object, its name through the shared text
  reader; the client name bound to the new session and thread
  (Lsp.Identidad); serverInfo.host.
- src/Managers/MCPServer.ResourcesManager.pas: resources/read reads "uri"
  through the shared text reader and refuses a missing, null or non-text
  one; an unknown URI is -32002, not a success with the error inside.
- src/Managers/MCPServer.ToolsManager.pas: host callbacks around every tool -
  ToolGate (one entry gate before any tool runs; the policy lives host-side,
  Lsp.Guard), ResultFilter (rewrites every textual result and denial:
  virtual drive units), ResultWrapper (the text plus attached images as a
  content array), ListFilter (hides tools from tools/list; they stay
  callable), ToolDecorator (annotations, _meta); one outcome reader (the
  label that opens a message, or a JSON object's "error"); structuredContent
  with {ok, code} (a JSON result becomes it; prose publishes none except on
  failure; jail answers are always DENIED); malformed or non-object
  "arguments" refused naming what arrived; a caller's EArgumentException
  returned as a refusal, other exceptions wrapped keeping their own outcome;
  messages from the catalog.
- src/Protocol/MCPServer.JsonRpcProcessor.pas: error codes chosen by the
  exception's class (EMetodoNoExiste -32601, ERecursoNoExiste -32002), never
  by its text; ErrorParaElCuerpo (the error for a raw body, with its own id)
  and NoSeContesta (one rule for "no reply": notifications and client
  responses), shared by HTTP and stdio; bad requests sorted into -32700 and
  -32600 with their label; a non-integer numeric id no longer raises; a
  request whose method returns nothing gets "result": {}; messages from the
  catalog.
- src/Protocol/MCPServer.Schema.Generator.pas: GetPropertyJsonName (trailing
  underscores stripped: ClassName_ publishes as classname) and
  IsRequiredProperty public, and a property is required only with
  [Required] (upstream made every parameter mandatory); [SchemaDefault]
  emitted typed; integers published as "integer" with "minimum": 0, as the
  binder takes them; AceptaJsonComoTexto, the one reader of [JsonComoTexto]:
  such a string parameter is published as an array of objects (its text form
  is still accepted).
- src/Protocol/MCPServer.Serializer.pas: NormalizeKey, MotivoEntero and
  MotivoBooleano public (one integer and one boolean rule, also for values
  inside a parameter); an unknown parameter reported with the published
  names; a missing or null [Required] parameter refused by its name; a JSON
  object or array for a string parameter refused unless [JsonComoTexto];
  null means "not provided"; unparsable numbers and booleans refused
  instead of turned into 0/False; messages from the catalog.
- src/Protocol/MCPServer.Types.pas: RequiredAttribute (parameters are
  optional by default), SchemaDefaultAttribute, and BearerToken, the one
  reader of a Bearer header (scheme case-insensitive).
- src/Server/MCPServer.IdHTTPServer.pas: USE_TAURUS_TLS disabled (standard
  Indy SSL, no TaurusTLS dependency; SSL off by default); two-tier Bearer
  auth (AuthToken read-write, ReadOnlyToken, AnonymousReadOnly; with any
  token configured everything else gets 401; OPTIONS exempt; OnAccessLevel
  on every request) or the host's OnAuthorize, which knows the per-workspace
  tokens; the Bearer scheme accepted (HandleParseAuthentication); a JSON 401
  with a hint; BindIP; a port that cannot be bound is named; FilesRoute /
  OnFileRequest for direct downloads behind the same gate; session ids
  checked against the host's registry (an unknown, expired or evicted id
  gets 404 -32001 with the request's id, on POST and GET); the handshake
  recognized by its "method"; the client name bound to the new session; one
  helper that announces the session id; body-less responses with
  ContentLength 0; 202 by the processor's NoSeContesta; a GET for an SSE
  stream gets 405; request bodies logged masked; the thread runs as the
  session's identity. It uses the host units Lsp.Identidad, Lsp.Texts and
  Lsp.Settings.
- src/Server/MCPServer.StdioTransport.pas: stdin and stdout set to UTF-8
  (accents arrived as mojibake); lines logged masked; error responses with
  the request's id and a labelled message.
- src/Tools/MCPServer.Tool.Base.pas (marked "LOCAL PATCH"): IMCPToolParams
  (ParamsClass), so the host's gate reads the attributes of a tool's
  parameter class.
