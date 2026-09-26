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
import subprocess
import time
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
BASE = mc.carpeta('tray')
EXE = mc.copia_exe(BASE)

TOK = 'tray-bat'
PORT_GUI = mc.puerto_libre()
PORT_TERM = mc.puerto_libre()

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


class NoArranca(Exception):
    """La bandeja no levanto: T1 ya lo ha dicho en rojo y el resto no tiene
    contra quien medir. Antes era un SystemExit a secas: salia con rc=0 y sin
    resumen."""


def contesta(r):
    """Una respuesta de tools/call que es un EXITO: con texto y sin isError
    (un "error: ..." o un "RECHAZADO" en prosa llegan con isError)."""
    res = (r or {}).get('result') or {}
    c = res.get('content') or [{}]
    return 'error' not in (r or {}) and res.get('isError') is not True and bool(c[0].get('text'))


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


# sin las DELPHI_MCP_* de quien lanza la bateria: el puerto, la jaula y el
# token salen de SU settings.ini y de nada mas
gui = subprocess.Popen([EXE, '/gui'], env=mc.entorno())
term = subprocess.Popen([EXE, '--http', str(PORT_TERM)], env=mc.entorno(),
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    # ---------------------------------------------------------------- T1
    # el host de bandeja levanta VCL antes que el HTTP: tarda mas que el
    # terminal. Se espera al PUERTO, no a un sleep a ojo
    arriba = mc.espera_puerto(PORT_GUI, gui, 40)
    check('T1 la bandeja levanta el puerto de settings.ini (%d)' % PORT_GUI,
          arriba, 'no escucha en 40s')
    if not arriba:
        raise NoArranca

    cg = mc.Http(PORT_GUI, TOK)
    cg.session('tray-bat')
    ini = cg.init
    check('T1b initialize contesta',
          bool(ini and ini.get('result', {}).get('serverInfo')), ini)

    # ---------------------------------------------------------------- T2
    r = cg.call_msg('delphi_workspace', {})
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
    mc.espera_puerto(PORT_TERM, term, 30)
    ct = mc.Http(PORT_TERM, TOK)
    ct.session('tray-bat')
    a = cg.request('tools/list')
    b = ct.request('tools/list')
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
        ('delphi_read', {'path': os.path.join(REPO, 'src', 'Server', 'Lsp.Texts.pas'),
                         'fromline': 1, 'toline': 20}),
        ('delphi_search', {'root': os.path.join(REPO, 'src'),
                           'query': 'SERVER_VERSION'}),
        ('delphi_git', {'repo': REPO, 'command': 'status'}),
        ('delphi_symbols', {'path': os.path.join(REPO, 'src', 'Server',
                                                 'Lsp.Service.pas')}),
    ]
    for tool, args in tanda:
        try:
            r = cg.call_msg(tool, args)
            t = r['result']['content'][0]['text']
            check('T4 %s contesta sin consola (%d bytes)' % (tool, len(t)),
                  contesta(r), t[:120])
        except Exception as e:
            check('T4 %s contesta sin consola' % tool, False, e)

    try:
        r = cg.call_msg('delphi_diagnostics',
                        {'path': os.path.join(REPO, 'src', 'Server', 'Lsp.Texts.pas')},
                        180)
        t = r['result']['content'][0]['text']
        check('T4b delphi_diagnostics (motor LSP) contesta en bandeja',
              contesta(r), t[:160])
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
except NoArranca:
    pass
finally:
    for pr in (gui, term):
        try:
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(pr.pid)],
                           capture_output=True, timeout=60)
        except Exception:
            pass

mc.fin('test_tray')
