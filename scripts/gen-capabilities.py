#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genera docs/CAPABILITIES.json desde el registro REAL de tools del exe.

Se ejecuta tras cada release (o cuando cambie el juego de tools):

    python scripts/gen-capabilities.py [ruta-al-DelphiLspMcp.exe]

Arranca el exe en stdio con un vault de mentira (para que las vault_* se
registren y el manifiesto refleje la superficie completa), pide tools/list y
escribe el manifiesto. tests/test_docs_consistency.py falla si el manifiesto
o el README divergen de la realidad.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
# el tools/list vivo lo trae livetools (el mismo que usa scripts/tools_md.py)
sys.path.insert(0, HERE)
from livetools import tools_list
version, lista = tools_list(sys.argv[1] if len(sys.argv) > 1 else None)
tools = sorted(t['name'] for t in lista)

vault_tools = [t for t in tools if t.startswith('vault_')]
lsp_backed = ['delphi_symbols', 'delphi_definition', 'delphi_hover',
              'delphi_completion', 'delphi_signature', 'delphi_diagnostics',
              'delphi_references', 'delphi_rename_symbol']
manifest = {
    "generatedBy": "scripts/gen-capabilities.py (from the live tools/list)",
    "version": version,
    "tools": len(tools),
    "coreTools": len(tools) - len(vault_tools),
    "optionalTools": len(vault_tools),
    "toolNames": tools,
    "optionalToolNames": vault_tools,
    # what a read-only credential may call, from the server's own access
    # table (tools/list _meta.access): read-only | read-write | mixed
    "access": {t['name']: (t.get('_meta') or {}).get('access') for t in sorted(lista, key=lambda t: t['name'])},
    "lspBacked": lsp_backed,
    "engines": {
        "semantics": "DelphiLSP.exe (Embarcadero, kept warm per workspace)",
        "build": "MSBuild via rsvars.bat",
        "deploy": "paclient.exe (PAServer) / adb",
        "editing": "anchor-based safe editing engine (encoding/EOL preserved)"
    },
    "security": {
        "workspaceJail": "[Workspace.<name>] Roots / DELPHI_MCP_ROOTS",
        "credentials": "Token (read-write) / ReadOnlyToken, per workspace; no token, no access",
        "execution": "AllowTests / AllowBuildScripts / AllowRemoteRun (all off by default; nothing else runs on the server)",
        "remoteRunScope": "RemoteRunProjects (empty = nothing; all/* = every project of the jail; McpDesktopNode = delphi_desktop may see and type on a target's desktop)",
        "libraryZone": "LibraryZone=1 opens the read zone; absent = off"
    }
}
out = os.path.join(REPO, 'docs', 'CAPABILITIES.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('escrito %s: %d tools (v%s)' % (out, len(tools), version))
