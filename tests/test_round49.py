# -*- coding: utf-8 -*-
"""Round 49: el MODO FRAGMENTO de las tools de edicion.

El ancla de linea completa es la regla de la casa: existe para que nadie edite
de memoria. Pero un parrafo de README es UNA linea de 600 caracteres, y cambiar
"68" por "69" obligaba a pegarla entera byte a byte. El fragmento no relaja la
regla: "atline" es obligatorio y el trozo tiene que salir UNA vez en esa linea;
un unico resolvedor (Lsp.Patch.FragmentoALinea) lo convierte en un ancla de
linea completa y el motor de siempre vuelve a casarla antes de escribir.

Se miden las CUATRO puertas por las que entra una edicion - delphi_textedit,
delphi_edit, las tandas ("edits") y el stage de delphi_changeset - porque el
fallo repetido de este repo es arreglar una gemela y dejar la otra.
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


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round49')


def borra(d):
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)


borra(BASE)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
for d in (EXEDIR, JAIL, FUERA):
    os.makedirs(d)
shutil.copy(SRC, os.path.join(EXEDIR, 'DelphiLspMcp.exe'))

TOK = 'r49'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R49]', 'Token=%s' % TOK, 'Roots=%s' % JAIL, '']))
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
                         'clientInfo': {'name': 'r49', 'version': '1'}}})
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


LARGA = ('La suite tiene 68 baterias y 1570 checks; de las 68, ninguna falla. '
         + 'Relleno ' * 60 + 'camión y señal.')
MD = os.path.join(JAIL, 'LEEME.md')
PAS = os.path.join(JAIL, 'Legado.pas')
AJENO = os.path.join(FUERA, 'Secreto.md')


def planta():
    # utf-8 sin BOM, CRLF, con una linea sangrada: el resto de la linea y del
    # fichero tiene que quedar byte a byte.
    open(MD, 'wb').write(('# Prueba\r\n\r\n%s\r\n\r\n  - sangrada: version '
                          '1.0.14-beta aqui\r\n' % LARGA).encode('utf-8'))
    # CP1252 de verdad: aqui es donde una edicion descuidada destruye acentos.
    open(PAS, 'wb').write((
        'unit Legado;\r\n\r\ninterface\r\n\r\nconst\r\n'
        "  AVISO = 'Atención: el camión lleva 68 cajas';\r\n\r\n"
        'implementation\r\n\r\nend.\r\n').encode('cp1252'))
    open(AJENO, 'wb').write(b'clave=SECRETO-DE-OTRO\r\n')


try:
    planta()
    antes = open(MD, 'rb').read()

    # ------------------------------------------------------------ rechazos
    r = call('delphi_textedit', {'path': MD, 'fragment': '68', 'new': '69',
                                 'atline': 3})
    check('F1 un trozo que sale DOS veces en la linea se rechaza, no se adivina',
          r.startswith('RECHAZADO') and '2 veces' in r, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': '1570', 'new': '1575'})
    check('F2 sin atline se rechaza: un fragmento nunca se busca por el fichero',
          r.startswith('RECHAZADO') and 'atline' in r, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': 'CAMIÓN',
                                 'new': 'tren', 'atline': 3})
    check('F3 distingue mayusculas, y el rechazo ensena la linea real',
          r.startswith('RECHAZADO') and 'no aparece' in r and '3|' in r, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': '1570', 'new': '1575',
                                 'atline': 3, 'old': '# Prueba'})
    check('F4 fragment + old: dos formas de decir donde, se rechaza',
          r.startswith('RECHAZADO') and '"old"' in r, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': '1570',
                                 'new': 'a\nb', 'atline': 3})
    check('F5 un salto de linea en "new" se rechaza en este modo',
          r.startswith('RECHAZADO') and 'saltos' in r, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': '1570', 'new': '1575',
                                 'atline': 99})
    check('F6 atline mas alla del final se rechaza',
          r.startswith('RECHAZADO') and '99' in r, r[:200])
    check('F7 ...y tras seis rechazos el fichero sigue byte a byte',
          open(MD, 'rb').read() == antes)
    r = call('delphi_textedit', {'path': AJENO, 'fragment': 'SECRETO',
                                 'new': 'x', 'atline': 1})
    check('F8 fuera de la jaula: ni se escribe ni el rechazo ensena la linea',
          'SECRETO-DE-OTRO' not in r and
          open(AJENO, 'rb').read() == b'clave=SECRETO-DE-OTRO\r\n', r[:200])

    # ------------------------------------------------------ delphi_textedit
    r = call('delphi_textedit', {'path': MD, 'fragment': '1570', 'new': '1575',
                                 'atline': 3})
    esperado = antes.replace(b'1570', b'1575')
    check('T1 delphi_textedit cambia SOLO el trozo: el resto, byte a byte',
          r.startswith('OK') and open(MD, 'rb').read() == esperado, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': '1.0.14',
                                 'new': '1.0.15', 'atline': 5})
    esperado = esperado.replace(b'1.0.14', b'1.0.15')
    check('T2 ...y en una linea sangrada la sangria no se toca',
          open(MD, 'rb').read() == esperado, r[:200])
    r = call('delphi_textedit', {'path': MD, 'fragment': ' y señal',
                                 'new': '', 'atline': 3})
    esperado = esperado.replace(' y señal'.encode('utf-8'), b'')
    check('T3 new vacio quita el trozo (acentos utf-8 intactos alrededor)',
          open(MD, 'rb').read() == esperado, r[:200])

    # ---------------------------------------------------------------- tanda
    planta()
    r = call('delphi_textedit', {'path': MD, 'edits': json.dumps([
        {'fragment': '68 baterias', 'new': '69 baterias', 'atline': 3},
        {'fragment': 'de las 68', 'new': 'de las 69', 'atline': 3},
        {'fragment': '1.0.14', 'new': '1.0.15', 'atline': 5}])})
    esperado = antes.replace(b'68', b'69').replace(b'1.0.14', b'1.0.15')
    check('B1 tanda: dos trozos de la MISMA linea en orden, y otro mas abajo',
          r.startswith('APLICADAS') and open(MD, 'rb').read() == esperado,
          r[:240])
    planta()
    r = call('delphi_textedit', {'path': MD, 'edits': json.dumps([
        {'fragment': '1570', 'new': '1575', 'atline': 3},
        {'fragment': 'no-esta', 'new': 'x', 'atline': 3}])})
    check('B2 tanda: si una falla, todo o nada - el fichero vuelve byte a byte',
          'ROLLBACK' in r and open(MD, 'rb').read() == antes, r[:240])
    r = call('delphi_textedit', {'path': MD, 'edits': json.dumps([
        {'fragment': '1570', 'new': '1575', 'atline': 3, 'delete': True}])})
    check('B3 tanda: fragment + delete se rechaza',
          'ROLLBACK' in r and '"delete"' in r and
          open(MD, 'rb').read() == antes, r[:240])

    # ---------------------------------------------------------- delphi_edit
    pas0 = open(PAS, 'rb').read()
    r = call('delphi_edit', {'path': PAS, 'fragment': '68', 'new': '69',
                             'atline': 6})
    check('E1 delphi_edit: el trozo cambia y el CP1252 sigue siendo CP1252',
          r.startswith('ESCRITO') and
          open(PAS, 'rb').read() == pas0.replace(b'68', b'69'), r[:240])
    r = call('delphi_edit', {'path': PAS, 'fragment': 'camión',
                             'new': 'camión grande', 'atline': 6})
    check('E2 ...tambien cuando el trozo LLEVA el acento (un byte, no dos)',
          open(PAS, 'rb').read() == pas0.replace(b'68', b'69').replace(
              'camión'.encode('cp1252'),
              'camión grande'.encode('cp1252')), r[:240])
    r = call('delphi_edit', {'path': PAS, 'fragment': '69', 'new': '70',
                             'atline': 6, 'insert': 'rutina-global'})
    check('E3 fragment + insert se rechaza', r.startswith('RECHAZADO'), r[:200])
    r = call('delphi_edit', {'path': MD, 'fragment': '1570', 'new': '1',
                             'atline': 3})
    check('E4 cada gemela sigue vigilando su extension (un .md no es de delphi_edit)',
          r.startswith('RECHAZADO') and 'delphi_textedit' in r, r[:200])

    # ------------------------------------------------------------ changeset
    planta()
    cs = call('delphi_changeset', {'command': 'begin'})
    cid = cs.split()[1]
    s1 = call('delphi_changeset', {'command': 'stage', 'id': cid,
                                   'kind': 'edit', 'path': PAS,
                                   'fragment': '68', 'new': '69', 'atline': 6})
    s2 = call('delphi_changeset', {'command': 'stage', 'id': cid,
                                   'kind': 'edit', 'path': MD,
                                   'fragment': '1570', 'new': '1575',
                                   'atline': 3})
    s3 = call('delphi_changeset', {'command': 'stage', 'id': cid,
                                   'kind': 'edit', 'path': MD,
                                   'fragment': '68', 'new': '69', 'atline': 3})
    check('C1 changeset: el fragmento se resuelve al apuntar (stage)',
          s1.startswith('STAGED') and s2.startswith('STAGED'), s1[:120] + s2[:120])
    check('C2 ...y el ambiguo se rechaza AHI, no en el commit',
          s3.startswith('RECHAZADO') and '2 veces' in s3, s3[:200])
    pv = call('delphi_changeset', {'command': 'preview', 'id': cid})
    cm = call('delphi_changeset', {'command': 'commit', 'id': cid})
    check('C3 preview limpio y commit: los dos ficheros, solo su trozo',
          '"unresolved":0' in pv.replace(' ', '') and 'COMMIT COMPLETO' in cm and
          open(PAS, 'rb').read() == pas0.replace(b'68', b'69') and
          open(MD, 'rb').read() == antes.replace(b'1570', b'1575'),
          pv[:160] + ' | ' + cm[:160])

    # La regla de siempre no se ha movido: un trozo en "old" NO es un ancla.
    r = call('delphi_textedit', {'path': MD, 'old': '1575', 'new': '1'})
    check('Z1 el ancla de linea completa sigue intacta: un trozo en "old" se rechaza',
          r.startswith('RECHAZADO'), r[:200])
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    borra(BASE)

print('== test_round49: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
