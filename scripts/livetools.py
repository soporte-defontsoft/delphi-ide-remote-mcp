# -*- coding: utf-8 -*-
"""El tools/list VIVO del exe, para los generadores de docs (CAPABILITIES.json,
los bloques de contrato de TOOLS.md). Arranca el exe en stdio con un vault de
mentira y escribible (para que las cinco vault_* se registren y la superficie
sea completa), pide initialize + tools/list y lo mata. No deja nada en el
%TEMP% de la maquina (26-sep-2026). Estaba dentro de gen-capabilities.py; a la
segunda (tools_md.py), helper."""
import json, os, queue, shutil, subprocess, tempfile, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE_DEFECTO = os.path.join(REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')


def tools_list(exe=None):
    """(version, tools): la version del serverInfo y la lista de tools/list tal
    como la da el exe (nombre, description, inputSchema...)."""
    src = exe or EXE_DEFECTO
    base = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'gencap')
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    try:
        copia = os.path.join(base, 'DelphiLspMcp.exe')
        shutil.copy(src, copia)
        vault = os.path.join(base, 'vault')
        os.makedirs(vault)
        open(os.path.join(vault, 'MEMORY.md'), 'w').write('# MEMORY\n')
        env = dict(os.environ)
        env['DELPHI_MCP_ROOTS'] = base
        env['DELPHI_MCP_VAULT_PATH'] = vault
        env['DELPHI_MCP_VAULT_READONLY'] = '0'  # full surface: the 3 write tools too
        proc = subprocess.Popen([copia], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
        q = queue.Queue()

        def reader():
            for line in proc.stdout:
                line = line.strip()
                if line:
                    q.put(line)
        threading.Thread(target=reader, daemon=True).start()

        def send(o):
            proc.stdin.write(json.dumps(o) + '\n')
            proc.stdin.flush()

        def recv(r, t=60):
            dl = time.time() + t
            while time.time() < dl:
                try:
                    line = q.get(timeout=1)
                except queue.Empty:
                    continue
                try:
                    m = json.loads(line)
                except Exception:
                    continue
                if m.get('id') == r:
                    return m
            return None

        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "gencap", "version": "1"}}})
        version = recv(1)['result']['serverInfo']['version']
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = recv(2)['result']['tools']
        proc.kill()
        proc.wait(timeout=10)
        return version, tools
    finally:
        # y no se deja nada en el %TEMP% de la maquina: la copia del exe y el
        # vault de mentira se quedaban en delphi-mcp-tests\gencap (26-sep-2026)
        shutil.rmtree(base, ignore_errors=True)
        try:
            os.rmdir(os.path.dirname(base))  # la raiz de las baterias, si queda vacia
        except OSError:
            pass
