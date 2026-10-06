"""E2E battery for v0.45.0-beta - the F2613 helper of delphi_build and
delphi_components platform=X (the IDE's Library Search Path per platform).

Field 2026-08-22: a Linux64 build needed two failed builds per component to
locate by hand the Source folders OBR and Steema register only for Windows.
Now a failed build says WHERE each missing unit's .pas lives in the library
zone, and delphi_components platform=Linux64 lists the component roots other
platforms register and this one does not.

Usage:  python tests/test_missing_units.py [path-to-DelphiLspMcp.exe]
Needs a RAD Studio with the Linux64 compiler (dcclinux64); no PAServer.
"""
import json, os, glob
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('missingunits')
EXE = mc.copia_exe(BASE)

# plazo de 300 s: aqui se compila para Linux64
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='missing-units-battery', t=300)
call = srv.call

# --- delphi_components platform=X -------------------------------------------
r = call('delphi_components', {'platform': 'Linux64'})
check('platform view header', mc.abre(r, 'SN_COMPONENTS_PLATFORM_HEAD_FMT')
      and 'Linux64' in r.split('\n')[0], r)
check('platform view lists folders',
      # enmascaradas en CUALQUIER unidad (daba por hecho que RAD Studio esta en C:)
      mc.es(r, 'SN_COMPONENTS_PLATFORM_HEAD_FMT') and mc.real(r) != r, r)
check('platform view names candidates or completeness',
      mc.es(r, 'SN_COMPONENTS_PLATFORM_MISSING_FMT')
      or mc.es(r, 'SN_COMPONENTS_PLATFORM_COMPLETE_FMT'), r)
# El trozo de una linea de candidato sale de SU plantilla del catalogo: con
# la frase espanola escrita a mano, tras traducir la negativa ya no podia
# fallar. Y si hay candidatos, el trozo TIENE que verse: una negativa que
# no ve la forma que vigila no vigila nada.
CAND = mc.catalogo()['SF_COMP_REGISTRADO_EN_FMT'].split('%s')[1]
check('platform view never shows the IDE own documents tree as a candidate',
      '\\Studio\\37.0' + CAND not in r
      and (CAND in r or not mc.es(r, 'SN_COMPONENTS_PLATFORM_MISSING_FMT')), r)
r = call('delphi_components', {'platform': 'Marte'})
check('unknown platform refused with the list',
      mc.es(r, 'SR_COMPONENTS_PLATFORM_FMT') and 'Linux64' in r, r)
r = call('delphi_components', {'platform': 'win64'})
check('platform is canonicalized (win64 -> Win64)',
      mc.abre(r, 'SN_COMPONENTS_PLATFORM_HEAD_FMT') and ' Win64 ' in r.split('\n')[0], r)
r = call('delphi_components', {})
check('no platform = packages list as before',
      mc.abre(r, 'SN_COMPONENTS_DESIGN_PACKAGES_FMT'), r)

# --- delphi_build: missingUnits ----------------------------------------------
r = call('delphi_create', {'kind': 'project-console', 'name': 'MissU', 'dir': BASE})
check('project created', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r)
dprs = glob.glob(os.path.join(BASE, '**', 'MissU.dpr'), recursive=True)
check('dpr on disk', bool(dprs))
dpr = dprs[0]
s = open(dpr, encoding='utf-8-sig').read()
s = s.replace('uses', 'uses\n  Tee.Grid, NoSuchUnitXyz,', 1)
open(dpr, 'w', encoding='utf-8').write(s)
dproj = dpr[:-4] + '.dproj'
# 1.16.0: solo se compila una plataforma que el proyecto declara (BUILD-046)
call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64', 'project': dproj})

r = call('delphi_build', {'project': dproj, 'platform': 'Linux64', 'config': 'Debug'})
try:
    j = json.loads(r)
except Exception:
    j = {}
check('build fails', j.get('success') is False, r)
mu = j.get('missingUnits') or []
check('missingUnits present', bool(mu), r)
names = [m.get('unit') for m in mu]
check('first missing unit named', 'Tee.Grid' in names, str(names))
tg = next((m for m in mu if m.get('unit') == 'Tee.Grid'), {})
check('Tee.Grid source folder found in the library zone (Steema Sources)',
      any('Steema' in d for d in tg.get('sourceFolders', [])), json.dumps(tg))
check('folders come masked (srvc:)', all(d.lower().startswith('srv') for d in tg.get('sourceFolders', [])), json.dumps(tg))
check('note explains add-searchpath',
      mc.es(j.get('missingUnitsNote') or '', 'SN_BUILD_MISSING_UNITS_NOTE')
      and 'add-searchpath' in (j.get('missingUnitsNote') or ''), r)

