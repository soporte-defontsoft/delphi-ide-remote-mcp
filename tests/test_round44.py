# -*- coding: utf-8 -*-
"""E2E battery: __delphi-temp, y nada en el %TEMP% de la maquina.

El servidor escribia sus temporales en el %TEMP% del PC, a mano y en SIETE
sitios distintos: fuera de toda jaula, sin recoger y sin un nombre comun.
Medido el 2026-09-21: 56,4 MB olvidados alli -33 capturas del escritorio del
operador de dos dias antes y una salida de remoterun de 10,7 MB-, y un
fichero de 10 bytes que una bateria se dejo suelto acabo siendo el "proyecto"
de las units de otras tres.

Decision de David: una carpeta nuestra, __delphi-temp, hermana de
__delphi-patch, y que se pueda borrar en cualquier momento. Con DOS casas y
un criterio:

    lo del SERVIDOR     junto al ejecutable   (el agente no lo toca nunca)
    lo ENTREGABLE       dentro del workspace  (el agente se lo baja)

La segunda no es un capricho: delphi_fetch comprueba la jaula, asi que una
captura fuera de ella es una captura que no se puede entregar - y la tool lo
prometia por escrito ("bajatela con delphi_fetch").

Usage:  python tests/test_round44.py [path-to-DelphiLspMcp.exe]
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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:280])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round44')


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
shutil.copy(SRC, os.path.join(EXEDIR, 'DelphiLspMcp.exe'))

NODO_SRC = os.path.join(REPO, 'node', 'McpDesktopNode.exe')
HAY_NODO = os.path.isfile(NODO_SRC)
if HAY_NODO:
    os.makedirs(os.path.join(EXEDIR, 'node'), exist_ok=True)
    shutil.copy(NODO_SRC, os.path.join(EXEDIR, 'node', 'McpDesktopNode.exe'))

TEMP_SERVIDOR = os.path.join(EXEDIR, '__delphi-temp')
TEMP_JAULA = os.path.join(JAIL, '__delphi-temp')
# El %TEMP% de la MAQUINA: las carpetas que el servidor usaba antes. Se mira
# que no vuelva a aparecer ninguna.
VIEJAS = [os.path.join(tempfile.gettempdir(), n) for n in
          ('delphi-mcp-desktop', 'delphi-mcp-remoterun')]
for v in VIEJAS:
    shutil.rmtree(v, ignore_errors=True)

# Una migaja plantada a mano en la casa del servidor: al arrancar tiene que
# desaparecer sola. Declarar una carpeta "borrable" no sirve de nada si no la
# borra nadie - eso es literalmente como se acumularon los 56 MB.
os.makedirs(TEMP_SERVIDOR, exist_ok=True)
MIGAJA = os.path.join(TEMP_SERVIDOR, 'sobra-de-la-vez-anterior.txt')
open(MIGAJA, 'w').write('basura de una ejecucion anterior\n')
os.makedirs(os.path.join(TEMP_SERVIDOR, 'carpeta-vieja'), exist_ok=True)

TOK = 'r44'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R44]', 'Token=%s' % TOK, 'Roots=%s' % JAIL,
    'AllowDesktopControl=1', '',
]))

proc = subprocess.Popen([os.path.join(EXEDIR, 'DelphiLspMcp.exe'),
                         '--http', str(PORT)],
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
                         'clientInfo': {'name': 'r44', 'version': '1'}}})
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


def pngs(d):
    if not os.path.isdir(d):
        return []
    return [os.path.join(r, f)
            for r, _, fs in os.walk(d) for f in fs if f.lower().endswith('.png')]


try:
    # ------------------------------------------------------------------ T1
    check('T1 al arrancar se vacia la casa del servidor',
          not os.path.exists(MIGAJA) and
          not os.path.isdir(os.path.join(TEMP_SERVIDOR, 'carpeta-vieja')),
          'sigue ahi %s' % MIGAJA)

    # ------------------------------------------------------------------ T2
    # El fichero del mensaje de git vivia en el %TEMP% de la maquina. Se crea
    # y se borra dentro de la misma llamada, asi que lo que se mide es DONDE:
    # que la casa del servidor exista despues, y la del PC no se toque.
    repo = os.path.join(JAIL, 'r')
    os.makedirs(repo, exist_ok=True)
    call('delphi_git', {'repo': repo, 'command': 'init'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.email', 'message': 'r44@test'})
    call('delphi_git', {'repo': repo, 'command': 'config',
                        'args': 'user.name', 'message': 'R44'})
    open(os.path.join(repo, 'a.txt'), 'w').write('uno\n')
    call('delphi_git', {'repo': repo, 'command': 'add', 'args': '-A'})
    c = call('delphi_git', {'repo': repo, 'command': 'commit',
                            'message': 'mensaje\n\ncon cuerpo'})
    check('T2 un commit con mensaje sigue funcionando',
          'exit=0' in c or '1 file changed' in c, c[:240])
    check('T2b ...y su fichero temporal se hizo en la casa del servidor',
          os.path.isdir(os.path.join(TEMP_SERVIDOR, 'git')),
          'no existe %s' % os.path.join(TEMP_SERVIDOR, 'git'))
    check('T2c ...y no quedo rastro del mensaje',
          not os.listdir(os.path.join(TEMP_SERVIDOR, 'git'))
          if os.path.isdir(os.path.join(TEMP_SERVIDOR, 'git')) else False,
          os.listdir(os.path.join(TEMP_SERVIDOR, 'git'))
          if os.path.isdir(os.path.join(TEMP_SERVIDOR, 'git')) else 'no existe')

    # ------------------------------------------------------------------ T3
    # La captura SIN "out": el defecto. Antes caia en el %TEMP% del PC, donde
    # delphi_fetch no puede ir a buscarla.
    # "NO pude capturar" es del NODO, no de la tool: la maquina no puede
    # copiar la pantalla en este momento (sesion bloqueada o desconectada:
    # "Acceso denegado"). Eso no es un fallo del contrato y no se pinta de
    # rojo - pero se DICE, porque una bateria que calla lo que no ha medido
    # es una bateria que miente en verde.
    s = call('delphi_desktop', {'command': 'screenshot'}) if HAY_NODO else ''
    PUEDE = HAY_NODO and 'NO pude capturar' not in s
    if HAY_NODO and not PUEDE:
        print('NOTA: esta maquina no puede capturar la pantalla ahora mismo '
              '(el nodo dice "NO pude capturar"). T3 y T4 no se miden.')
    if PUEDE:
        check('T3 la captura por defecto cae DENTRO del workspace',
              bool(pngs(TEMP_JAULA)),
              'no hay png bajo %s | %s' % (TEMP_JAULA, s[:200]))
    # Esta SI se mide siempre: aunque la captura falle, lo que no puede pasar
    # es que el servidor vuelva a tocar el %TEMP% de la maquina.
    check('T3b el servidor no vuelve a tocar el %TEMP% de la maquina',
          all(not os.path.isdir(v) for v in VIEJAS),
          'han vuelto: %s' % [v for v in VIEJAS if os.path.isdir(v)])
    if PUEDE:

        # -------------------------------------------------------------- T4
        # Y ahora lo que la tool promete por escrito: "bajatela con
        # delphi_fetch". Con el defecto viejo esto era imposible.
        foto = pngs(TEMP_JAULA)[0] if pngs(TEMP_JAULA) else ''
        if foto:
            g = call('delphi_fetch', {'path': foto})
            check('T4 y delphi_fetch SI puede bajarsela, como promete la tool',
                  'FUERA de los workspaces' not in g and
                  ('sha256' in g.lower() or 'bytes' in g.lower() or
                   'base64' in g.lower()), g[:280])
        else:
            check('T4 y delphi_fetch SI puede bajarsela', False,
                  'no hubo captura que bajar')
    elif not HAY_NODO:
        print('NOTA: no hay node/McpDesktopNode.exe; T3 y T4 no se miden.')

    # ------------------------------------------------------------------ T7
    # "__delphi-temp puede limpiarse entero en cada arranque del server"
    # (David). La del SERVIDOR se vacia en el arranque de verdad; la del
    # WORKSPACE no puede -al arrancar no hay workspace activo, los roots los
    # elige el token- asi que se vacia en el PRIMER uso de cada proceso. Lo
    # que se mide es el efecto, que es el mismo: lo de la vez anterior no
    # sobrevive.
    # Sin depender del nodo: lo que se mide es el ARRANQUE, y ya no hace
    # falta que nadie pida una captura para que la carpeta se vacie. Esa
    # dependencia era justo el fallo del primer intento.
    if True:
        antes = pngs(TEMP_JAULA)
        proc.kill()
        time.sleep(1.5)
        # Una migaja de la "ejecucion anterior" que tiene que desaparecer.
        # Se crea la carpeta si no esta: si T3 no llego a dejar la captura
        # -dos baterias peleandose por el nodo del escritorio, que es UNO por
        # maquina- esto reventaba con FileNotFoundError en vez de medir. Una
        # bateria informa, no se cae.
        os.makedirs(TEMP_JAULA, exist_ok=True)
        vieja = os.path.join(TEMP_JAULA, 'de-la-vez-anterior.txt')
        open(vieja, 'w').write('x')
        p2 = subprocess.Popen(
            [os.path.join(EXEDIR, 'DelphiLspMcp.exe'), '--http', str(PORT)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)
        proc = p2
        SID = None
        _, SID = rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                      'params': {'protocolVersion': '2025-06-18',
                                 'capabilities': {},
                                 'clientInfo': {'name': 'r44', 'version': '1'}}})
        rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        check('T7 al rearrancar, la carpeta del workspace se vacia entera',
              not os.path.exists(vieja),
              'sobrevivio %s' % vieja)
        check('T7b ...y las capturas de la vez anterior tampoco sobreviven',
              not any(os.path.exists(f) for f in antes),
              'sobrevivio alguna de %s' % antes[:2])

    # ------------------------------------------------------------------ T5
    # La carpeta es del servidor: se lee, no se escribe dentro.
    d = call('delphi_textedit', {'path': os.path.join(TEMP_JAULA, 'mio.txt'),
                                 'create': True, 'content': 'no'})
    check('T5 escribir DENTRO de __delphi-temp se rechaza',
          'RECHAZADO' in d and 'temporales' in d, d[:240])

    # ------------------------------------------------------------------ T6
    # Y no ensucia los listados: no es papelera, es temporal, asi que se
    # salta SIEMPRE, tambien con includetrash.
    l1 = call('delphi_list', {'root': JAIL, 'pattern': '*.png'})
    l2 = call('delphi_list', {'root': JAIL, 'pattern': '*.png',
                              'includetrash': True})
    check('T6 __delphi-temp no aparece en un listado del workspace',
          '__delphi-temp' not in l1, l1[:240])
    check('T6b ...ni siquiera pidiendo la papelera: no es papelera',
          '__delphi-temp' not in l2, l2[:240])
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    borra(BASE)

print('== test_round44: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
