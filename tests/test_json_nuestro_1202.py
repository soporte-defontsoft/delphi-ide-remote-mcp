"""1.20.2 - the engine's settings are always OURS, made again on every request
for the configuration and platform the project has SELECTED (what the IDE and
msbuild build while nobody asks for another), and an engine already running
gets them again when they change. Measured on 17/18-oct-2026 against 1.20.1:

  M4  the IDE's .delphilsp.json was preferred while it named a project that
      existed: what an agent changed in the .dproj (delphi_config) was not seen
      until somebody opened the IDE - and nobody does on a server
  M5  an engine already running never got new settings: they went to it once,
      when it started
  M9  ours chained every DCC_Define of every configuration (DEBUG and RELEASE
      at once) and lacked FRAMEWORK_<type>: an error under {$IFDEF
      FRAMEWORK_VCL}, which dcc reports in every configuration, was invisible,
      and one under {$IFDEF RELEASE} was reported in Debug
  FD  the project of a unit was the first .dproj whose TEXT carried its name: a
      unit its project reaches by search path had none (LSP-035), and with two
      copies side by side the unit of one was linted with the other's project

The fixture is the IDE's own VCL template (ObjRepos\\en\\DelphiWin32\\SDIApp:
DEBUG;$(DCC_Define) in Debug, RELEASE in Release, as the IDE writes them), and
the judge of the defines is msbuild (delphi_build).

  J1 (M4) an IDE settings file next to the project, then add-searchpath:
     diagnostics and definition see the new folder
  J2 (M5) engines already running (agent and linter) see add-searchpath with
     no restart, and the lint of the SAME text is done again
  J3 (M9) diagnostics = the errors msbuild gives for the SELECTED
     configuration (Debug): FRAMEWORK_VCL defined, RELEASE not, and a define
     of the Base group (MIDEF;$(DCC_Define)) next to Debug's own - two groups
     with a value each, the case where $(DCC_Define) is what came before
  J4 delphi_build without config= builds the selected one and says which
  J5 set-active config=Release: the selector changes and nothing else, the
     running linter follows it with the same text, build without config=
     builds Release, view says it; platform= the same (Win64, once enabled)
  J6 set-active refuses what the project does not declare (a configuration, a
     disabled platform) and nothing is written; it needs one of the two
  J7 a copy whose IDE settings name the ORIGINAL: its unit resolves inside the
     copy, with the copy's project
  J8 (FD) two copies side by side: by search path only, and one by search
     path while the other lists it - each unit, its own copy's project; both
     listing it, the same (control)
  J9 a VCL project delphi_create makes is born as the IDE makes one (the
     judge of what the IDE writes: projects David created in the 37.0 IDE,
     18-oct-2026): DEBUG in Debug and RELEASE in Release - msbuild says it,
     and diagnostics follows the selected Debug -, and its exe carries a
     manifest and an icon (the judge: Windows, the resources of the exe)

  J10 (review of 18-oct) the main .dpr of a folder with two .dproj is linted
      with its own; a unit only the SECOND lists, with that one
  J11 the project above that LISTS a unit wins over a demo below that only
      reaches its folder by search path
  J12 a .dproj next to it that neither lists it nor reaches it does not serve
      it: no settings (LSP-035) - the negative case the judge lacked
  J13 build config=Base (CFG-120), config of blanks (the selected one), a
      selected configuration the project does not declare (CFG-121),
      set-active with the value it already has (CFG-119, nothing written),
      and delphi_test discover saying the selected config
  J14 (reading of the own diff, 18-oct) the SAME server sees a second
      project that lists the unit, created beside the first one or in a
      folder below that was already there (the cache kept only the chosen
      one's stamps: RED against the first version of the cache)
  (and in J2/J5: the SAME engines follow the change; J5: the engine's
  dllname and the build follow platform=; J9: the unit paths as the IDE gives
  them to its engine - the Debug DCU Path in front in Debug, not in Release)

J1-J3, J5-J9 are RED against 1.20.1 (7a2e461, pass its exe as argument); J4
and the control of J8 are green with both. J10 and J11 are RED against the
first version of this step (two judges at one level, the main source lost).

Usage:  python tests/test_json_nuestro_1202.py [path-to-DelphiLspMcp.exe]
"""
import ctypes, json, os, re, shutil
from urllib.parse import unquote, urlparse
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('json1202')
EXE = mc.copia_exe(BASE)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA)
ENV = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA})


def servidor():
    return mc.Stdio(EXE, ENV, nombre='json1202', t=600)


S = servidor()

