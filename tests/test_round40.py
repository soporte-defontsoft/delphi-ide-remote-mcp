# -*- coding: utf-8 -*-
"""E2E battery: la letra de unidad real se escapaba por el CREADO.

El enmascarador de salida (MaskDriveText, montado como ResultFilter UNICO en
Lsp.Host) exime a seis tools enteras -delphi_read, delphi_search, delphi_edit,
delphi_textedit, vault_read, vault_search- y con razon: su respuesta es
contenido LITERAL del disco, y un ancla enmascarada no casa con el fichero.

Pero la exencion es por TOOL, no por TROZO. delphi_textedit componia su propia
ruta en el "CREADO %s" -la unica linea de su respuesta que NO es eco- y salia
con la letra real del servidor. Su gemelo delphi_edit no lo hacia: imprime el
nombre del fichero. Asi derivan dos gemelos, y el comentario de la exencion
afirmaba de los dos que "sus ecos de exito no llevan rutas absolutas".

Mide las DOS direcciones, que es lo que la hace util:

  L1..L3  nada de lo que COMPONE el servidor lleva la letra real
  L4..L6  ...y nada de lo que COPIA del disco viene enmascarado

Usage:  python tests/test_round40.py [path-to-DelphiLspMcp.exe]
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
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:240])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round40')


def borra(d):
    def alafuerza(func, path, _exc):
        try:
            os.chmod(path, 0o700)
            func(path)
        except Exception:
            pass
    shutil.rmtree(d, onexc=alafuerza) if sys.version_info >= (3, 12) else \
        shutil.rmtree(d, onerror=alafuerza)


if os.path.isdir(BASE):
    borra(BASE)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(EXEDIR, exist_ok=True)
os.makedirs(JAIL, exist_ok=True)
EXE = os.path.join(EXEDIR, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

# La letra REAL donde vive la jaula (la temp de la maquina), y su forma
# virtual. No se dan por supuestas: la temp puede no estar en C:.
DRIVE = os.path.splitdrive(JAIL)[0].upper()          # 'C:'
VIRT = 'srv' + DRIVE[0].lower() + ':'                # 'srvc:'
# Una ruta ABSOLUTA dentro del CONTENIDO de un fichero. No es de este
# servidor: es texto del fichero, y tiene que viajar intacto para que sirva
# de ancla. El enmascarador tapa CUALQUIER letra, no solo las servidas, asi
# que si alguien enmascara de mas esto se ve aqui.
RUTA = r'D:\Proyectos\Cliente\datos.ini'

TOK = 'r40'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R40]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '',
]))

proc = subprocess.Popen([EXE, '--http', str(PORT)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(3)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body, timeout=180):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOK}
    if SID:
        h['Mcp-Session-Id'] = SID
    r = urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(), headers=h, method='POST'),
        timeout=timeout)
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
                         'clientInfo': {'name': 'r40', 'version': '1'}}})
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


def sin_letra_real(texto):
    """La letra real del servidor no puede salir. Se mira la forma completa
    (letra + dos puntos + separador), que es lo que el enmascarador reconoce:
    buscar 'C:' a secas daria falso positivo con cualquier otra cosa."""
    return (DRIVE + '\\') not in texto and (DRIVE + '/') not in texto


try:
    nuevo = os.path.join(JAIL, 'nuevo.txt')
    # ------------------------------------------------------------------ L1
    a = call('delphi_textedit', {'path': nuevo, 'create': True,
                                 'content': 'alfa\nbeta\n'})
    check('L1 el CREADO de delphi_textedit no saca la letra real',
          sin_letra_real(a), a[:200])
    check('L1b ...y dice la ruta como unidad virtual, que es la usable',
          VIRT in a, a[:200])

    # ------------------------------------------------------------------ L2
    # El gemelo. Nunca fallo -imprime el nombre del fichero-, y por eso mismo
    # se mide: es el que demuestra que la pareja iba descuadrada.
    b = call('delphi_edit', {'path': os.path.join(JAIL, 'UNueva.pas'),
                             'createunit': True})
    check('L2 el CREADA de delphi_edit tampoco',
          sin_letra_real(b), b[:200])

    # ------------------------------------------------------------------ L3
    # La negativa ya se enmascaraba (empieza por RECHAZADO, que la exencion
    # excluye). Se fija aqui para que el arreglo no la rompa.
    c = call('delphi_textedit', {'path': nuevo, 'create': True,
                                 'content': 'choque'})
    check('L3 y la negativa de "ya existe" sigue enmascarada',
          sin_letra_real(c) and 'RECHAZADO' in c, c[:200])

    # ------------------------------------------------------------------ L4
    pas = os.path.join(JAIL, 'UPath.pas')
    open(pas, 'w', newline='\r\n').write(
        'unit UPath;\n\ninterface\n\nconst\n'
        "  RUTA = '%s';\n\nimplementation\n\nend.\n" % RUTA)
    r = call('delphi_read', {'path': pas})
    check('L4 delphi_read devuelve una ruta del CONTENIDO intacta',
          RUTA in r, r[:240])

    # ------------------------------------------------------------------ L5
    e = call('delphi_edit', {'path': pas,
                             'old': "  RUTA = '%s';" % RUTA,
                             'new': "  RUTA_INI = '%s';" % RUTA})
    check('L5 el eco de delphi_edit es literal: no enmascara el contenido',
          RUTA in e, e[:240])
    t = call('delphi_textedit', {'path': nuevo, 'old': 'beta',
                                 'new': 'beta %s' % RUTA})
    check('L5b ...y el de delphi_textedit igual',
          RUTA in t, t[:240])

    # ------------------------------------------------------------------ L7
    # El OTRO emisor de la misma tool: el "copia=" dice donde quedo la copia
    # de seguridad, y esa ruta la compone el servidor. Se escapo del primer
    # barrido -se busco el identificador y no el FORMATO- y lo canto la
    # propia tool cortando un release. La ruta de la copia vive en la jaula,
    # asi que lleva la letra REAL: es exactamente lo que se mira aqui.
    check('L7 el "copia=" del eco de delphi_edit tampoco saca la letra real',
          sin_letra_real(e), e[:300])
    check('L7b ...y sigue diciendo DONDE quedo la copia',
          'copia=' in e and (VIRT in e or 'ya existia' in e), e[:300])

    # ------------------------------------------------------------------ L8
    # El nombrador, por los dos lados. La lista de unidades validas de una
    # negativa la compone PathAnomaly; las rutas de las respuestas las
    # compone MaskDriveText. Eran CUATRO escrituras a mano de la misma forma
    # y tienen que decir lo mismo: si un dia una baja la letra de otra
    # manera, aqui se ve.
    z = call('delphi_list', {'root': 'srvz:\\loquesea'})
    check('L8 una unidad que no se sirve se rechaza POR NOMBRE',
          'srvz' in z and 'RECHAZADO' in z, z[:240])
    check('L8b ...y las validas se nombran con la misma forma que las rutas',
          VIRT in z, z[:240])

    # ------------------------------------------------------------------ L6
    s = call('delphi_search', {'root': JAIL, 'query': r'D:\Proyectos'})
    try:
        hits = json.loads(s)['hits']
    except Exception:
        hits = []
    check('L6 delphi_search enmascara su campo "path"',
          bool(hits) and hits[0]['path'].lower().startswith(VIRT),
          s[:240])
    check('L6b ...y NO el campo "text", que es el ancla',
          bool(hits) and RUTA in hits[0]['text'], s[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass

print('== test_round40: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
