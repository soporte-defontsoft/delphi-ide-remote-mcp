# -*- coding: utf-8 -*-
"""BUILD-049 (1.21.1): un F2613 de una unit sin ambito que SI existe bajo uno.
Hermes (punto 9 de la 1.18.2) escribio `uses Dialogs` en un proyecto FMX: F2613,
sin candidatas, y la nota mandaba a add-searchpath o a "el componente no esta
instalado" - y lo que faltaba era escribirla cualificada (FMX.Dialogs), porque
los ambitos del proyecto (DCC_Namespace) no incluyen FMX ni Vcl. El juez es lo
que hay en disco (los <ambito>.<unit>.pas de las raices y de la biblioteca), no
una lista de ambitos.

  Q1 uses Dialogs en una consola: F2613, Dialogs sin sourceFolders y con
     qualified = FMX.Dialogs y Vcl.Dialogs; la nota lleva BUILD-049
  Q2 el consejo cierra el bucle: con Vcl.Dialogs compila
  Q3 una unit que no existe con ningun nombre: ni qualified ni BUILD-049
  Q4 una unit cualificada del PROPIO workspace (Casa.UQualX.pas): qualified
  Q5 una cualificada detras de un junction a FUERA de la jaula: no se ofrece

Q1 y Q4 son ROJAS contra 1.21.0 (pasar su exe como argumento).

Uso:  python tests/test_build_cualifica_1211.py [ruta-a-DelphiLspMcp.exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build_cualifica_1211')
JAIL = os.path.join(BASE, 'jail')
P = os.path.join(JAIL, 'cual')
VEND = os.path.join(JAIL, 'vendor')
os.makedirs(VEND)
FUERA = mc.carpeta('build_cualifica_1211-fuera')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='build-cualifica', t=600)
UNIDAD = ('unit %s;\n\ninterface\n\nfunction Dame: Integer;\n\nimplementation\n\n'
          'function Dame: Integer;\nbegin\n  Result := 1;\nend;\n\nend.\n')


def compila(usos):
    """Compila la consola con esos usos delante de los suyos; el JSON del build."""
    open(DPR, 'w', encoding='utf-8').write(ORIGINAL.replace('uses', 'uses\n  ' + usos + ',', 1))
    r = S.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Debug'}, t=600)
    try:
        return json.loads(r), r
    except Exception:
        return {}, r


def falta(j, unidad):
    return next((m for m in (j.get('missingUnits') or []) if m.get('unit') == unidad), None)


try:
    r = S.call('delphi_create', {'kind': 'project-console', 'name': 'Cual', 'dir': P})
    check('preparacion: consola Cual', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPR = os.path.join(P, 'Cual.dpr')
    DPROJ = os.path.join(P, 'Cual.dproj')
    ORIGINAL = open(DPR, encoding='utf-8-sig').read()

    j, r = compila('Dialogs')
    d = falta(j, 'Dialogs')
    nota = j.get('missingUnitsNote') or ''
    check('Q1 uses Dialogs: F2613 y Dialogs sin sourceFolders (el caso existe en esta maquina)',
          j.get('success') is False and d is not None and not d.get('sourceFolders'), r[:400])
    check('Q1b ...con qualified = FMX.Dialogs y Vcl.Dialogs',
          d is not None and {'FMX.Dialogs', 'Vcl.Dialogs'} <= set(d.get('qualified') or []), json.dumps(d))
    check('Q1c ...y la nota dice que se cualifique (BUILD-049)',
          mc.es(nota, 'SN_BUILD_MISSING_UNITS_QUALIFY'), nota[:400])

    j, r = compila('Vcl.Dialogs')
    check('Q2 cualificada como dice, compila', j.get('success') is True, r[:300])

    j, r = compila('NoSuchUnitXyzQ')
    d = falta(j, 'NoSuchUnitXyzQ')
    check('Q3 una unit que no existe con ningun nombre: ni qualified ni BUILD-049',
          d is not None and 'qualified' not in d and
          not mc.es(j.get('missingUnitsNote') or '', 'SN_BUILD_MISSING_UNITS_QUALIFY'), r[:400])

    open(os.path.join(VEND, 'Casa.UQualX.pas'), 'w', encoding='utf-8').write(UNIDAD % 'Casa.UQualX')
    j, r = compila('UQualX')
    d = falta(j, 'UQualX')
    check('Q4 una cualificada del propio workspace: qualified = Casa.UQualX',
          d is not None and (d.get('qualified') or []) == ['Casa.UQualX'], json.dumps(d or j)[:300])

    open(os.path.join(FUERA, 'Fuera.UQualY.pas'), 'w', encoding='utf-8').write(UNIDAD % 'Fuera.UQualY')
    ENLACE = os.path.join(JAIL, 'enlace-fuera')
    if mc.junction(ENLACE, FUERA):
        j, r = compila('UQualY')
        d = falta(j, 'UQualY')
        check('Q5 una cualificada detras de un junction a fuera de la jaula no se ofrece',
              d is not None and 'qualified' not in d, json.dumps(d or j)[:300])
        os.rmdir(ENLACE)  # el enlace, no lo de detras
    else:
        check('Q5 (preparacion): el junction se pudo crear', False, ENLACE)
finally:
    S.cierra()

mc.borra(FUERA)
mc.borra(BASE)
mc.fin('build cualifica 1.21.1')