# la plantilla del IDE, donde delphi_installs dice que esta la instalacion
inst = mc.como_json(S.call('delphi_installs', {})) or {}
activa = next((i for i in inst.get('installs', []) if i.get('active')), {})
SDI = os.path.join(mc.real(activa.get('rootdir', '')).rstrip('\\'), 'ObjRepos', 'en', 'DelphiWin32', 'SDIApp')
check('la plantilla VCL del IDE esta (ObjRepos\\en\\DelphiWin32\\SDIApp)',
      os.path.isfile(os.path.join(SDI, 'SDIAPP.dproj')), SDI)

U_EXTRA = ('unit UExtra;\r\n\r\ninterface\r\n\r\nfunction Triple(A: Integer): Integer;\r\n\r\n'
           'implementation\r\n\r\nfunction Triple(A: Integer): Integer;\r\nbegin\r\n  Result := A * 3;\r\n'
           'end;\r\n\r\nend.\r\n')
U_USA = ('unit UUsa;\r\n\r\ninterface\r\n\r\nfunction Usa: Integer;\r\n\r\nimplementation\r\n\r\n'
         'uses\r\n  UExtra;\r\n\r\nfunction Usa: Integer;\r\nbegin\r\n  Result := Triple(2);\r\nend;\r\n\r\nend.\r\n')
LINEA_TRIPLE = U_USA.split('\r\n').index('  Result := Triple(2);')
U_IFDEF = '\r\n'.join([
    'unit UIfdef;', '', 'interface', '', 'procedure Usa;', '', 'implementation', '',
    '{$IFDEF FRAMEWORK_VCL}', 'procedure EnVcl;', 'begin', '  NoExisteVcl;', 'end;', '{$ENDIF}', '',
    '{$IFDEF DEBUG}', 'procedure EnDebug;', 'begin', '  NoExisteDebug;', 'end;', '{$ENDIF}', '',
    '{$IFDEF RELEASE}', 'procedure EnRelease;', 'begin', '  NoExisteRelease;', 'end;', '{$ENDIF}', '',
    '{$IFDEF MIDEF}', 'procedure EnMidef;', 'begin', '  NoExisteMidef;', 'end;', '{$ENDIF}', '',
    'procedure Usa;', 'begin', 'end;', '', 'end.', ''])
SELECTOR_CFG = re.compile(r"(<Config\s+Condition=\"'\$\(Config\)'==''\">)([^<]*)(</Config>)")
SELECTOR_PLAT = re.compile(r"(<Platform\s+Condition=\"'\$\(Platform\)'==''\">)([^<]*)(</Platform>)")


def escribe(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'wb').write(texto.encode('utf-8'))


def sdi(dest):
    """Una copia de la plantilla del IDE en dest; su .dproj."""
    shutil.copytree(SDI, dest)
    return os.path.join(dest, 'SDIAPP.dproj')


def con_usa(dest, extra):
    """La plantilla con UUsa en el proyecto (usa UExtra) y UExtra en la carpeta
    extra, que el proyecto NO alcanza todavia. (dproj, uusa)."""
    dproj = sdi(dest)
    escribe(os.path.join(extra, 'UExtra.pas'), U_EXTRA)
    usa = os.path.join(dest, 'UUsa.pas')
    escribe(usa, U_USA)
    r = S.call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': usa})
    check('preparacion: UUsa en el proyecto (%s)' % os.path.basename(os.path.dirname(dest + '\\')),
          not mc.fallo(r), r[:200])
    return dproj, usa


def diag(ruta):
    """delphi_diagnostics, repetido mientras el lint siga en curso: el json."""
    r = ''
    for _ in range(8):
        r = S.call('delphi_diagnostics', {'path': ruta}, 300)
        if '"in-progress"' not in r:
            break
    return mc.como_json(r) or {'crudo': r}


def errores(d):
    """(linea, codigo) de los errores de una respuesta de diagnostics."""
    return sorted((x.get('line'), x.get('code')) for x in d.get('diagnostics', []) if x.get('severity') == 1)


def definicion_triple(usa):
    return S.call('delphi_definition', {'path': usa, 'line': LINEA_TRIPLE, 'character': 13}, 300)


def lineas_build(dproj, config=None, platform=None):
    """delphi_build: (json, lineas con error de UIfdef)."""
    a = {'project': dproj}
    if config:
        a['config'] = config
    if platform:
        a['platform'] = platform
    d = mc.como_json(S.call('delphi_build', a, 600)) or {}
    lin = sorted({int(m) for e in d.get('errors') or [] for m in re.findall(r'UIfdef\.pas\((\d+)\)', str(e))})
    return d, lin


