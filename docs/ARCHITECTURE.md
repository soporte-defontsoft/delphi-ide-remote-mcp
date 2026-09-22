# Architecture

## Overview

```
                     ┌───────────────────────────────────┐
  Claude Code ───────┤  HTTP (MCP Streamable)            │
  Claude Desktop ────┤                                   │
  other MCP client ──┤   Delphi IDE Remote MCP Server    │
                     │  ┌─────────────────────────────┐  │
   (no switch =      │  │ MCP layer (tools, routing)  │  │
    stdio, for       │  ├─────────────────────────────┤  │
    per-session      │  │ Workspace Manager           │  │  one supervised DelphiLSP
    clients)         │  │  spawn / warm / queue       │  │  per workspace, kept alive
                     │  ├─────────────────────────────┤  │  between agent sessions
                     │  │ Config Fabricator           │  │  .dproj → LSP settings when
                     │  │                             │  │  no fresh .delphilsp.json
                     │  ├─────────────────────────────┤  │
                     │  │ LSP Client                  │  │  JSON-RPC framing, retries,
                     │  │                             │  │  encoding-safe didOpen
                     │  └─────────────────────────────┘  │
                     │  Host: service / terminal / tray  │
                     └───────────────┬───────────────────┘
                                     │ stdio (LSP JSON-RPC)
                             ┌───────▼────────┐
                             │ DelphiLSP.exe  │  controller + agent + linter
                             │ (RAD Studio)   │  (same topology the IDE uses)
                             └────────────────┘
```

## Layers

| Layer | Responsibility |
|---|---|
| **MCP layer** | Tool registration/dispatch, MCP handshake, Streamable HTTP + stdio transports |
| **Workspace Manager** | Lifecycle of one DelphiLSP per workspace: spawn on first request, keep warm, request queue (the LSP agent is single-request). LRU eviction, idle shutdown and kill+respawn on hang: planned, not implemented |
| **Config Fabricator** | Locate RAD Studio via registry (newest with DelphiLSP unless the workspace pins `DelphiVersion=`); use project's `.delphilsp.json` if fresh; otherwise generate settings from the `.dproj` (search paths, defines, platform, namespaces) |
| **LSP Client** | `Content-Length` framing over child stdio, request/response correlation, retry with escalating delays (indexing returns `-32800 Request removed`), document sync (`didOpen` with correct encoding) |
| **Host** | ONE executable, three modes of the same core: Windows Service (headless, `-install`), terminal (stdio, or `--http`) and VCL tray (live log). All three share `Lsp.Host`, which builds the managers, the single access gate and its outbound filter — never copied per mode. **The service must log on as the user who owns the IDE** — RAD Studio's configuration lives in `HKEY_CURRENT_USER`, so under `LocalSystem` the server starts and answers with no Library Search Path and no registered packages. See the README and `settings.example.ini`. |

## Why a resident service (and not per-session stdio)

Measured on a real ~12k-line unit: DelphiLSP takes seconds to index after `didOpen` and holds ~550 MB per agent. A per-session stdio MCP pays that cost on **every** agent session. A resident service:

- keeps indexes **warm across sessions** and across multiple concurrent AI clients;
- lets `enableFileWatcher` (default `true`) handle cache invalidation — DelphiLSP refreshes itself on disk changes;
- centralizes resource policy (max workspaces, idle shutdown — planned, not implemented).

Running with no switch (stdio) remains available for clients that cannot speak HTTP; it simply hosts the same core with session lifetime.

## DelphiLSP operating modes (per Embarcadero docs, verified)

- `agent` — single process, language features, **no diagnostics**. Default.
- `linter` — single process, **only** diagnostics (`publishDiagnostics`).
- `controller` + `agentCount=2` — spawns 1 agent + 1 linter and **supervises/replaces them if they die**. Same topology as the IDE. **This is the mode the Workspace Manager uses** — process babysitting comes for free.

## The `references` gap

DelphiLSP does **not** implement `textDocument/references` nor `workspace/symbol` (verified: `-32601 Method not found`). The `delphi_references` tool is therefore a hybrid:

1. Text-scan the workspace for candidate identifier occurrences (respecting Delphi case-insensitivity, skipping IDE artifacts like `__history/`).
2. For each candidate, ask DelphiLSP `definition` at that exact position.
3. Keep only candidates whose definition resolves to the target symbol's location — homonyms are eliminated by the compiler engine itself.

Result quality is compiler-grade; cost is one `definition` round-trip per candidate (batched, cached). A future LSIF-based path (RAD Studio 13 added LSIF generation to the LSP engine) may replace the scan.

## Encoding rules

Legacy Delphi sources are frequently Windows-1252 while LSP mandates UTF-8 JSON. `didOpen` reads: BOM → honor it; no BOM → configurable fallback codepage (default: system ANSI). The LSP client never writes sources back; the editing tools do, through their own engine.

## Build tool

`delphi_build` shells out to MSBuild (`rsvars.bat` located via the same registry discovery) and returns structured compiler output. Compilation is intentionally **not** attempted through the LSP: the protocol has no build operation.

## What this document does not cover

This document describes the LSP core only. The guard gate, the editing engine, MSBuild, the PAServer/adb chain, the desktop node, the run-job launcher and the vault are described in the README and in [TOOLS.md](TOOLS.md).
