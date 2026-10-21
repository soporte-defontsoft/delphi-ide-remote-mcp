# -*- coding: utf-8 -*-
r"""El build en LISTA BLANCA (1.21.2). Hasta la 1.21.1 la puerta del build era
una lista negra de 21 tareas de MSBuild: lo que la lista no conocia, compilaba;
y lo que el build LEE por lo que el proyecto escribe (el icono, el manifiesto,
los search paths, un .rc, un DCCReference) no lo juzgaba nadie (hallazgo de la
1.20.1: un RcCompile y un Manifest_File de fuera acababan en el .res y el exe).
Fixtures INERTES: lo negado no llega a msbuild y, si llegara, no ejecutaria
nada (un <Foo/>, un <Touch Files=""/>, un icono, un .rc, un .pas vacio).

  W1  un elemento desconocido bajo <Project> se niega por su nombre y su padre
  W2  dentro de un <Target>: un elemento desconocido, y una tarea conocida
      nombrada como tarea (a <touch> task)
  W3  un <Target> INERTE (Message, PropertyGroup, CallTarget) compila
  W4  un elemento desconocido dentro de un COMENTARIO no se niega (msbuild no
      lo ve: la lista blanca es fiel al juez)
  W5  XML que no se puede seguir (un cierre que no casa) se niega diciendolo
  W6  Icon_MainIcon de FUERA de las raices: BUILD-050; el mismo icono DENTRO
      (relativo) compila
  W7  Manifest_File de fuera: BUILD-050
  W8  DCC_UnitSearchPath de fuera: absoluto, relativo con .., y uno que NO
      existe (se juzga la ruta, no si existe: nada de oraculos)
  W9  DCC_UnitSearchPath dentro (lib;$(DCC_UnitSearchPath)) compila
  W10 RcCompile cuyo .rc nombra un fichero de fuera: BUILD-052 (con la
      negativa del lector del .rc dentro); el .rc que nombra uno de dentro compila;
      un RcItem (un .gif RCDATA, un FICHERO, no un guion) de dentro compila y uno
      de fuera es BUILD-050 por su ruta (1.21.3: se leia como guion y citaba sus
      bytes, BUILD-052 con basura)
  W11 DCC_AdditionalSwitches no vacio: negado; con AllowBuildScripts compila
  W12 un ENLACE DURO en el arbol del proyecto a un fichero de fuera: BUILD-053;
      uno entre dos ficheros de dentro compila (donde Windows lista los
      nombres; donde no - el %TEMP% de la app MSIX, error 50 - se niega
      cerrado, y se dice)
  W13 DCCReference de fuera: BUILD-050, tambien dentro de una lista (a;b)
  W14 lo que no es una ruta (VerInfo_Keys, un define, un texto con ':', una
      URL) no se juzga: compila; un flujo alternativo (f.ico:s) se juzga por
      su fichero: el de fuera, BUILD-050

W1, W2 (foo), W5, W6, W7, W8, W10, W11, W12 y W13 son ROJAS contra 1.21.1
(pasar su exe como argumento).

Uso:  python tests/test_build_lista_blanca_1212.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, os, shutil
from ctypes import wintypes as w
from xml.sax.saxutils import escape
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-lista-blanca')
# FUERA de la raiz del servidor (DELPHI_MCP_ROOTS = BASE), hermana de BASE
FUERA = mc.carpeta('build-lista-blanca-fuera')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='lb', t=600)
IDE_ICONO = r'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\delphi_PROJECTICON.ico'
N = 0


def attr(v):
    return escape(v, {'"': '&quot;'})


def nombres_listables(p):
    """El juez, preguntado aqui: lista Windows los nombres de p?"""
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.FindFirstFileNameW.restype = ctypes.c_void_p
    k.FindFirstFileNameW.argtypes = [w.LPCWSTR, w.DWORD, ctypes.POINTER(w.DWORD), w.LPWSTR]
    k.FindClose.argtypes = [ctypes.c_void_p]
    buf = ctypes.create_unicode_buffer(32768)
    n = w.DWORD(32768)
    h = k.FindFirstFileNameW(p, 0, ctypes.byref(n), buf)
    if h in (None, ctypes.c_void_p(-1).value):
        return False
    k.FindClose(h)
    return True


def fixture(nombre):
    """Un proyecto de consola nuevo (delphi_create) en su carpeta: (carpeta, .dproj, xml)."""
    carpeta = os.path.join(BASE, nombre)
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check(nombre + ': fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    return carpeta, proyecto, xml


def escribe(proyecto, xml, payload):
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace('</Project>', payload + '</Project>'))


def build(proyecto, servidor=None):
    return (servidor or srv).call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def peligro(r, motivo):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and motivo in r


def lectura_fuera(r, elemento):
    return mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT') and ('<%s>' % elemento) in r


try:
    # --- W1-W5: la estructura ---
    carpeta, proyecto, xml = fixture('estructura')
    r = build(proyecto)
    check('W0 control: el proyecto recien creado compila', compila(r), detalle(r))
    escribe(proyecto, xml, '<Foo/>')
    r = build(proyecto)
    check('W1 un <Foo/> bajo <Project> se niega por su nombre y su padre',
          peligro(r, 'a <foo> element inside <project>'), r[:300])
    escribe(proyecto, xml, '<Target Name="T" AfterTargets="Build"><ItemGroup/><Foo/></Target>')
    r = build(proyecto)
    check('W2 un <Foo/> dentro de un <Target> se niega',
          peligro(r, 'a <foo> element inside <target>'), r[:300])
    escribe(proyecto, xml, '<Target Name="T" AfterTargets="Build"><Touch Files=""/></Target>')
    r = build(proyecto)
    check('W2 una tarea conocida se nombra como tarea (a <touch> task)',
          peligro(r, 'a <touch> task'), r[:300])
    escribe(proyecto, xml,
            '<Target Name="T" AfterTargets="Build"><Message Text="inerte" Importance="high"/>'
            '<PropertyGroup><LbProp>1</LbProp></PropertyGroup><ItemGroup><LbItem Include="x"/></ItemGroup>'
            '<CallTarget Targets="T2"/></Target><Target Name="T2"><Message Text="dos"/></Target>')
    r = build(proyecto)
    check('W3 un <Target> INERTE (Message, PropertyGroup, ItemGroup, CallTarget) compila',
          compila(r), detalle(r))
    escribe(proyecto, xml, '<!-- <Foo/> <Target><Bar/></Target> -->')
    r = build(proyecto)
    check('W4 un elemento desconocido dentro de un comentario no se niega (msbuild no lo ve)',
          compila(r), detalle(r))
    escribe(proyecto, xml, '<PropertyGroup><X>1</PropertyGroup>')
    r = build(proyecto)
    check('W5 XML que no se puede seguir se niega diciendo que cierra que',
          peligro(r, 'XML that cannot be followed (</propertygroup> closes <x>)'), r[:300])

    # --- W6-W9, W13, W14: lo que el build lee ---
    carpeta, proyecto, xml = fixture('lecturas')
    icono_fuera = os.path.join(FUERA, 'icono.ico')
    shutil.copyfile(IDE_ICONO, icono_fuera)
    escribe(proyecto, xml, '<PropertyGroup><Icon_MainIcon>%s</Icon_MainIcon></PropertyGroup>' % escape(icono_fuera))
    r = build(proyecto)
    check('W6 Icon_MainIcon de FUERA de las raices: BUILD-050 nombrando el elemento',
          lectura_fuera(r, 'Icon_MainIcon'), r[:300])
    shutil.copyfile(IDE_ICONO, os.path.join(carpeta, 'icono.ico'))
    escribe(proyecto, xml, '<PropertyGroup><Icon_MainIcon>icono.ico</Icon_MainIcon></PropertyGroup>')
    r = build(proyecto)
    check('W6 el mismo icono DENTRO (relativo al proyecto) compila', compila(r), detalle(r))
    manifiesto = os.path.join(FUERA, 'app.manifest')
    open(manifiesto, 'w', encoding='utf-8').write('<assembly/>')
    escribe(proyecto, xml, '<PropertyGroup><Manifest_File>%s</Manifest_File></PropertyGroup>' % escape(manifiesto))
    r = build(proyecto)
    check('W7 Manifest_File de fuera: BUILD-050', lectura_fuera(r, 'Manifest_File'), r[:300])
    for valor, label in ((FUERA, 'absoluto'),
                         (os.path.join('..', '..', os.path.basename(FUERA)), 'relativo con ..'),
                         (r'C:\no-existe-1212\lib', 'que no existe')):
        escribe(proyecto, xml, '<PropertyGroup><DCC_UnitSearchPath>%s;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>' % escape(valor))
        r = build(proyecto)
        check('W8 DCC_UnitSearchPath de fuera (%s): BUILD-050' % label,
              lectura_fuera(r, 'DCC_UnitSearchPath'), r[:300])
    os.makedirs(os.path.join(carpeta, 'lib'))
    escribe(proyecto, xml, '<PropertyGroup><DCC_UnitSearchPath>lib;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>')
    r = build(proyecto)
    check('W9 DCC_UnitSearchPath dentro (lib;$(DCC_UnitSearchPath)) compila', compila(r), detalle(r))
    ajena = os.path.join(FUERA, 'Ajena.pas')
    open(ajena, 'w', encoding='utf-8').write('unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n')
    escribe(proyecto, xml, '<ItemGroup><DCCReference Include="%s"/></ItemGroup>' % attr(ajena))
    r = build(proyecto)
    check('W13 DCCReference de fuera: BUILD-050', lectura_fuera(r, 'DCCReference'), r[:300])
    # un Include es una LISTA para msbuild: el segundo de la lista tambien se juzga
    escribe(proyecto, xml, '<ItemGroup><DCCReference Include="Fixture.dpr;%s"/></ItemGroup>' % attr(ajena))
    r = build(proyecto)
    check('W13 ...y dentro de una lista (dentro.dpr;fuera.pas) tambien', lectura_fuera(r, 'DCCReference'), r[:300])
    escribe(proyecto, xml,
            '<PropertyGroup><VerInfo_Keys>CompanyName=;FileDescription=$(MSBuildProjectName);Comments=D:\\no\\es\\ruta</VerInfo_Keys>'
            '<DCC_Define>LB1212;$(DCC_Define)</DCC_Define>'
            '<LbTexto>Version: 1.0 (c) Acme</LbTexto><LbUrl>https://example.invalid/x</LbUrl></PropertyGroup>')
    r = build(proyecto)
    check('W14 lo que no es una ruta (VerInfo_Keys, un define, un texto con :, una URL) no se juzga: compila',
          compila(r), detalle(r))
    # un flujo alternativo (f:s) se juzga por SU fichero: el de fuera, negado
    escribe(proyecto, xml, '<PropertyGroup><Icon_MainIcon>%s:flujo</Icon_MainIcon></PropertyGroup>' % escape(icono_fuera))
    r = build(proyecto)
    check('W14 un flujo alternativo de un fichero de fuera (icono.ico:flujo): BUILD-050',
          lectura_fuera(r, 'Icon_MainIcon'), r[:300])

    # --- W10: el .rc de un RcCompile ---
    carpeta, proyecto, xml = fixture('recursos')
    secreto = os.path.join(FUERA, 'secreto.txt')
    open(secreto, 'w', encoding='utf-8').write('SECRETO-LB-1212\n')
    rc = os.path.join(carpeta, 'recursos.rc')
    open(rc, 'w', encoding='utf-8').write('DATOS RCDATA "%s"\r\n' % secreto)
    escribe(proyecto, xml, '<ItemGroup><RcCompile Include="recursos.rc"><Form>recursos.res</Form></RcCompile></ItemGroup>')
    r = build(proyecto)
    check('W10 el .rc de un RcCompile que nombra un fichero de fuera: BUILD-052 con la negativa del lector',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_RC_FMT') and mc.es(r, 'SR_STYLES_RC_OUTSIDE_FMT'), r[:400])
    check('W10 ...y el .res no nacio', not os.path.exists(os.path.join(carpeta, 'recursos.res')))
    open(os.path.join(carpeta, 'dentro.txt'), 'w', encoding='utf-8').write('dentro\n')
    open(rc, 'w', encoding='utf-8').write('DATOS RCDATA "dentro.txt"\r\n')
    r = build(proyecto)
    check('W10 el .rc que nombra uno de dentro compila', compila(r), detalle(r))
    # un RcItem es un FICHERO de recurso (RCDATA), no un guion: se juzga por su
    # ruta y no se lee como texto (1.21.3; en 1.21.2 salia BUILD-052 con sus bytes)
    open(os.path.join(carpeta, 'dentro.gif'), 'wb').write(b'GIF89a' + bytes(range(1, 200)))
    escribe(proyecto, xml, '<ItemGroup><RcItem Include="dentro.gif"><ResourceType>RCDATA</ResourceType>'
                           '<ResourceId>dentro</ResourceId></RcItem></ItemGroup>')
    r = build(proyecto)
    check('W10 un RcItem binario de DENTRO (un .gif RCDATA) compila: es un fichero, no un guion', compila(r), detalle(r))
    escribe(proyecto, xml, '<ItemGroup><RcItem Include="%s"><ResourceType>RCDATA</ResourceType>'
                           '<ResourceId>fuera</ResourceId></RcItem></ItemGroup>' % attr(secreto))
    r = build(proyecto)
    check('W10 un RcItem de FUERA: BUILD-050 por su ruta', lectura_fuera(r, 'RcItem'), r[:300])

    # --- W12: un enlace duro en el arbol ---
    carpeta, proyecto, xml = fixture('enlace')
    escribe(proyecto, xml, '')
    enlace = os.path.join(carpeta, 'Ajena.pas')
    os.link(ajena, enlace)
    r = build(proyecto)
    check('W12 un enlace duro del arbol a un fichero de fuera: BUILD-053',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_ENLACE_DURO_FMT') and 'Ajena.pas' in r, r[:300])
    os.remove(enlace)
    propio = os.path.join(carpeta, 'Propia.pas')
    open(propio, 'w', encoding='utf-8').write('unit Propia;\r\ninterface\r\nimplementation\r\nend.\r\n')
    os.link(propio, os.path.join(carpeta, 'Propia2.pas'))
    r = build(proyecto)
    if nombres_listables(propio):
        check('W12 un enlace duro entre dos ficheros de DENTRO compila', compila(r), detalle(r))
    else:
        check('W12 donde Windows no lista los nombres (error 50) el enlace de dentro se niega cerrado (GUARD-042)',
              mc.rechazado(r) and mc.es(r, 'SR_BUILD_ENLACE_DURO_FMT'), r[:300])

    # --- W11: opciones libres (el servidor de confianza, aparte, al final) ---
    carpeta, proyecto, xml = fixture('opciones')
    escribe(proyecto, xml, '<PropertyGroup><DCC_AdditionalSwitches>-$O+</DCC_AdditionalSwitches></PropertyGroup>')
    r = build(proyecto)
    check('W11 DCC_AdditionalSwitches no vacio se niega sin AllowBuildScripts',
          peligro(r, 'a non-empty <DCC_AdditionalSwitches>'), r[:300])
    srv.cierra()
    srv = None
    confiado = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_ALLOW_BUILD_SCRIPTS': '1'}),
                        nombre='lb-confiado', t=600)
    try:
        r = build(proyecto, confiado)
        check('W11 ...y con AllowBuildScripts compila', compila(r), detalle(r))
    finally:
        confiado.cierra()
finally:
    if srv is not None:
        srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('build en lista blanca 1212')
