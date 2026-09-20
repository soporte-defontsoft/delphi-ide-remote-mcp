# -*- coding: utf-8 -*-
"""E2E battery for the TRAY host (/gui) - the mode nobody had ever tested.

Las 51 baterias que existian arrancan el exe en modo TERMINAL: 36 por stdio y
13 con --http. El modo bandeja, que es EL QUE CORRE EN PRODUCCION, tenia cero.
Eso significa que las tres diferencias reales del host de bandeja no las
cubria nadie:

  - hace FreeConsole al arrancar: cualquier cosa que escriba en la consola
    despues de eso levanta un error de E/S en un proceso que ya no la tiene
  - corre dentro de un bucle de mensajes VCL, no en un main lineal
  - coge el puerto de settings.ini y solo de ahi (RunTray ignora la linea de
    comandos: CreateHttpServer(0))

  T1  la bandeja levanta el HTTP que dice settings.ini, sin puerto en la
      linea de comandos, y contesta initialize
  T2  el bloque "server" dice la verdad sobre quien contesta: modo bandeja,
      transporte http, y el pid es el del proceso que hemos lanzado
  T3  NO HAY DERIVA entre hosts: el mismo exe con el mismo settings.ini
      sirve exactamente las mismas tools en bandeja y en terminal. El .dpr
      lo promete ("one project cannot drift"); esto lo mide
  T4  FreeConsole no rompe ninguna tool: una tanda representativa contesta,
      incluida una que arranca un hijo DelphiLSP
  T5  cerrar la bandeja A LO BRUTO (taskkill /F, que es como se cierra de
      verdad) no deja hijos DelphiLSP huerfanos

Usage:  python tests/test_tray.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
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


def libre():
    sk = socket.socket()
    sk.bind(('127.0.0.1', 0))
    n = sk.getsockname()[1]
    sk.close()
    return n


BASE = os.path.join(tempfile.gettempdir(), 'delphi-mcp-tests', 'tray')
shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(BASE)
EXE = os.path.join(BASE, 'DelphiLspMcp.exe')
shutil.copy(SRC, EXE)

TOK = 'tray-bat'
PORT_GUI = libre()
PORT_TERM = libre()

# La jaula es el repo de verdad: las tools de LSP necesitan un proyecto real
# para tener algo que decir. Esta bateria SOLO LEE - no edita nada aqui.
open(os.path.join(BASE, 'settings.ini'), 'w').write('\n'.join([
    '[Server]',
    'Port=%d' % PORT_GUI,
    'BindIP=127.0.0.1',        # explicito: nada de pedir permiso al firewall
    '',
    '[Workspace.Bandeja]',
    'Token=%s' % TOK,
    'Roots=%s' % REPO,
    '',
]))


def rpc(port, body, sid=None, timeout=90):
    h = {'Content-Type': 'application/json',
         'Accept': 'application/json, text/event-stream',
         'Authorization': 'Bearer ' + TOK}
    if sid:
        h['Mcp-Session-Id'] = sid
    r = urllib.request.urlopen(urllib.request.Request(
        'http://127.0.0.1:%d/mcp' % port, data=json.dumps(body).encode(),
        headers=h, method='POST'), timeout=timeout)
    raw = r.read().decode('utf-8', 'replace')
    msgs = []
    for l in raw.splitlines():
        if l.startswith('data:'):
            try:
                msgs.append(json.loads(l[5:].strip()))
            except Exception:
                pass
    if not msgs:
        try:
            msgs.append(json.loads(raw))
        except Exception:
            pass
    return (msgs[-1] if msgs else None), r.headers.get('Mcp-Session-Id')


def espera(port, segundos=30):
    """El host de bandeja levanta VCL antes que el HTTP: tarda mas que el
    terminal. Se espera al PUERTO, no a un sleep a ojo."""
    fin = time.time() + segundos
    while time.time() < fin:
        sk = socket.socket()
        sk.settimeout(0.5)
        try:
            sk.connect(('127.0.0.1', port))
            sk.close()
            return True
        except Exception:
            pass
        finally:
            try:
                sk.close()
            except Exception:
                pass
        time.sleep(0.4)
    return False


def sesion(port):
    r, sid = rpc(port, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                        "params": {"protocolVersion": "2025-06-18",
                                   "capabilities": {},
                                   "clientInfo": {"name": "tray-bat",
                                                  "version": "1"}}})
    rpc(port, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    return r, sid


def llama(port, sid, tool, args, rid, timeout=90):
    r, _ = rpc(port, {"jsonrpc": "2.0", "id": rid, "method": "tools/call",
                      "params": {"name": tool, "arguments": args}}, sid,
               timeout)
    return r


def hijos_lsp(ppid):
    """Los DelphiLSP.exe cuyo padre es ESTE proceso. Filtrar por padre es
    obligatorio: en esta maquina suele haber una bandeja de produccion con
    los suyos, y matar los de otro seria mucho peor que el bug buscado."""
    out = subprocess.run(
        ['powershell', '-NoProfile', '-Command',
         "Get-CimInstance Win32_Process -Filter \"Name='DelphiLSP.exe'\" | "
         "ForEach-Object { \"$($_.ProcessId),$($_.ParentProcessId)\" }"],
        capture_output=True, text=True, timeout=60).stdout
    r = []
    for l in out.splitlines():
        p = l.strip().split(',')
        if len(p) == 2 and p[1].isdigit() and int(p[1]) == ppid:
            r.append(int(p[0]))
    return r


def vivo(pid):
    out = subprocess.run(
        ['powershell', '-NoProfile', '-Command',
         "if (Get-Process -Id %d -ErrorAction SilentlyContinue) "
         "{ 'si' } else { 'no' }" % pid],
        capture_output=True, text=True, timeout=30).stdout
    return 'si' in out


gui = subprocess.Popen([EXE, '/gui'])
term = subprocess.Popen([EXE, '--http', str(PORT_TERM)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    # ---------------------------------------------------------------- T1
    arriba = espera(PORT_GUI, 40)
    check('T1 la bandeja levanta el puerto de settings.ini (%d)' % PORT_GUI,
          arriba, 'no escucha en 40s')
    if not arriba:
        raise SystemExit

    ini, sid = sesion(PORT_GUI)
    check('T1b initialize contesta',
          bool(ini and ini.get('result', {}).get('serverInfo')), ini)

    # ---------------------------------------------------------------- T2
    r = llama(PORT_GUI, sid, 'delphi_workspace', {}, 20)
    txt = r['result']['content'][0]['text']
    d = json.loads(txt)
    srv = d.get('server') or {}
    check('T2 el bloque server dice modo bandeja',
          srv.get('mode') == 'bandeja', srv.get('mode'))
    check('T2b dice transporte http', srv.get('transport') == 'http',
          srv.get('transport'))
    check('T2c el pid es el proceso que hemos lanzado (%d)' % gui.pid,
          srv.get('pid') == gui.pid, '%s vs %s' % (srv.get('pid'), gui.pid))

    # ---------------------------------------------------------------- T3
    espera(PORT_TERM, 30)
    _, sidt = sesion(PORT_TERM)
    a, _ = rpc(PORT_GUI, {"jsonrpc": "2.0", "id": 30,
                          "method": "tools/list"}, sid)
    b, _ = rpc(PORT_TERM, {"jsonrpc": "2.0", "id": 30,
                           "method": "tools/list"}, sidt)
    na = sorted(t['name'] for t in a['result']['tools'])
    nb = sorted(t['name'] for t in b['result']['tools'])
    check('T3 bandeja y terminal sirven las MISMAS tools (%d)' % len(na),
          na == nb, 'solo bandeja: %s | solo terminal: %s' %
          (set(na) - set(nb), set(nb) - set(na)))

    # ---------------------------------------------------------------- T4
    # Sin consola (FreeConsole), cualquier escritura a Output seria un error
    # de E/S. Se ejercitan tools de distinta naturaleza, la ultima de las que
    # levantan el motor LSP.
    tanda = [
        ('delphi_help', {'command': 'tasks'}),
        ('delphi_list', {'root': os.path.join(REPO, 'src')}),
        ('delphi_read', {'path': os.path.join(REPO, 'src', 'Lsp.Texts.pas'),
                         'fromline': 1, 'toline': 20}),
        ('delphi_search', {'root': os.path.join(REPO, 'src'),
                           'query': 'SERVER_VERSION'}),
        ('delphi_git', {'repo': REPO, 'command': 'status'}),
        ('delphi_symbols', {'path': os.path.join(REPO, 'src',
                                                 'Lsp.Service.pas')}),
    ]
    rid = 100
    for tool, args in tanda:
        rid += 1
        try:
            r = llama(PORT_GUI, sid, tool, args, rid)
            t = r['result']['content'][0]['text']
            check('T4 %s contesta sin consola (%d bytes)' % (tool, len(t)),
                  len(t) > 0 and 'error' not in str(r.get('error', '')), t[:120])
        except Exception as e:
            check('T4 %s contesta sin consola' % tool, False, e)

    rid += 1
    try:
        r = llama(PORT_GUI, sid, 'delphi_diagnostics',
                  {'path': os.path.join(REPO, 'src', 'Lsp.Texts.pas')},
                  rid, 180)
        t = r['result']['content'][0]['text']
        check('T4b delphi_diagnostics (motor LSP) contesta en bandeja',
              len(t) > 0, t[:160])
    except Exception as e:
        check('T4b delphi_diagnostics (motor LSP) contesta en bandeja',
              False, e)

    # ---------------------------------------------------------------- T5
    hijos = hijos_lsp(gui.pid)
    check('T5 la bandeja tiene hijos DelphiLSP que perder (%d)' % len(hijos),
          len(hijos) > 0,
          'ninguno: T5b no estaria midiendo nada')
    subprocess.run(['taskkill', '/F', '/PID', str(gui.pid)],
                   capture_output=True, timeout=60)
    time.sleep(3)
    vivos = [p for p in hijos if vivo(p)]
    check('T5b cerrada a lo bruto no deja DelphiLSP huerfanos',
          not vivos, 'siguen vivos: %s' % vivos)
finally:
    for pr in (gui, term):
        try:
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(pr.pid)],
                           capture_output=True, timeout=60)
        except Exception:
            pass

print('== test_tray: %d OK | %d fallos ==' % (P, F))
sys.exit(1 if F else 0)
