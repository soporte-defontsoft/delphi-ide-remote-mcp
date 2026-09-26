# -*- coding: utf-8 -*-
"""E2E battery for v0.89.0-beta - one auth mechanism: workspaces.

Operator decision (2026-09-11, after his own [Workopenclaw]+AuthToken= section
vanished silently and its token answered 401 with no clue anywhere):

  - inside a [Workspace.<name>] section, AuthToken= works as an ALIAS of
    Token= (everyone had typed AuthToken= for years; the hand repeats it);
  - the startup log LISTS the loaded workspaces and WARNS about
    misconfigurations: misspelled sections ([Workopenclaw]), tokenless
    workspaces, unparseable roots. La vieja seccion global de seguridad es
    INERTE desde v0.98: ni autentica, ni avisa, ni existe (A4a/A4b).

  A1  AuthToken= inside a workspace section authenticates (alias)
  A2  a misspelled [Workopenclaw] section: token 401 AND a startup AVISO
      naming the section and the right format
  A3  a tokenless workspace: startup AVISO says IGNORADA and names the key
  A4  startup lists 'Workspaces:' with default (legacy pair) + the sections

Usage:  python tests/test_round24.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess, threading
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round24')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR)
os.makedirs(os.path.join(JAIL, 'alias'))
EXE = mc.copia_exe(EXEDIR)

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Security]', 'AuthToken=op-24', '',
    '[Workspace]', 'Roots=%s' % JAIL, '',
    '[Workspace.Alias]',
    'AuthToken=alias-24',                 # the alias, on purpose
    'Roots=%s' % os.path.join(JAIL, 'alias'), '',
    '[Workopenclaw]',                     # the misspelled section, verbatim
    'Token=perdido-24',
    'Roots=%s' % JAIL, '',
    '[Workspace.SinToken]',               # tokenless: ignored with a warning
    'Roots=%s' % JAIL, '',
]))

PORT = mc.puerto_libre()
# espera a que ESCUCHE (antes un sleep fijo de 2,5 s); solo loopback
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}),
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                     text=True, encoding='utf-8', errors='replace')
# Su salida es lo que miran A2b..A4b: se lee MIENTRAS vive (antes solo tras
# matarlo; una tuberia llena bloquea al servidor en su siguiente linea de log)
salida = []
lector = threading.Thread(target=lambda: salida.extend(proc.stdout), daemon=True)
lector.start()


def init(tok, name):
    """(status HTTP, mensajes) del initialize con ese token: un 401 no lanza."""
    st, _, raw = mc.Http(PORT, tok).post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": name, "version": "1"}}})
    return st, mc.Http.mensajes(raw)


try:
    # A1: the alias authenticates and is jailed to its workspace
    _, m = init('alias-24', 'alias-check')
    check('A1 AuthToken= dentro del workspace autentica (alias de Token=)',
          bool(m and m[0].get('result')), m)

    # A2: the misspelled section's token gets 401
    st, _ = init('perdido-24', 'x')
    check('A2 el token de [Workopenclaw] (mal escrita) da 401', st == 401, st)

    # v0.98: la seccion [Security] del ini es INERTE - ni autentica ni existe
    st, _ = init('op-24', 'op')
    check('A4a un AuthToken en la vieja seccion global es INERTE: 401', st == 401, st)
finally:
    proc.kill()

lector.join(10)
out = ''.join(salida)
check('A2b el arranque AVISA de la seccion mal escrita, por su nombre',
      'Workopenclaw' in out and 'Workspace.<nombre>' in out, out[-400:])
check('A3 el arranque AVISA del workspace sin token (IGNORADA, clave Token=)',
      'SinToken' in out and 'IGNORADA' in out and 'Token=' in out, out[-400:])
check('A4 el arranque LISTA los workspaces (sin ningun "default")',
      'Workspaces:' in out and 'Alias' in out and 'default' not in out, out[-500:])
check('A4b el arranque NO menciona la seccion retirada para nada (v0.98)',
      'Security' not in out, out[-600:])

mc.fin('round-24 battery')
