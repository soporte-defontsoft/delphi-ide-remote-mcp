# -*- coding: utf-8 -*-
"""1.29 (A17-2): delphi_create kind=project-library, la DLL como la crea el IDE. Sin ella un agente partia de un
project-console y cambiaba la cabecera, y el proyecto se quedaba sin GenDll (BUILD-072, test_libreria_sin_gendll_129).
El juez: un proyecto que el IDE 37.0 acababa de crear (File > New > Other > Delphi > Dynamic-link Library, David,
8-nov-2026): el .dpr es library + uses System.SysUtils, System.Classes + {$R *.res} + begin end.; el .dproj,
AppType=Library, FrameworkType=None, GenDll=true en la base, Borland.ProjectType=Application (ni vacio ni Library),
sin manifiesto, icono, DPI ni ConsoleTarget, y la informacion de version en Win32. Lo nuestro, como en los demas
tipos: Win32 y Win64 activas (el IDE solo Win32) y sus carpetas de salida.

  P1 kind=project-library: CREATED con el .dpr y el .dproj. ROJO contra 8a2ad91e (CREATE-011)
  P2 el .dpr: library, sin {$APPTYPE}, con System.SysUtils y System.Classes, {$R *.res} y begin end.
  P3 el .dproj como el del IDE: AppType, FrameworkType, GenDll en la base, Borland.ProjectType
  P4 ...y sin lo que el IDE no pone a una DLL: manifiesto, icono, DPI, ConsoleTarget
  P5 build Win64: la DLL, sin BUILD-072
  P6 build Win32 (la plataforma del IDE): la DLL
  P7 un kind que no existe: CREATE-011 nombra project-library

Uso:  python tests/test_project_library_129.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import re
import xml.etree.ElementTree as ET
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('project_library_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='project-library', t=120)
NS = '{http://schemas.microsoft.com/developer/msbuild/2003}'


def grupo(raiz, condicion):
    """Los valores del PropertyGroup con esa Condition (None si no esta)."""
    for g in raiz.findall(NS + 'PropertyGroup'):
        if g.get('Condition') == condicion:
            return {e.tag[len(NS):]: (e.text or '') for e in g}
    return None


def build(dproj, plataforma):
    return mc.como_json(srv.call('delphi_build', {'project': dproj, 'platform': plataforma, 'config': 'Debug',
                                                  'target': 'Build'}, 600))


try:
    D = os.path.join(JAIL, 'MideDll')
    r = srv.call('delphi_create', {'kind': 'project-library', 'name': 'MideDll', 'dir': D})
    DPR = os.path.join(D, 'MideDll.dpr')
    DPROJ = os.path.join(D, 'MideDll.dproj')
    check('P1 kind=project-library: CREATED con el .dpr y el .dproj. ROJO contra 8a2ad91e (CREATE-011)',
          not mc.fallo(r) and os.path.isfile(DPR) and os.path.isfile(DPROJ), r[:400])
    dpr = mc.lee(DPR) if os.path.isfile(DPR) else ''
    check('P2 el .dpr: library, sin {$APPTYPE}, System.SysUtils y System.Classes, {$R *.res} y begin end.',
          dpr.startswith('library MideDll;') and '{$APPTYPE' not in dpr.upper() and
          re.search(r'uses\s+System\.SysUtils,\s+System\.Classes;', dpr) is not None and
          '{$R *.res}' in dpr and re.search(r'begin\s+end\.\s*$', dpr) is not None, dpr[:600])
    texto = mc.lee(DPROJ) if os.path.isfile(DPROJ) else ''
    raiz = ET.fromstring(texto) if texto else None
    principal = {}
    if raiz is not None:
        g0 = raiz.find(NS + 'PropertyGroup')
        principal = {e.tag[len(NS):]: (e.text or '') for e in g0} if g0 is not None else {}
    base = (grupo(raiz, "'$(Base)'!=''") if raiz is not None else None) or {}
    win32 = (grupo(raiz, "'$(Base_Win32)'!=''") if raiz is not None else None) or {}
    tipo = re.search(r'<Borland\.ProjectType>([^<]*)</Borland\.ProjectType>', texto)
    check('P3 el .dproj como el del IDE: AppType=Library, FrameworkType=None, GenDll=true en la base, '
          'Borland.ProjectType=Application, version en Win32',
          principal.get('AppType') == 'Library' and principal.get('FrameworkType') == 'None' and
          base.get('GenDll') == 'true' and tipo is not None and tipo.group(1) == 'Application' and
          win32.get('VerInfo_IncludeVerInfo') == 'true',
          json.dumps({'principal': principal, 'base': base, 'win32': win32,
                      'tipo': tipo.group(1) if tipo else None})[:800])
    check('P4 ...y sin lo que el IDE no pone a una DLL: manifiesto, icono, DPI, ConsoleTarget',
          texto != '' and not any(x in texto for x in ('Manifest_File', 'Icon_MainIcon', 'AppDPIAwarenessMode',
                                                         'DCC_ConsoleTarget')), texto[:300])
    j = build(DPROJ, 'Win64')
    check('P5 build Win64: MideDll.dll, sin BUILD-072',
          j.get('success') is True and j.get('output', '').lower().endswith('midedll.dll') and
          not mc.es(json.dumps(j), 'SN_BUILD_LIBRERIA_SIN_GENDLL_FMT'), json.dumps(j)[:600])
    j = build(DPROJ, 'Win32')
    check('P6 build Win32 (la plataforma del IDE): MideDll.dll',
          j.get('success') is True and j.get('output', '').lower().endswith('midedll.dll'), json.dumps(j)[:600])
    r = srv.call('delphi_create', {'kind': 'project-web', 'name': 'NoVa', 'dir': os.path.join(JAIL, 'NoVa')})
    check('P7 un kind que no existe: CREATE-011 nombra project-library',
          mc.es(r, 'SR_CREATE_PROJECT_KIND') and 'project-library' in r and
          not os.path.exists(os.path.join(JAIL, 'NoVa')), r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('delphi_create kind=project-library (1.29, A17-2)')
