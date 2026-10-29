# -*- coding: utf-8 -*-
"""V161/V162 (1.23.1): CORS read as the rest of the operator's config.

V162 - [CORS] AllowedOrigins was split with TStringList.CommaText (comma AND
whitespace, not ';') and matched with an exact SameText loop whose only wildcard
was a lone exact '*': AllowedOrigins=http://a;http://b was ONE entry, so every
Origin got 403. It now uses EntradasDeLista + NombreEnLaLista (the V128 reader),
which split on ';'/',' and honour the '*' wildcard.

V161 - [CORS] Enabled read an ILLEGIBLE value (a typo) as the OPEN side (off, no
Origin validation), while V110 promises the closed side. The closed side of CORS
is ON (validate the Origin); an illegible value now reads as True.

  C1 Enabled=1, AllowedOrigins=http://a;http://b, Origin http://b -> allowed
     (not 403). RED against 06f59ce (403: ';' not a separator)
  C2 (control) Enabled=1, same list, a foreign Origin -> 403
  C3 Enabled=ture (illegible), AllowedOrigins=http://localhost, foreign Origin
     -> 403 (illegible read as the closed side = validate). RED against 06f59ce
     (processed: illegible read as off)

Each uses its OWN settings.ini in the battery folder; the production one is
never touched.

Usage:  python tests/test_cors_v161_v162.py [path-to-DelphiLspMcp.exe]
"""
import os, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
TOKEN = 'bateria-workspace'
INIT = {"jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "b", "version": "1"}}}


def instancia(etiqueta, cors):
    base = mc.carpeta(os.path.join('cors_v161_v162', etiqueta))
    exe = mc.copia_exe(base, src=exe_src)
    port = mc.puerto_libre()
    with open(os.path.join(base, 'settings.ini'), 'w') as f:
        f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n\n%s' % (TOKEN, base, cors))
    proc = mc.lanza_http(exe, port, mc.entorno({'DELPHI_MCP_ROOTS': base,
                                                'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
    return base, port, proc


def post_origin(port, origin):
    code, _, body = mc.post('http://127.0.0.1:%d/mcp' % port, INIT, TOKEN,
                            accept='application/json', cabeceras={'Origin': origin})
    return code, body


# --- V162: AllowedOrigins separada por ';' ---
base, port, proc = instancia('v162', '[CORS]\nEnabled=1\nAllowedOrigins=http://a;http://b\n')
try:
    code, body = post_origin(port, 'http://b')
    check('C1 (V162) AllowedOrigins con ; : un Origin de la lista (http://b) se admite, no 403',
          code != 403, '%s %s' % (code, body[:120]))
    code, body = post_origin(port, 'http://evil.example')
    check('C2 control: un Origin que NO esta en la lista -> 403',
          code == 403, '%s %s' % (code, body[:120]))
finally:
    proc.kill()

# --- V161: Enabled ilegible -> lado cerrado = validar ---
base, port, proc = instancia('v161', '[CORS]\nEnabled=ture\nAllowedOrigins=http://localhost\n')
try:
    code, body = post_origin(port, 'http://evil.example')
    check('C3 (V161) [CORS] Enabled ilegible se lee CERRADO (valida el Origin): un Origin ajeno -> 403',
          code == 403, '%s %s' % (code, body[:120]))
finally:
    proc.kill()

mc.fin('V161/V162 CORS battery')
