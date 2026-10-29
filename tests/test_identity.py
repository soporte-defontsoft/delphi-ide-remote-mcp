"""E2E battery for v0.68.0-beta - per-session agent identity.

The operator asked for two things at once: that each agent purge ITS OWN trash
without touching another's, and whether agents can be made to identify
themselves on the handshake and on requests. They are the same question.

The answer here is two-phase, over HTTP: the SHARED Bearer token is the door;
then the handshake's clientInfo.name is bound to the Mcp-Session-Id the server
issues - a secret it generated and the client echoes on every request. So the
name is fixed at connect time and cannot be re-declared per call: to be taken
for another agent you would have to steal their session id.

  I1  the mailbox knows who you are without you typing your id
  I2  a trashed item is tagged with who trashed it
  I3  one agent cannot purge another's copy; it can purge its own
  I4  an HTTP session with no name is NOT the operator: it has its own
      identity and cannot purge another agent's copy (V111 of 1.23.1, David:
      "identidad propia"; it was trusted with anyone's trash)
  I5  the operator (stdio with no name) is still trusted with anyone's trash
  I6  a request with NO session at all (no Mcp-Session-Id, no initialize) is
      NOT the operator either: its own identity, so it cannot purge another
      agent's copy - the hole V111 left for a header-less request (V159 of
      1.23.1, measured; server/discover is a real header-less probe, so a 400
      would break it - the fix is its own identity, never the empty one)

Usage:  python tests/test_identity.py [path-to-DelphiLspMcp.exe]
"""
import os, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('identity')
EXE = mc.copia_exe(BASE)
for name in ('a.txt', 'b.txt', 'c.txt'):
    open(os.path.join(BASE, name), 'w').write(name)

PORT = mc.puerto_libre()
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE,
                  'DELPHI_MCP_BIND_IP': '127.0.0.1'})  # loopback: sin avisos del firewall
# v0.98: o workspace o nada - la bateria presenta su token
TOKEN = 'bateria-workspace'
with open(os.path.join(BASE, 'settings.ini'), 'w') as _f:
    _f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
proc = mc.lanza_http(EXE, PORT, env)
# un cliente, una SESION por agente: la identidad va atada al Mcp-Session-Id,
# y cada llamada dice con cual habla (sid=)
cli = mc.Http(PORT, TOKEN)


def trashed(name):
    return mc.copias(BASE, name, 'CAJON_BORRADOS')


def sin_cabecera(cli, name, args):
    """Un tools/call por HTTP SIN la cabecera Mcp-Session-Id y sin initialize
    (sid=None): el hueco de V159. Devuelve el texto de la tool, como
    cli.call()."""
    body = {"jsonrpc": "2.0", "id": 777, "method": "tools/call",
            "params": {"name": name, "arguments": args}}
    _st, _h, raw = mc.post(cli.url, body, cli.token, sid=None)
    return mc.texto(next((m for m in mc.Http.mensajes(raw) if m.get('id') == 777), None))


try:
    alice = cli.session('alice')
    bob = cli.session('bob')
    # sid=None volveria a la ULTIMA sesion del cliente (la de bob): sin dos
    # sesiones distintas de verdad, I3 mediria a bob contra si mismo
    assert alice and bob and alice != bob, (alice, bob)

    # I1
    r = cli.call('delphi_messages', {'command': 'check'}, sid=alice)
    check('I1 el buzon usa tu identidad sin que la teclees',
          'alice' in r, r[:150])

    # I2
    cli.call('delphi_delete', {'path': os.path.join(BASE, 'a.txt')}, sid=alice)
    ca = trashed('a.txt')
    check('I2 la copia lleva marcador de quien la borro',
          bool(ca) and os.path.exists(mc.marca_dueno(ca[0])) and
          open(mc.marca_dueno(ca[0])).read().strip().endswith('alice'), ca)

    # I3
    r = cli.call('delphi_delete', {'path': ca[0], 'purge': True}, sid=bob)
    check('I3 otro agente NO puede purgar tu copia',
          mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_NOT_YOURS_FMT') and 'alice' in r and os.path.exists(ca[0]), r[:200])
    r = cli.call('delphi_delete', {'path': ca[0], 'purge': True}, sid=alice)
    check('I3 pero tu SI purgas la tuya',
          mc.abre(r, 'SN_FILE_PURGED_FMT') and not os.path.exists(ca[0]), r[:150])

    # I4 - una sesion HTTP SIN nombre ya no es el operador (V111 de la 1.23.1):
    # era la identidad vacia y purgaba la papelera de todos; ahora tiene la suya
    cli.call('delphi_delete', {'path': os.path.join(BASE, 'b.txt')}, sid=bob)
    cb = trashed('b.txt')
    anon = cli.session('')  # no clientInfo.name
    assert anon and anon not in (alice, bob), anon
    r = cli.call('delphi_delete', {'path': cb[0], 'purge': True}, sid=anon)
    check('I4 una sesion HTTP sin nombre NO purga la copia de otro: tiene su identidad propia',
          mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_NOT_YOURS_FMT') and 'bob' in r and os.path.exists(cb[0]),
          r[:200])

    # I6 - una peticion HTTP SIN la cabecera Mcp-Session-Id (ni initialize)
    # caia en la identidad VACIA, la del operador, y purgaba la papelera de
    # cualquiera, tambien en produccion (sin confinamiento). Ahora tiene la
    # suya. cb[0] sigue ahi tras I4 (denegado).
    r = sin_cabecera(cli, 'delphi_delete', {'path': cb[0], 'purge': True})
    check('I6 una peticion sin Mcp-Session-Id NO es el operador: no purga la copia de bob',
          mc.rechazado(r) and mc.es(r, 'SR_FILE_PURGE_NOT_YOURS_FMT') and 'bob' in r and os.path.exists(cb[0]),
          r[:200])
finally:
    proc.kill()

# I5 - el operador de verdad (stdio, un proceso, sin nombre) si: su propia copia
# del exe (sin el settings.ini del workspace de arriba) con las mismas raices
STDIO = os.path.join(BASE, 'stdio')
srv = mc.Stdio(mc.copia_exe(STDIO), mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='')
try:
    r = srv.call('delphi_delete', {'path': cb[0], 'purge': True})
    check('I5 el operador (stdio sin nombre) purga cualquier copia',
          mc.abre(r, 'SN_FILE_PURGED_FMT') and not os.path.exists(cb[0]), r[:150])
finally:
    srv.mata()

mc.fin('identity battery')
