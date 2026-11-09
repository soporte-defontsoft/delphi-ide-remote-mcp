# -*- coding: utf-8 -*-
"""Las DLL que carga el SERVIDOR salen de su casa, nunca del PATH (P4 y P5 de la 1.29.1).

Medido el 9-nov-2026 (sonda_sin_libpq.py del scratchpad): con libpq.dll sola en drivers\\PG\\lib, sus
cinco dependencias (libssl, libcrypto, libintl, libiconv, libwinpthread) se cargaban de las carpetas del
PATH (las de Git for Windows y un pgsql\\bin): FireDAC pone su carpeta con SetDllDirectory y carga por la
ruta, y Windows busca lo que falta tambien en el PATH. Lo que carga el servidor es codigo que ejecuta con
la cuenta del servicio: desde la 1.29.1 el proceso del servidor busca sus DLL solo en la carpeta de su exe,
en System32 y en las carpetas que se le ANADEN (SetDefaultDllDirectories); sus hijos no lo heredan.
Y sin la libreria, DB-009 llevaba la pista de FireDAC ("check it is in the PATH or application EXE
directories"), falsa aqui: ahora DB-030 dice donde va.

La base es 192.0.2.1 (TEST-NET, no existe): la libreria se carga ANTES de conectar, asi que no hace
falta ninguna base de verdad. Las DLL se copian de las de produccion (C:\\Delphi-mcp-Server\\drivers\\PG\\lib);
sin ellas, la bateria termina sin checks y lo dice.

  D1 con libpq.dll sola en la casa y sus dependencias en una carpeta del PATH: ninguna DLL sale de esa
     carpeta, y la respuesta es DB-030 (no se conecta con DLL ajenas)
  D2 con las seis en la casa y la carpeta del PATH tambien: las seis de la casa y ninguna del PATH; la
     respuesta no es DB-030 (llega a intentar conectar)
  D3 sin drivers\\PG: DB-030, dice drivers\\PG, sin la pista del PATH de FireDAC y sin la ruta real
  D4 lo que ya funcionaba, con la busqueda nueva (regla 7): la ayuda por COM (delphi_docs) y el XML de un
     .dproj (delphi_create + delphi_read) siguen igual

Uso:  python tests/test_dll_de_la_casa_1291.py [ruta-a-DelphiLspMcp.exe]
"""
import io
import json
import os
import shutil
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

PROD_LIB = r'C:\Delphi-mcp-Server\drivers\PG\lib'
TITULO = 'las DLL del servidor, de su casa y no del PATH (1.29.1)'
if not os.path.isfile(os.path.join(PROD_LIB, 'libpq.dll')):
    print('NOTA: sin %s no se mide nada' % PROD_LIB)
    mc.fin(TITULO, sin_checks='sin las DLL de PostgreSQL de produccion en esta maquina')
    raise SystemExit(0)

BASE = mc.carpeta('dll_de_la_casa_1291')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SRV = os.path.join(BASE, 'srv')
EXE = mc.copia_exe(SRV)
LIB = os.path.join(SRV, 'drivers', 'PG', 'lib')
EN_PATH = os.path.join(BASE, 'en-el-path')
os.makedirs(EN_PATH)
TODAS = sorted(os.listdir(PROD_LIB))
COMPANERAS = [f for f in TODAS if f.lower() != 'libpq.dll']
for f in COMPANERAS:
    shutil.copy(os.path.join(PROD_LIB, f), EN_PATH)
d = os.path.join(SRV, 'connections', 'databases')
os.makedirs(d)
io.open(os.path.join(d, 'db-connections.json'), 'w', encoding='utf-8').write(json.dumps(
    {'db-connections': {'projects': {'p': {'databases': {'pg': {
        'server': '192.0.2.1', 'database': 'inventada', 'user': 'nadie', 'password': 'x1',
        'engine': 'PG', 'provider': 'FIREDAC', 'readonly': True}}}}}}))


