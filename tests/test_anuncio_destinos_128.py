# -*- coding: utf-8 -*-
"""B10 de la 1.28 (David, 4-nov: "solo lo quirurgico"): delphi_adb y delphi_desktop se anuncian en
tools/list SOLO donde el workspace declara a donde ir - AdbAllowedDevices; DesktopAllowedHosts o
DesktopViewHosts (aqui, el modo local: DELPHI_MCP_ADB_DEVICES, DELPHI_MCP_DESKTOP_HOSTS,
DELPHI_MCP_DESKTOP_VIEW_HOSTS). Sin nada declarado toda llamada se niega, y las dos eran ~10 KB de
cada tools/list (medido en superficie-tools-1-27). Como el vault: siguen llamables (la llamada dice
que falta) y delphi_help dice que no estan y que clave las abre.

  D1 sin nada declarado: tools/list no anuncia delphi_adb ni delphi_desktop (ROJO en produccion)
  D2 ...delphi_help tasks dice cuales faltan y por que (ROJO en produccion)
  D3 ...delphi_help tool name=adb: HELP-010 con su clave (ROJO en produccion: la describia entera)
  D4 ...siguen llamables: la llamada contesta la tool (no "no existe")
  D5 solo DesktopViewHosts: se anuncia delphi_desktop y no delphi_adb (ROJO en produccion)
  D6 solo un dispositivo adb: se anuncia delphi_adb y no delphi_desktop (ROJO en produccion)
  D7 con los dos: las dos, y tasks no dice que falte nada

Uso:  python tests/test_anuncio_destinos_128.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('anuncio_destinos_128')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
ADB = {'DELPHI_MCP_ADB_DEVICES': mc.DESTINOS_DECLARADOS['DELPHI_MCP_ADB_DEVICES']}
DESK = {'DELPHI_MCP_DESKTOP_VIEW_HOSTS': mc.DESTINOS_DECLARADOS['DELPHI_MCP_DESKTOP_VIEW_HOSTS']}


def anunciadas(srv):
    r = srv.request('tools/list') or {}
    return {t['name'] for t in (r.get('result') or {}).get('tools', [])}


def servidor(extra, nombre):
    return mc.Stdio(EXE, mc.entorno(dict({'DELPHI_MCP_ROOTS': JAIL}, **extra)), nombre=nombre, t=60)


cat = mc.catalogo()
srv = servidor({}, 'sin-destinos')
try:
    a = anunciadas(srv)
    check('D1 sin nada declarado: tools/list no anuncia delphi_adb ni delphi_desktop',
          'delphi_help' in a and 'delphi_adb' not in a and 'delphi_desktop' not in a, sorted(a))
    t = srv.call('delphi_help', {'command': 'tasks'})
    check('D2 ...delphi_help tasks dice cuales faltan y la clave de cada una',
          cat['SF_HELP_SIN_DESTINO_ADB'] in t and cat['SF_HELP_SIN_DESTINO_DESKTOP'] in t, t[-500:])
    t = srv.call('delphi_help', {'command': 'tool', 'name': 'adb'})
    check('D3 ...delphi_help tool name=adb: HELP-010 con AdbAllowedDevices, no la tool entera',
          mc.abre(t, 'SR_HELP_TOOL_NO_DISPONIBLE_FMT') and cat['SF_HELP_SIN_DESTINO_ADB'] in t, t[:400])
    t = srv.call('delphi_desktop', {'command': 'status', 'profile': 'no-existe-b10'})
    check('D4 ...siguen llamables: delphi_desktop contesta (una negativa suya, no "esa tool no existe")',
          t != '' and not mc.es(t, 'SR_SYS_TOOL_NOT_FOUND_FMT'), t[:300])
finally:
    srv.cierra()

srv = servidor(DESK, 'solo-escritorio')
try:
    a = anunciadas(srv)
    check('D5 solo DesktopViewHosts: delphi_desktop si, delphi_adb no', 'delphi_desktop' in a and 'delphi_adb' not in a,
          sorted(a))
finally:
    srv.cierra()

srv = servidor(ADB, 'solo-adb')
try:
    a = anunciadas(srv)
    check('D6 solo un dispositivo adb: delphi_adb si, delphi_desktop no', 'delphi_adb' in a and 'delphi_desktop' not in a,
          sorted(a))
finally:
    srv.cierra()

srv = servidor(mc.DESTINOS_DECLARADOS, 'los-dos')
try:
    a = anunciadas(srv)
    t = srv.call('delphi_help', {'command': 'tasks'})
    check('D7 con los dos: las dos anunciadas, y tasks no dice que falte ninguna',
          'delphi_adb' in a and 'delphi_desktop' in a and cat['SF_HELP_SIN_DESTINO_ADB'] not in t
          and cat['SF_HELP_SIN_DESTINO_DESKTOP'] not in t, (sorted(a), t[-300:]))
    # C3 de cierre-final-1-29-1: las coordenadas y la cuenta de lineas, NUMEROS por contrato, se publican como
    # number ([NumeroComoTexto]): como string, un cliente que valida negaba 152 antes de llamar (Hermes, 9 veces);
    # code sigue siendo texto (en Windows es el NOMBRE de una tecla)
    tl = {x['name']: x['inputSchema']['properties'] for x in (srv.request('tools/list') or {})['result']['tools']}
    tipos = {(t, p): tl[t][p].get('type') for t, ps in (('delphi_desktop', ('x', 'y', 'tox', 'toy', 'code')),
                                                        ('delphi_adb', ('x', 'y', 'lines'))) for p in ps}
    check('D8 x, y, tox, toy y lines se publican como number, code como texto (ROJO: todos string)',
          all(v == 'number' for (t, p), v in tipos.items() if p != 'code') and
          tipos[('delphi_desktop', 'code')] == 'string', tipos)
    r = srv.call('delphi_adb', {'command': 'tap', 'device': 'no-declarado', 'x': 152, 'y': 10})
    r2 = srv.call('delphi_adb', {'command': 'tap', 'device': 'no-declarado', 'x': '152', 'y': '10'})
    check('D8 ...y el servidor toma el numero y su texto igual: los dos llegan a juzgar el dispositivo (ADB-005)',
          mc.abre(r, 'SR_ADB_ALLOWLIST_FMT') and mc.abre(r2, 'SR_ADB_ALLOWLIST_FMT'),
          (r[:200], r2[:200]))
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('adb y desktop, anunciados solo donde se declara a donde ir (B10 de la 1.28)')
