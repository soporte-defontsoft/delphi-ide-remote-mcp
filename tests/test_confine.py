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
  C8  ON: nor through a junction from its own folder to another agent's
      (V113 of 1.23.1: the confinement judged the text, the jail the real path)
  C9  ON: an HTTP session with no name, or one the sanitizer empties (Cyrillic,
      '...'), is confined under its OWN identity (V111 of 1.23.1: it was '',
      the operator's)
  C10 ON: a request with NO session at all (no Mcp-Session-Id, no initialize)
      is confined too, under its own identity - not the operator (V159 of
      1.23.1: the hole V111 left for a header-less request)

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
    return (mc.abre(r, 'SK_TEXT_CREADO_ENCODING_FINALES_FMT') and os.path.basename(path) in r and os.path.isfile(path)
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
          mc.rechazado(r) and mc.es(r, 'SR_AGENT_CONFINED_FMT') and
          not os.path.exists(os.path.join(base, 'bob', 'hack.txt')), r)
    check('C3 ON: una carpeta compartida es escribible',
          crea(a, os.path.join(base, 'shared', 's.txt')))
    r = a.call('delphi_textedit',
               {'path': os.path.join(base, 'loose.txt'), 'create': True, 'content': 'x'})
    check('C4 ON: escribir suelto en la raiz se rechaza',
          mc.rechazado(r) and mc.es(r, 'SR_AGENT_CONFINED_FMT') and not os.path.exists(os.path.join(base, 'loose.txt')), r)
    r = a.call('delphi_read', {'path': os.path.join(base, 'bob', 'b.pas')})
    # el contenido de verdad, en el formato numero|linea del read
    check('C5 ON: leer NO esta confinado (lee el arbol entero)', '1|unit b;' in r, r)
    # Las capturas son NUESTRAS y viven en la casa del servidor, no en el
    # workspace (2af de la 1.18.2: hasta la 1.18.1 vivian en el __delphi-temp
    # de la raiz, y aqui se media que el confinamiento no impidiera
    # consumirlas). Un png con su forma plantado en el workspace NO es nuestro:
    # el agente lo lee como cualquier fichero de su jaula y no se borra. La
    # entrega y el consumo de las nuestras, con un agente confinado tambien,
    # los mide test_captura_puertas_1182 (C1-C2, F1, E3-E4)
    CAP = os.path.join(base, mc.TEMPORALES, 'alice', 'desktop', 'cap.png')
    os.makedirs(os.path.dirname(CAP), exist_ok=True)
    open(CAP, 'wb').write(b'\x89PNG\r\n\x1a\n' + b'0' * 64)
    r = a.call('delphi_fetch', {'path': CAP, 'offset': 0})
    check('C7 ON: un png con forma de captura en el workspace se lee, pero no es nuestro y no se borra',
          mc.como_json(r).get('bytes', 0) > 0 and mc.como_json(r).get('consumedOnServer') is not True and
          os.path.exists(CAP), r[:300])
    # V113 de la 1.23.1: el confinamiento por la ruta REAL. alice\lnk, una union
    # a la carpeta de bob, dejaba a alice escribir en ella (medido)
    LNK = os.path.join(base, 'alice', 'lnk')
    check('C8 (preparacion) la union de la carpeta de alice a la de bob',
          mc.junction(LNK, os.path.join(base, 'bob')), LNK)
    try:
        r = a.call('delphi_textedit', {'path': os.path.join(LNK, 'por-enlace.txt'), 'create': True, 'content': 'x'})
        check('C8 ON: por una union de SU carpeta a la de otro agente, tampoco escribe',
              mc.rechazado(r) and mc.es(r, 'SR_AGENT_CONFINED_FMT') and
              not os.path.exists(os.path.join(base, 'bob', 'por-enlace.txt')), r[:300])
    finally:
        if os.path.isdir(LNK):
            os.rmdir(LNK)  # quita el ENLACE, no lo de detras
    # V111 de la 1.23.1: una sesion HTTP sin nombre, o con uno que el saneado deja
    # vacio, era la identidad VACIA, la del operador: sin confinar (medido). Ahora
    # tiene la SUYA, y el confinamiento la nombra
    puerto = int(a.url.rsplit(':', 1)[1].split('/')[0])
    cirilico = ''.join(chr(c) for c in (0x425, 0x435, 0x440, 0x43C, 0x435, 0x441))  # un nombre que el saneado vacia
    for nombre in (cirilico, '...', ''):
        c = mc.Http(puerto, TOKEN)
        c.session(nombre)
        f = os.path.join(base, 'bob', 'v111-%d.txt' % len(nombre))
        r = c.call('delphi_textedit', {'path': f, 'create': True, 'content': 'x'})
        check('C9 ON: una sesion HTTP llamada %r tampoco escribe en la carpeta de bob, con su identidad propia' % nombre,
              mc.es(r, 'SR_AGENT_CONFINED_FMT') and 'session-' in r and not os.path.exists(f), r[:300])
    # C10 (V159 de la 1.23.1): una peticion HTTP SIN la cabecera Mcp-Session-Id
    # (ni initialize) caia en la identidad VACIA, la del operador: SIN confinar.
    # Ahora tiene la suya y el confinamiento la nombra. (La misma identidad que
    # en produccion cierra la purga de la papelera de otro: test_identity I6.)
    cuerpo = {"jsonrpc": "2.0", "id": 888, "method": "tools/call", "params": {
        "name": "delphi_textedit",
        "arguments": {"path": os.path.join(base, 'bob', 'nohdr.txt'), "create": True, "content": "x"}}}
    _st, _h, raw = mc.post(a.url, cuerpo, TOKEN, sid=None)
    r = mc.texto(next((m for m in mc.Http.mensajes(raw) if m.get('id') == 888), None))
    check('C10 ON: una peticion sin Mcp-Session-Id tampoco escribe en la carpeta de bob (identidad propia, no el operador)',
          mc.es(r, 'SR_AGENT_CONFINED_FMT') and 'session-' in r and not os.path.exists(os.path.join(base, 'bob', 'nohdr.txt')), r[:300])
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
# (revisor de baterias, 18-oct-2026) el control: el MISMO entorno con identidad SI
# confina - si el confinamiento ni se encendia, C6 pasaba igual
srv = mc.Stdio(exe, env, nombre='alice')
r6 = srv.call('delphi_textedit', {'path': os.path.join(base, 'bob', 'alice.txt'), 'create': True, 'content': 'x'})
srv.mata()
check('C6b control: con identidad (alice), escribir en la carpeta de bob se niega (el confinamiento esta encendido)',
      mc.es(r6, 'SR_AGENT_CONFINED_FMT') and not os.path.exists(os.path.join(base, 'bob', 'alice.txt')), r6[:300])

mc.fin('confine battery')
