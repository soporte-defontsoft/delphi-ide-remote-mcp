# -*- coding: utf-8 -*-
"""V118 (1.23.1): the build door reads the msbuild macros the way msbuild does.

The door expanded msbuild macros with its OWN tables and in two measured cases
judged a different file than msbuild uses (28-oct-2026, against production):

  A  <Import Project="$(ProjectDir)\\v.targets"/> at the START of the .dproj.
     $(ProjectDir) is NOT a reserved property: CodeGear.Delphi.Targets DEFINES
     it (empty in the body, the project folder after that Import), and the
     project may redefine it. msbuild read it EMPTY here and imported
     <unit>:\\v.targets (the drive root, OUTSIDE the jail) while the door, which
     expanded $(ProjectDir) to the project folder, scanned <project>\\v.targets.
     Now: $(ProjectDir) in an <Import> is NON-VERIFIABLE (its value depends on
     the position and on who defines it) and the build is refused.
  B  the SAME import at the END (after CodeGear.Delphi.Targets): there msbuild
     reads $(ProjectDir) = the project folder. Also NON-VERIFIABLE, refused -
     this is the red for the wrong "always empty" fix, which for B would scan
     the drive root while msbuild imports the project's, unscanned.
  C  DCC_ExeOutput = $(ProjectDir)\\salida: $(ProjectDir) empty in a value (H4)
     -> \\salida, the drive root, outside -> BUILD-050. Control, denied before
     and after.
  D  a .targets imported from ANOTHER folder sets DCC_UnitSearchPath with
     $(MSBuildThisFileDirectory)..\\..\\fuera: msbuild resolves that macro from
     the imported FILE's own folder (outside the jail); the door used the
     project folder for EVERY document of the chain, so it resolved inside.
     Now per-file -> the search path falls outside -> BUILD-050.

The unit root (X:\\) is OUTSIDE the jail (the jail is X:\\proj) and INSIDE the
battery folder: a subst unit over a temp folder, like test_raiz_unidad, so
nothing is ever written outside the battery's own folder.

Usage:  python tests/test_build_macros_v118.py [path-to-DelphiLspMcp.exe]
"""
import atexit, os, subprocess, sys
import mcp_cliente as mc

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('build_macros_v118')
UNI = os.path.join(BASE, 'unidad')
os.makedirs(UNI)
L = mc.letras_libres(1)[0]
_r = subprocess.run(['subst', L + ':', UNI], capture_output=True, text=True)
assert _r.returncode == 0 and os.path.isdir(L + ':\\'), _r.stdout + _r.stderr
atexit.register(lambda: subprocess.run(['subst', L + ':', '/d'], capture_output=True))
X = L + ':\\'
J = os.path.join(X, 'proj')          # la jaula; X:\ (la raiz de la unidad) queda FUERA
os.makedirs(J)

NS = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
# un v.targets que, si msbuild lo importa, dispara un <Error> con una marca: si
# la marca sale, el build toco un fichero que el escaner no vio.
ERR = NS + '<Target Name="V118" BeforeTargets="Build"><Error Text="V118-IMPORTADO-DE-FUERA"/></Target></Project>'
BEN = NS + '<Target Name="V118b" BeforeTargets="Build"><Message Text="v118-benigno"/></Target></Project>'

S = mc.Stdio(mc.copia_exe(os.path.join(BASE, 's'), src=exe_src),
             mc.entorno({'DELPHI_MCP_ROOTS': J}), nombre='v118', t=600)


def proyecto(sub, nombre):
    d = os.path.join(J, sub)
    out = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    assert mc.abre(out, 'SK_CREATE_CREADO_PROYECTO_FMT'), out[:300]
    return d, os.path.join(d, nombre + '.dproj')


def lee(p):
    return open(p, 'rb').read().decode('utf-8-sig')


def escribe(p, t):
    open(p, 'wb').write(b'\xef\xbb\xbf' + t.encode('utf-8'))


def build(p):
    r = S.call('delphi_build', {'project': p, 'platform': 'Win32', 'verbosity': 'normal'}, 600)
    return r, mc.como_json(r)


