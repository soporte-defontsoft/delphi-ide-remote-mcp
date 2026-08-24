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
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'gencap')
shutil.rmtree(BASE, ignore_errors=True); os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe'); shutil.copy(SRC, EXE)
VAULT = os.path.join(BASE, 'vault'); os.makedirs(VAULT)
open(os.path.join(VAULT, 'MEMORY.md'), 'w').write('# MEMORY\n')

env = dict(os.environ)
env['DELPHI_MCP_ROOTS'] = BASE
env['DELPHI_MCP_VAULT_PATH'] = VAULT
env['DELPHI_MCP_VAULT_READONLY'] = '0'  # full surface: the 3 write tools too
proc = subprocess.Popen([EXE], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
q = queue.Queue()
def reader():
    for line in proc.stdout:
        line = line.strip()
        if line: q.put(line)
threading.Thread(target=reader, daemon=True).start()
def send(o): proc.stdin.write(json.dumps(o) + '\n'); proc.stdin.flush()
def recv(r, t=60):
    dl = time.time() + t
    while time.time() < dl:
        try: line = q.get(timeout=1)
        except queue.Empty: continue
        try: m = json.loads(line)
        except Exception: continue
        if m.get('id') == r: return m
    return None
send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "gencap", "version": "1"}}})
init = recv(1)
version = init['result']['serverInfo']['version']
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
tools = sorted(t['name'] for t in recv(2)['result']['tools'])
proc.kill()

vault_tools = [t for t in tools if t.startswith('vault_')]
lsp_backed = ['delphi_symbols', 'delphi_definition', 'delphi_hover',
              'delphi_completion', 'delphi_signature', 'delphi_diagnostics',
              'delphi_references']
manifest = {
    "generatedBy": "scripts/gen-capabilities.py (from the live tools/list)",
    "version": version,
    "tools": len(tools),
    "coreTools": len(tools) - len(vault_tools),
    "optionalTools": len(vault_tools),
    "toolNames": tools,
    "optionalToolNames": vault_tools,
    "lspBacked": lsp_backed,
    "engines": {
        "semantics": "DelphiLSP.exe (Embarcadero, kept warm per workspace)",
        "build": "MSBuild via rsvars.bat",
        "deploy": "paclient.exe (PAServer) / adb",
        "editing": "anchor-based safe editing engine (encoding/EOL preserved)"
    },
    "security": {
        "workspaceJail": "[Workspace] Roots / DELPHI_MCP_ROOTS",
        "credentials": "AuthToken (read-write) / ReadOnlyToken / AnonymousReadOnly",
        "execution": "AllowRun / AllowBuildScripts / AllowRemoteRun (all off by default)",
        "remoteRunScope": "RemoteRunProjects (empty = any project of the jail)",
        "libraryZone": "LibraryZone=0 confines reads to the roots"
    }
}
out = os.path.join(REPO, 'docs', 'CAPABILITIES.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('escrito %s: %d tools (v%s)' % (out, len(tools), version))
