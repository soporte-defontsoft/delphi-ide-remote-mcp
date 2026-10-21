# -*- coding: utf-8 -*-
r"""El nombre del binario lo manda OutputExt (1.21.3). Un .dproj puede declarar
<OutputExt> por plataforma y configuracion (Project Options > Application >
Target file extension): el IDE y msbuild escriben entonces <proyecto>.<OutputExt>
(App.x64.exe, App.Debug.exe). Hasta la 1.21.2 quien buscaba el
binario (ResolveBuildOutput: el "output" de delphi_build y el exe de
delphi_test) solo probaba <proyecto>.exe/.dll/.bpl, y el DeployFile del
.deployproj se escribia con .exe a secas. Medido el 21-oct-2026 con un
proyecto real: el build de Win32 contesto "output" con un <proyecto>.exe de
diciembre de 2025 que quedaba en la carpeta, mientras acababa de escribir el
.DPI.exe al lado; en Win64 no contesto ninguno. Ahora UN nombrador
(Lsp.Dproj.NombreDelBinario) compone el nombre como los targets.

  E1  con <OutputExt>Mio.exe</OutputExt> en la config: "output" es
      Fixture.Mio.exe y el fichero existe
  E2  con un Fixture.exe VIEJO plantado en la carpeta de salida: "output"
      sigue siendo Fixture.Mio.exe (no el viejo)
  E3  sin OutputExt: "output" es Fixture.exe (como siempre)
  E4  el DeployFile que escribe add-deployfile en el .deployproj nombra
      Fixture.Mio.exe en Debug (donde OutputExt esta declarada) y Fixture.exe
      en Release (donde no), como lo escribe el IDE: por configuracion

E1, E2 y E4 son ROJAS contra 1.21.2 (pasar su exe como argumento).

Uso:  python tests/test_build_outputext_1213.py [ruta-a-DelphiLspMcp.exe]
"""
import os, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build-outputext')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='oe', t=600)


def lee(path):
    with open(path, encoding='utf-8-sig') as f:
        return f.read()


def escribe(path, texto):
    with open(path, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(texto)


def fixture(nombre, outputext=None):
    carpeta = os.path.join(BASE, nombre)
    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check(nombre + ': fixture creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    dproj = os.path.join(carpeta, 'Fixture.dproj')
    if outputext:
        xml = lee(dproj)
        # en el grupo de la config Debug (su clave, la del .dproj), para todas las plataformas
        cond = "'$(" + mc.clave_de_config(xml, 'Debug') + ")'!=''"
        grupo = '    <PropertyGroup Condition="' + cond + '">\r\n        <OutputExt>' + outputext + \
                '</OutputExt>\r\n    </PropertyGroup>\r\n    <ItemGroup>'
        check(nombre + ': fixture con OutputExt', '    <ItemGroup>' in xml, xml[:300])
        escribe(dproj, xml.replace('    <ItemGroup>', grupo, 1))
    return carpeta, dproj


def build(dproj):
    return srv.call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'}, 600)


def salida(r):
    return (mc.como_json(r).get('output') or '').replace('/', '\\')


def detalle(r):
    j = mc.como_json(r)
    return str(j.get('errors') or j.get('error') or r[:300])[:400]


try:
    # --- E1: OutputExt manda el nombre ---
    carpeta, dproj = fixture('e1', 'Mio.exe')
    r = build(dproj)
    check('E1 con OutputExt compila', mc.como_json(r).get('success') is True, detalle(r))
    check('E1 "output" es Fixture.Mio.exe y existe',
          salida(r).lower().endswith('\\win64\\debug\\fixture.mio.exe') and
          os.path.isfile(os.path.join(carpeta, 'Win64', 'Debug', 'Fixture.Mio.exe')), salida(r) or r[:300])
    # --- E2: un .exe viejo al lado no es el de este build ---
    viejo = os.path.join(carpeta, 'Win64', 'Debug', 'Fixture.exe')
    with open(viejo, 'wb') as f:
        f.write(b'MZ viejo')
    antiguo = time.time() - 300 * 86400
    os.utime(viejo, (antiguo, antiguo))
    r = build(dproj)
    check('E2 con un Fixture.exe viejo plantado, "output" sigue siendo Fixture.Mio.exe',
          salida(r).lower().endswith('\\fixture.mio.exe'), salida(r) or r[:300])
    # --- E3: sin OutputExt, como siempre ---
    carpeta3, dproj3 = fixture('e3')
    r = build(dproj3)
    check('E3 sin OutputExt "output" es Fixture.exe', salida(r).lower().endswith('\\win64\\debug\\fixture.exe'),
          salida(r) or r[:300])
    # --- E4: el DeployFile del .deployproj ---
    dato = os.path.join(carpeta, 'datos.txt')
    with open(dato, 'w', encoding='utf-8') as f:
        f.write('datos\n')
    r = srv.call('delphi_config', {'project': dproj, 'command': 'add-deployfile', 'platform': 'Win64', 'path': dato})
    check('E4 add-deployfile crea el manifiesto', not mc.rechazado(r), r[:300])
    manifiesto = os.path.join(carpeta, 'Fixture.deployproj')
    texto = lee(manifiesto) if os.path.isfile(manifiesto) else ''
    check('E4 el DeployFile del proyecto nombra Fixture.Mio.exe en Debug y Fixture.exe en Release (por config)',
          'Win64\\Debug\\Fixture.Mio.exe' in texto and 'Win64\\Release\\Fixture.exe' in texto, texto[:600])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('build outputext 1213')