try:
    # --- A y B: $(ProjectDir)\v.targets, al PRINCIPIO (A) y al FINAL (B) ---
    for caso, al_final in (('A', False), ('B', True)):
        d, p = proyecto('imp' + caso, 'P' + caso)
        # el benigno DENTRO de la carpeta del proyecto (donde miraba el escaner)
        with open(os.path.join(d, 'v.targets'), 'w', newline='') as f:
            f.write(BEN)
        # el <Error> en la raiz de la unidad (donde lo importa msbuild en A)
        with open(os.path.join(X, 'v.targets'), 'w', newline='') as f:
            f.write(ERR)
        t = lee(p)
        imp = '<Import Project="$(ProjectDir)\\v.targets"/>'
        if al_final:
            t = t.replace('</Project>', imp + '\r\n</Project>')
        else:
            i = t.index('<PropertyGroup')
            t = t[:i] + imp + '\r\n    ' + t[i:]
        escribe(p, t)
        r, j = build(p)
        mc.check('%s: $(ProjectDir) en un <Import> se niega como NO verificable '
                 '(rojo contra prod y contra la variante "vacio siempre")' % caso,
                 mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT')
                 and 'cannot be verified' in r and 'V118-IMPORTADO-DE-FUERA' not in r,
                 j.get('firstError') or r[:400])
        os.remove(os.path.join(X, 'v.targets'))

    # --- C (control): DCC_ExeOutput = $(ProjectDir)\salida -> BUILD-050 ---
    # En un VALOR del cuerpo $(ProjectDir) lo lee msbuild VACIO (H4): \salida118
    # es la raiz de la unidad, fuera. Negado antes y despues del arreglo.
    d, p = proyecto('sal', 'PC')
    t = lee(p)
    i = t.lower().index('<import project="$(bds)\\bin\\codegear.delphi.targets"')
    t = t[:i] + ('<PropertyGroup><DCC_ExeOutput>$(ProjectDir)\\salida118</DCC_ExeOutput>'
                 '<DCC_DcuOutput>$(ProjectDir)\\salida118</DCC_DcuOutput></PropertyGroup>\r\n    ') + t[i:]
    escribe(p, t)
    r, j = build(p)
    # control, negado antes y despues: contra prod la niega el gate de valores
    # (BUILD-050, $(ProjectDir) vacio -> \salida118 en la raiz); con el lector
    # nuevo la salida ya no se resuelve (no reservada) y la niega la puerta de
    # salida como NO verificable (BUILD-031), antes de llegar al de valores.
    mc.check('C (control): $(ProjectDir)\\salida en un valor del cuerpo se niega '
             '(BUILD-050 lee fuera, o BUILD-031 salida no verificable)',
             mc.rechazado(r) and (mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT')
                                  or mc.es(r, 'SR_BUILD_OUTPUT_UNRESOLVED_FMT')),
             j.get('firstError') or r[:400])

    # --- D: $(MSBuildThisFileDirectory) en un .targets importado de otra carpeta ---
    # msbuild lo evalua con la carpeta del FICHERO importado (J\o), asi
    # J\o\..\..\fuera118 = X:\fuera118, fuera de la jaula. El escaner lo hacia
    # desde la carpeta del PROYECTO (J\a\b -> J\fuera118, dentro) y aprobaba.
    d, p = proyecto(os.path.join('a', 'b'), 'PD')
    os.makedirs(os.path.join(J, 'o'))
    with open(os.path.join(J, 'o', 'o.targets'), 'w', newline='') as f:
        f.write(NS + '<PropertyGroup><DCC_UnitSearchPath>$(MSBuildThisFileDirectory)..\\..\\fuera118;'
                '$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup></Project>')
    os.makedirs(os.path.join(X, 'fuera118'))
    with open(os.path.join(X, 'fuera118', 'U118.pas'), 'w', newline='') as f:
        f.write('unit U118;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
    t = lee(p)
    i = t.index('<PropertyGroup')
    t = t[:i] + '<Import Project="..\\..\\o\\o.targets"/>\r\n    ' + t[i:]
    escribe(p, t)
    dpr = p[:-6] + '.dpr'
    tdpr = lee(dpr)
    assert 'System.SysUtils' in tdpr, tdpr[:300]
    escribe(dpr, tdpr.replace('System.SysUtils', 'System.SysUtils, U118', 1))
    r, j = build(p)
    mc.check('D: $(MSBuildThisFileDirectory) se resuelve POR FICHERO; el search path '
             'de fuera se niega BUILD-050 (rojo contra prod, que compilaba leyendo fuera)',
             mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT'),
             j.get('firstError') or r[:400])

    # --- E: lo mismo que D pero en un DCC_*Output (lo que el build ESCRIBE): la
    # salida caeria FUERA de la jaula. ExpandOutputMacros recorre la cadena sin
    # saber de que documento sale cada salida, asi que no resuelve
    # $(MSBuildThisFileDirectory) (lo deja no verificable, como antes de V118);
    # el gate de valores, por documento, tambien lo niega (segunda barrera).
    # Negado antes (BUILD-050, el gate de valores) y con el fix (BUILD-029/031, la
    # puerta de salidas): control de que la salida no escapa por este camino.
    d, p = proyecto(os.path.join('c', 'e'), 'PE')
    os.makedirs(os.path.join(J, 'o2'))
    with open(os.path.join(J, 'o2', 'o2.targets'), 'w', newline='') as f:
        f.write(NS + '<PropertyGroup>'
                '<DCC_ExeOutput>$(MSBuildThisFileDirectory)..\\..\\fuera118b</DCC_ExeOutput>'
                '<DCC_DcuOutput>$(MSBuildThisFileDirectory)..\\..\\fuera118b</DCC_DcuOutput>'
                '</PropertyGroup></Project>')
    t = lee(p)
    i = t.index('<PropertyGroup')
    t = t[:i] + '<Import Project="..\\..\\o2\\o2.targets"/>\r\n    ' + t[i:]
    escribe(p, t)
    r, j = build(p)
    mc.check('E: un DCC_*Output con $(MSBuildThisFileDirectory) de un .targets de otra carpeta '
             'no escapa de la jaula (salida fuera, negada: BUILD-050 el gate de valores, o '
             'BUILD-029/031 la puerta de salidas)',
             mc.rechazado(r) and (mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT')
                                  or mc.es(r, 'SR_BUILD_OUTPUT_DENIED_FMT')
                                  or mc.es(r, 'SR_BUILD_OUTPUT_UNRESOLVED_FMT')),
             j.get('firstError') or r[:400])
finally:
    S.cierra()
    subprocess.run(['subst', L + ':', '/d'], capture_output=True)
    mc.borra(BASE)

mc.fin('V118 build macros battery')