def fabricado(dpr):
    """El .delphilsp.json que fabrico el servidor para ese .dpr (su cache), por
    la ruta LARGA y entera: la bateria la tiene corta (8.3, del %TEMP%) y el
    servidor la escribe larga; comparar solo la cola cruzaba las dos formas en
    las carpetas cortas (j3, j9: la primera pasada del 18-oct-2026)."""
    quiero = os.path.normcase(mc.larga(dpr))
    for f in os.listdir(mc.cache_servidor('configs', APPDATA)):
        p = os.path.join(mc.cache_servidor('configs', APPDATA), f)
        try:
            proj = json.load(open(p, encoding='utf-8-sig'))['settings']['project']
        except Exception:
            continue
        ruta = unquote(urlparse(proj).path).lstrip('/') if proj.startswith('file:') else mc.real(proj)
        if os.path.normcase(mc.larga(ruta)) == quiero:
            return p
    return ''


def de_la_copia(r, carpeta):
    """True si la ruta que trae la respuesta cae en ESA carpeta (las dos en su
    forma larga: el servidor escribe la larga y BASE puede venir corta)."""
    return os.path.normcase(mc.larga(carpeta)) + '\\' in os.path.normcase(mc.real(r).replace('/', '\\'))


# ---------------------------------------------------------------- J1 (M4)
J1 = os.path.join(BASE, 'j1')
dproj1, usa1 = con_usa(os.path.join(J1, 'app'), os.path.join(J1, 'Extra'))
diag(usa1)  # el servidor fabrica la suya: esa, junto al proyecto, es "la del IDE"
fab = fabricado(os.path.join(J1, 'app', 'SDIAPP.DPR'))
check('J1 preparacion: la configuracion fabricada de la plantilla', fab != '', os.listdir(mc.cache_servidor('configs', APPDATA)))
if fab:
    shutil.copy(fab, os.path.join(J1, 'app', 'SDIAPP.delphilsp.json'))
S.cierra()
S = servidor()  # motores nuevos: M4 es el json del IDE, no un motor vivo
r = S.call('delphi_config', {'command': 'add-searchpath', 'project': dproj1, 'path': '..\\Extra'})
check('J1 add-searchpath ..\\Extra', not mc.fallo(r), r[:200])
d = diag(usa1)
check('J1 con un .delphilsp.json del IDE al lado, diagnostics ve el search path nuevo: sin errores',
      d.get('errors') == 0, (errores(d), str(d)[:300]))
r = definicion_triple(usa1)
check('J1 ...y definition lleva a Extra\\UExtra.pas', 'UExtra.pas' in r and not mc.fallo(r), r[:300])

# ---------------------------------------------------------------- J2 (M5)
J2 = os.path.join(BASE, 'j2')
dproj2, usa2 = con_usa(os.path.join(J2, 'app'), os.path.join(J2, 'Extra'))
r = definicion_triple(usa2)
check('J2 preparacion: el motor de agente vivo, sin UExtra a la vista',
      not mc.fallo(r) and 'UExtra.pas' not in r, r[:200])
d = diag(usa2)
check('J2 preparacion: el linter vivo da F2063 de UExtra', ('F2063' in [c for _, c in errores(d)]), errores(d))
motores_j2 = sorted(mc.hijos_lsp(S.p.pid))
r = S.call('delphi_config', {'command': 'add-searchpath', 'project': dproj2, 'path': '..\\Extra'})
check('J2 add-searchpath con los dos motores vivos', not mc.fallo(r), r[:200])
d = diag(usa2)
check('J2 el linter vivo lo ve SIN reiniciar, con el mismo texto: sin errores', d.get('errors') == 0,
      (errores(d), str(d)[:300]))
r = definicion_triple(usa2)
check('J2 ...y el motor de agente vivo tambien: definition -> UExtra.pas', 'UExtra.pas' in r, r[:300])
check('J2 ...los MISMOS motores: ninguno nuevo por el cambio de ajustes',
      bool(motores_j2) and sorted(mc.hijos_lsp(S.p.pid)) == motores_j2, (motores_j2, mc.hijos_lsp(S.p.pid)))

