# -*- coding: utf-8 -*-
"""E2E battery for v0.88.0-beta - token-scoped workspaces ([Workspace.*]).

The secret decides the jail, not the self-declared agent name: each
[Workspace.<name>] section carries its own Token (read-write inside its
Roots), optional ReadOnlyToken, and optional Profile. HARD boundary by
operator decision (2026-08-28): other workspaces' roots are not even
READABLE. The operator is just the widest workspace (v0.91: workspace o nada).

Overlap is deliberate and must never subtract: here Workspace.Ancho holds a
whole tree and Workspace.Fino holds a THIRD-LEVEL subfolder of that same
tree (the operator's exact case). Ancho still sees the subfolder; Fino never
leaves it.

  W1  wrong token: 401
  W2  Fino (subfolder root): writes inside; write AND read outside -> refused
  W3  Ancho: writes its whole tree INCLUDING Fino's subfolder (no subtraction),
      but not the operator's area outside its root
  W4  operator token: everything, as always
  W5  per-workspace ReadOnlyToken: reads inside its roots, cannot write
  W6  per-workspace Profile=reader trims that token's tools/list only

Usage:  python tests/test_round23.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round23')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'ws23base')
ANCHO = os.path.join(JAIL, 'ancho')
FINO = os.path.join(ANCHO, 'a', 'b', 'c')          # 3rd-level subfolder of ANCHO
os.makedirs(EXEDIR)
os.makedirs(FINO)
os.makedirs(os.path.join(ANCHO, 'otra'))
open(os.path.join(ANCHO, 'otra', 's.pas'), 'w').write('unit s;\n')
open(os.path.join(FINO, 'dentro.pas'), 'w').write('unit dentro;\n')
open(os.path.join(JAIL, 'fuera.txt'), 'w').write('operador\n')

EXE = mc.copia_exe(EXEDIR)
OP, TA, TF, TFRO = 'op-token-23', 'tok-ancho-23', 'tok-fino-23', 'tok-fino-ro-23'
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Workspace.Operador]', 'Token=%s' % OP, 'Roots=%s' % JAIL, '',
    '[Workspace]', 'Roots=%s' % JAIL, '',
    '[Workspace.Ancho]', 'Token=%s' % TA, 'Roots=%s' % ANCHO, '',
    '[Workspace.Fino]', 'Token=%s' % TF, 'ReadOnlyToken=%s' % TFRO,
    'Roots=%s' % FINO, 'Profile=reader', '',
]))

PORT = mc.puerto_libre()
# espera a que ESCUCHE (antes un sleep fijo de 2,3 s); solo loopback
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))


def session(token, name):
    cli = mc.Http(PORT, token)
    cli.session(name)
    return cli


try:
    # W1: wrong token -> 401
    st, _, _ = mc.Http(PORT, 'token-malo').post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "x", "version": "1"}}})
    check('W1 token malo: 401', st == 401, st)

    # W2: Fino - a 3rd-level subfolder as its whole world
    sf = session(TF, 'fino')
    r = sf.call('delphi_textedit',
                {'path': os.path.join(FINO, 'mio.txt'), 'create': True, 'content': 'x'})
    check('W2 Fino escribe dentro de su subcarpeta',
          os.path.exists(os.path.join(FINO, 'mio.txt')), r[:160])
    r = sf.call('delphi_textedit',
                {'path': os.path.join(ANCHO, 'hack.txt'), 'create': True, 'content': 'x'})
    check('W2 Fino NO escribe fuera (un nivel arriba)',
          'RECHAZADO' in r and not os.path.exists(os.path.join(ANCHO, 'hack.txt')), r[:160])
    r = sf.call('delphi_read', {'path': os.path.join(ANCHO, 'otra', 's.pas')})
    check('W2 frontera DURA: Fino ni siquiera LEE fuera de su root',
          'RECHAZADO' in r and 'unit s' not in r, r[:160])
    r = sf.call('delphi_list', {'root': JAIL})
    check('W2 Fino tampoco lista el arbol del operador',
          'RECHAZADO' in r and 'fuera.txt' not in r, r[:160])

    # W3: Ancho - overlap never subtracts
    sa = session(TA, 'ancho')
    r = sa.call('delphi_textedit',
                {'path': os.path.join(FINO, 'de-ancho.txt'), 'create': True, 'content': 'x'})
    check('W3 Ancho SI escribe en la subcarpeta que ademas es root de Fino (el solape no resta)',
          os.path.exists(os.path.join(FINO, 'de-ancho.txt')), r[:160])
    r = sa.call('delphi_textedit',
                {'path': os.path.join(ANCHO, 'suyo.txt'), 'create': True, 'content': 'x'})
    check('W3 Ancho escribe en su arbol', os.path.exists(os.path.join(ANCHO, 'suyo.txt')), r[:160])
    r = sa.call('delphi_read', {'path': os.path.join(JAIL, 'fuera.txt')})
    check('W3 Ancho no sale de su workspace (zona del operador vetada)',
          'RECHAZADO' in r and 'operador' not in r, r[:160])

    # W4: operator token - everything, as always
    so = session(OP, 'operador')
    r = so.call('delphi_read', {'path': os.path.join(FINO, 'dentro.pas')})
    check('W4 operador lee dentro de Fino', 'unit dentro' in r, r[:160])
    r = so.call('delphi_textedit',
                {'path': os.path.join(JAIL, 'op.txt'), 'create': True, 'content': 'x'})
    check('W4 operador escribe en la raiz global', os.path.exists(os.path.join(JAIL, 'op.txt')), r[:160])

    # W5: per-workspace read-only token
    sro = session(TFRO, 'fino-ro')
    r = sro.call('delphi_read', {'path': os.path.join(FINO, 'dentro.pas')})
    check('W5 token RO del workspace lee dentro', 'unit dentro' in r, r[:160])
    r = sro.call('delphi_textedit',
                 {'path': os.path.join(FINO, 'ro.txt'), 'create': True, 'content': 'x'})
    # el rechazo CONCRETO del modo lectura, y el fichero sin crear (antes
    # bastaba con que no existiera: un timeout o cualquier error pasaban)
    check('W5 token RO no escribe ni dentro',
          r.startswith('RECHAZADO') and 'SOLO LECTURA' in r and
          not os.path.exists(os.path.join(FINO, 'ro.txt')), r[:160])
    r = sro.call('delphi_read', {'path': os.path.join(ANCHO, 'otra', 's.pas')})
    check('W5 token RO tampoco lee fuera de sus roots', 'RECHAZADO' in r, r[:160])

    # W6: per-workspace Profile trims only that token's listing
    names_f = sf.toolnames()
    names_a = sa.toolnames()
    check('W6 Profile=reader del workspace Fino recorta SU tools/list',
          'delphi_edit' not in names_f and 'delphi_read' in names_f and
          len(names_f) < len(names_a), (len(names_f), len(names_a)))
    check('W6 Ancho (sin Profile) sigue viendo el censo completo',
          'delphi_edit' in names_a and 'delphi_build' in names_a, len(names_a))
finally:
    proc.kill()

mc.fin('round-23 battery')
