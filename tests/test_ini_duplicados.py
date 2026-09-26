# -*- coding: utf-8 -*-
"""Duplicados en settings.ini (David, 2026-09-23): un copia-pega futuro puede
dejar el mismo token en dos workspaces, la misma clave dos veces en una
seccion o la misma seccion dos veces. TIniFile lee lo primero y calla; el
servidor CIERRA los workspaces afectados (401) y lo dice al arrancar.

  D1  dos workspaces con el mismo Token=: los dos 401
  D2  Token= igual a ReadOnlyToken= en uno: 401 (con cualquiera de los dos)
  D3  clave repetida dentro de la seccion (Roots= dos veces): 401
  D4  seccion escrita dos veces: 401 con el token de cualquiera de las dos
  D5  el workspace limpio de al lado sigue entrando, y se llama como se llama
  D6  el arranque nombra cada caso (AVISO ...)

Usage:  python tests/test_ini_duplicados.py [path-to-DelphiLspMcp.exe]
"""
import json, os, subprocess
import mcp_cliente as mc
from mcp_cliente import check


BASE = mc.carpeta('inidup')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(EXEDIR)

open(os.path.join(EXEDIR, 'settings.ini'), 'w').write('\n'.join([
    '[Server]', 'BindIP=127.0.0.1', '',
    '[Workspace.Uno]', 'Token=t-uno', 'Roots=%s' % JAIL, '',
    '[Workspace.Dos]', 'Token=t-uno', 'Roots=%s' % JAIL, '',        # D1: copia-pega del token
    '[Workspace.Tres]', 'Token=t-tres', 'ReadOnlyToken=t-tres', 'Roots=%s' % JAIL, '',  # D2
    '[Workspace.Cuatro]', 'Token=t-cuatro', 'Roots=%s' % JAIL, 'Roots=%s' % JAIL, '',   # D3
    '[Workspace.Cinco]', 'Token=t-cinco', 'Roots=%s' % JAIL, '',
    '[Workspace.Cinco]', 'Token=t-cinco-bis', 'Roots=%s' % JAIL, '',  # D4
    '[Workspace.Limpio]', 'Token=t-limpio', 'Roots=%s' % JAIL, '',
]))

PORT = mc.puerto_libre()
# lo que dice al arrancar (los AVISO de D6) va a un FICHERO: una tuberia que
# nadie lee hasta matarlo puede llenarse y bloquear al servidor
LOG = os.path.join(BASE, 'arranque.log')
with open(LOG, 'w') as _log:
    proc = mc.lanza_http(EXE, PORT, mc.entorno(), stdout=_log, stderr=subprocess.STDOUT)


def init(tok):
    """HTTP status of an initialize with that Bearer, and the session id."""
    st, h, _ = mc.Http(PORT, tok).post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": mc.PROTOCOLO, "capabilities": {},
        "clientInfo": {"name": "inidup", "version": "1"}}})
    return st, (None if st >= 400 else h.get('Mcp-Session-Id'))


def workspace_name(tok, sid):
    cli = mc.Http(PORT, tok)
    cli.rpc({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid=sid)
    t = cli.call('delphi_workspace', {}, sid=sid)
    try:
        return json.loads(t).get('workspace')
    except Exception:
        return t[:200]


try:
    check('D1 token compartido: el primero 401', init('t-uno')[0] == 401, init('t-uno'))
    check('D2 Token = ReadOnlyToken: 401', init('t-tres')[0] == 401, init('t-tres'))
    check('D3 clave repetida en la seccion: 401', init('t-cuatro')[0] == 401, init('t-cuatro'))
    check('D4 seccion repetida: 401 con el primer token', init('t-cinco')[0] == 401, init('t-cinco'))
    check('D4 seccion repetida: 401 con el segundo token', init('t-cinco-bis')[0] == 401, init('t-cinco-bis'))
    code, sid = init('t-limpio')
    check('D5 el workspace limpio entra', code == 200 and sid, (code, sid))
    if sid:
        check('D5 y se llama Limpio', workspace_name('t-limpio', sid) == 'Limpio', '')
finally:
    proc.kill()
    proc.wait()
    out = open(LOG, encoding='utf-8', errors='replace').read()

avisos = [l for l in out.splitlines() if 'AVISO' in l]
check('D6 arranque: nombra el par que comparte token', any('[Workspace.Uno] y [Workspace.Dos]' in l for l in avisos), avisos)
check('D6 arranque: nombra Token = ReadOnlyToken', any('[Workspace.Tres]' in l and 'MISMO valor' in l for l in avisos), avisos)
check('D6 arranque: nombra la clave repetida', any('[Workspace.Cuatro] repite la clave Roots' in l for l in avisos), avisos)
check('D6 arranque: nombra la seccion repetida', any('[Workspace.Cinco] aparece DOS veces' in l for l in avisos), avisos)

mc.fin('ini duplicados')
