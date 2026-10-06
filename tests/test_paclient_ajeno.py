# -*- coding: utf-8 -*-
"""paclient contra un PAServer que no es el suyo (1.16.0).

Una maquina puede tener un PAServer por Delphi, cada uno en su puerto (el
Zorin de David: el de la 13.1 y el de la 13.2), y cada Delphi tiene que usar
su paclient. Si un perfil apunta al puerto del otro, paclient rechaza la
conexion con su texto crudo (leido de paclient.exe 37.1.10.6): "Platform
Assistant Server version mismatch - expecting version 'X'", o "Profile
platform (A) does not match remote/host machine platform (B)". Desde la
1.16.0 todo lo que llama a paclient pasa por UN helper
(Lsp.RemoteRun.Paclient) que anade que hacer (PAS-056 / PAS-057); antes
test-connection, get-sdk y add-profile lo lanzaban a mano.

Sin PAServer: paclient es un .cmd FALSO (DELPHI_MCP_PACLIENT, como
test_remoterun) que imprime esos textos y sale con 1.

  A1  test-connection: PAServer de otro Delphi -> PAS-056 con la version
  A2  test-connection: perfil de otra plataforma -> PAS-057
  A3  get-sdk (su comprobacion de conexion) -> PAS-056
  A4  remote-run (la subida del .job y de McpRunJob) -> PAS-056
  A5  control: un paclient que conecta (sale con 0) no lleva aviso

Mutante: el binario de antes del helper (o el helper sin AvisoDePaclient):
A1-A4 rojos.

Uso:  python tests/test_paclient_ajeno.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

PERFIL = 'x'
BASE = mc.carpeta('pacajeno')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL, exist_ok=True)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
# remote-run sube el lanzador que el servidor lleva en node\ junto a su exe
# (como test_remoterun): sin el, RUN-011 antes de llamar a paclient
import shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(os.path.join(os.path.dirname(EXE), 'node'), exist_ok=True)
for _f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', _f), os.path.join(os.path.dirname(EXE), 'node', _f))
AD, HOST = mc.appdata_perfil(BASE, PERFIL, '127.0.0.1', 'Linux64')

MISMATCH = "Connection refused. Platform Assistant Server version mismatch - expecting version '37.1.10.6'."
PLATAFORMA = 'Connection refused. Profile platform (Linux64) does not match remote/host machine platform (Windows)'


def stub(nombre, linea, codigo):
    p = os.path.join(BASE, nombre + '.cmd')
    with open(p, 'w', newline='') as f:
        f.write('@echo off\r\n' + ('echo %s\r\n' % linea if linea else '') + 'exit /b %d\r\n' % codigo)
    return p


def servidor(paclient):
    return mc.Stdio(EXE, mc.entorno({
        'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': AD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
        'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': 'all',
        'DELPHI_MCP_PACLIENT': paclient}), nombre='pacajeno', t=300)


def con(paclient, fn):
    s = servidor(paclient)
    try:
        return fn(s.call)
    finally:
        try: s.mata()
        except Exception: pass


ST_MISMATCH = stub('mismatch', MISMATCH, 1)
ST_PLAT = stub('plataforma', PLATAFORMA, 1)
ST_OK = stub('conecta', '', 0)

try:
    r = con(ST_MISMATCH, lambda c: c('delphi_paserver', {'command': 'test-connection', 'name': PERFIL}))
    check('A1 test-connection, PAServer de otro Delphi: PAS-056 con la version que espera',
          mc.es(r, 'SN_PACLIENT_OTRO_DELPHI_FMT') and '37.1.10.6' in r, r[:400])

    r = con(ST_PLAT, lambda c: c('delphi_paserver', {'command': 'test-connection', 'name': PERFIL}))
    check('A2 test-connection, perfil de otra plataforma: PAS-057',
          mc.es(r, 'SN_PACLIENT_OTRA_PLATAFORMA_FMT') and 'Windows' in r, r[:400])

    r = con(ST_MISMATCH, lambda c: c('delphi_paserver', {'command': 'get-sdk', 'name': PERFIL}, 300))
    check('A3 get-sdk (su comprobacion de conexion): PAS-056',
          mc.es(r, 'SN_PACLIENT_OTRO_DELPHI_FMT'), r[:400])

    def remote_run(c):
        c('delphi_create', {'kind': 'project-console', 'name': 'RR', 'dir': os.path.join(JAIL, 'RR')})
        return c('delphi_paserver', {'command': 'remote-run', 'name': PERFIL,
                                     'project': os.path.join(JAIL, 'RR', 'RR.dproj'), 'timeoutms': 5000})
    r = con(ST_MISMATCH, remote_run)
    check('A4 remote-run (la subida del .job y de McpRunJob): PAS-056',
          mc.es(r, 'SN_PACLIENT_OTRO_DELPHI_FMT'), r[:400])

    r = con(ST_OK, lambda c: c('delphi_paserver', {'command': 'test-connection', 'name': PERFIL}))
    check('A5 control: un paclient que conecta no lleva aviso',
          not mc.es(r, 'SN_PACLIENT_OTRO_DELPHI_FMT') and not mc.es(r, 'SN_PACLIENT_OTRA_PLATAFORMA_FMT')
          and 'PAS-056' not in r and 'PAS-057' not in r, r[:300])
finally:
    try:
        mc.fin('paclient ajeno battery')  # sys.exit: la carpeta se borra en el finally
    finally:
        mc.borra(BASE)