# ---------------------------------------------------------------- J3, J4, J5, J6
J3 = os.path.join(BASE, 'j3')
dproj3 = sdi(J3)
ifdef = os.path.join(J3, 'UIfdef.pas')
escribe(ifdef, U_IFDEF)
r = S.call('delphi_config', {'command': 'add-unit', 'project': dproj3, 'path': ifdef})
check('J3 preparacion: UIfdef en el proyecto', not mc.fallo(r), r[:200])
# un define del grupo Base, como lo escribe el IDE (lo de antes detras): no hay
# tool que escriba defines, asi que lo pone la bateria, a mano, en el fixture
t3 = open(dproj3, 'rb').read().decode('utf-8-sig')
BASE_G = '<PropertyGroup Condition="\'$(Base)\'!=\'\'">'
check('J3 preparacion: la plantilla tiene su grupo Base', t3.count(BASE_G) == 1, t3[:200])
t3 = t3.replace(BASE_G, BASE_G + '\r\n        <DCC_Define>MIDEF;$(DCC_Define)</DCC_Define>', 1)
open(dproj3, 'wb').write(b'\xef\xbb\xbf' + t3.encode('utf-8'))  # con su BOM, como la plantilla
b_dbg, juez_dbg = lineas_build(dproj3, 'Debug')
b_rel, juez_rel = lineas_build(dproj3, 'Release')
check('J3 el juez (msbuild): Debug da las lineas 12, 19 y 33, Release 12, 26 y 33',
      juez_dbg == [12, 19, 33] and juez_rel == [12, 26, 33], (juez_dbg, juez_rel, str(b_dbg)[:300]))
d = diag(ifdef)
check('J3 diagnostics = la configuracion SELECCIONADA (Debug): las lineas de msbuild, FRAMEWORK_VCL incluida',
      [l for l, _ in errores(d)] == juez_dbg, (errores(d), juez_dbg))

b, lin = lineas_build(dproj3)
check('J4 build sin config= compila la seleccionada (Debug) y lo dice', b.get('config') == 'Debug' and lin == juez_dbg,
      (b.get('config'), lin))

motores_j5 = sorted(mc.hijos_lsp(S.p.pid))
antes = open(dproj3, 'rb').read().decode('utf-8-sig')
r = S.call('delphi_config', {'command': 'set-active', 'project': dproj3, 'config': 'release'})
despues = open(dproj3, 'rb').read().decode('utf-8-sig')
check('J5 set-active config=release contesta', not mc.fallo(r) and 'Release' in r, r[:300])
check('J5 ...cambia el selector, con el nombre que declara el proyecto, y nada mas',
      despues == SELECTOR_CFG.sub(r'\1Release\3', antes, count=1) and despues != antes,
      SELECTOR_CFG.search(despues).group(0) if SELECTOR_CFG.search(despues) else despues[:300])
d = diag(ifdef)
check('J5 el linter vivo sigue la seleccion con el MISMO texto: las lineas de Release',
      [l for l, _ in errores(d)] == juez_rel, (errores(d), juez_rel))
check('J5 ...con los MISMOS motores', bool(motores_j5) and sorted(mc.hijos_lsp(S.p.pid)) == motores_j5,
      (motores_j5, mc.hijos_lsp(S.p.pid)))
b, lin = lineas_build(dproj3)
check('J5 build sin config= compila ahora Release', b.get('config') == 'Release' and lin == juez_rel,
      (b.get('config'), lin))
v = mc.como_json(S.call('delphi_config', {'command': 'view', 'project': dproj3})) or {}
check('J5 view dice la configuracion seleccionada', v.get('defaultConfig') == 'Release', str(v)[:300])
r = S.call('delphi_config', {'command': 'add-platform', 'project': dproj3, 'platform': 'Win64'})
check('J5 preparacion: Win64 activa', not mc.fallo(r), r[:200])
r = S.call('delphi_config', {'command': 'set-active', 'project': dproj3, 'platform': 'win64'})
v = mc.como_json(S.call('delphi_config', {'command': 'view', 'project': dproj3})) or {}
sel = SELECTOR_PLAT.search(open(dproj3, 'rb').read().decode('utf-8-sig'))
check('J5 set-active platform=win64: el selector de plataforma, con su grafia',
      not mc.fallo(r) and v.get('defaultPlatform') == 'Win64' and sel is not None and sel.group(2) == 'Win64',
      (r[:200], v.get('defaultPlatform')))
diag(ifdef)  # una peticion del motor: los ajustes, hechos otra vez
fab3 = fabricado(os.path.join(J3, 'SDIAPP.DPR'))
dll3 = json.load(open(fab3, encoding='utf-8-sig'))['settings'].get('dllname', '') if fab3 else ''
b, _ = lineas_build(dproj3)
check('J5 ...y la siguen el motor (dcc64 en sus ajustes) y el build sin platform= (Win64)',
      dll3.startswith('dcc64') and b.get('platform') == 'Win64', (dll3, b.get('platform')))

