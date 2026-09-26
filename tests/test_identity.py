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
  I4  an agent with no name (or the operator) is trusted with anyone's trash

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
    return [x for x in glob.glob(os.path.join(BASE, '__delphi-patch', '*', 'deleted', name + '-*'))
            if not x.endswith('.by')]


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
          bool(ca) and os.path.exists(ca[0] + '.by') and
          open(ca[0] + '.by').read().strip().endswith('alice'), ca)

    # I3
    r = cli.call('delphi_delete', {'path': ca[0], 'purge': True}, sid=bob)
    check('I3 otro agente NO puede purgar tu copia',
          'RECHAZADO' in r and 'alice' in r and os.path.exists(ca[0]), r[:200])
    r = cli.call('delphi_delete', {'path': ca[0], 'purge': True}, sid=alice)
    check('I3 pero tu SI purgas la tuya',
          'PURGADO' in r and not os.path.exists(ca[0]), r[:150])

    # I4 - a session with no name is trusted with anyone's trash
    cli.call('delphi_delete', {'path': os.path.join(BASE, 'b.txt')}, sid=bob)
    cb = trashed('b.txt')
    anon = cli.session('')  # no clientInfo.name
    assert anon and anon not in (alice, bob), anon
    r = cli.call('delphi_delete', {'path': cb[0], 'purge': True}, sid=anon)
    check('I4 una sesion sin nombre (operador) purga cualquier copia',
          'PURGADO' in r and not os.path.exists(cb[0]), r[:150])
finally:
    proc.kill()

mc.fin('identity battery')
