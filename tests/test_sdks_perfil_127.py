# -*- coding: utf-8 -*-
r"""A7 de la 1.27: una bateria no deja carpetas de sus perfiles en la de SDKs de la maquina.

Medido el 3-nov-2026: en Documents\Embarcadero\Studio\SDKs hay carpetas vacias con los nombres de los
perfiles de las baterias (x, perfil, linux-p, win-p, mcp-e2e-noprof...). paclient deja una carpeta
VACIA con el nombre del perfil al usarlo (Mcp.Tools.PAServer, medido el 22-sep-2026), y no mira el
APPDATA falso de la bateria (mc.appdata_perfil, medido el 9-oct-2026): darle otro entorno no la
aparta. Ahora mc.appdata_perfil apunta la carpeta de cada perfil que NO estaba, y mc.fin la recoge si
sigue vacia. Las que ya estaban son del operador y no se tocan.

Un perfil con un nombre que no existe y el host de pruebas 192.0.2.1 (TEST-NET-1: nada responde), con
el paclient de VERDAD: ningun PAServer real se toca.

  S1 test-connection con ese perfil: paclient deja SDKs\<perfil> (premisa: la causa, medida)
  S2 mc.recoge_huellas() se la lleva (la que deja una bateria)
  S3 una que ya estaba no se toca: una carpeta plantada antes con otro nombre sigue ahi

Uso:  python tests/test_sdks_perfil_127.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('sdks-perfil-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SDKS = mc.carpeta_sdks()
PERFIL = 'mcp-a7-%d' % os.getpid()
HUELLA = os.path.join(SDKS, PERFIL)
check('fixture: la carpeta del perfil no existe antes', not os.path.lexists(HUELLA), HUELLA)
# S3: una "del operador", plantada ANTES de apuntar el perfil, con el mismo mecanismo
YA_ESTABA = 'mcp-a7-estaba-%d' % os.getpid()
os.makedirs(os.path.join(SDKS, YA_ESTABA))
# desde aqui, la plantada es de esta bateria y se quita pase lo que pase (revisor del paisaje de la 1.27)
try:
    _ad2, _ = mc.appdata_perfil(os.path.join(BASE, 'otro'), YA_ESTABA, host='192.0.2.1')
    _ad, _host = mc.appdata_perfil(BASE, PERFIL, host='192.0.2.1')
    env = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': _ad, 'DELPHI_MCP_REMOTE_HOSTS': _host})
    srv = mc.Stdio(EXE, env, nombre='sdks-perfil-127', t=180)
    try:
        r = srv.call('delphi_paserver', {'command': 'test-connection', 'profile': PERFIL}, 120)
        s1 = os.path.isdir(HUELLA)
        check('S1 test-connection con un perfil de bateria: paclient deja SDKs\\<perfil>', s1, r[:300])
    finally:
        srv.cierra()

    mc.recoge_huellas()
    # (sin S1 no hay nada que recoger: S2 no puede pasar por eso; revisor de baterias de la 1.27)
    check('S2 mc.recoge_huellas() se lleva la carpeta que dejo la bateria', s1 and not os.path.lexists(HUELLA), HUELLA)
    check('S3 la que ya estaba no se toca', os.path.isdir(os.path.join(SDKS, YA_ESTABA)), YA_ESTABA)
finally:
    # si algo revento entre S1 y la recogida, la huella no se queda en la carpeta real
    mc.recoge_huellas()
    # la plantada para S3 es de esta bateria: se quita aqui, a mano y solo ella
    if os.path.isdir(os.path.join(SDKS, YA_ESTABA)):
        os.rmdir(os.path.join(SDKS, YA_ESTABA))
mc.borra(BASE)
mc.fin('una bateria no deja carpetas de sus perfiles en la de SDKs 1.27 (A7)')
