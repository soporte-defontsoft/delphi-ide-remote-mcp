"""E2E battery for v0.75.0-beta - optional per-agent write confinement.

sweep10 found that the jail is per-ROOT, not per-agent: any agent could write
into another agent's folder inside a shared workspace. The operator asked for an
OPTIONAL confined mode (off by default): with it on, an identified agent may
WRITE only inside <root>\\<its-name>\\... or a folder the operator marked shared;
reading the whole tree stays open, and a caller with no identity (stdio, the
operator's console) is unconfined - the same rule the recoverable trash uses.

  C0  OFF by default: nothing changes, an agent writes anywhere in the jail
  C1  ON: an agent writes inside its own folder
  C2  ON: an agent CANNOT write into another agent's folder
  C3  ON: a folder the operator marked shared is writable by anyone
  C4  ON: writing loose at the root is refused
  C5  ON: reading is NOT confined - the whole tree is readable
  C6  ON: a caller with no identity is not confined (stdio path)

Usage:  python tests/test_confine.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check


TOKEN = 'bateria-workspace'


def start(confine):
    # Carpeta FIJA por modo (no con marca de tiempo): la raiz temporal la
    # comparten todas las baterias, y una que deja rastro en cada arranque
    # acaba con cientos de carpetas ahi - hasta que el listado de otra bateria
    # se trunca y falla algo que no tiene nada que ver (medido 2026-09-20:
    # 521 entradas, ~500 de esta).
    base = mc.carpeta(os.path.join('confine', 'on' if confine else 'off'))
    exe = mc.copia_exe(base)
    for a in ('alice', 'bob', 'shared'):
        os.makedirs(os.path.join(base, a))
    open(os.path.join(base, 'bob', 'b.pas'), 'w').write('unit b;\n')
    port = mc.puerto_libre()
    env = mc.entorno({'DELPHI_MCP_ROOTS': base,
                      'DELPHI_MCP_BIND_IP': '127.0.0.1'})  # loopback: sin avisos del firewall
    # v0.98: o workspace o nada - el confinamiento se declara EN el workspace
    with open(os.path.join(base, 'settings.ini'), 'w') as _f:
        _f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, base))
        if confine:
            _f.write('AgentConfinement=1\nSharedFolders=shared\n')
    # espera a que ESCUCHE (antes un sleep fijo de 2,3 s)
    proc = mc.lanza_http(exe, port, env)
    return base, mc.Http(port, TOKEN), proc


def crea(cli, path):
    """delphi_textedit create de 'x' en path: True solo si la tool dice
    CREADO de ESE fichero y el fichero esta en disco con ese contenido (antes
    valia cualquier respuesta sin RECHAZADO: un timeout o un error pasaban)."""
    r = cli.call('delphi_textedit', {'path': path, 'create': True, 'content': 'x'})
    return (r.startswith('CREADO') and os.path.basename(path) in r and os.path.isfile(path)
            and open(path, encoding='utf-8').read() == 'x')


# ---- OFF by default ----
base, a, proc = start(False)
try:
    a.session('alice')
    check('C0 OFF por defecto: un agente escribe donde sea del jail',
          crea(a, os.path.join(base, 'bob', 'off.txt')))
finally:
    proc.kill()

# ---- ON ----
base, a, proc = start(True)
try:
    a.session('alice')
    check('C1 ON: escribe en su propia carpeta',
          crea(a, os.path.join(base, 'alice', 'n.txt')))
    r = a.call('delphi_textedit',
               {'path': os.path.join(base, 'bob', 'hack.txt'), 'create': True, 'content': 'x'})
    check('C2 ON: NO escribe en la carpeta de otro agente',
          'RECHAZADO' in r and 'confinado' in r and
          not os.path.exists(os.path.join(base, 'bob', 'hack.txt')), r)
    check('C3 ON: una carpeta compartida es escribible',
          crea(a, os.path.join(base, 'shared', 's.txt')))
    r = a.call('delphi_textedit',
               {'path': os.path.join(base, 'loose.txt'), 'create': True, 'content': 'x'})
    check('C4 ON: escribir suelto en la raiz se rechaza',
          'RECHAZADO' in r and not os.path.exists(os.path.join(base, 'loose.txt')), r)
    r = a.call('delphi_read', {'path': os.path.join(base, 'bob', 'b.pas')})
    # el contenido de verdad, en el formato numero|linea del read
    check('C5 ON: leer NO esta confinado (lee el arbol entero)', '1|unit b;' in r, r)
finally:
    proc.kill()

# ---- ON, but stdio has no identity: unconfined ----
# carpeta fija, ver el comentario de start(): la raiz temporal es compartida
base = mc.carpeta(os.path.join('confine', 'stdio'))
exe = mc.copia_exe(base)
os.makedirs(os.path.join(base, 'bob'))
env = mc.entorno({'DELPHI_MCP_ROOTS': base,
                  'DELPHI_MCP_AGENT_CONFINEMENT': '1'})
# clientInfo.name vacio: la sesion NO tiene identidad
srv = mc.Stdio(exe, env, nombre='')
ok6 = crea(srv, os.path.join(base, 'bob', 'stdio.txt'))
srv.mata()
check('C6 ON: una sesion sin identidad (stdio/operador) no esta confinada', ok6)

mc.fin('confine battery')