# el juez de la configuracion es UNO para build, test y config (ConfigDelBuild, 1.22.2): sus negativas
for args, que, cual in (({'config': 'Inventada'}, 'una configuracion que no declara', mc.id_de('SR_TEST_CONFIG_FMT')),
                        ({'config': 'Base'}, 'Base, que no es una configuracion que se compile',
                         mc.id_de('SR_CFG_BASE_NO_SE_COMPILA_FMT')),
                        ({}, 'sin config ni platform', mc.id_de('SR_CFG_SET_ACTIVE_NECESITA'))):
    antes = open(dproj3, 'rb').read()
    a = {'command': 'set-active', 'project': dproj3}
    a.update(args)
    r = S.call('delphi_config', a)
    # la negativa de set-active, no la de un comando o un parametro que no existe
    check('J6 set-active con %s: negado (%s)' % (que, cual or 'la regla del framework'),
          mc.rechazado(r) and not mc.tiene(r, 'CFG-084') and not mc.tiene(r, 'SYS-015')
          and mc.tiene(r, cual), r[:300])
    check('J6 ...y no escribio nada', open(dproj3, 'rb').read() == antes)
# la regla del framework, y no la de una plataforma que no declara (la plantilla
# no declara Linux64: sin CanTarget saldria BUILD-046 y una negativa cualquiera
# lo daba por bueno; revisor de baterias, 18-oct-2026)
antes = open(dproj3, 'rb').read()
r = S.call('delphi_config', {'command': 'set-active', 'project': dproj3, 'platform': 'Linux64'})
VCL_SOLO = mc.catalogo()['SF_CFG_VCL_SOLO_WINDOWS_FMT'].split('(')[0].strip()
check('J6 set-active con una plataforma que el VCL no puede: negado por la regla del framework',
      mc.abre(r, 'SR_RECHAZADO_FMT') and VCL_SOLO in r and 'Linux64' in r
      and not mc.es(r, 'SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT'), r[:300])
check('J6 ...y no escribio nada', open(dproj3, 'rb').read() == antes)
r = S.call('delphi_config', {'command': 'set-active', 'project': dproj3, 'platform': 'Win32'})
r = S.call('delphi_config', {'command': 'remove-platform', 'project': dproj3, 'platform': 'Win64'})
antes = open(dproj3, 'rb').read()
r = S.call('delphi_config', {'command': 'set-active', 'project': dproj3, 'platform': 'Win64'})
check('J6 set-active de una plataforma desactivada: negado con la regla del build',
      mc.tiene(r, mc.id_de('SR_BUILD_PLATAFORMA_NO_DECLARADA_FMT')), r[:300])
check('J6 ...y no escribio nada', open(dproj3, 'rb').read() == antes)

# ---------------------------------------------------------------- J7 (la copia)
J7 = os.path.join(BASE, 'j7')
A = os.path.join(J7, 'app_1_0')
dproj7, usa7 = con_usa(A, os.path.join(A, 'Extra'))
r = S.call('delphi_config', {'command': 'add-searchpath', 'project': dproj7, 'path': 'Extra'})
diag(usa7)
fab = fabricado(os.path.join(A, 'SDIAPP.DPR'))
check('J7 preparacion: la configuracion fabricada del original', fab != '')
if fab:
    shutil.copy(fab, os.path.join(A, 'SDIAPP.delphilsp.json'))  # el del IDE, que nombra el original
B = os.path.join(J7, 'app_2_0')
shutil.copytree(A, B)
d = diag(os.path.join(B, 'UUsa.pas'))
check('J7 la copia con el json del original: se linta con SU proyecto',
      de_la_copia(d.get('project', ''), B), d.get('project'))
r = definicion_triple(os.path.join(B, 'UUsa.pas'))
check('J7 ...y definition lleva a SU Extra\\UExtra.pas, no al del original',
      de_la_copia((mc.como_json(r) or {}).get('path', ''), os.path.join(B, 'Extra')), r[:300])

# ---------------------------------------------------------------- J8 (FD)
J8 = os.path.join(BASE, 'j8')
U_SHARED = ('unit UShared;\r\n\r\ninterface\r\n\r\nfunction Doble(A: Integer): Integer;\r\n\r\nimplementation\r\n\r\n'
            'function Doble(A: Integer): Integer;\r\nbegin\r\n  Result := A * 2;\r\nend;\r\n\r\nend.\r\n')


def copia_fd(caso, version, como):
    raiz = os.path.join(J8, caso, version)
    S.call('delphi_create', {'kind': 'project-console', 'name': 'P', 'dir': os.path.join(raiz, 'codigofuente')})
    dproj = os.path.join(raiz, 'codigofuente', 'P.dproj')
    unidad = os.path.join(raiz, 'SharedSource', 'UShared.pas')
    escribe(unidad, U_SHARED)
    if como == 'unit':
        r = S.call('delphi_config', {'command': 'add-unit', 'project': dproj, 'path': unidad})
    else:
        r = S.call('delphi_config', {'command': 'add-searchpath', 'project': dproj, 'path': '..\\SharedSource'})
    check('J8 preparacion %s %s (%s)' % (caso, version, como), not mc.fallo(r), r[:200])
    return dproj, unidad