# the suggested fix closes the loop: add-searchpath -> the unit resolves
folder = tg.get('sourceFolders', [''])[0]
if folder:
    r = call('delphi_config', {'command': 'add-searchpath', 'project': dproj, 'platform': 'Linux64', 'path': folder})
    check('add-searchpath accepted',
          not mc.fallo(r) and mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT'), r)
    r = call('delphi_build', {'project': dproj, 'platform': 'Linux64', 'config': 'Debug'})
    try: j = json.loads(r)
    except Exception: j = {}
    mu = j.get('missingUnits') or []
    names = [m.get('unit') for m in mu]
    check('Tee.Grid resolved after add-searchpath', 'Tee.Grid' not in names, str(names))
    check('NoSuchUnitXyz still missing with no candidates',
          'NoSuchUnitXyz' in names and not next((m for m in mu if m.get('unit') == 'NoSuchUnitXyz'), {}).get('sourceFolders'), r)

# a successful build carries no missingUnits
s = open(dpr, encoding='utf-8-sig').read().replace('  Tee.Grid, NoSuchUnitXyz,\n', '')
open(dpr, 'w', encoding='utf-8').write(s)
r = call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'})
try: j = json.loads(r)
except Exception: j = {}
check('clean build succeeds', j.get('success') is True, r[:300])
r = call('delphi_build', {'project': dproj, 'platform': 'Linux64', 'config': 'Debug'})
try: j = json.loads(r)
except Exception: j = {}
check('Linux64 clean build succeeds', j.get('success') is True, r[:300])
out = j.get('output') or ''
check('Linux64 build declares output (ELF without extension, v0.46)',
      out.endswith(os.sep + 'MissU') and 'Linux64' in out, r[:300])
check('no missingUnits on success', 'missingUnits' not in j, r[:300])

# --- BUILD-042: una unit del PROPIO workspace (3-oct-2026) ---------------------
# solo se buscaba en la zona de biblioteca: una unit de una carpeta vendor del
# proyecto (MCPServer.Types) salia sin ningun candidato. Y la copia de la
# papelera del servidor no es un candidato
VEND = os.path.join(BASE, 'vendor')
os.makedirs(VEND, exist_ok=True)
UNIDAD = 'unit UVendorX;\n\ninterface\n\nfunction Dame: Integer;\n\nimplementation\n\nfunction Dame: Integer;\nbegin\n  Result := 1;\nend;\n\nend.\n'
open(os.path.join(VEND, 'UVendorX.pas'), 'w', encoding='utf-8').write(UNIDAD)
PAPELERA = os.path.join(BASE, '__delphi-patch', '20261004')
os.makedirs(PAPELERA, exist_ok=True)
open(os.path.join(PAPELERA, 'UVendorX.pas'), 'w', encoding='utf-8').write(UNIDAD)
s = open(dpr, encoding='utf-8-sig').read()
open(dpr, 'w', encoding='utf-8').write(s.replace('uses', 'uses\n  UVendorX,', 1))
r = call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'})
try: j = json.loads(r)
except Exception: j = {}
uv = next((m for m in (j.get('missingUnits') or []) if m.get('unit') == 'UVendorX'), {})
check('BUILD-042: la unit de una carpeta del workspace tiene su carpeta como candidata',
      any(d.rstrip('\\').lower().endswith('vendor') for d in uv.get('sourceFolders', [])) and
      not any('__delphi-patch' in d for d in uv.get('sourceFolders', [])), json.dumps(uv)[:300])

# ...y el paseo por las raices no cruza a lo que no se puede leer: un junction
# del workspace a una carpeta de FUERA de la jaula no da candidatas (la
# respuesta nombraria carpetas de fuera; el paseo de la RTL sigue enlaces)
FUERA = mc.carpeta('missingunits-fuera')
open(os.path.join(FUERA, 'UFueraX.pas'), 'w', encoding='utf-8').write(UNIDAD.replace('UVendorX', 'UFueraX'))
ENLACE = os.path.join(BASE, 'enlace-fuera')
if mc.junction(ENLACE, FUERA):
    s = open(dpr, encoding='utf-8-sig').read()
    open(dpr, 'w', encoding='utf-8').write(s.replace('uses', 'uses\n  UFueraX,', 1))
    r = call('delphi_build', {'project': dproj, 'platform': 'Win64', 'config': 'Debug'})
    try: j = json.loads(r)
    except Exception: j = {}
    uf = next((m for m in (j.get('missingUnits') or []) if m.get('unit') == 'UFueraX'), None)
    # diagnostico: rojo una vez en una regresion entera (4-oct-2026) y verde
    # suelto; si vuelve, que diga si en ESE momento la puerta de lectura deja
    # leer por el enlace (jaula) o no (el filtro de UnitSourceFolders)
    diag = ''
    if uf is None or uf.get('sourceFolders'):
        diag = ' | read por el enlace: ' + call('delphi_read', {'path': os.path.join(ENLACE, 'UFueraX.pas')})[:160]
    check('BUILD-042: un junction a una carpeta de fuera de la jaula no da candidatas',
          uf is not None and not uf.get('sourceFolders'), json.dumps(uf or j)[:300] + diag)
    os.rmdir(ENLACE)  # el enlace, no lo de detras
else:
    check('BUILD-042 (preparacion): el junction se pudo crear', False, ENLACE)
mc.borra(FUERA)

srv.mata()
mc.fin('missing units battery')
