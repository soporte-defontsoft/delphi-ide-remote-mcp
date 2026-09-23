# -*- coding: utf-8 -*-
"""E2E battery: EL GUARDIAN de la jaula, parametro a parametro.

La regla de la jaula vive en UNA funcion (PathDenied / ReadPathDenied). Lo que
no esta centralizado es acordarse de llamarla: ~60 llamadas a mano repartidas
por una veintena de units, y nada obliga a una tool nueva -ni a un parametro
nuevo de una vieja- a pasar por ahi. Medido el 2026-09-21: de los cinco
parametros de "destino que elige quien llama", tres comprobaban y dos no, y con
el nodo de escritorio real eso dejo que una llamada escribiera una captura del
escritorio del operador FUERA de la jaula.

Esta bateria no arregla eso: lo VIGILA. Y tiene dos mitades, de las cuales la
segunda es la que de verdad importa:

  1. A cada parametro que sea una ruta LOCAL se le mete una ruta de fuera de
     la jaula y se exige el rechazo de la jaula.
  2. Se comprueba que NINGUN parametro del contrato vivo con pinta de ruta se
     haya quedado sin clasificar. Esta mitad no sabe probar un parametro que
     no conoce - pero sabe decir "esto parece una ruta y nadie lo ha mirado",
     y eso es lo que caza la tool que se escriba manana.

POR QUE UNA LISTA REVISADA Y NO UN REGEX: no todo lo que parece ruta lo es, y
equivocarse aqui es exigir un rechazo que seria un bug. Medido sobre el
contrato vivo (38 tools, 200 parametros):

  delphi_paserver exe      un fichero de la carpeta desplegada EN EL TARGET
  delphi_config   remotedir  carpeta EN EL TARGET
      -> son rutas, pero de OTRA maquina: nuestra jaula no aplica.
  delphi_adb_linux project   un NOMBRE (el nodo incluido), no una ruta
  delphi_search   pattern    una MASCARA de fichero
  delphi_git      args       argumentos libres de git, con su propio filtro

Usage:  python tests/test_round45.py [path-to-DelphiLspMcp.exe]
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
        print('FAIL', name, '--', str(detail).replace('\n', ' ')[:260])


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'round45')


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
# El vault de mentira: sin VaultPath las cinco vault_* (el unico registro
# CONDICIONAL del repo) no salen en tools/list y G1 no las ve - asi
# quedaron sus 'path' sin clasificar hasta la auditoria del 21-sep.
VAULT = os.path.join(BASE, 'vault')
os.makedirs(VAULT, exist_ok=True)
JAIL = os.path.join(BASE, 'jail')
# FUERA de la jaula y FUERA de la zona de biblioteca (leer la RTL SI es
# legitimo, asi que un path de Embarcadero no valdria de prueba). Y dentro
# del arbol de la bateria, que no se deja nada en la maquina.
FUERA = os.path.join(BASE, 'ajeno')
for d in (EXEDIR, JAIL, FUERA):
    os.makedirs(d, exist_ok=True)
shutil.copy(SRC, os.path.join(EXEDIR, 'DelphiLspMcp.exe'))
NODO_SRC = os.path.join(REPO, 'node', 'McpDesktopNode.exe')
if os.path.isfile(NODO_SRC):
    os.makedirs(os.path.join(EXEDIR, 'node'), exist_ok=True)
    shutil.copy(NODO_SRC, os.path.join(EXEDIR, 'node', 'McpDesktopNode.exe'))

# Ficheros de verdad ahi fuera: un rechazo tiene que ser POR LA JAULA, no por
# "no existe". Si el fichero no estuviera, media bateria mediria otra cosa.
AJENO_PAS = os.path.join(FUERA, 'Ajena.pas')
open(AJENO_PAS, 'w', newline='\r\n').write(
    'unit Ajena;\n\ninterface\n\nimplementation\n\nend.\n')
AJENO_DPROJ = os.path.join(FUERA, 'Ajeno.dproj')
open(AJENO_DPROJ, 'w', newline='\r\n').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<Project><PropertyGroup>'
    '<MainSource>Ajeno.dpr</MainSource></PropertyGroup></Project>\n')
open(os.path.join(FUERA, 'Ajeno.dpr'), 'w', newline='\r\n').write(
    'program Ajeno;\nbegin\nend.\n')
AJENO_DFM = os.path.join(FUERA, 'Ajena.dfm')
open(AJENO_DFM, 'w', newline='\r\n').write('object Form1: TForm1\nend\n')
AJENO_EXE = os.path.join(FUERA, 'ajeno.exe')
open(AJENO_EXE, 'wb').write(b'MZ')
# Y uno DENTRO, para poder probar "workdir" sin que el "path" falle antes.
open(os.path.join(JAIL, 'propio.exe'), 'wb').write(b'MZ')
AJENO_TXT = os.path.join(FUERA, 'ajeno.txt')
open(AJENO_TXT, 'w').write('hola\n')
AJENO_STYLE = os.path.join(FUERA, 'ajeno.style')
open(AJENO_STYLE, 'w').write('object TStyleContainer\nend\n')
AJENO_PNG = os.path.join(FUERA, 'ajena.png')
AJENO_ZIP = os.path.join(FUERA, 'ajeno.zip')
AJENO_APK = os.path.join(FUERA, 'ajena.apk')
open(AJENO_APK, 'wb').write(b'PK\x03\x04')

DEV = '127.0.0.1:5555'

# ---------------------------------------------------------------------------
# LA LISTA CLASIFICADA. Cada entrada: (tool, parametro, argumentos completos).
# Los argumentos llevan lo OBLIGATORIO de esa tool ademas del parametro que se
# prueba, porque si falta algo obligatorio el rechazo que llega es otro y la
# comprobacion mediria el orden de dos negativas (me paso el 2026-09-21).
# ---------------------------------------------------------------------------
PROBAR = [
    ('delphi_read', 'path', {'path': AJENO_PAS}),
    ('delphi_symbols', 'path', {'path': AJENO_PAS}),
    ('delphi_definition', 'path', {'path': AJENO_PAS, 'line': 0, 'character': 5}),
    ('delphi_hover', 'path', {'path': AJENO_PAS, 'line': 0, 'character': 5}),
    ('delphi_completion', 'path', {'path': AJENO_PAS, 'line': 0, 'character': 5}),
    ('delphi_signature', 'path', {'path': AJENO_PAS, 'line': 0, 'character': 5}),
    ('delphi_references', 'path', {'path': AJENO_PAS, 'line': 0, 'character': 5}),
    ('delphi_rename_symbol', 'path', {'path': AJENO_PAS, 'line': 0,
                                      'character': 5, 'newname': 'Otra'}),
    ('delphi_diagnostics', 'path', {'path': AJENO_PAS}),
    ('delphi_edit', 'path', {'path': AJENO_PAS, 'old': 'unit Ajena;',
                             'new': 'unit Ajena2;'}),
    ('delphi_textedit', 'path', {'path': AJENO_TXT, 'old': 'hola',
                                 'new': 'adios'}),
    ('delphi_search', 'root', {'root': FUERA, 'query': 'unit'}),
    ('delphi_list', 'root', {'root': FUERA}),
    ('delphi_projects', 'root', {'root': FUERA}),
    ('delphi_fetch', 'path', {'path': AJENO_TXT}),
    ('delphi_upload', 'path', {'path': os.path.join(FUERA, 'subido.txt'),
                               'offset': 0, 'chunkbase64': 'aG9sYQ=='}),
    ('delphi_delete', 'path', {'path': AJENO_TXT}),
    ('delphi_move', 'path', {'path': AJENO_TXT,
                             'dest': os.path.join(JAIL, 'movido.txt')}),
    ('delphi_move', 'dest', {'path': os.path.join(JAIL, 'x.txt'),
                             'dest': os.path.join(FUERA, 'movido.txt')}),
    ('delphi_package', 'dir', {'dir': FUERA}),
    ('delphi_package', 'outfile', {'dir': JAIL, 'outfile': AJENO_ZIP}),
    ('delphi_build', 'project', {'project': AJENO_DPROJ}),
    ('delphi_config', 'project', {'project': AJENO_DPROJ, 'command': 'view'}),
    ('delphi_create', 'dir', {'kind': 'project-console', 'name': 'Nuevo',
                              'dir': FUERA}),
    ('delphi_create', 'project', {'kind': 'unit', 'name': 'UNueva',
                                  'project': AJENO_DPROJ}),
    ('delphi_designer', 'path', {'command': 'tree', 'path': AJENO_DFM}),
    ('delphi_styles', 'path', {'command': 'view', 'path': AJENO_STYLE}),
    ('delphi_git', 'repo', {'repo': FUERA, 'command': 'status'}),
    ('delphi_test', 'path', {'command': 'discover', 'path': FUERA}),
    ('delphi_test', 'project', {'command': 'run', 'project': AJENO_DPROJ}),
    ('delphi_desktop', 'out', {'command': 'screenshot', 'out': FUERA}),
    ('delphi_adb', 'out', {'command': 'screenshot', 'device': DEV,
                           'out': AJENO_PNG}),
    ('delphi_adb', 'apk', {'command': 'install', 'device': DEV,
                           'apk': AJENO_APK}),
    # LA PRUEBA DE QUE EL SUELO DE LA PUERTA VIVE (v1.0.14). Dentro de la
    # tool el rechazo del profile llega ANTES que el PathDenied de project,
    # asi que sin un PAServer vivo esta sonda era imposible. El suelo
    # (ArgPathOutsideDenied, que lee [RutaDelServidor]) muerde en la puerta,
    # antes que la tool: si esto contesta JAULA, es el suelo quien contesta.
    # 1.0.16: delphi_desktop ES la tool (el alias delphi_adb_linux ya no
    # existe), asi que su project es la sonda.
    ('delphi_desktop', 'project', {'command': 'screenshot', 'profile': 'x',
                                   'project': AJENO_DPROJ}),
    # OJO: en delphi_paserver el perfil se llama "name", no "profile". Un
    # parametro inventado contesta "Unknown parameter" y la comprobacion
    # mediria eso en vez de la jaula.
    ('delphi_paserver', 'project', {'command': 'remote-run',
                                    'project': AJENO_DPROJ, 'name': 'x'}),
]

# NO son rutas locales. Cada exclusion lleva SU MOTIVO: una exclusion sin
# motivo escrito es por donde se cuela la siguiente.
EXCLUIDOS = {
    ('delphi_paserver', 'exe'): 'fichero de la carpeta desplegada EN EL TARGET',
    ('delphi_config', 'remotedir'): 'carpeta EN EL TARGET, no de esta maquina',
    ('delphi_git', 'args'): 'argumentos libres de git; filtro propio (GitArgDenied)',
    ('delphi_search', 'pattern'): 'mascara de fichero, no una ruta',
    ('delphi_list', 'pattern'): 'mascara de fichero, no una ruta',
    ('delphi_config', 'output'): 'nombre relativo de carpeta de salida; vetado aparte',
    ('delphi_config', 'path'): 'search path: puede apuntar a la zona de biblioteca, que es legitima',
    ('delphi_styles', 'project'): 'acepta carpeta o .dproj; cubierto por test_styles',
    ('delphi_styles', 'child'): 'ruta DENTRO de un estilo, no del disco',
    ('delphi_changeset', 'path'): 'necesita el id de un begin: lo mide G2b',
    ('delphi_changeset', 'dest'):
        'idem G2b, y FUERA de la jaula (la excusa vieja apuntaba a '
        'test_changeset, que solo usa rutas de dentro - auditoria 21-sep)',
    # Las vault_* existen porque el settings declara VaultPath: sus rutas
    # son RELATIVAS al vault y las vigila la guarda del vault, no la jaula.
    ('vault_read', 'path'): 'ruta RELATIVA al vault; guarda propia',
    ('vault_append', 'path'): 'idem vault',
    ('vault_create', 'path'): 'idem vault',
    ('vault_patch', 'path'): 'idem vault',
    ('vault_search', 'target'): 'nota/carpeta RELATIVA al vault; guarda propia',
    ('vault_search', 'subfolder'): 'idem vault',
    ('vault_search', 'pattern'): 'mascara de nombre de nota, no una ruta',
    ('vault_append', 'anchor'): 'texto ancla DENTRO de la nota, no una ruta',
    ('vault_patch', 'old_text'): 'texto a sustituir en la nota, no una ruta',
}

TOK = 'r45'
sk = socket.socket()
sk.bind(('127.0.0.1', 0))
PORT = sk.getsockname()[1]
sk.close()
# TODOS los interruptores encendidos: lo que se mide es la jaula, y un "esta
# tool esta apagada" contestaria antes y la comprobacion no mediria nada.
open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.R45]', 'Token=%s' % TOK, 'Roots=%s' % JAIL,
    'AllowDesktopControl=1', 'AllowRemoteRun=1', 'AllowTests=1',
    'RemoteRunProjects=Ajeno;McpDesktopNode',
    'AdbAllowedDevices=%s' % DEV,
    'VaultPath=%s' % VAULT, '',
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
                         'clientInfo': {'name': 'r45', 'version': '1'}}})
rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
RID = [100]


def call(tool, args):
    RID[0] += 1
    r, _ = rpc({'jsonrpc': '2.0', 'id': RID[0], 'method': 'tools/call',
                'params': {'name': tool, 'arguments': args}})
    try:
        return r['result']['content'][0]['text']
    except Exception:
        return json.dumps(r)[:300]


# La negativa de la JAULA, no una cualquiera: casi todas empiezan por
# RECHAZADO y dar por buena otra seria justo el fallo que esto vigila.
JAULA = 'FUERA de los workspaces permitidos'

# Pista de que la descripcion de un parametro habla de una ruta. Solo se usa
# para DESCUBRIR, nunca para decidir: lo que decide es la lista de arriba.
PISTA = re.compile(r'(?i)\b(ruta|path|carpeta|directorio|directory|folder|'
                   r'fichero|file|absolut|\.dproj|\.pas|\.apk|\.exe)')
# Parametros cuya descripcion menciona ficheros de pasada (una mascara, un
# numero de lineas, un modo) y que no son rutas ni de lejos. Aparte de
# EXCLUIDOS porque aqui no hay nada que razonar: es ruido del descubridor.
RUIDO = {'lines', 'maxbytes', 'command', 'kind', 'mode', 'platform', 'sdk',
         'section', 'version', 'filter', 'prop', 'value', 'framework',
         'create', 'dirs', 'includetrash', 'purge', 'restore', 'toline',
         'atline', 'old', 'new', 'content', 'edits', 'chunkbase64',
         'sha256', 'title', 'agent', 'profile', 'name', 'newname',
         'message', 'args', 'query', 'text', 'code', 'x', 'y', 'line',
         'character', 'verbosity', 'config', 'target', 'deviceid',
         'device', 'out_', 'offset', 'maxresults', 'wholeword', 'limit',
         'linecount', 'subfolder', 'from', 'to'}

try:
    # ------------------------------------------------------------------ G1
    # LA MITAD QUE VIGILA, y la que caza la tool que se escriba manana: todo
    # parametro del contrato VIVO con pinta de ruta tiene que estar
    # clasificado - probado o excluido CON MOTIVO. Uno nuevo no se sabe
    # probar, pero si se sabe decir que nadie lo ha mirado.
    r, _ = rpc({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'})
    tools = r['result']['tools']
    probados = {(t, p) for t, p, _ in PROBAR}
    sin_clasificar = []
    for t in tools:
        props = (t.get('inputSchema') or {}).get('properties') or {}
        for p, meta in props.items():
            if p.lower() in RUIDO:
                continue
            if not PISTA.search(meta.get('description') or ''):
                continue
            if (t['name'], p) in probados or (t['name'], p) in EXCLUIDOS:
                continue
            sin_clasificar.append('%s.%s' % (t['name'], p))
    check('G1 ningun parametro con pinta de ruta se queda sin clasificar',
          not sin_clasificar,
          'sin clasificar: %s  (anadelo a PROBAR o a EXCLUIDOS con su motivo)'
          % sorted(sin_clasificar))
    # 41 = el contrato entero (delphi_run retirada el 23-sep) con los interruptores y el vault encendidos.
    # Con >=30, un recorte de ocho tools pasaba callado y el descubridor
    # perdia justo a las de registro condicional (auditoria 21-sep).
    check('G1b ...y la lista mira el contrato VIVO, no una copia',
          len(tools) >= 41, '%d tools' % len(tools))

    # ------------------------------------------------------------------ G2
    # Y ahora, una por una. Cada fallo aqui es un parametro por el que se
    # escribe o se lee fuera del workspace.
    fugas = []
    for tool, par, args in PROBAR:
        try:
            t = call(tool, args)
        except Exception as ex:
            t = 'EXCEPCION %s' % ex
        if JAULA not in t:
            fugas.append('%s.%s -> %s' % (tool, par, t[:110].replace('\n', ' ')))
    check('G2 los %d parametros de ruta rechazan una ruta de fuera'
          % len(PROBAR), not fugas, ' | '.join(fugas[:4]))
    if fugas:
        print()
        for f in fugas:
            print('    FUGA:', f)
        print()

    # ------------------------------------------------------------------ G4
    # El suelo es una capa REDUNDANTE: si se quedase vacio (RTTI que no
    # emite, un registro que cambia) no romperia nada y nadie lo notaria.
    # Por eso publica cuantos parametros vigila. Son 39 y no las MARCAS
    # que hay en el fuente: la de TDelphiFileParams.path la heredan cuatro
    # tools (definition, signature, hover, completion) - una marca, cuatro
    # parametros del contrato. El primer censo contaba marcas y decia 39;
    # lo corrigio el propio servidor la primera vez que se le pregunto.
    # 1.0.16: 42 -> 43, porque delphi_desktop paso a ser la tool del
    # escritorio por perfil y gano el "project" marcado que tenia su alias.
    # 22-sep: 43 -> 41, al retirar el alias delphi_adb_linux (out y project).
    # 23-sep: 41 -> 39, al retirar delphi_run (path y workdir).
    w = call('delphi_workspace', {})
    try:
        vigilados = json.loads(w).get('server', {}).get('jailedParams', -1)
    except Exception:
        vigilados = -1
    check('G4 el suelo de la puerta vigila los 39 parametros marcados',
          vigilados == 39, 'jailedParams=%s' % vigilados)

    # ----------------------------------------------------------------- G2b
    # Los dos parametros de delphi_changeset que la tabla no puede sondar
    # (stage necesita el id de un begin). Su exclusion decia "cubierto por
    # test_changeset" y era FALSO: aquella bateria solo usa rutas de
    # DENTRO - se podia borrar el PathDenied del stage con la suite en
    # verde (auditoria 21-sep). El stage valida en el momento: dos llamadas.
    rb = call('delphi_changeset', {'command': 'begin'})
    cid = rb.split('CHANGESET ')[1].split(' ')[0] if 'CHANGESET ' in rb else ''
    check('G2b begin da un changeset para sondar', bool(cid), rb[:150])
    if cid:
        t = call('delphi_changeset', {'command': 'stage', 'id': cid,
                                      'kind': 'edit', 'path': AJENO_PAS,
                                      'old': 'unit Ajena;', 'new': 'unit A2;'})
        check('G2b delphi_changeset.path rechaza la ruta de fuera',
              JAULA in t, t[:150])
        t = call('delphi_changeset', {'command': 'stage', 'id': cid,
                                      'kind': 'move',
                                      'path': os.path.join(JAIL, 'Propia.pas'),
                                      'dest': os.path.join(FUERA, 'robada.pas')})
        check('G2b delphi_changeset.dest rechaza el destino de fuera',
              JAULA in t, t[:150])

    # ------------------------------------------------------------------ G3
    # El otro lado, sin el cual esto no vale: la misma llamada DENTRO de la
    # jaula no puede morir por la ruta. Un guardian que cierra de mas hace
    # mas dano que el agujero.
    dentro = os.path.join(JAIL, 'Propia.pas')
    open(dentro, 'w', newline='\r\n').write(
        'unit Propia;\n\ninterface\n\nimplementation\n\nend.\n')
    d1 = call('delphi_read', {'path': dentro})
    d2 = call('delphi_list', {'root': JAIL})
    check('G3 lo de DENTRO de la jaula sigue pasando',
          JAULA not in d1 and JAULA not in d2, (d1 + ' | ' + d2)[:240])

    # ------------------------------------------------------------------ G5
    # El demonio de adb tiene que sobrevivir a la llamada: nacia dentro del
    # job de la llamada y moria con ella, y una conexion wifi se perdia entre
    # un connect y el devices siguiente (medido 2026-09-23 con un movil).
    # Sin dispositivo aqui, lo que se mide es el demonio: vivo tras la llamada.
    a = call('delphi_adb', {'command': 'devices'})
    t = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq adb.exe'],
                       capture_output=True, text=True).stdout
    check('G5 el demonio adb.exe sobrevive a la llamada (fuera del job)',
          '"devices"' in a and 'adb.exe' in t, (a[:120] + ' | ' + t[-120:]))
finally:
    try:
        proc.kill()
    except Exception:
        pass
    time.sleep(0.5)
    borra(BASE)

print('== test_round45: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
