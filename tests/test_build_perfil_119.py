# -*- coding: utf-8 -*-
"""delphi_build elige, no copia (punto 3 del build, 1.19.0): el perfil es UNO de
los que el IDE declara (PerfilDelIde, el juez de set-profile) y el target, uno
del cuarteto con su nombre. Un perfil bien formado pero inexistente pasaba la
puerta (solo mira los caracteres) y llegaba a /p:Profile= tal cual; el target
iba a /t: con las mayusculas del agente.

  P1 profile=noexiste en un Build: PAS-053 (el mismo "no existe" del deploy), y NO se compila
     (ni "success" ni binario)
  P2 target=make (minusculas): se compila y la respuesta dice target "Make"
  P3 con un perfil real de la maquina (delphi_paserver profiles): el Build
     local pasa el juez y compila (NOTA si la maquina no tiene ninguno)

Uso:  python tests/test_build_perfil_119.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build_perfil_119')
JAIL = os.path.join(BASE, 'jail')
PROY = os.path.join(JAIL, 'P')
os.makedirs(PROY)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
DPROJ = os.path.join(PROY, 'P.dproj')

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='build-perfil', t=300)
try:
    r = s.call('delphi_create', {'kind': 'project-console', 'dir': PROY, 'name': 'P'}, t=120)
    check('fixture proyecto P', not mc.fallo(r), r[:200])

    r = s.call('delphi_build', {'project': DPROJ, 'target': 'Build', 'profile': 'noexiste'}, t=300)
    j = mc.como_json(r)
    check('P1 profile=noexiste: PAS-053 y sin compilar',
          'PAS-053' in r and 'noexiste' in r and not j.get('success', False) and 'binary' not in j, r[:300])

    r = s.call('delphi_build', {'project': DPROJ, 'target': 'make'}, t=300)
    j = mc.como_json(r)
    check('P2 target=make: compila y la respuesta dice "Make" (su nombre)',
          j.get('success') is True and j.get('target') == 'Make', (j.get('success'), j.get('target'), r[:200]))

    r = s.call('delphi_paserver', {'command': 'profiles'})
    j = mc.como_json(r)
    perfiles = [p for p in (j.get('profiles') or []) if isinstance(p, str) and p]  # una lista de NOMBRES
    if perfiles:
        r = s.call('delphi_build', {'project': DPROJ, 'target': 'Build', 'profile': perfiles[0]}, t=300)
        j = mc.como_json(r)
        check('P3 un perfil real (%s) en un Build local: pasa el juez y compila' % perfiles[0],
              j.get('success') is True, r[:300])
    else:
        print('NOTA P3 sin medir: la maquina no tiene ningun perfil de PAServer')
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('build: perfil y target elegidos 1.19.0')
