# -*- coding: utf-8 -*-
"""Round 51: quien lee un fichero como UTF-8 ESTRICTO muere con el primer CP1252.

Salio revisando un pendiente viejo ("delphi_styles lint escanea comentarios",
que ya estaba arreglado): el lint leia los .pas con TEncoding.UTF8 "porque los
lookups son ASCII" - pero el FICHERO no lo es. Un solo fuente en CP1252 con un
acento, que es lo normal en un proyecto Delphi con anos, tumbaba el lint entero
con "No mapping for the Unicode character". Es el gemelo del fallo CESU-8 del
decodificador de hijos (test_round47).

El paisaje: los otros lectores UTF-8 estrictos eran los del vault. Una nota
guardada en CP1252 por un editor viejo no se podia ni leer.

La regla: nadie decodifica a mano. El lector de la casa es
Lsp.Patch.DecodeSourceBytes / PatchLoadText (BOM, UTF-8 estricto, y CP1252 solo
cuando algun byte alto no forma secuencia valida).
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Server', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:300])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round51')


def borra(d):
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)


borra(BASE)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
VAULT = os.path.join(BASE, 'vault')
for d in (EXEDIR, JAIL, FUERA, VAULT):
    os.makedirs(d)
shutil.copy(SRC, os.path.join(EXEDIR, 'DelphiLspMcp.exe'))

TOK = 'r51'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R51]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, 'VaultPath=%s' % VAULT,
    'VaultReadOnly=0', '']))
proc = subprocess.Popen(
    [os.path.join(EXEDIR, 'DelphiLspMcp.exe'), '--http', str(PORT)],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOK}
    if SID:
        h['Mcp-Session-Id'] = SID
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'),
        timeout=120)
    raw = r.read().decode('utf-8', 'replace')
    for l in raw.splitlines():
        if l.startswith('data:'):
            m = json.loads(l[5:].strip())
            if 'result' in m or 'error' in m:
                return m, r.headers.get('Mcp-Session-Id')
    try:
        return json.loads(raw), r.headers.get('Mcp-Session-Id')
    except Exception:
        return None, r.headers.get('Mcp-Session-Id')


_, SID = rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
              'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                         'clientInfo': {'name': 'r51', 'version': '1'}}})
rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
RID = [100]


def call(tool, args):
    RID[0] += 1
    r, _ = rpc({'jsonrpc': '2.0', 'id': RID[0], 'method': 'tools/call',
                'params': {'name': tool, 'arguments': args}})
    try:
        return r['result']['content'][0]['text']
    except Exception:
        return json.dumps(r)[:400]


ACENTOS = 'Atención: el camión lleva señales'

try:
    # ------------------------------------------------------------------- L
    # Un proyecto FMX de los de verdad: fuentes viejos en CP1252 con acentos.
    proy = os.path.join(JAIL, 'App')
    os.makedirs(os.path.join(proy, 'Styles'))
    open(os.path.join(proy, 'Styles', 'App.style'), 'w', newline='\r\n').write(
        "object TStyleContainer\n  object TLayout\n"
        "    StyleName = 'cardstyle'\n  end\nend\n")
    open(os.path.join(proy, 'ULegado.pas'), 'wb').write((
        'unit ULegado;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\n'
        "// %s. StyleLookup := 'comentadostyle';\r\n"
        'procedure P(B: TObject);\r\nbegin\r\n'
        "  TButton(B).StyleLookup := 'noexistestyle';\r\n"
        "  TButton(B).StyleLookup := 'cardstyle';\r\n"
        'end;\r\n\r\nend.\r\n' % ACENTOS).encode('cp1252'))
    r = call('delphi_styles', {'command': 'lint',
                               'path': os.path.join(proy, 'Styles')})
    check('L1 el lint de estilos no muere con un .pas en CP1252',
          'EEncodingError' not in r and 'No mapping' not in r, r[:240])
    check('L2 ...ve el lookup que ningun estilo define',
          'noexistestyle' in r, r[:400])
    check('L3 ...y NO cuenta el que esta en un comentario',
          'comentadostyle' not in r, r[:400])

    # ------------------------------------------------------------------- V
    # Un vault con una nota que alguien guardo en CP1252 con un editor viejo.
    open(os.path.join(VAULT, 'MEMORY.md'), 'wb').write(
        b'# Indice\r\n- [[vieja]]\r\n')
    open(os.path.join(VAULT, 'vieja.md'), 'wb').write(
        ('# Nota vieja\r\n\r\n%s\r\n' % ACENTOS).encode('cp1252'))
    r = call('vault_read', {'path': 'vieja.md'})
    check('V1 vault_read de una nota en CP1252 no muere',
          'EEncodingError' not in r and 'No mapping' not in r, r[:240])
    check('V2 ...y los acentos llegan bien, no como U+FFFD',
          'camión' in r and '�' not in r, r[:240])
    r = call('vault_search', {'pattern': 'lleva', 'target': 'content'})
    check('V3 vault_search por contenido tampoco muere, y la encuentra',
          'No mapping' not in r and 'vieja' in r, r[:240])
    r = call('vault_read', {})
    check('V4 el arranque del vault (reglas + indice) sigue contestando',
          'No mapping' not in r and 'Indice' in r, r[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    borra(BASE)

print('== test_round51: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
