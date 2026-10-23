"""1.20.1 - the project XML family on one parse (Lsp.Dproj): what an agent
sees change, one check per line of the CHANGELOG. Each F1..F7 is RED
against 7a3733d (the binary before the family moved onto the core: run this
battery with that exe as argument) and green now; F8 guards the hole the
review of the diff found in the new core before any commit.

  F1  add-platform finds a platform written in single quotes: it flips it,
      it does not add a second one
  F2  a platform inside a comment is not declared: remove-platform says so
      and writes nothing
  F3  set-version changes FileVersion only as a key of VerInfo_Keys, not the
      same text inside a build event
  F4  add-deployfile adds the manifest's <Import> to a .dproj whose
      CodeGear.Delphi.Targets import has its Condition first
  F5  remove-unit takes out a DCCReference written in single quotes
  F6  moving a folder re-points a path in a single-quoted attribute, and not
      one inside a comment
  F7  add-project appends to the group's aggregate target written "build",
      not a second "Build"
  F8  a build event behind an unclosed tag inside a comment is still seen:
      the build skips it (it does not run)

Usage:  python tests/test_xml_familia_1201.py [path-to-DelphiLspMcp.exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('xmlfam1201')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='xmlfam', t=600)


def proyecto(nombre, dir_=None):
    d = dir_ or os.path.join(BASE, nombre)
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    check('%s creado' % nombre, mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    return os.path.join(d, nombre + '.dproj')


def reescribe(fichero, cambio):
    b = open(fichero, 'rb').read()
    bom = b.startswith(b'\xef\xbb\xbf')
    x = b.decode('utf-8-sig')
    y = cambio(x)
    assert y != x, 'el cambio no cambio nada: la fixture no mide'
    open(fichero, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + y.encode('utf-8'))
    return y


def config(dproj, **kw):
    return S.call('delphi_config', dict(kw, project=dproj))


# ---- F1 una plataforma en comillas simples ----
P1 = proyecto('Fam1')
reescribe(P1, lambda x: re.sub(r'<Platform value="Win64">\w+</Platform>',
                               "<Platform value='Win64'>False</Platform>", x))
r = config(P1, command='add-platform', platform='Win64')
x = mc.lee(P1)
check('F1 add-platform la encuentra y la habilita (CFG: ya estaba declarada)',
      mc.abre(r, 'SN_CFG_HABILITADA_PLATAFORMA_ESTABA_DECLARAD_FMT'), r[:300])
check('F1 ...en su sitio: UNA sola Win64 en el bloque, y activa',
      len(re.findall(r'<Platform value=.Win64.>', x)) == 1 and "<Platform value='Win64'>True</Platform>" in x,
      re.findall(r'<Platform value=.Win64.>\w*</Platform>', x))

# ---- F2 una plataforma dentro de un comentario ----
P2 = proyecto('Fam2')
x = reescribe(P2, lambda x: x.replace('<Platforms>',
                                      '<Platforms>\r\n            <!-- <Platform value="OSX64">True</Platform> -->', 1))
r = config(P2, command='remove-platform', platform='OSX64')
check('F2 remove-platform: la comentada no esta declarada',
      mc.abre(r, 'SN_CFG_PLATAFORMA_ESTA_DECLARADA_PROYECTO_FMT'), r[:300])
check('F2 ...y no se escribe nada (el comentario sigue diciendo True)', mc.lee(P2) == x, '')

# ---- F3 set-version y un evento que dice FileVersion= ----
P3 = proyecto('Fam3')
BLOQUE = ('<VerInfo_MajorVer>1</VerInfo_MajorVer>\r\n'
          '        <VerInfo_Keys>FileVersion=1.0.0.0;ProductVersion=1.0.0.0</VerInfo_Keys>\r\n'
          '        <PostBuildEvent>echo FileVersion=1.0.0.0</PostBuildEvent>\r\n        ')
reescribe(P3, lambda x: re.sub(r"(<PropertyGroup Condition=\"'\$\(Base\)'!=''\">\s*)", r'\g<1>' + BLOQUE.replace('\\', '\\\\'),
                               x, count=1))
r = config(P3, command='set-version', version='2.3.4.5')
x = mc.lee(P3)
check('F3 set-version contesta', mc.abre(r, 'SN_CONFIG_VERSION_OK_FMT'), r[:300])
check('F3 la clave de VerInfo_Keys cambia',
      'FileVersion=2.3.4.5;ProductVersion=2.3.4.5</VerInfo_Keys>' in x, re.findall(r'<VerInfo_Keys>.*?</VerInfo_Keys>', x))
check('F3 ...y el evento de build NO', '<PostBuildEvent>echo FileVersion=1.0.0.0</PostBuildEvent>' in x,
      re.findall(r'<PostBuildEvent>.*?</PostBuildEvent>', x))

# ---- F4 el ancla del Deploy con la Condition delante ----
P4 = proyecto('Fam4')


def ancla_condicion_delante(x):
    x = re.sub(r'[ \t]*<Import[^>]*\.deployproj[^>]*/>\r?\n', '', x)
    return re.sub(r'<Import Project="(\$\(BDS\)\\Bin\\CodeGear\.Delphi\.Targets)" Condition="([^"]*)"\s*/>',
                  r'<Import Condition="\2" Project="\1"/>', x)


x = reescribe(P4, ancla_condicion_delante)
check('F4 la fixture: el ancla con la Condition delante y sin el Import del manifiesto',
      re.search(r'<Import Condition="[^"]*" Project="\$\(BDS\)\\Bin\\CodeGear\.Delphi\.Targets"', x) is not None
      and '.deployproj' not in x.lower(), '')
DEP = os.path.join(os.path.dirname(P4), 'Fam4.deployproj')
if os.path.exists(DEP):
    os.remove(DEP)
DATO = os.path.join(os.path.dirname(P4), 'dato.txt')
open(DATO, 'w').write('x')
# la plataforma, declarada como el IDE: no se escribe para una que el proyecto no tiene (A14 de la 1.23)
config(P4, command='add-platform', platform='Linux64')
r = config(P4, command='add-deployfile', platform='Linux64', path=DATO)
x = mc.lee(P4)
check('F4 add-deployfile contesta', mc.abre(r, 'SN_CONFIG_DEPLOY_ADDED_FMT'), r[:300])
check('F4 ...y el .dproj importa ya el manifiesto (sin el, el Deploy cae en MSB4057)',
      re.search(r'<Import Project="\$\(MSBuildProjectName\)\.deployproj"', x) is not None,
      re.findall(r'<Import[^>]*>', x))

# ---- F5 un DCCReference en comillas simples ----
P5 = proyecto('Fam5')
U5 = os.path.join(os.path.dirname(P5), 'UFam5.pas')
open(U5, 'w', newline='').write('unit UFam5;\r\n\r\ninterface\r\n\r\nimplementation\r\n\r\nend.\r\n')
r = config(P5, command='add-unit', path=U5)
reescribe(P5, lambda x: x.replace('<DCCReference Include="UFam5.pas"/>', "<DCCReference Include='UFam5.pas'/>"))
r = config(P5, command='remove-unit', path=U5)
x = mc.lee(P5)
check('F5 remove-unit contesta', 'UFam5' in r and not mc.es(r, 'SN_UNIT_ABSENT_FMT'), r[:300])
check('F5 ...y el DCCReference en comillas simples se va del .dproj', 'UFam5' not in x,
      re.findall(r'<DCCReference[^>]*>', x))

# ---- F6 la mudanza: un atributo en comillas simples y un comentario ----
D6 = os.path.join(BASE, 'f6')
P6 = proyecto('Fam6', os.path.join(D6, 'P'))
os.makedirs(os.path.join(D6, 'shared'))
open(os.path.join(D6, 'shared', 'R.rc'), 'w').write('// rc\r\n')
reescribe(P6, lambda x: x.replace('    <ItemGroup>',
                                  "    <!-- <PropertyGroup><DCC_IncludePath>..\\shared</DCC_IncludePath></PropertyGroup> -->\r\n"
                                  "    <ItemGroup>\r\n        <RcCompile Include='..\\shared\\R.rc'><Form>R.res</Form></RcCompile>", 1))
r = S.call('delphi_move', {'path': os.path.join(D6, 'P'), 'dest': os.path.join(D6, 'sub', 'P')})
P6N = os.path.join(D6, 'sub', 'P', 'Fam6.dproj')
x = mc.lee(P6N) if os.path.isfile(P6N) else ''
check('F6 la carpeta se mueve', os.path.isfile(P6N), r[:300])
check("F6 la ruta del atributo en comillas simples se re-apunta (..\\..\\shared\\R.rc)",
      "<RcCompile Include='..\\..\\shared\\R.rc'>" in x, re.findall(r'<RcCompile[^>]*>', x))
check('F6 ...y la del comentario NO se toca', '<DCC_IncludePath>..\\shared</DCC_IncludePath></PropertyGroup> -->' in x,
      re.findall(r'<!--.*?-->', x))

# ---- F7 el agregado del grupo escrito "build" ----
D7 = os.path.join(BASE, 'f7')
A7 = proyecto('Fam7a', os.path.join(D7, 'a'))
B7 = proyecto('Fam7b', os.path.join(D7, 'b'))
G7 = os.path.join(D7, 'Grupo.groupproj')
open(G7, 'w', newline='').write(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\r\n'
    '    <ItemGroup>\r\n'
    '        <Projects Include="a\\Fam7a.dproj">\r\n            <Dependencies/>\r\n        </Projects>\r\n'
    '    </ItemGroup>\r\n'
    '    <Target Name="Fam7a">\r\n        <MSBuild Projects="a\\Fam7a.dproj"/>\r\n    </Target>\r\n'
    '    <Target Name="build">\r\n        <CallTarget Targets="Fam7a"/>\r\n    </Target>\r\n'
    '</Project>\r\n')
r = config(G7, command='add-project', path=B7)
x = mc.lee(G7)
builds = re.findall(r'<Target Name="build"', x, re.I)
check('F7 add-project contesta', mc.abre(r, 'SN_GRUPO_ANADIDO_FMT'), r[:300])
check('F7 ...un solo agregado build (msbuild no distingue mayusculas), con los dos',
      len(builds) == 1 and '<CallTarget Targets="Fam7a;Fam7b"/>' in x, (builds, re.findall(r'<CallTarget[^>]*>', x)))

# ---- F8 un evento detras de una etiqueta sin cerrar en un comentario ----
P8 = proyecto('Fam8')
MARCA = os.path.join(os.path.dirname(P8), 'marca.txt')
reescribe(P8, lambda x: x.replace('    <ItemGroup>',
                                  '    <!-- <PostBuildEvent> -->\r\n'
                                  '    <PropertyGroup><PostBuildEvent>copy /y "$(MSBuildProjectFullPath)" '
                                  '"$(MSBuildProjectDirectory)\\marca.txt"</PostBuildEvent></PropertyGroup>\r\n'
                                  '    <ItemGroup>', 1))
out = S.call('delphi_build', {'project': P8, 'platform': 'Win64', 'config': 'Debug'}, 600)
j = mc.como_json(out) or {}
check('F8 compila', j.get('success') is True, out[:300])
check('F8 el evento escondido se ve: el build lo SALTA y lo dice', j.get('buildEventsSkipped') not in (None, False, []),
      out[:400])
check('F8 ...y no se ejecuta (sin marca)', not os.path.exists(MARCA), MARCA)

S.cierra()
mc.borra(BASE)
mc.fin('xml-familia-1201 battery')
