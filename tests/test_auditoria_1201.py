"""1.20.1 - dos huecos de la auditoria de Hermes (D4 y D8), medidos el
17-oct-2026 en el sandbox.

D4: delphi_config set-output solo reescribia la PRIMERA <DCC_ExeOutput> del
.dproj. Un proyecto que fija su propia carpeta en la config Debug (de los 296
.dproj de los Samples de la 37.0, 192 la fijan y 5 en mas de un grupo) se quedaba
con ella: el build de Debug salia en SalidaDebug mientras la respuesta decia
Compiled. Ahora cada grupo que la fija se reescribe, la respuesta dice que
tenia cada uno, y si la base no la lleva se le escribe.

D8: adduses metia una unidad de biblioteca en el .dpr (System.JSON) y nada la
sacaba: removeuses contestaba USES-014 y remitia a remove-unit, que pide un
.pas (GUARD-021). Ahora removeuses en un .dpr quita unidades de BIBLIOTECA, el
espejo de adduses; una del proyecto (su .pas en el arbol, o una entrada con
su in '...' aunque el .pas viva fuera) sigue yendo por remove-unit (USES-025,
nada escrito).

Usage:  python tests/test_auditoria_1201.py [path-to-DelphiLspMcp.exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('aud1201')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='aud1201', t=600)

COMPILED = r'.\Compiled\$(Platform)\$(Config)'
SALIDA_DEBUG = r'.\SalidaDebug\$(Platform)'


def clave_debug(x):
    """La clave (Cfg_N) con la que el .dproj nombra Debug (mc.clave_de_config)."""
    return mc.clave_de_config(x, 'Debug')


def grupo_debug(x):
    return ('    <PropertyGroup Condition="\'$(%s)\'!=\'\'">\r\n' % clave_debug(x) +
            '        <DCC_ExeOutput>' + SALIDA_DEBUG + '</DCC_ExeOutput>\r\n'
            '    </PropertyGroup>\r\n')

EXES = re.compile(r'<DCC_ExeOutput\s*>(.*?)</DCC_ExeOutput\s*>', re.I | re.S)
GRUPO_BASE = re.compile(r'<PropertyGroup Condition="\'\$\(Base\)\'!=\'\'">(.*?)</PropertyGroup>', re.S)


def proyecto(nombre):
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre,
                                 'dir': os.path.join(BASE, nombre)})
    check('%s creado' % nombre, mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    return os.path.join(BASE, nombre, nombre + '.dproj')


def reescribe(dproj, cambio):
    b = open(dproj, 'rb').read()
    bom = b.startswith(b'\xef\xbb\xbf')
    x = b.decode('utf-8-sig')
    y = cambio(x)
    open(dproj, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + y.encode('utf-8'))
    return x, y


def con_grupo_debug(x):
    return x.replace('    <ItemGroup>', grupo_debug(x) + '    <ItemGroup>', 1)


def set_output(dproj, carpeta='Compiled'):
    return S.call('delphi_config', {'project': dproj, 'command': 'set-output',
                                    'output': carpeta})


# ---- D4 a. la config Debug fija su propia carpeta ----
P1 = proyecto('SalD4')
antes, despues = reescribe(P1, con_grupo_debug)
check('D4a el .dproj lleva DOS <DCC_ExeOutput> (sin esto la roja no mide el hueco)',
      len(EXES.findall(despues)) == 2, EXES.findall(despues))
r = set_output(P1)
check('D4a set-output contesta CFG-081', mc.abre(r, 'SN_CFG_SALIDA_BINARIOS_FIJADA_AHORA_FMT'), r[:300])
x = mc.lee(P1)
check('D4a TODAS las <DCC_ExeOutput> dicen Compiled, la de Debug tambien',
      EXES.findall(x) == [COMPILED, COMPILED], EXES.findall(x))
check('D4a la respuesta dice lo que tenia la de Debug y su grupo',
      SALIDA_DEBUG in r and "'$(%s)'!=''" % clave_debug(antes) in r, r[:500])
ok, err = mc.build_ok(S.call, P1)
check('D4a el build de Debug compila', ok, err)
DIR1 = os.path.dirname(P1)
check('D4a ...y el binario sale en Compiled\\Win64\\Debug, no en SalidaDebug',
      os.path.isfile(os.path.join(DIR1, 'Compiled', 'Win64', 'Debug', 'SalD4.exe'))
      and not os.path.exists(os.path.join(DIR1, 'SalidaDebug')),
      sorted(os.listdir(DIR1)))

# ---- D4 b. la base no la lleva: solo la config Debug ----
P2 = proyecto('SalD4Base')
reescribe(P2, lambda x: re.sub(r'\s*<DCC_(Exe|Dcu)Output>[^<]*</DCC_(Exe|Dcu)Output>', '',
                               con_grupo_debug(x).replace(grupo_debug(x), '@@'), flags=re.I)
          .replace('@@', grupo_debug(x)))
x0 = mc.lee(P2)
check('D4b la unica <DCC_ExeOutput> es la de Debug, y no hay <DCC_DcuOutput>',
      EXES.findall(x0) == [SALIDA_DEBUG] and 'DCC_DcuOutput' not in x0, EXES.findall(x0))
r = set_output(P2)
x = mc.lee(P2)
base = GRUPO_BASE.search(x)
cuerpo = base.group(1) if base else ''
# (1.22.1) una propiedad nueva entra al FINAL de su grupo, como la pone el IDE:
# set-output crea la Dcu y luego la Exe, el orden de la plantilla del IDE
check('D4b la base las recibe al final de su grupo, la Dcu y detras la Exe (como el IDE)',
      re.search(r'<DCC_DcuOutput>[^<]*</DCC_DcuOutput>\s*<DCC_ExeOutput>' + re.escape(COMPILED) +
                r'</DCC_ExeOutput>\s*$', cuerpo) is not None, cuerpo[-300:])
check('D4b ...y la de Debug se reescribe: dos, las dos Compiled',
      EXES.findall(x) == [COMPILED, COMPILED], EXES.findall(x))
check('D4b la respuesta: la Exe estaba solo en Debug, la Dcu sin definir',
      SALIDA_DEBUG in r and "'$(%s)'!=''" % clave_debug(x0) in r and '(not set)' in r, r[:500])

# ---- D4 c. sin grupo base: CFG-087 y nada escrito ----
P3 = proyecto('SalD4SinBase')
reescribe(P3, lambda x: con_grupo_debug(GRUPO_BASE.sub('', x, count=1)))
b3 = open(P3, 'rb').read()
check('D4c el .dproj ya no tiene grupo base (sin esto la roja no mide el hueco)',
      not GRUPO_BASE.search(b3.decode('utf-8-sig')), '')
r = set_output(P3)
check('D4c sin grupo base: CFG-087', mc.rechazado(r) and mc.es(r, 'SR_CFG_NO_ENCUENTRO_PROPERTYGROUP_BASE'), r[:300])
check('D4c ...y el .dproj sigue byte a byte', open(P3, 'rb').read() == b3, '')

# ---- D4 d. control: el caso de siempre (una, en la base) contesta como antes ----
P4 = proyecto('SalD4Una')
r = set_output(P4)
check('D4d una sola, en la base: "before" es su valor, sin grupo',
      '(before: ' + r'.\$(Platform)\$(Config)' + ')' in r and 'in the group' not in r, r[:400])

# ---- D8 a. adduses de biblioteca en el .dpr, y removeuses la saca ----
P5 = proyecto('UsesD8')
DPR5 = P5[:-len('.dproj')] + '.dpr'
r = S.call('delphi_edit', {'path': DPR5, 'adduses': 'System.JSON'})
check('D8a adduses System.JSON en el .dpr: USES-013', mc.abre(r, 'SN_ADDUSES_ADDED_FMT'), r[:300])
check('D8a ...y esta en el .dpr', 'System.JSON' in mc.lee(DPR5), '')
r = S.call('delphi_edit', {'path': DPR5, 'removeuses': 'System.JSON'})
check('D8a removeuses System.JSON en el .dpr: USES-020', mc.abre(r, 'SN_REMOVEUSES_REMOVED_FMT'), r[:300])
check('D8a ...y ya no esta', 'System.JSON' not in mc.lee(DPR5), mc.lee(DPR5)[:400])
ok, err = mc.build_ok(S.call, P5)
check('D8a el programa sigue compilando', ok, err)
r = S.call('delphi_edit', {'path': DPR5, 'removeuses': 'System.JSON'})
check('D8a otra vez: USES-017, no esta', mc.abre(r, 'SN_REMOVEUSES_ABSENT_FMT'), r[:300])

# ---- D8 b. una unidad del PROYECTO va por remove-unit ----
DIR5 = os.path.dirname(P5)
PAS = os.path.join(DIR5, 'UDatosD8.pas')
open(PAS, 'w', newline='\r\n').write('unit UDatosD8;\n\ninterface\n\nimplementation\n\nend.\n')
r = S.call('delphi_config', {'project': P5, 'command': 'add-unit', 'path': PAS})
check('D8b add-unit UDatosD8', not mc.rechazado(r) and 'UDatosD8' in mc.lee(DPR5), r[:300])
d5 = open(DPR5, 'rb').read()
r = S.call('delphi_edit', {'path': DPR5, 'removeuses': 'UDatosD8'})
check('D8b removeuses de una unidad del proyecto: USES-025',
      mc.rechazado(r) and mc.es(r, 'SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT'), r[:300])
check('D8b ...y el .dpr sigue byte a byte', open(DPR5, 'rb').read() == d5, '')
# en el uses SIN su in '...' y con su .pas en el arbol (add-unit siempre
# escribe el in, asi que esta la mide el otro juez: el del arbol)
SUB = os.path.join(DIR5, 'Dominio')
os.makedirs(SUB, exist_ok=True)
open(os.path.join(SUB, 'USinInD8.pas'), 'w', newline='\r\n').write(
    'unit USinInD8;\n\ninterface\n\nimplementation\n\nend.\n')
reescribe(DPR5, lambda x: x.replace('  System.SysUtils', '  System.SysUtils,' +
                                   ('\r\n' if '\r\n' in x else '\n') + '  USinInD8', 1))
d5 = open(DPR5, 'rb').read()
check('D8b el .dpr lista USinInD8 sin in (sin esto la roja no mide el juez)',
      re.search(r'USinInD8\s*[,;]', d5.decode('utf-8-sig')) is not None, d5[:300])
r = S.call('delphi_edit', {'path': DPR5, 'removeuses': 'USinInD8'})
check('D8b sin in pero con su .pas en el arbol: USES-025 con su ruta',
      mc.rechazado(r) and mc.es(r, 'SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT')
      and r'Dominio\USinInD8.pas' in r, r[:300])
check('D8b ...y el .dpr sigue byte a byte', open(DPR5, 'rb').read() == d5, '')
# su .pas en la carpeta pero NO en el uses: no esta, no es cosa de remove-unit
open(os.path.join(DIR5, 'USueltaD8.pas'), 'w', newline='\r\n').write(
    'unit USueltaD8;\n\ninterface\n\nimplementation\n\nend.\n')
r = S.call('delphi_edit', {'path': DPR5, 'removeuses': 'USueltaD8'})
check('D8b un .pas de la carpeta que no esta en el uses: USES-017, no USES-025',
      mc.abre(r, 'SN_REMOVEUSES_ABSENT_FMT') and not mc.es(r, 'SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT'), r[:300])

# ---- D8 c. con su in '...' y el .pas FUERA del arbol del .dpr: tambien ----
COMUN = os.path.join(BASE, 'ComunD8')
os.makedirs(COMUN, exist_ok=True)
PAS2 = os.path.join(COMUN, 'UComunD8.pas')
open(PAS2, 'w', newline='\r\n').write('unit UComunD8;\n\ninterface\n\nimplementation\n\nend.\n')
r = S.call('delphi_config', {'project': P5, 'command': 'add-unit', 'path': PAS2})
check('D8c add-unit de una unidad de otra carpeta: entra con su in',
      re.search(r"UComunD8\s+in\s+'\.\.\\ComunD8\\UComunD8\.pas'", mc.lee(DPR5)) is not None,
      r[:300] + ' | ' + mc.lee(DPR5)[:400])
d5 = open(DPR5, 'rb').read()
r = S.call('delphi_edit', {'path': DPR5, 'removeuses': 'UComunD8'})
check('D8c removeuses de una entrada con in de fuera del arbol: USES-025 con su ruta',
      mc.rechazado(r) and mc.es(r, 'SR_REMOVEUSES_UNIDAD_DEL_PROYECTO_FMT')
      and r'..\ComunD8\UComunD8.pas' in r, r[:300])
check('D8c ...y el .dpr sigue byte a byte', open(DPR5, 'rb').read() == d5, '')

# ---- D8 d. un .dpk sigue siendo cosa de remove-unit ----
DPK = os.path.join(BASE, 'PaqD8.dpk')
open(DPK, 'w', newline='\r\n').write('package PaqD8;\n\nrequires\n  rtl;\n\nend.\n')
r = S.call('delphi_edit', {'path': DPK, 'removeuses': 'rtl'})
check('D8d removeuses en un .dpk: USES-014', mc.rechazado(r) and mc.es(r, 'SR_REMOVEUSES_NOT_PAS_FMT'), r[:300])

# ---- D4 e. el grupo de una plataforma escrito a mano (blancos): es el mismo grupo ----
# El buscador de grupos de delphi_config comparaba la Condition letra a letra:
# no lo encontraba, creaba OTRO '$(Base_Linux64)'!='' y la ruta caia en el nuevo.
P6 = proyecto('SpD4e')
GRUPO_A_MANO = ("    <PropertyGroup Condition=\"'$(Base_Linux64)' != ''\">\r\n"
                '        <DCC_UnitSearchPath>uno;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>\r\n'
                '    </PropertyGroup>\r\n')
reescribe(P6, lambda x: x.replace('    <ItemGroup>', GRUPO_A_MANO + '    <ItemGroup>', 1))
DIR6 = os.path.dirname(P6)
# la plataforma, declarada como el IDE: no se escribe para una que el proyecto no tiene (A14 de la 1.23)
S.call('delphi_config', {'project': P6, 'command': 'add-platform', 'platform': 'Linux64'})
r = S.call('delphi_config', {'project': P6, 'command': 'add-searchpath', 'platform': 'Linux64', 'path': DIR6})
x = mc.lee(P6)
VALORES_LINUX = re.compile(r"<PropertyGroup Condition=\"'\$\(Base_Linux64\)'\s*!=\s*''\">(.*?)</PropertyGroup>", re.S)
grupos = VALORES_LINUX.findall(x)
check('D4e add-searchpath reconoce el grupo escrito a mano: UN grupo de valores Linux64',
      mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and len(grupos) == 1, r[:200] + ' | grupos=%d' % len(grupos))
check('D4e ...y la ruta entra en SU DCC_UnitSearchPath, junto a la que tenia',
      len(grupos) == 1 and 'SpD4e;uno;$(DCC_UnitSearchPath)' in grupos[0], grupos)

# ---- D3 a. dos PlatformSDK en el grupo de la plataforma: se quitan las dos ----
# set-sdk y set-profile eran gemelas que solo quitaban la PRIMERA: con dos, la
# otra seguia en el grupo y msbuild se quedaba con ella.
P7 = proyecto('SdkD3')
DOS_SDK = ("    <PropertyGroup Condition=\"'$(Base_Linux64)'!=''\">\r\n"
           '        <PlatformSDK>viejo1.sdk</PlatformSDK>\r\n'
           '        <PlatformSDK>viejo2.sdk</PlatformSDK>\r\n'
           '    </PropertyGroup>\r\n')
reescribe(P7, lambda x: x.replace('    <ItemGroup>', DOS_SDK + '    <ItemGroup>', 1))
r = S.call('delphi_config', {'project': P7, 'command': 'set-sdk', 'platform': 'Linux64', 'sdk': 'none'})
x = mc.lee(P7)
check('D3a set-sdk none con dos PlatformSDK: CFG-011 y "before" es la que valia (la ultima)',
      mc.abre(r, 'SN_CONFIG_SDK_QUITADO_FMT') and 'viejo2.sdk' in r, r[:300])
check('D3a ...y no queda NINGUNA en el .dproj', 'PlatformSDK' not in x, x[x.find('Base_Linux64'):][:300])

# ---- D4 f. el .deployproj por el mismo analisis ----
# La vista, remove-deployfile y add-deployfile leian cada DeployFile con una
# regex que pedia el Include PRIMERO y entre comillas dobles, y su plataforma
# por "el ultimo <itemgroup antes": una entrada con la Condition delante no
# existia, y un <DeployFile .../> vacio se comia la entrada siguiente.
P8 = proyecto('DepD4f')
DEP8 = P8[:-len('.dproj')] + '.deployproj'
DIR8 = os.path.dirname(P8)
open(DEP8, 'w', encoding='utf-8', newline='\r\n').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
    '    <ItemGroup Condition="\'$(Platform)\'==\'Linux64\'">\n'
    '        <DeployFile Condition="\'$(Config)\'==\'Debug\'" Include="libuno.so">\n'
    '            <RemoteDir>P\\</RemoteDir>\n'
    '            <DeployClass>File</DeployClass>\n'
    '        </DeployFile>\n'
    '        <DeployFile Include="vacio.dat"/>\n'
    '        <DeployFile Include="libdos.so" Condition="\'$(Config)\'==\'Debug\'">\n'
    '            <RemoteDir>Q\\</RemoteDir>\n'
    '            <DeployClass>File</DeployClass>\n'
    '        </DeployFile>\n'
    '    </ItemGroup>\n'
    '    <ItemGroup Condition="\'$(Platform)\'==\'OSX64\' And \'$(Config)\'==\'Release\'">\n'
    '        <DeployFile Include="OSX64\\Release\\DepD4f">\n'
    '            <RemoteDir>DepD4f\\</RemoteDir>\n'
    '            <DeployClass>File</DeployClass>\n'
    '        </DeployFile>\n'
    '    </ItemGroup>\n'
    '    <ItemGroup Condition="\'$(Platform)\'==\'OSX32\'">\n'
    '        <DeployFile Condition="\'$(Config)\'==\'Debug\'" Include="OSX32\\Debug\\DepD4f.icns">\n'
    '            <RemoteDir>DepD4f.app\\Contents\\Resources\\</RemoteDir>\n'
    '            <DeployClass>File</DeployClass>\n'
    '        </DeployFile>\n'
    '    </ItemGroup>\n'
    '</Project>\n')
r = S.call('delphi_config', {'project': P8, 'command': 'view', 'section': 'deploy'})
# (1.22.2: la vista lee el .dproj, como el IDE; lo que solo esta en el .deployproj, que el
# proyecto no lista, va aparte - estas, escritas a mano, son todas de ahi; y de ahi solo los
# ficheros anadidos, clase File: la vacia no tiene clase y no sale, pero libdos, detras, si)
vista = mc.como_json(r).get('deployFilesOnlyInManifest') or {}
check('D4f la vista ve las de Linux64: la de la Condition delante, y la vacia no se come la siguiente',
      sorted(vista.get('Linux64', [])) == sorted(['libuno.so -> P\\', 'libdos.so -> Q\\']),
      vista)
check('D4f ...y el grupo con la forma del manifiesto del servidor (plataforma And config) es de OSX64',
      vista.get('OSX64') == ['OSX64\\Release\\DepD4f -> DepD4f\\'], vista)
# como RegExpressionDemo.deployproj de los Samples (escrito por el IDE): OSX32,
# que ya no es una plataforma conocida, y la Condition delante del Include
check('D4f ...y el de OSX32, una plataforma que ya no esta entre las conocidas, con lo suyo',
      vista.get('OSX32') == ['OSX32\\Debug\\DepD4f.icns -> DepD4f.app\\Contents\\Resources\\'], vista)
r = S.call('delphi_config', {'project': P8, 'command': 'remove-deployfile', 'platform': 'Linux64',
                             'path': os.path.join(DIR8, 'vacio.dat')})
x = mc.lee(DEP8)
check('D4f remove-deployfile de la vacia: se va SOLO ella',
      mc.abre(r, 'SN_CONFIG_DEPLOY_REMOVED_FMT') and 'vacio.dat' not in x and 'libdos.so' in x
      and 'libuno.so' in x, r[:200] + ' | ' + x[:600])
r = S.call('delphi_config', {'project': P8, 'command': 'remove-deployfile', 'platform': 'Linux64',
                             'path': os.path.join(DIR8, 'libuno.so')})
x = mc.lee(DEP8)
check('D4f remove-deployfile encuentra la de la Condition delante',
      mc.abre(r, 'SN_CONFIG_DEPLOY_REMOVED_FMT') and 'libuno.so' not in x, r[:200])
r = S.call('delphi_config', {'project': P8, 'command': 'remove-deployfile', 'platform': 'Linux64',
                             'path': os.path.join(DIR8, 'libdos.so')})
x = mc.lee(DEP8)
check('D4f quitada la ultima de Linux64, su ItemGroup queda vacio como lo escribe el IDE; el de OSX64 se queda',
      mc.abre(r, 'SN_CONFIG_DEPLOY_REMOVED_FMT') and "<ItemGroup Condition=\"'$(Platform)'=='Linux64'\"/>" in x
      and x.count("'Linux64'") == 1 and 'OSX64\\Release\\DepD4f' in x, x)

# ---- D4 g. la Condition del ELEMENTO cuenta (5 Samples del IDE la escriben) ----
# <Profile Condition="'$(Platform)'=='Win32'"> en el grupo sin condicion: msbuild
# solo lo aplica en Win32. Medido con el juez (MSXML) el 17-oct: el lector que
# leia ya las etiquetas con atributos se lo daba a OSX64 e iOS.
P9 = proyecto('PerfilD4g')
reescribe(P9, lambda x: x.replace(
    '        <ProjectVersion>',
    '        <Profile Condition="\'$(Platform)\'==\'Win32\'">win_desktop</Profile>\r\n        <ProjectVersion>', 1))
r = S.call('delphi_config', {'project': P9, 'command': 'add-platform', 'platform': 'OSX64'})
check('D4g OSX64 declarada (la vista solo ensena las declaradas)', not mc.rechazado(r), r[:200])
r = S.call('delphi_config', {'project': P9, 'command': 'view', 'section': 'platforms'})
plats = {p.get('name'): p for p in (mc.como_json(r).get('platforms') or [])}
check('D4g el perfil con la condicion de Win32 NO es el de OSX64',
      'OSX64' in plats and plats['OSX64'].get('profile') == '' and plats['OSX64'].get('profileSource') == 'none',
      plats.get('OSX64'))

mc.fin('auditoria 1.20.1 (D4 set-output y el analisis del .dproj y .deployproj, D8 removeuses en .dpr, D3)')
