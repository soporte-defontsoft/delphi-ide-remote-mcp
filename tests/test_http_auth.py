"""E2E battery for the --http host: Streamable HTTP + Bearer auth.

Usage:  python tests/test_http_auth.py [path-to-DelphiLspMcp.exe]
Exit code 0 = all green.
"""
import json, subprocess, time, os, sys, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, '..', 'src', 'Win64', 'Debug', 'DelphiLspMcp.exe')
PORT = 3999
URL = 'http://127.0.0.1:%d/mcp' % PORT
TOKEN = 'test-token-123'

env = dict(os.environ)
env['DELPHI_MCP_TOKEN'] = TOKEN
proc = subprocess.Popen([EXE, '--http', str(PORT)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)

P = F = 0
def check(name, cond, detail=''):
    global P, F
    if cond:
        P += 1
        print('PASS -', name)
    else:
        F += 1
        print('FAIL -', name, '|', str(detail)[:170])

def post(payload, token=None):
    req = urllib.request.Request(URL, json.dumps(payload).encode('utf-8'),
        {'Content-Type': 'application/json', 'Accept': 'application/json'})
    if token:
        req.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8', 'replace')

INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "http-battery", "version": "1"}}}

try:
    code, body = post(INIT)
    check('http: sin token -> 401', code == 401, '%s %s' % (code, body[:100]))
    code, body = post(INIT, 'wrong-token')
    check('http: token erroneo -> 401', code == 401, '%s %s' % (code, body[:100]))
    code, body = post(INIT, TOKEN)
    ok = code == 200 and 'delphi-lsp-mcp-service' in body
    check('http: initialize con token', ok, '%s %s' % (code, body[:150]))

    code, body = post({"jsonrpc": "2.0", "id": 2, "method": "tools/list",
                       "params": {}}, TOKEN)
    try:
        names = sorted(t['name'] for t in json.loads(body)['result']['tools'])
    except Exception:
        names = []
    expected = ['delphi_build', 'delphi_completion', 'delphi_definition',
                'delphi_diagnostics', 'delphi_edit', 'delphi_git',
                'delphi_hover', 'delphi_list', 'delphi_read',
                'delphi_references', 'delphi_search', 'delphi_symbols']
    check('http: tools/list = 12 tools', names == expected, names)

    code, body = post({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": "delphi_list",
                   "arguments": {"root": os.path.join(HERE, '..', 'src'),
                                  "pattern": "*.pas"}}}, TOKEN)
    check('http: tools/call funciona', code == 200 and 'Lsp.Patch.pas' in body,
          '%s %s' % (code, body[:150]))
finally:
    proc.kill()

print()
print('== http battery: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