for caso, comos, que in (('b2', ('path', 'path'), 'las dos solo por search path'),
                         ('b3', ('unit', 'path'), '1_0 la lista, 2_0 por search path'),
                         ('b1', ('unit', 'unit'), 'las dos la listan (control)')):
    copia_fd(caso, 'a_1_0', comos[0])
    dproj20, unidad20 = copia_fd(caso, 'a_2_0', comos[1])
    d = diag(unidad20)
    check('J8 %s: la UShared de 2_0 se linta con el proyecto de 2_0' % que,
          de_la_copia(d.get('project', ''), os.path.dirname(dproj20)), (d.get('project'), str(d)[:200]))

# ---------------------------------------------------------------- J9 (create como el IDE)
J9 = os.path.join(BASE, 'j9')
r = S.call('delphi_create', {'kind': 'project-vcl', 'name': 'NueVcl', 'dir': J9})
check('J9 preparacion: delphi_create project-vcl', not mc.fallo(r), r[:200])
dproj9 = os.path.join(J9, 'NueVcl.dproj')
ifdef9 = os.path.join(J9, 'UIfdef.pas')
escribe(ifdef9, U_IFDEF)
r = S.call('delphi_config', {'command': 'add-unit', 'project': dproj9, 'path': ifdef9})
check('J9 preparacion: UIfdef en el proyecto nuevo', not mc.fallo(r), r[:200])
b9d, lin9d = lineas_build(dproj9, 'Debug')
b9r, lin9r = lineas_build(dproj9, 'Release')
check('J9 un proyecto nuevo define DEBUG en Debug y RELEASE en Release (msbuild: 12+19 y 12+26)',
      lin9d == [12, 19] and lin9r == [12, 26], (lin9d, lin9r))
d = diag(ifdef9)
check('J9 ...y diagnostics, la seleccionada (Debug): las mismas lineas',
      [l for l, _ in errores(d)] == lin9d, (errores(d), lin9d))
# el exe, sin UIfdef (sus errores son a proposito): el del proyecto tal cual nace
r = S.call('delphi_config', {'command': 'remove-unit', 'project': dproj9, 'path': ifdef9})
b9 = mc.como_json(S.call('delphi_build', {'project': dproj9, 'config': 'Release'}, 600)) or {}
exe9 = mc.real(b9.get('output', ''))


def recurso(exe, tipo):
    """True si el exe lleva un recurso de ese tipo (24 manifiesto, 14 grupo de iconos)."""
    k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    k32.LoadLibraryExW.restype = ctypes.c_void_p
    k32.LoadLibraryExW.argtypes = [ctypes.c_wchar_p, ctypes.c_void_p, ctypes.c_uint]
    k32.EnumResourceNamesW.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    k32.FreeLibrary.argtypes = [ctypes.c_void_p]
    h = k32.LoadLibraryExW(exe, None, 0x2)  # LOAD_LIBRARY_AS_DATAFILE
    if not h:
        return False
    hay = []
    PROC = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)
    cb = PROC(lambda *a: hay.append(1) or 0)
    k32.EnumResourceNamesW(h, ctypes.c_void_p(tipo), cb, None)
    k32.FreeLibrary(h)
    return bool(hay)


check('J9 el exe de un VCL nuevo lleva su manifiesto y su icono, como el del IDE',
      b9.get('success') is True and os.path.isfile(exe9) and recurso(exe9, 24) and recurso(exe9, 14),
      (b9.get('success'), exe9, os.path.isfile(exe9) and recurso(exe9, 24), os.path.isfile(exe9) and recurso(exe9, 14)))


def unidades(dpr):
    """Las rutas de unidades (-U) de los ajustes que fabrico el servidor, en minusculas."""
    fab = fabricado(dpr)
    o = json.load(open(fab, encoding='utf-8-sig'))['settings'].get('dccOptions', '') if fab else ''
    m = re.search(r'-U"([^"]*)"', o)
    return [p.lower() for p in m.group(1).split(';')] if m else []


# las rutas de unidades como el IDE se las da a su propio motor (su
# .delphilsp.json de un proyecto recien creado, 18-oct-2026) y como compila
# msbuild (CodeGear.Delphi.Targets 132-137): con DCC_DebugDCUs -el Debug que
# crea el IDE- las de depuracion delante y la biblioteca release detras; en
# Release, sin las de depuracion
RELEASE9 = '\\lib\\win64\\release'
u9 = unidades(os.path.join(J9, 'NueVcl.dpr'))
check('J9 rutas de unidades en Debug: las de depuracion delante, la biblioteca release detras',
      bool(u9) and u9[0].endswith('\\debug') and RELEASE9 in [p[-len(RELEASE9):] for p in u9], u9[:4])
