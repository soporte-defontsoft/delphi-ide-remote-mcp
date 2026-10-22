# -*- coding: utf-8 -*-
r"""Un .dproj a medias no se compila: BUILD-055 (1.21.4). Hermes (21-oct-2026) subio un .dproj
por trozos, lo corto antes del final y el build contesto BUILD-046 "plataforma no habilitada":
el bloque <Platforms> va al final del fichero, y sin el todo parece no declarado. Ahora el build
dice que el fichero no cierra su <Project> y como reponerlo, antes de juzgar nada.

  B1  el proyecto entero compila (control)
  B2  el .dproj cortado al 60%: BUILD-055, nada compilado, y la negativa dice como reponerlo
  B3  repuesto byte a byte: compila otra vez
  B4  cortado por un delphi_upload offset=0 (deja una copia del entero): BUILD-055 dice COMO
      reponerla (delphi_delete + delphi_move sin copy=true), y siguiendo el mensaje queda byte
      a byte y compila (Hermes, dirigido de la 1.22.0: "Restore the copy from __delphi-patch"
      no decia con que tool; ROJA contra rel1220j en el mensaje)

B2 es ROJA contra 1.21.3: segun donde corte el fichero, BUILD-046 (Hermes: sin el bloque
<Platforms>, que va al final) o BUILD-017 "XML that cannot be followed" (aqui, al 60%: un
PropertyGroup sin cerrar), ninguno dice que el fichero esta a medias ni como reponerlo.

Uso:  python tests/test_build_dproj_truncado_1214.py [ruta-a-DelphiLspMcp.exe]
"""
import base64
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-dproj-truncado')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='bdt', t=600)

try:
    carpeta = os.path.join(BASE, 'p')
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('fixture creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    dproj = os.path.join(carpeta, 'Fixture.dproj')
    with open(dproj, 'rb') as f:
        entero = f.read()
    j = mc.como_json(srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Release'}, t=600)) or {}
    check('B1 control: el proyecto entero compila', j.get('success') is True, str(j)[:300])

    with open(dproj, 'wb') as f:
        f.write(entero[:int(len(entero) * 0.6)])
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Release'}, t=600)
    check('B2 el .dproj cortado al 60%: BUILD-055 y como reponerlo',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_DPROJ_INCOMPLETO_FMT') and mc.PAPELERA in r, r[:400])

    with open(dproj, 'wb') as f:
        f.write(entero)
    j = mc.como_json(srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Release'}, t=600)) or {}
    check('B3 repuesto byte a byte: compila otra vez', j.get('success') is True, str(j)[:300])

    corto = base64.b64encode(entero[:int(len(entero) * 0.6)]).decode('ascii')
    copia = (mc.como_json(srv.call('delphi_upload', {'path': dproj, 'offset': 0, 'chunkbase64': corto})) or {}).get('backup', '')
    check('B4 un upload offset=0 a medias deja la copia del entero', copia != '', copia)
    r = srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Release'}, t=600)
    check('B4 ...BUILD-055 dice como reponerla: delphi_delete y delphi_move sin copy=true',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_DPROJ_INCOMPLETO_FMT') and 'delphi_delete' in r and 'delphi_move' in r, r[:500])
    r1 = srv.call('delphi_delete', {'path': dproj})
    r2 = srv.call('delphi_move', {'path': copia, 'dest': dproj})
    repuesto = b''
    if os.path.exists(dproj):
        with open(dproj, 'rb') as f:
            repuesto = f.read()
    check('B4 ...siguiendo el mensaje queda byte a byte', repuesto == entero, '%s | %s' % (r1[:150], r2[:150]))
    j = mc.como_json(srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Release'}, t=600)) or {}
    check('B4 ...y compila', j.get('success') is True, str(j)[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('build dproj truncado 1214')
