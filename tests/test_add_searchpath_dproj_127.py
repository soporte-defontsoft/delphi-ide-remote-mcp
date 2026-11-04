# -*- coding: utf-8 -*-
r"""delphi_config add-searchpath resuelve una propiedad que el .dproj define, como la puerta del
build (resto de P9 de la revision de la 1.27; aparcado desde la 1.23). Hasta cfa6113 expandia SOLO
las macros del IDE/msbuild (MacrosDelProyecto) y negaba con CFG-148 un $(X) que el propio .dproj
define - set-property MiLib=libs y luego add-searchpath $(MiLib)\comun -, mientras delphi_build SI
lo resuelve (VeredictosDeElementos / EffectiveProperty). Ahora add-searchpath pregunta lo que vale
$(X) por EL lector del build (EffectiveProperty, el de get-property: la misma funcion que el punto
H8), para cada build al que se aplica. El entorno del servidor sigue negado a proposito (A10).

CAUSA MEDIDA en vivo contra produccion (cfa6113, 4-nov-2026): add-searchpath $(MiLib)\comun -> CFG-148.

El JUEZ de que el valor resuelto coincide con lo que el build ve es el build mismo (P2): si el
.dproj con $(MiLib)\comun compila, add-searchpath acepto lo que la puerta resuelve igual.

  P1 add-searchpath $(MiLib)\comun para Win64, con MiLib=libs y libs\comun\ creada: ACEPTADO, y el
     .dproj lleva el valor crudo $(MiLib)\comun. ROJA contra el build sin el arreglo: CFG-148.
  P2 msbuild lo resuelve: Win64 compila con la unidad que SOLO esta en libs\comun (el build ve el
     mismo $(MiLib) que add-searchpath resolvio).
  P3 control: una macro que NADIE define ($(NoDefinidaJamas)\x) sigue negada con CFG-148.
  P4 control (A10): una variable del ENTORNO del servidor ($(MI_VAR_SRV)\x, puesta en su entorno)
     sigue negada con CFG-148 - add-searchpath resuelve el .dproj y el IDE, no la casa del servidor.

Uso:  python tests/test_add_searchpath_dproj_127.py [ruta-a-DelphiLspMcp.exe]
(sin ruta, el exe recien compilado del worktree; con la de produccion, mide la roja de P1)
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('add-searchpath-dproj-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
# el entorno del servidor lleva una variable propia: add-searchpath NO debe resolverla (A10)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'MI_VAR_SRV': 'libs'}), nombre='asp', t=600)


def config(proyecto, comando, **campos):
    args = {'project': proyecto, 'command': comando}
    args.update(campos)
    return srv.call('delphi_config', args)


def compila(r):
    return mc.como_json(r).get('success') is True


def lee(proyecto):
    with open(proyecto, encoding='utf-8-sig') as f:
        return f.read()


try:
    carpeta = os.path.join(BASE, 'fixture')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fix', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fix.dproj')
    # una unidad que SOLO vive en libs\comun\, y el .dpr la usa
    os.makedirs(os.path.join(carpeta, 'libs', 'comun'))
    open(os.path.join(carpeta, 'libs', 'comun', 'Ajena.pas'), 'w', encoding='utf-8').write(
        'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n')
    dpr = os.path.join(carpeta, 'Fix.dpr')
    with open(dpr, encoding='utf-8-sig') as f:
        fuente = f.read()
    assert 'uses' in fuente, fuente[:200]
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente.replace('uses', 'uses\r\n  Ajena,', 1))

    r = config(proyecto, 'set-property', name='MiLib', value='libs', platform='Win64')
    check('fixture: set-property MiLib=libs para Win64', mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT'), r[:300])

    r = config(proyecto, 'add-searchpath', path=r'$(MiLib)\comun', platform='Win64')
    check('P1 add-searchpath $(MiLib)\\comun (Win64): aceptado, no CFG-148',
          not mc.rechazado(r) and not mc.es(r, 'SR_CONFIG_PATH_MACRO_DESCONOCIDA_FMT'), r[:300])
    check('P1 ...y el .dproj lleva el valor crudo $(MiLib)\\comun (la macro, que el build resuelve)',
          r'$(MiLib)\comun' in lee(proyecto), lee(proyecto)[:1500])

    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': 'Release'}, 600)
    check('P2 msbuild resuelve $(MiLib): Win64 compila con la unidad de libs\\comun',
          compila(r), mc.como_json(r).get('firstError') or r[:400])

    r = config(proyecto, 'add-searchpath', path=r'$(NoDefinidaJamas)\x', platform='Win64')
    check('P3 control: una macro que nadie define sigue negada con CFG-148',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PATH_MACRO_DESCONOCIDA_FMT'), r[:300])

    r = config(proyecto, 'add-searchpath', path=r'$(MI_VAR_SRV)\x', platform='Win64')
    check('P4 control (A10): una variable del entorno del servidor sigue negada con CFG-148',
          mc.rechazado(r) and mc.es(r, 'SR_CONFIG_PATH_MACRO_DESCONOCIDA_FMT'), r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('add-searchpath resuelve el .dproj 127 (P9)')