r = S.call('delphi_config', {'command': 'set-active', 'project': dproj9, 'config': 'Release'})
diag(ifdef9)
u9r = unidades(os.path.join(J9, 'NueVcl.dpr'))
check('J9 ...y en Release, sin las de depuracion',
      not mc.fallo(r) and bool(u9r) and not any(p.endswith('\\lib\\win64\\debug') for p in u9r)
      and RELEASE9 in [p[-len(RELEASE9):] for p in u9r], (r[:120], u9r[:4]))

# ------------------------------------------------- J10-J12 (el juez de FindDproj)
# (revisores del 18-oct-2026: el juez nuevo no tenia ningun caso en que un
# .dproj de cerca NO sirva, y dos regresiones contra el de antes)
def consola(nombre, dir_):
    r = S.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': dir_})
    check('preparacion: consola %s' % nombre, not mc.fallo(r), r[:200])
    return os.path.join(dir_, nombre + '.dproj')


def proyecto_de(ruta):
    """El proyecto con el que diagnostics linto esa unidad, en su forma real y
    larga ('' si no linto: su negativa va en el crudo)."""
    d = diag(ruta)
    return os.path.normcase(mc.larga(mc.real(d.get('project', '')))) if d.get('project') else '', d


def es(p, ruta):
    return p == os.path.normcase(mc.larga(ruta))


J10 = os.path.join(BASE, 'j10', 'dos')  # la carpeta no se llama como ninguno
dprA = consola('A', J10)
dprB = consola('B', J10)
p, d = proyecto_de(os.path.join(J10, 'B.dpr'))
check('J10 el .dpr de B, con A.dproj al lado: se linta con B (su fuente principal)',
      es(p, dprB), (p, str(d)[:200]))
ub = os.path.join(J10, 'UB.pas')
escribe(ub, U_SHARED.replace('UShared', 'UB'))
r = S.call('delphi_config', {'command': 'add-unit', 'project': dprB, 'path': ub})
check('J10b preparacion: UB en B', not mc.fallo(r), r[:200])
p, d = proyecto_de(ub)
check('J10b una unidad que solo lista el SEGUNDO de dos .dproj: se linta con ese',
      es(p, dprB), (p, str(d)[:200]))

J11 = os.path.join(BASE, 'j11', 'repo')
dprApp = consola('App', J11)
uc = os.path.join(J11, 'Src', 'UClientes.pas')
escribe(uc, U_SHARED.replace('UShared', 'UClientes'))
r = S.call('delphi_config', {'command': 'add-unit', 'project': dprApp, 'path': uc})
check('J11 preparacion: UClientes en App (arriba)', not mc.fallo(r), r[:200])
dprDemo = consola('Demo', os.path.join(J11, 'Src', 'Demos'))
r = S.call('delphi_config', {'command': 'add-searchpath', 'project': dprDemo, 'path': '..'})
check('J11 preparacion: Demo (abajo) alcanza Src por search path', not mc.fallo(r), r[:200])
p, d = proyecto_de(uc)
check('J11 el que la LISTA (arriba) gana al que solo la alcanza (abajo)',
      es(p, dprApp), (p, str(d)[:200]))

J12 = os.path.join(BASE, 'j12', 'a')
consola('P', os.path.join(J12, 'codigofuente'))
suelta = os.path.join(J12, 'SharedSource', 'UShared.pas')
escribe(suelta, U_SHARED)
p, d = proyecto_de(suelta)
check('J12 un .dproj de al lado que ni la lista ni la alcanza no la sirve: sin ajustes (LSP-035)',
      p == '' and mc.abre(d.get('crudo', ''), 'SR_LSP_LINT_SIN_AJUSTES_FMT'), (p, str(d)[:200]))

# ---------------------------------------------------------------- J13 (lo de la revision)
J13 = os.path.join(BASE, 'j13')
dpr13 = consola('C', J13)
r = S.call('delphi_build', {'project': dpr13, 'config': 'Base'}, 600)
check('J13 build config=Base: su negativa propia (CFG-120), no "no existe"',
      mc.abre(r, 'SR_CFG_BASE_NO_SE_COMPILA_FMT'), r[:300])
b13 = mc.como_json(S.call('delphi_build', {'project': dpr13, 'config': '   '}, 600)) or {}
check('J13 build config de blancos: la seleccionada (Debug), no /p:Config=" "',
      b13.get('success') is True and b13.get('config') == 'Debug', str(b13)[:300])
