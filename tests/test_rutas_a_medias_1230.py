# -*- coding: utf-8 -*-
"""Una ruta LEIDA de un fichero se resuelve como la lee quien la lee (A9 de la 1.23).

Una ruta escrita en un .dproj, un .groupproj, un .rc o un form puede venir "a
medias": "\\x" (la raiz de la unidad ACTUAL de quien la lea) o "C:x" (la
carpeta actual de esa unidad). TPath.IsPathRooted las da por completas y
GetFullPath las resolvia contra el PROCESO del servidor - su unidad y su
carpeta, que nadie nombro - mientras msbuild, el motor y el ayudante del
renderizador corren en la carpeta del proyecto o del form. Con el servidor en
otra unidad (en produccion, el servicio en C:\\Windows\\system32 y las raices en
D:), el juez de los literales del render miraba en una unidad lo que el
ayudante lee en otra, y los buscadores no veian lo que el build si. Ahora UN
resolutor (Lsp.Rutas.RutaDesde) aplica la regla de Windows desde la carpeta de
quien lee, y lo que no se resuelve ("X:y" de otra unidad) no se usa.

El servidor de la bateria corre con su carpeta actual en OTRA unidad que la
jaula (la carpeta de las baterias, en el disco del repo): sin dos unidades no
hay roja que medir y la bateria lo dice (GUARDA); y esa carpeta sale como
estaba.

  M1  delphi_projects: compilesAgainst sigue "\\x" y "<unidad>:x" del search
      path desde la carpeta del .dproj (control: el relativo de siempre)
  M2  delphi_config view de un .groupproj: sus proyectos "\\x" y "<unidad>:x",
      en su sitio y existentes (no outsideWorkspace)
  M3  delphi_styles lint: los ficheros "\\x" y "<unidad>:x" de un .rc estan;
      ni faltan ni se niegan (controles: el relativo esta, y uno que falta
      de verdad sale)
  M4  delphi_designer set before=: un Caption "\\x" que nombra un fichero de
      FUERA de la jaula es DSGN-115 - lo que el ayudante leeria desde la
      carpeta del form -, y el form no cambia
  M5  la carpeta actual del servidor (en el repo) sale como estaba

Usage:  python tests/test_rutas_a_medias_1230.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('a_medias_1230')
JAIL = os.path.join(BASE, 'jail')
UNIDAD, _ = os.path.splitdrive(JAIL)
# la carpeta actual del servidor, en OTRA unidad: la de esta bateria
OTRA = os.path.dirname(os.path.abspath(__file__))
DOS_UNIDADES = os.path.splitdrive(OTRA)[0].upper() != UNIDAD.upper()
if not DOS_UNIDADES:
    print('GUARDA: la jaula y la carpeta actual del servidor estan en la misma unidad (%s): '
          'los checks pasan, pero no hay roja que medir' % UNIDAD)


def sin_unidad(p):
    """La ruta "a medias" de raiz: \\x, sin su unidad."""
    return os.path.splitdrive(p)[1]


def escribe(p, texto, nl='\r\n'):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8', newline=nl).write(texto)


XML_VACIO = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"></Project>\n'

# M1: un .dproj cuyo search path lleva las dos formas a medias y un relativo
PROY = os.path.join(JAIL, 'Proy')
for d in ('libA', 'libB', 'libC'):
    os.makedirs(os.path.join(PROY, d))
escribe(os.path.join(PROY, 'P.dproj'),
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
        '  <PropertyGroup>\n'
        '    <DCC_UnitSearchPath>%s;%slibB;libC;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>\n'
        '  </PropertyGroup>\n</Project>\n' % (sin_unidad(os.path.join(PROY, 'libA')), UNIDAD))

# M2: un grupo con sus dos proyectos escritos a medias
GRUPO = os.path.join(JAIL, 'Grupo')
GPROJ = os.path.join(GRUPO, 'G.groupproj')
for n in ('P2', 'P3'):
    escribe(os.path.join(GRUPO, n + '.dproj'), XML_VACIO)
escribe(GPROJ,
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
        '  <ItemGroup>\n'
        '    <Projects Include="%s"><Dependencies/></Projects>\n'
        '    <Projects Include="%sP3.dproj"><Dependencies/></Projects>\n'
        '  </ItemGroup>\n</Project>\n' % (sin_unidad(os.path.join(GRUPO, 'P2.dproj')), UNIDAD))

# M3: una carpeta de estilos con un .rc que nombra sus tres ficheros
EST = os.path.join(JAIL, 'Est')
escribe(os.path.join(EST, 'Uno.style'),
        'object TStyleContainer\n  object TLayout\n    StyleName = \'uno\'\n  end\nend\n')
for n in ('a.bin', 'b.bin', 'c.bin'):
    open(os.path.join(EST, n), 'wb').write(b'x')
escribe(os.path.join(EST, 'Estilos.rc'),
        'A RCDATA "%s"\nB RCDATA "%sb.bin"\nC RCDATA "c.bin"\nD RCDATA "falta.bin"\n'
        % (sin_unidad(os.path.join(EST, 'a.bin')), UNIDAD))

# M4: un form cuyo Caption nombra, a medias, un fichero de FUERA de la jaula
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(FUERA)
open(os.path.join(FUERA, 'x.txt'), 'w').write('x')
FORMS = os.path.join(JAIL, 'Forms')
DFM = os.path.join(FORMS, 'UMedias.dfm')
escribe(DFM,
        'object FormMedias: TFormMedias\n  Left = 0\n  Top = 0\n  Caption = \'%s\'\n'
        '  ClientHeight = 200\n  ClientWidth = 300\n  object Button1: TButton\n    Left = 8\n'
        '    Top = 8\n    TabOrder = 0\n  end\n  object Button2: TButton\n    Left = 8\n'
        '    Top = 40\n    TabOrder = 1\n  end\nend\n' % sin_unidad(os.path.join(FUERA, 'x.txt')))
escribe(os.path.join(FORMS, 'UMedias.pas'),
        'unit UMedias;\n\ninterface\n\nuses\n  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;\n\n'
        'type\n  TFormMedias = class(TForm)\n    Button1: TButton;\n    Button2: TButton;\n  end;\n\n'
        'var\n  FormMedias: TFormMedias;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')

ANTES_OTRA = sorted(os.listdir(OTRA))
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'LOCALAPPDATA': os.path.join(BASE, 'appdata')}),
               nombre='a_medias_1230', cwd=OTRA, t=300)


def nombre_de(virtual):
    return os.path.basename(mc.real(virtual).rstrip('\\/'))


try:
    # ------------------------------------------------------------------ M1
    j = mc.como_json(srv.call('delphi_projects', {'root': JAIL}))
    contra = []
    proys = mc.ficheros(j, campo='projects')
    for e in proys:
        if e.get('name') == 'P.dproj':
            contra = sorted(nombre_de(c) for c in e.get('compilesAgainst') or [])
    check('M1 (control) delphi_projects lista el .dproj de la prueba',
          any(e.get('name') == 'P.dproj' for e in proys), str(j)[:400])
    check('M1 delphi_projects: compilesAgainst sigue "\\x" y "%s:x" desde la carpeta del .dproj, y el '
          'relativo de siempre' % UNIDAD[0], contra == ['libA', 'libB', 'libC'], (contra, str(j)[:400]))

    # ------------------------------------------------------------------ M2
    j = mc.como_json(srv.call('delphi_config', {'project': GPROJ}))
    ps = j.get('projects') or []
    vistos = [(os.path.basename(mc.real(p.get('path', ''))), p.get('exists'), p.get('outsideWorkspace'))
              for p in ps]
    check('M2 view de un .groupproj: sus proyectos "\\x" y "%s:x", en su sitio y existentes' % UNIDAD[0],
          vistos == [('P2.dproj', True, None), ('P3.dproj', True, None)], (vistos, str(j)[:400]))

    # ------------------------------------------------------------------ M3
    j = mc.como_json(srv.call('delphi_styles', {'command': 'lint', 'path': EST}, t=180))
    malos = [(e.get('resource'), e.get('missing'), e.get('refused', '')[:60]) for e in j.get('rcMissingFiles') or []]
    check('M3 delphi_styles lint: los ficheros "\\x" y "%s:x" del .rc estan; ni faltan ni se niegan (y el '
          'que falta de verdad, si: el lint miro)' % UNIDAD[0],
          malos == [('D', 'falta.bin', '')], (malos, str(j)[:400]))

    # ------------------------------------------------------------------ M4
    antes = open(DFM, 'rb').read()
    r = srv.call('delphi_designer', {'command': 'set', 'path': DFM, 'component': 'Button2', 'before': 'Button1'},
                 t=240)
    check('M4 un Caption "\\x" que nombra un fichero de FUERA: DSGN-115 (lo que el ayudante lee desde la '
          'carpeta del form) y el form no cambia',
          mc.abre(r, 'SR_DESIGNER_LITERAL_FUERA_FMT') and open(DFM, 'rb').read() == antes, r[:300])
finally:
    srv.cierra()

# ------------------------------------------------------------------ M5
check('M5 la carpeta actual del servidor (en el repo) sale como estaba',
      sorted(os.listdir(OTRA)) == ANTES_OTRA, set(os.listdir(OTRA)) ^ set(ANTES_OTRA))

mc.fin('rutas a medias 1.23.0 battery')
