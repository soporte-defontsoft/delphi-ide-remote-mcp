# -*- coding: utf-8 -*-
"""Round 46: la red de la auditoria del 2026-09-21.

Cada check de aqui es un bug CONFIRMADO ese dia (revision multi-agente +
verificacion a mano sobre el codigo vivo). Los junctions son la pieza
central: la jaula ya comparaba con RealPath, pero (1) el perdon de
ReadOnlyPaths recomprobaba POR TEXTO y perdonaba el enlace que RealPath
acababa de cazar, y (2) el TDirectory.Delete recursivo de la RTL entra en
cualquier faDirectory sin mirar el bit de reparse, asi que la purga del
arranque borraba AL OTRO LADO del enlace. Ademas: el eco RESTAURAR de
delphi_edit salia sin enmascarar (el segundo emisor, otra vez), delphi_edit
no conocia la veda de __delphi-temp, delphi_package se llevaba los
temporales en el zip, el centinela 'srvx' chocaba con una unidad X: servida
(ahora 'srv0'), y un arranque stdio purgaba los temporales del servicio
vivo (ahora: solo purga la PRIMERA instancia del exe).

Lo que esta bateria NO mide, y se dice en voz alta para no mentir en verde:
la decodificacion CESU-8 (necesita un hijo que emita esos bytes), el
AgentTempDir con la primera raiz en ReadOnlyPaths (necesita el nodo del
escritorio) y la clave de cache de sesion entre workspaces solapados
(necesita dos tokens y un arbol LSP vivo). Apuntados en el CHANGELOG.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile

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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round46')


def borra(d):
    def alafuerza(func, path, _exc):
        try:
            os.chmod(path, 0o700)
            func(path)
        except Exception:
            pass
    if not os.path.isdir(d):
        return
    shutil.rmtree(d, onexc=alafuerza) if sys.version_info >= (3, 12) else \
        shutil.rmtree(d, onerror=alafuerza)


def junction(link, target):
    """mklink /J no necesita privilegios; devuelve True si el enlace quedo."""
    r = subprocess.run(['cmd', '/c', 'mklink', '/J', link, target],
                       capture_output=True)
    return r.returncode == 0 and os.path.isdir(link)


borra(BASE)
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
VICTIMA = os.path.join(BASE, 'victima')       # fuera de la jaula
SECRETO = os.path.join(BASE, 'secreto')       # fuera de la jaula
os.makedirs(EXEDIR)
os.makedirs(os.path.join(JAIL, 'vendor'))
os.makedirs(VICTIMA)
os.makedirs(SECRETO)
open(os.path.join(VICTIMA, 'vive.txt'), 'w').write('sigo aqui')
open(os.path.join(SECRETO, 'secreto.txt'), 'w').write('ultrasecreto-r46')
open(os.path.join(JAIL, 'vendor', 'normal.txt'), 'w').write('vendor legitimo')
shutil.copy(SRC, os.path.join(EXEDIR, 'DelphiLspMcp.exe'))

TOK = 'r46'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT2 = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R46]', 'Token=%s' % TOK, 'Roots=%s' % JAIL,
    'ReadOnlyPaths=%s' % os.path.join(JAIL, 'vendor'), '']))

# Los dos junctions, ANTES de arrancar: el de lectura bajo el ReadOnlyPath
# (el perdon), y el de la purga dentro de __delphi-temp.
TEMP_JAULA = os.path.join(JAIL, '__delphi-temp')
os.makedirs(os.path.join(TEMP_JAULA, 'normal'))
open(os.path.join(TEMP_JAULA, 'normal', 'basura.txt'), 'w').write('x')
HAY_J1 = junction(os.path.join(JAIL, 'vendor', 'out'), SECRETO)
HAY_J2 = junction(os.path.join(TEMP_JAULA, 'trampa'), VICTIMA)


def arranca(puerto):
    p = subprocess.Popen(
        [os.path.join(EXEDIR, 'DelphiLspMcp.exe'), '--http', str(puerto)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)
    return p


proc = arranca(PORT)
URL = 'http://127.0.0.1:%d/mcp' % PORT
SID = None


def rpc(body, timeout=120):
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


def sesion():
    global SID
    SID = None
    _, SID = rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                  'params': {'protocolVersion': '2025-06-18',
                             'capabilities': {},
                             'clientInfo': {'name': 'r46', 'version': '1'}}})
    rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})


sesion()
RID = [100]


def call(tool, args):
    RID[0] += 1
    r, _ = rpc({'jsonrpc': '2.0', 'id': RID[0], 'method': 'tools/call',
                'params': {'name': tool, 'arguments': args}})
    try:
        return r['result']['content'][0]['text']
    except Exception:
        return json.dumps(r)[:400]


UNIDAD = os.path.splitdrive(JAIL)[0].lower() + '\\'  # p.ej. 'c:\'
# La fuga es la unidad CRUDA. Cuidado con el substring a secas: 'c:\' esta
# DENTRO de 'srvc:\' y este check se puso en rojo a si mismo la primera vez
# que corrio, con la mascara funcionando perfectamente.
FUGA = re.compile('(?<![a-z0-9])' + re.escape(UNIDAD))


def filtra(texto):
    return bool(FUGA.search(texto.lower()))

try:
    # ------------------------------------------------------------------ J1
    # El perdon de ReadOnlyPaths ya no perdona al junction: PathDenied lo
    # cazo con RealPath y ReadPathDenied recomprobaba POR TEXTO (GetFullPath)
    # y lo dejaba pasar - delphi_fetch servia ficheros de FUERA de la jaula.
    if HAY_J1:
        r = call('delphi_read',
                 {'path': os.path.join(JAIL, 'vendor', 'out', 'secreto.txt')})
        check('J1 leer a traves del junction bajo ReadOnlyPaths se rechaza',
              'ultrasecreto-r46' not in r and 'RECHAZADO' in r, r[:240])
        r = call('delphi_fetch',
                 {'path': os.path.join(JAIL, 'vendor', 'out', 'secreto.txt')})
        check('J1b ...y delphi_fetch tampoco lo sirve',
              'ultrasecreto-r46' not in r, r[:240])
    else:
        print('NOTA: mklink /J fallo en este sistema de ficheros; '
              'J1/J1b no se miden.')
    # El otro lado, siempre: el perdon LEGITIMO sigue vivo. Un guardian que
    # cierra de mas hace mas dano que el agujero.
    r = call('delphi_read', {'path': os.path.join(JAIL, 'vendor', 'normal.txt')})
    check('J1c un fichero REAL bajo ReadOnlyPaths se sigue leyendo',
          'vendor legitimo' in r, r[:240])

    # ------------------------------------------------------------------ T5
    # La veda de __delphi-temp vale tambien para delphi_edit: la regla entro
    # en 1 de los 3 guardianes y delphi_edit era el que faltaba.
    pobre = os.path.join(TEMP_JAULA, 'Pobre.pas')
    os.makedirs(TEMP_JAULA, exist_ok=True)
    open(pobre, 'w').write('unit Pobre;\ninterface\nimplementation\nend.\n')
    r = call('delphi_edit', {'path': pobre, 'old': 'unit Pobre;',
                             'new': 'unit Rico;'})
    check('T5 delphi_edit tambien rechaza escribir en __delphi-temp',
          'RECHAZADO' in r and 'temporales' in r, r[:240])
    os.remove(pobre)

    # ------------------------------------------------------------------ T6
    # delphi_package no se lleva los temporales: ahi caen capturas del
    # escritorio del OPERADOR, y este era el unico recorredor que las
    # COPIABA fuera del workspace.
    open(os.path.join(JAIL, 'datos.txt'), 'w').write('parte del entregable')
    os.makedirs(os.path.join(TEMP_JAULA, 'alice'), exist_ok=True)
    open(os.path.join(TEMP_JAULA, 'alice', 'cap.png'), 'wb').write(b'PNGno')
    zpath = os.path.join(JAIL, 'paq.zip')
    r = call('delphi_package', {'dir': JAIL, 'outfile': zpath})
    dentro = []
    if os.path.exists(zpath):
        with zipfile.ZipFile(zpath) as z:
            dentro = z.namelist()
    check('T6 el zip lleva el trabajo y NO los temporales',
          any('datos.txt' in n for n in dentro) and
          not any('__delphi-temp' in n for n in dentro),
          '%s | %s' % (dentro[:6], r[:120]))

    # ------------------------------------------------------------------ T3
    # El RESTAURAR/RESTAURADO de delphi_edit sale enmascarado: era el
    # segundo emisor vivo tras el barrido de 1.0.11, en la MISMA unidad
    # donde BackupFile dejo escrita la obligacion.
    uno = os.path.join(JAIL, 'Uno.pas')
    open(uno, 'w', newline='\n').write(
        'unit Uno;\ninterface\nconst K = 1;\nimplementation\nend.\n')
    call('delphi_edit', {'path': uno, 'old': 'const K = 1;',
                         'new': 'const K = 2;'})
    r = call('delphi_edit', {'path': uno, 'restore': True})
    check('T3 el aviso de RESTAURAR no filtra la letra real del disco',
          'RESTAURAR' in r and not filtra(r) and 'srv' in r.lower(),
          r[:240])
    r = call('delphi_edit', {'path': uno, 'restore': True, 'confirm': True})
    check('T3b ...y el RESTAURADO (con Src y PreCopy) tampoco',
          'RESTAURADO' in r and not filtra(r), r[:280])

    # ------------------------------------------------------------------ T4
    # El centinela de letra no servida es 'srv0' (el viejo 'srvx' ERA la
    # mascara de una unidad X: servida de verdad: el nombrador dejaba de
    # ser inyectivo). Las dos formas se rechazan POR NOMBRE, sin tocar
    # disco y sin filtrar ninguna letra real.
    r = call('delphi_read', {'path': 'srv0:\\loque\\sea.pas'})
    check('T4 el centinela srv0: se rechaza por nombre',
          'RECHAZADO' in r and not filtra(r), r[:240])
    r = call('delphi_read', {'path': 'srvq:\\loque\\sea.pas'})
    check('T4b una unidad virtual no servida tambien',
          'RECHAZADO' in r and not filtra(r), r[:240])

    # ------------------------------------------------------------------ T7
    # Solo purga la PRIMERA instancia viva del exe: la premisa "no pueden
    # correr dos a la vez, comparten puerto" era falsa para stdio, y la
    # purga del segundo borraba ficheros EN USO del primero.
    en_uso = os.path.join(EXEDIR, '__delphi-temp', 'git')
    os.makedirs(en_uso, exist_ok=True)
    testigo = os.path.join(en_uso, 'msg-en-vuelo.txt')
    open(testigo, 'w').write('commit -F en vuelo')
    b = arranca(PORT2)
    try:
        check('T7 una SEGUNDA instancia del mismo exe no purga al primero',
              os.path.exists(testigo), 'la instancia B se llevo %s' % testigo)
    finally:
        b.kill()
        time.sleep(1.0)

    # ------------------------------------------------------------------ J2
    # La purga del arranque no cruza enlaces: el junction cae como ENTRADA
    # y su destino ni se mira. Antes, TDirectory.Delete recursivo entraba
    # y borraba AL OTRO LADO (fuera de la jaula, con las credenciales del
    # servicio y sin peticion de nadie).
    proc.kill()
    time.sleep(1.5)
    proc = arranca(PORT)
    sesion()
    check('T7b ...y al morir el primero, el siguiente arranque SI purga',
          not os.path.exists(testigo), 'sobrevivio %s' % testigo)
    if HAY_J2:
        check('J2 el fichero al OTRO LADO del junction sobrevive a la purga',
              os.path.exists(os.path.join(VICTIMA, 'vive.txt')),
              'la purga cruzo el enlace y borro la victima')
        check('J2b el junction mismo si se quita de la carpeta',
              not os.path.exists(os.path.join(TEMP_JAULA, 'trampa')),
              'el enlace sigue plantado')
    else:
        print('NOTA: mklink /J fallo; J2/J2b no se miden.')
    check('J2c y la purga normal sigue purgando',
          not os.path.exists(os.path.join(TEMP_JAULA, 'normal')),
          'quedo __delphi-temp\\normal')

    print('NOTA: sin medir aqui y apuntado en el CHANGELOG: la caida CESU-8 '
          'del decodificador (necesita un hijo que emita esos bytes), el '
          'AgentTempDir con Roots[0] en ReadOnlyPaths (necesita el nodo del '
          'escritorio) y la clave de cache entre workspaces solapados.')
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    # Los junctions se quitan como ENTRADA antes del rmtree, por la misma
    # razon que la purga: no vaya a cruzarlos alguien.
    for j in (os.path.join(JAIL, 'vendor', 'out'),
              os.path.join(TEMP_JAULA, 'trampa')):
        try:
            os.rmdir(j)
        except OSError:
            pass
    borra(BASE)

print('== test_round46: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
