# -*- coding: utf-8 -*-
r"""Las salidas que el proyecto no declara las SUPLE el build (1.21.3). Hasta la
1.21.2 un proyecto sin DCC_DcuOutput (o un paquete sin DCC_BplOutput /
DCC_DcpOutput) para la plataforma y config del build se rechazaba con
BUILD-030: sin ellas dcc deja cada .dcu junto a su fuente - los de un
componente instalado o de una referencia, FUERA del proyecto - y el .bpl y el
.dcp en las carpetas globales del IDE. Medido el 21-oct-2026 en la VM 13.2:
un proyecto real de veinte anos (sin DCC_DcuOutput desde siempre) compilaba en
el IDE, que dejo 14 .dcu de un componente en Program Files, y aqui no. Desde la
1.21.3 el build pone
el mismo esas carpetas en la linea de msbuild (la del binario de ese build,
dentro del proyecto; .\$(Platform)\$(Config) si tampoco la hay), sin tocar el
.dproj, y la respuesta lo dice (outputSupplied, BUILD-054). Lo que el proyecto
declara se respeta tal cual; la .hpp (salida C++) no se suple.

  S1  sin DCC_DcuOutput: compila, outputSupplied nombra DCC_DcuOutput con la
      carpeta del exe, el .dcu de la unidad cae ahi y no junto al fuente, y el
      .dproj queda byte a byte
  S2  con DCC_DcuOutput declarada (lo que escribe delphi_create): nada
      suplido, el .dcu donde dice el proyecto (el operador manda)
  S3  EL CASO: una unidad de una REFERENCIA de solo lectura, en el search
      path, compilada desde su fuente: su .dcu cae en el proyecto y la carpeta
      de la referencia queda intacta
  S4  por plataforma: Win32 y Win64 del mismo proyecto, cada uno en su carpeta
  S5  un paquete sin DCC_BplOutput ni DCC_DcpOutput: compila, el .bpl y el
      .dcp dentro, outputSupplied nombra las dos
  S6  salida C++ (DCC_CBuilderOutput) sin DCC_HppOutput: BUILD-030 sigue
  S7  nada en ningun sitio (ni DCC_ExeOutput): .\$(Platform)\$(Config), el exe
      junto al .dpr
  S8  target=Clean con la carpeta suplida: borra lo que borra msbuild (el exe;
      el .dcu de una unidad referenciada se queda, como en el IDE) y deja el
      fuente

S1, S3, S4, S5 y S7 son ROJAS contra 1.21.2 (pasar su exe como argumento).

Uso:  python tests/test_build_salida_suplida_1213.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-salida-suplida')
REF = mc.carpeta('build-salida-suplida-ref')  # raiz de SOLO LECTURA, hermana de BASE
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_READONLY_ROOTS': REF}), nombre='ss', t=600)
UNIDAD = ('unit %s;\r\n\r\ninterface\r\n\r\nfunction Dos: Integer;\r\n\r\nimplementation\r\n\r\n'
          'function Dos: Integer;\r\nbegin\r\n  Result := 2;\r\nend;\r\n\r\nend.\r\n')


def fixture(nombre, kind='project-console', unidad='UUno'):
    """Un proyecto nuevo (delphi_create) con una unidad registrada: (carpeta, .dproj, xml)."""
    carpeta = os.path.join(BASE, nombre)
    r = srv.call('delphi_create', {'kind': kind, 'name': 'Fixture', 'dir': carpeta})
    check(nombre + ': fixture creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    if unidad:
        r = srv.call('delphi_create', {'kind': 'unit', 'name': unidad, 'project': proyecto, 'content': UNIDAD % unidad})
        check(nombre + ': unidad registrada', not mc.rechazado(r), r[:200])
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    return carpeta, proyecto, xml


def sin(xml, *tags):
    """El .dproj sin esas propiedades, en el grupo que esten."""
    for tag in tags:
        xml = re.sub(r'\s*<' + tag + r'>[^<]*</' + tag + r'>', '', xml)
    return xml


def escribe(proyecto, xml, payload=''):
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace('</Project>', payload + '</Project>') if payload else xml)


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def build(proyecto, plat='Win64', target='Build'):
    return srv.call('delphi_build', {'project': proyecto, 'platform': plat, 'config': 'Debug', 'target': target}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def suplidas(r):
    """{propiedad: carpeta} de outputSupplied, vacio si no va."""
    return {e.get('property'): e.get('dir', '') for e in (mc.como_json(r).get('outputSupplied') or [])}


def detalle(r):
    j = mc.como_json(r)
    return str(j.get('errors') or j.get('error') or r[:300])[:400]


def termina_en(ruta, cola):
    return ruta.replace('/', '\\').lower().rstrip('\\').endswith(cola.lower())


def hay(carpeta, *sub):
    return os.path.isfile(os.path.join(carpeta, *sub))


def lista(carpeta, *sub):
    d = os.path.join(carpeta, *sub)
    return str(sorted(os.listdir(d))) if os.path.isdir(d) else '(no existe) ' + d


try:
    # --- S1: sin DCC_DcuOutput ---
    carpeta1, proyecto1, xml = fixture('s1')
    escribe(proyecto1, sin(xml, 'DCC_DcuOutput'))
    antes = sha(proyecto1)
    r = build(proyecto1)
    check('S1 sin DCC_DcuOutput compila', compila(r), detalle(r))
    sup = suplidas(r)
    check('S1 outputSupplied nombra DCC_DcuOutput con la carpeta del exe (s1\\Win64\\Debug)',
          list(sup) == ['DCC_DcuOutput'] and termina_en(sup.get('DCC_DcuOutput', ''), r'\s1\Win64\Debug'), str(sup))
    check('S1 ...y la nota BUILD-054', mc.es(r, 'SN_BUILD_OUTPUT_SUPPLIED'), r[:300])
    check('S1 el .dcu cae en la carpeta del exe, no junto al fuente',
          hay(carpeta1, 'Win64', 'Debug', 'UUno.dcu') and not hay(carpeta1, 'UUno.dcu'), lista(carpeta1))
    check('S1 el .dproj no se ha tocado', sha(proyecto1) == antes)

    # --- S2: declarada, el operador manda ---
    carpeta, proyecto, xml = fixture('s2')
    r = build(proyecto)
    check('S2 con DCC_DcuOutput declarada compila', compila(r), detalle(r))
    check('S2 ...nada suplido: lo declarado se respeta', suplidas(r) == {} and not mc.es(r, 'SN_BUILD_OUTPUT_SUPPLIED'), r[:300])
    check('S2 el .dcu donde dice el proyecto (Win64\\Debug\\dcu)', hay(carpeta, 'Win64', 'Debug', 'dcu', 'UUno.dcu'),
          lista(carpeta, 'Win64', 'Debug'))

    # --- S3: EL CASO, una unidad de una referencia de solo lectura ---
    lib = os.path.join(REF, 'lib')
    os.makedirs(lib, exist_ok=True)
    with open(os.path.join(lib, 'ULib.pas'), 'w', encoding='utf-8', newline='') as f:
        f.write(UNIDAD % 'ULib')
    antes_ref = sorted(os.listdir(lib))
    carpeta, proyecto, xml = fixture('s3', unidad='')
    r = srv.call('delphi_edit', {'path': os.path.join(carpeta, 'Fixture.dpr'), 'adduses': 'ULib'})
    check('S3 fixture: el .dpr usa ULib', not mc.rechazado(r), r[:200])
    # el search path por la tool (escribe DCC_UnitSearchPath en el grupo base, antes
    # de los Import: un PropertyGroup al final del .dproj ya no llega a dcc)
    r = srv.call('delphi_config', {'project': proyecto, 'command': 'add-searchpath', 'path': lib})
    check('S3 fixture: la referencia en el search path', not mc.rechazado(r), r[:300])
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    escribe(proyecto, sin(xml, 'DCC_DcuOutput'))
    r = build(proyecto)
    check('S3 una unidad de una referencia de solo lectura, compilada desde su fuente: compila', compila(r), detalle(r))
    check('S3 su .dcu cae en el proyecto', hay(carpeta, 'Win64', 'Debug', 'ULib.dcu'), lista(carpeta, 'Win64', 'Debug'))
    check('S3 ...y la carpeta de la referencia queda INTACTA (ningun .dcu junto a su fuente)',
          sorted(os.listdir(lib)) == antes_ref, lista(lib))

    # --- S4: por plataforma ---
    r = build(proyecto1, 'Win32')
    check('S4 Win32 del mismo proyecto compila', compila(r), detalle(r))
    check('S4 ...en SU carpeta (s1\\Win32\\Debug), y la de Win64 sigue',
          termina_en(suplidas(r).get('DCC_DcuOutput', ''), r'\s1\Win32\Debug') and
          hay(carpeta1, 'Win32', 'Debug', 'UUno.dcu') and hay(carpeta1, 'Win64', 'Debug', 'UUno.dcu'),
          str(suplidas(r)) + ' ' + lista(carpeta1, 'Win32', 'Debug'))

    # --- S5: un paquete sin DCC_BplOutput ni DCC_DcpOutput ---
    carpeta, proyecto, xml = fixture('s5', kind='project-package', unidad='UPk')
    escribe(proyecto, sin(xml, 'DCC_BplOutput', 'DCC_DcpOutput'))
    r = build(proyecto)
    check('S5 un paquete sin DCC_BplOutput ni DCC_DcpOutput compila', compila(r), detalle(r))
    sup = suplidas(r)
    check('S5 outputSupplied nombra las dos', sorted(sup) == ['DCC_BplOutput', 'DCC_DcpOutput'], str(sup))
    check('S5 el .bpl y el .dcp dentro del proyecto',
          hay(carpeta, 'Win64', 'Debug', 'Fixture.bpl') and hay(carpeta, 'Win64', 'Debug', 'Fixture.dcp'),
          lista(carpeta, 'Win64', 'Debug'))

    # --- S6: salida C++ sin DCC_HppOutput: BUILD-030 sigue ---
    carpeta, proyecto, xml = fixture('s6', unidad='')
    escribe(proyecto, xml, '<PropertyGroup><DCC_CBuilderOutput>All</DCC_CBuilderOutput></PropertyGroup>')
    r = build(proyecto)
    check('S6 salida C++ sin DCC_HppOutput: BUILD-030 sigue (esa no se suple)',
          mc.rechazado(r) and mc.es(r, 'SR_BUILD_OUTPUT_UNDECLARED_FMT') and 'DCC_HppOutput' in r, r[:300])

    # --- S7: nada en ningun sitio ---
    carpeta, proyecto, xml = fixture('s7')
    escribe(proyecto, sin(xml, 'DCC_ExeOutput', 'DCC_DcuOutput'))
    r = build(proyecto)
    check('S7 nada en ningun sitio compila', compila(r), detalle(r))
    check('S7 ...los .dcu a .\\Win64\\Debug (lo del IDE) y el exe junto al .dpr',
          termina_en(suplidas(r).get('DCC_DcuOutput', ''), r'\s7\Win64\Debug') and
          hay(carpeta, 'Win64', 'Debug', 'UUno.dcu') and hay(carpeta, 'Fixture.exe'),
          str(suplidas(r)) + ' ' + lista(carpeta))

    # --- S8: Clean con la carpeta suplida ---
    r = build(proyecto1, 'Win64', 'Clean')
    check('S8 target=Clean con la carpeta suplida: borra el exe (lo que borra msbuild) y deja el fuente',
          compila(r) and not hay(carpeta1, 'Win64', 'Debug', 'Fixture.exe') and hay(carpeta1, 'UUno.pas'),
          detalle(r) + ' ' + lista(carpeta1, 'Win64', 'Debug'))
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(REF)
mc.fin('build salida suplida 1213')
