"""E2E battery for v0.81.0-beta - hermes' P1.7: shared SHA-256 cache.

delphi_fetch offset=0 hashed the whole file, then the /files download hashed
it AGAIN before streaming, and delphi_run (retired 2026-09-23) hashed the exe too: one big zip was
read end-to-end three times for a single download. Now one shared cache keyed
by (path, mtime, size). The contract must be untouched:

  H1  fetch sha256 equals a locally computed sha256 (correctness)
  H2  /files X-File-SHA256 equals the fetch sha (shared, consistent)
  H3  changing the file changes the sha (the stamp invalidates the entry)
  H4  a repeat fetch of the unchanged file still answers the same sha

Usage:  python tests/test_round18.py [path-to-DelphiLspMcp.exe]
"""
import json, time, os, hashlib, urllib.request
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('round18')
EXE = mc.copia_exe(BASE)
BIG = os.path.join(BASE, 'gordo.bin')
data1 = os.urandom(1024) * 5120  # ~5 MB, above the 4 MB link threshold
open(BIG, 'wb').write(data1)

PORT = mc.puerto_libre()
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE,
                  'DELPHI_MCP_BIND_IP': '127.0.0.1'})  # loopback: sin avisos del firewall
# v0.98: o workspace o nada - la bateria presenta su token
TOKEN = 'bateria-workspace'
with open(os.path.join(BASE, 'settings.ini'), 'w') as _f:
    _f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
proc = mc.lanza_http(EXE, PORT, env)
HOST = 'http://127.0.0.1:%d' % PORT
cli = mc.Http(PORT, TOKEN)


try:
    cli.session('round18')

    local1 = hashlib.sha256(data1).hexdigest()
    j1 = json.loads(cli.call('delphi_fetch', {'path': BIG}))
    check('H1 fetch sha256 == sha256 local', j1.get('sha256') == local1,
          (j1.get('sha256'), local1))

    dl = j1.get('download', '')
    check('H1b fichero grande responde enlace, no base64',
          j1.get('bytes') == 0 and dl != '', j1)
    with urllib.request.urlopen(urllib.request.Request(
            HOST + dl, headers={'Authorization': 'Bearer ' + TOKEN}), timeout=60) as r:
        body = r.read()
        sha_cabecera = r.headers.get('X-File-SHA256')
    check('H2 /files X-File-SHA256 == fetch sha y el contenido casa',
          sha_cabecera == local1 and
          hashlib.sha256(body).hexdigest() == local1,
          sha_cabecera)

    # H3: mutate the file - the stamp must invalidate the cached hash
    time.sleep(1.1)  # ensure a distinct mtime even on coarse filesystems
    data2 = os.urandom(1024) * 5120
    open(BIG, 'wb').write(data2)
    local2 = hashlib.sha256(data2).hexdigest()
    j2 = json.loads(cli.call('delphi_fetch', {'path': BIG}))
    check('H3 tras cambiar el fichero, sha nuevo y correcto (invalidacion)',
          j2.get('sha256') == local2 and j2.get('sha256') != local1,
          (j2.get('sha256'), local2))

    j3 = json.loads(cli.call('delphi_fetch', {'path': BIG}))
    check('H4 repetir sin cambios: mismo sha', j3.get('sha256') == local2,
          j3.get('sha256'))
finally:
    proc.kill()

mc.fin('round-18 battery')