def modulos(pid):
    ps = '(Get-Process -Id %d).Modules | ForEach-Object FileName' % pid
    salida = subprocess.run(['powershell', '-NoProfile', '-Command', ps], capture_output=True, text=True).stdout
    return [m.strip() for m in salida.split('\n') if m.strip()]


def bajo(mods, carpeta):
    c = os.path.normcase(mc.larga(carpeta)) + os.sep
    return sorted(os.path.basename(m) for m in mods if os.path.normcase(mc.larga(m)).startswith(c))


def servidor():
    return mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_DB_PROJECTS': 'p',
                                     'PATH': EN_PATH + os.pathsep + os.environ.get('PATH', '')}),
                    nombre='dll_casa', t=90)


def prepara_lib(nombres):
    shutil.rmtree(os.path.join(SRV, 'drivers'), ignore_errors=True)
    if nombres is None:
        return
    os.makedirs(LIB)
    for f in nombres:
        shutil.copy(os.path.join(PROD_LIB, f), LIB)


try:
    # D1: libpq sola en la casa, sus dependencias en una carpeta del PATH
    prepara_lib(['libpq.dll'])
    srv = servidor()
    try:
        r = srv.call('delphi_db', {'command': 'tables', 'db': 'p/pg'})
        mods = modulos(srv.p.pid)
    finally:
        srv.cierra()
    check('D1 con libpq sola en la casa, ninguna DLL sale de la carpeta del PATH',
          not bajo(mods, EN_PATH), bajo(mods, EN_PATH))
    check('D1 ...y la respuesta es DB-030 (no conecta con DLL ajenas)', mc.es(r, 'SR_DB_SIN_LIBRERIA_FMT'), r[:400])

    # D2: las seis en la casa, y la carpeta del PATH sigue ahi
    prepara_lib(TODAS)
    srv = servidor()
    try:
        r = srv.call('delphi_db', {'command': 'tables', 'db': 'p/pg'})
        mods = modulos(srv.p.pid)
    finally:
        srv.cierra()
    check('D2 con las seis en la casa, las seis salen de la casa', bajo(mods, LIB) == TODAS, (bajo(mods, LIB), TODAS))
    check('D2 ...y ninguna de la carpeta del PATH', not bajo(mods, EN_PATH), bajo(mods, EN_PATH))
    check('D2 ...y no es DB-030 (llega a intentar conectar)', not mc.es(r, 'SR_DB_SIN_LIBRERIA_FMT'), r[:400])

    # D3: sin drivers\PG
    prepara_lib(None)
    srv = servidor()
    try:
        r = srv.call('delphi_db', {'command': 'tables', 'db': 'p/pg'})
        # D4: lo que ya cargaba el proceso, con la busqueda nueva
        r_docs = srv.call('delphi_docs', {'command': 'search', 'query': 'FormatDateTime'})
        r_crea = srv.call('delphi_create', {'kind': 'project-console', 'name': 'P1', 'dir': os.path.join(JAIL, 'P1')})
        r_lee = srv.call('delphi_read', {'path': os.path.join(JAIL, 'P1', 'P1.dproj'), 'toline': 3})
    finally:
        srv.cierra()
    check('D3 sin drivers\\PG: DB-030 y dice drivers\\PG', mc.es(r, 'SR_DB_SIN_LIBRERIA_FMT') and 'drivers\\PG' in r,
          r[:400])
    check('D3 ...sin la pista del PATH de FireDAC ni la ruta real del servidor',
          'PATH or application EXE' not in r and mc.larga(SRV).lower() not in r.lower() and SRV.lower() not in r.lower(),
          r[:400])
    check('D4 la ayuda por COM sigue (delphi_docs search)', 'FormatDateTime' in r_docs and '"id"' in r_docs, r_docs[:300])
    check('D4 ...y el XML de un .dproj (delphi_create + delphi_read)',
          mc.es(r_crea, 'SK_CREATE_CREADO_PROYECTO_FMT') and '<Project' in r_lee, (r_crea[:300], r_lee[:300]))
finally:
    mc.borra(BASE)
mc.fin(TITULO)