antes = open(dpr13, 'rb').read()
r = S.call('delphi_config', {'command': 'set-active', 'project': dpr13, 'config': 'Debug'})
check('J13 set-active con la que ya es: CFG-119 y no escribe nada',
      mc.abre(r, 'SN_CFG_SET_ACTIVE_YA_FMT') and open(dpr13, 'rb').read() == antes, r[:300])
# una seleccionada que el proyecto no declara: el selector, a mano en el
# fixture (ninguna tool lo deja asi), con la codificacion que tenga
crudo = open(dpr13, 'rb').read()
bom = crudo.startswith(b'\xef\xbb\xbf')
t13 = SELECTOR_CFG.sub(r'\1Staging\3', crudo.decode('utf-8-sig'), count=1)
open(dpr13, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + t13.encode('utf-8'))
r = S.call('delphi_build', {'project': dpr13}, 600)
check('J13 sin config= y una seleccionada que no declara: lo dice (CFG-121)',
      'Staging' in t13 and mc.abre(r, 'SR_CFG_SELECCIONADA_NO_DECLARADA_FMT') and 'Staging' in r, r[:300])
DT = os.path.join(BASE, 'j13t')
r = S.call('delphi_create', {'kind': 'project-test', 'name': 'PT', 'dir': DT})
check('J13 preparacion: un proyecto de test', not mc.fallo(r), r[:200])
r = S.call('delphi_config', {'command': 'set-active', 'project': os.path.join(DT, 'PT.dproj'), 'config': 'Release'})
pt = [p for p in mc.ficheros(S.call('delphi_test', {'command': 'discover', 'path': DT}), 'projects')
      if os.path.basename(mc.real(p.get('path', ''))).lower() == 'pt.dpr']
check('J13 delphi_test discover dice la configuracion seleccionada (la que run compila sin config=)',
      not mc.fallo(r) and len(pt) == 1 and pt[0].get('config') == 'Release', (r[:120], pt))

# ------------------------------------------------- J14 (la cache de FindDproj)
# (lectura del diff propio, 18-oct-2026) la respuesta guardada solo llevaba los
# sellos del ELEGIDO: un segundo proyecto que lista la unidad, creado despues,
# no se veia hasta reiniciar el servidor (produccion vive dias). Medido: el
# mismo servidor decia A y uno nuevo B
UNIDAD14 = 'unit %s;\ninterface\nprocedure P;\nimplementation\nprocedure P; begin end;\nend.\n'
J14 = os.path.join(BASE, 'j14', 'f')
dpr14A = consola('A', J14)
u14 = os.path.join(J14, 'U14.pas')
open(u14, 'w', newline='\r\n').write(UNIDAD14 % 'U14')
p, d = proyecto_de(u14)
check('J14 preparacion: U14 con A, el unico de su carpeta (respuesta que se guarda)', es(p, dpr14A), d)
dpr14B = consola('B', J14)
r = S.call('delphi_config', {'project': dpr14B, 'command': 'add-unit', 'path': u14})
check('J14 preparacion: U14 en B', mc.abre(r, 'SN_UNIT_ADDED_FMT'), r[:200])
p, d = proyecto_de(u14)
check('J14 el MISMO servidor: un segundo .dproj al lado que LISTA la unidad la gana (se sella la carpeta)',
      es(p, dpr14B), d)
# ...y uno que aparece en una subcarpeta que YA estaba: solo lo ve el sello de
# las carpetas recorridas hacia abajo (la suya no tiene .dproj: el juez baja)
J14P = os.path.join(BASE, 'j14b', 'proy')
dpr14P = consola('P', J14P)
G14 = os.path.join(J14P, 'g')
SUB14 = os.path.join(G14, 'sub')
os.makedirs(SUB14)
u14b = os.path.join(G14, 'U14b.pas')
open(u14b, 'w', newline='\r\n').write(UNIDAD14 % 'U14b')
p, d = proyecto_de(u14b)
check('J14b preparacion: U14b (sin .dproj en su carpeta) con P, el de encima', es(p, dpr14P), d)
dpr14S = consola('S', SUB14)
r = S.call('delphi_config', {'project': dpr14S, 'command': 'add-unit', 'path': u14b})
check('J14b preparacion: U14b en S', mc.abre(r, 'SN_UNIT_ADDED_FMT'), r[:200])
p, d = proyecto_de(u14b)
check('J14b ...un .dproj que aparece en una subcarpeta que ya estaba y la LISTA la gana (se sellan las de abajo)',
      es(p, dpr14S), d)

S.cierra()
mc.borra(BASE)
mc.fin('json-nuestro-1202 battery')
