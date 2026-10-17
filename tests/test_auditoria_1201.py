"""1.20.1 - dos huecos de la auditoria de Hermes (D4 y D8), medidos el
17-oct-2026 en el sandbox.

D4: delphi_config set-output solo reescribia la PRIMERA <DCC_ExeOutput> del
.dproj. Un proyecto que fija su propia carpeta en la config Debug (5 de los
192 .dproj de los Samples de la 37.0 la fijan en mas de un grupo) se quedaba
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
GRUPO_DEBUG = ('    <PropertyGroup Condition="\'$(Cfg_2)\'!=\'\'">\r\n'
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
    return x.replace('    <ItemGroup>', GRUPO_DEBUG + '    <ItemGroup>', 1)


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
      SALIDA_DEBUG in r and "'$(Cfg_2)'!=''" in r, r[:500])
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
                               con_grupo_debug(x).replace(GRUPO_DEBUG, '@@'), flags=re.I)
          .replace('@@', GRUPO_DEBUG))
x0 = mc.lee(P2)
check('D4b la unica <DCC_ExeOutput> es la de Debug, y no hay <DCC_DcuOutput>',
      EXES.findall(x0) == [SALIDA_DEBUG] and 'DCC_DcuOutput' not in x0, EXES.findall(x0))
r = set_output(P2)
x = mc.lee(P2)
base = GRUPO_BASE.search(x)
cuerpo = base.group(1) if base else ''
check('D4b la base las recibe, la Exe delante de la Dcu (como antes)',
      0 <= cuerpo.find('<DCC_ExeOutput>' + COMPILED) < cuerpo.find('<DCC_DcuOutput>'), cuerpo[:300])
check('D4b ...y la de Debug se reescribe: dos, las dos Compiled',
      EXES.findall(x) == [COMPILED, COMPILED], EXES.findall(x))
check('D4b la respuesta: la Exe estaba solo en Debug, la Dcu sin definir',
      SALIDA_DEBUG in r and "'$(Cfg_2)'!=''" in r and '(not set)' in r, r[:500])

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

mc.fin('auditoria 1.20.1 (D4 set-output, D8 removeuses en .dpr)')
