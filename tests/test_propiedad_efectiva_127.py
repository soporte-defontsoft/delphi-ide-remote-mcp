# -*- coding: utf-8 -*-
r"""EffectiveProperty, el lector de una propiedad del .dproj para UN build (H8 de la revision
de la 1.22.0, aparcado desde la 1.23; get-property, la salida, el SDK, el perfil, los paquetes
y los ajustes del motor lo usan). Tiene que dar el MISMO valor que la puerta del build: msbuild
fija una propiedad EN EL PUNTO de su definicion -una referencia a otra definida DESPUES vale
vacio, a una de antes su valor de entonces- y lo desconocido queda escrito como $(X). Hasta
cfa6113, EffectiveProperty re-expandia el valor CRUDO con un expansor propio (solo la
autorreferencia) y <X>a</X><P>$(X)</P><X>b</X> daba '$(X)' donde msbuild fija 'a'.

CAUSA MEDIDA con el oraculo de msbuild (oraculo2.py, 4-nov-2026):
  ORA|E|ORA_PRE_DEF|[]      una referencia a una propiedad definida DESPUES vale vacio
  ORA|E|ORA_POST|[tarde]    la misma referencia, DESPUES de la definicion, vale el valor

Casos (todos en el PropertyGroup incondicional, que se aplica a cualquier build -> vSi):
  P0 control: get-property de una propiedad que trae el proyecto (DCC_DcuOutput) la da
  P1 hacia atras (el caso del informe): <PG_Base>alfa</PG_Base><PG_Deriv>$(PG_Base)</PG_Deriv>
     <PG_Base>beta</PG_Base> -> get-property PG_Deriv = alfa (lo que msbuild fija en su punto).
     ROJA contra el build sin el arreglo: da '$(PG_Base)'.
  P2 hacia adelante: <PG_Ant>[$(PG_Tarde)]</PG_Ant><PG_Tarde>tarde</PG_Tarde> -> PG_Ant = []
     (PG_Tarde vale vacio en ese punto, como ORA_PRE_DEF). ROJA sin el arreglo: da
     '[$(PG_Tarde)]'.
  P3 control: PG_Base, dos veces, gana la ultima -> beta (igual con o sin el arreglo: que la
     cadena y el proyecto estan bien).

Uso:  python tests/test_propiedad_efectiva_127.py [ruta-a-DelphiLspMcp.exe]
(sin ruta, el exe recien compilado del worktree; con la de produccion, mide la roja)
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('propiedad-efectiva-127')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='pe', t=600)

# los dos casos, en el PropertyGroup incondicional (tras el ProjectGuid): su orden entre si es
# el que mide -PG_Deriv ve a PG_Base ya en 'alfa'; PG_Ant ve a PG_Tarde todavia sin definir-
BLOQUE = ('        <PG_Base>alfa</PG_Base>\r\n'
          '        <PG_Deriv>$(PG_Base)</PG_Deriv>\r\n'
          '        <PG_Base>beta</PG_Base>\r\n'
          '        <PG_Ant>[$(PG_Tarde)]</PG_Ant>\r\n'
          '        <PG_Tarde>tarde</PG_Tarde>\r\n')


def config(proyecto, comando, **campos):
    args = {'project': proyecto, 'command': comando}
    args.update(campos)
    return srv.call('delphi_config', args)


try:
    carpeta = os.path.join(BASE, 'fixture')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fix', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fix.dproj')

    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    assert '</ProjectGuid>' in xml, xml[:400]
    xml = xml.replace('</ProjectGuid>', '</ProjectGuid>\r\n' + BLOQUE.rstrip('\r\n'), 1)
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml)

    r = config(proyecto, 'get-property', name='DCC_DcuOutput')
    check('P0 control: get-property de una propiedad del proyecto (DCC_DcuOutput) la da',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and 'not set' not in r, r[:300])

    r = config(proyecto, 'get-property', name='PG_Deriv')
    # el valor efectivo es la parte "= X."; el "Set in:" repite el texto CRUDO (diagnostico), asi
    # que la roja se mide en el valor: el build sin el arreglo da "= $(PG_Base)."
    check('P1 hacia atras: PG_Deriv = alfa (lo que msbuild fija en su punto), no $(PG_Base)',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and '= alfa.' in r and '= $(PG_Base).' not in r, r[:300])

    r = config(proyecto, 'get-property', name='PG_Ant')
    check('P2 hacia adelante: PG_Ant = [] (PG_Tarde vacio en ese punto), no [$(PG_Tarde)]',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and '= [].' in r and '= [$(PG_Tarde)].' not in r, r[:300])

    r = config(proyecto, 'get-property', name='PG_Base')
    check('P3 control: PG_Base, dos veces, gana la ultima = beta (igual con o sin el arreglo)',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and '= beta.' in r, r[:300])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('propiedad efectiva 127 (H8)')
