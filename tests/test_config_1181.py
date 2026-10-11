"""1.18.1 - el nombre de una configuracion llega a la linea de cmd.exe del
build por delphi_build Y por delphi_test.

4.8, revision de la jaula de la 1.18.1: la puerta universal juzgaba config
solo para delphi_build (BuildArgDenied); delphi_test compila por el mismo
RunMsBuild y su unico control era ConfigDesconocida, que con un .dproj sin
<BuildConfiguration> lo aceptaba todo, y con uno que DECLARA el nombre raro
tambien - y el valor iba sin comillas a /p:Config=. Ahora UNA regla del
nombre (Lsp.Dproj.NombreDeConfigNoValido) en la puerta, para las dos tools, y
en el fondo (ConfigDesconocida, por donde pasan las dos antes de la linea).

El valor de prueba es 'Debug;Release': un ';' dentro de /p: es OTRA propiedad
para msbuild y no ejecuta nada aunque el arreglo falte - la roja no corre
nada ajeno. La contraprueba: un nombre limpio con espacio sigue valiendo, y
ahora compila (sin comillas msbuild lo partia en dos argumentos).

Usage:  python tests/test_config_1181.py [path-to-DelphiLspMcp.exe]
"""
import os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('cfg1181')
EXE = mc.copia_exe(BASE)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_ALLOW_TESTS': '1'}),
             nombre='cfg', t=600)
MALA = 'Debug;Release'


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


# ---- 1. un .dproj que NO declara configuraciones: ConfigDesconocida lo
#         aceptaba todo ----
SIN = proyecto('SinCfgTest')
antes, despues = reescribe(SIN, lambda x: re.sub(
    r'\s*<BuildConfiguration\b.*?</BuildConfiguration>', '', x, flags=re.S))
check('el .dproj ya no declara configuraciones (sin esto la roja no mide el hueco)',
      '<BuildConfiguration' in antes and '<BuildConfiguration' not in despues, '')
r = S.call('delphi_test', {'command': 'run', 'project': SIN, 'config': MALA}, t=900)
check('C1 delphi_test config con ";" en un proyecto SIN configuraciones: BUILD-015, nada compilado',
      mc.rechazado(r) and mc.es(r, 'SR_BUILD_CONFIG_FMT'), r[:300])

# ---- 2. un .dproj que DECLARA ese nombre: HasConfig decia que si ----
CON = proyecto('RaroCfgTest')
reescribe(CON, lambda x: x.replace('<BuildConfiguration Include="Debug">',
                                   '<BuildConfiguration Include="%s">' % MALA, 1))
check('el .dproj declara la configuracion rara',
      ('<BuildConfiguration Include="%s">' % MALA) in open(CON, encoding='utf-8-sig').read(), '')
r = S.call('delphi_test', {'command': 'run', 'project': CON, 'config': MALA}, t=900)
check('C2 delphi_test config con ";" que el proyecto DECLARA: BUILD-015 igual',
      mc.rechazado(r) and mc.es(r, 'SR_BUILD_CONFIG_FMT'), r[:300])

# ---- 3. control: delphi_build ya pasaba por la puerta ----
r = S.call('delphi_build', {'project': CON, 'config': MALA}, t=900)
check('C3 control: delphi_build con la misma config, BUILD-015',
      mc.rechazado(r) and mc.es(r, 'SR_BUILD_CONFIG_FMT'), r[:300])

# ---- 4. contraprueba: un nombre limpio con espacio vale y compila ----
ESP = proyecto('EspacioCfgTest')
reescribe(ESP, lambda x: x.replace('<BuildConfiguration Include="Release">',
                                   '<BuildConfiguration Include="Release Plus">', 1))
r = S.call('delphi_build', {'project': ESP, 'config': 'Release Plus'}, t=900)
check('C4 contraprueba: config "Release Plus" declarada NO es BUILD-015',
      not mc.es(r, 'SR_BUILD_CONFIG_FMT'), r[:300])
check('C4b ...y msbuild la recibe en UN argumento (sin comillas: MSB1008, dos proyectos)',
      'MSB1008' not in r and not mc.rechazado(r), r[:600])

S.mata()
mc.fin('config 1.18.1 battery')
