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
import json, os, glob, re
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
CAND = mc.trozo_de_formato('SF_COMP_REGISTRADO_EN_FMT', 1)
# los arboles del propio IDE acaban en ...\Studio\<su version>: la de la instalacion activa
# (delphi_installs), no '37.0' a mano
VER = mc.instalacion_activa(call).get('version', '')
check('platform view never shows the IDE own documents tree as a candidate',
      bool(VER) and '\\Studio\\' + VER + CAND not in r
      and (CAND in r or not mc.es(r, 'SN_COMPONENTS_PLATFORM_MISSING_FMT')), r)
# La unidad de muestra de missingUnits: Tee.Grid, de TeeChart, que compila para Linux64 desde su
# fuente. Se mide con ella solo si ESTA maquina la tiene en una carpeta que otras plataformas
# registran y Linux64 no (una candidata de esta misma vista); era TeeChart dado por instalado
MUESTRA = 'Tee.Grid'
TEE = next((d for d in (mc.real(l.split(CAND)[0].strip()) for l in r.splitlines() if CAND in l)
            if os.path.isfile(os.path.join(d, MUESTRA + '.pas'))), '')
if not TEE:
    print('NOTA: missingUnits con carpeta candidata no se mide: %s.pas no esta en ninguna carpeta que otra '
          'plataforma registre y Linux64 no' % MUESTRA)
USADAS = (MUESTRA + ', ' if TEE else '') + 'NoSuchUnitXyz,'
r = call('delphi_components', {'platform': 'Marte'})
check('unknown platform refused with the list',
      mc.es(r, 'SR_PLATAFORMA_NO_VALIDA_FMT') and 'Linux64' in r, r)  # LA negativa de toda tool (A36 de la 1.23)
r = call('delphi_components', {'platform': 'win64'})
check('platform is canonicalized (win64 -> Win64)',
      mc.abre(r, 'SN_COMPONENTS_PLATFORM_HEAD_FMT') and ' Win64 ' in r.split('\n')[0], r)
r = call('delphi_components', {})
check('no platform = packages list as before',
      mc.abre(r, 'SN_COMPONENTS_DESIGN_PACKAGES_FMT'), r)

# --- filter tambien en el Library Search Path (depuracion de la 1.23, David
# 23-oct-2026): una biblioteca sin paquete, solo unidades, vive solo ahi, y
# filter contestaba COMP-005 "ningun paquete la tiene" de una que compila
# (superobject). La carpeta sale del registro de ESTA maquina: una de Win64,
# fuera de los arboles del propio IDE (lib\Win64\release no es una
# biblioteca), cuyo nombre no aparece en ningun paquete
paquetes = r.lower()
rw = call('delphi_components', {'platform': 'Win64'})
libre = None
for l in rw.split('\n\n')[0].split('\n')[1:]:
    d = l.strip().split('  (')[0]
    hoja = d.rstrip('\\').split('\\')[-1]
    if len(hoja) >= 5 and hoja.lower() not in paquetes and ('\\studio\\' + VER.lower()) not in d.lower():
        libre = (d, hoja)
        break
check('filter (preparacion): una carpeta del Library Search Path de Win64 que ningun paquete nombra',
      libre is not None, rw[:300])
if libre:
    r = call('delphi_components', {'filter': libre[1]})
    check('filter la encuentra en el Library Search Path (COMP-012 con su carpeta y Win64, no COMP-005)',
          mc.abre(r, 'SN_COMPONENTS_PATH_HEAD_FMT') and libre[0] in r and 'Win64' in r, r[:300])
r = call('delphi_components', {'filter': 'zz-no-existe-zz'})
check('filter sin nada ni en paquetes ni en el Library Search Path: COMP-005',
      mc.es(r, 'SN_COMPONENTS_NONE_FMT'), r[:300])

# --- delphi_build: missingUnits ----------------------------------------------
r = call('delphi_create', {'kind': 'project-console', 'name': 'MissU', 'dir': BASE})
check('project created', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r)
dprs = glob.glob(os.path.join(BASE, '**', 'MissU.dpr'), recursive=True)
check('dpr on disk', bool(dprs))
dpr = dprs[0]
s = open(dpr, encoding='utf-8-sig').read()
s = s.replace('uses', 'uses\n  ' + USADAS, 1)
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
check('first missing unit named', (MUESTRA if TEE else 'NoSuchUnitXyz') in names, str(names))
tg = next((m for m in mu if m.get('unit') == MUESTRA), {})
if TEE:
    check('%s source folder found in the library zone (%s)' % (MUESTRA, TEE),
          any(mc.real(d).rstrip('\\').lower() == TEE.rstrip('\\').lower() for d in tg.get('sourceFolders', [])),
          json.dumps(tg))
    check('folders come masked (srvc:)', bool(tg.get('sourceFolders')) and
          all(d.lower().startswith('srv') for d in tg.get('sourceFolders', [])), json.dumps(tg))
    check('note explains add-searchpath',
          mc.es(j.get('missingUnitsNote') or '', 'SN_BUILD_MISSING_UNITS_NOTE')
          and 'add-searchpath' in (j.get('missingUnitsNote') or ''), r)
else:
    check('NoSuchUnitXyz missing with no candidates',
          not next((m for m in mu if m.get('unit') == 'NoSuchUnitXyz'), {'sourceFolders': ['?']}).get('sourceFolders'), r)

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
    check('%s resolved after add-searchpath' % MUESTRA, MUESTRA not in names, str(names))
    check('NoSuchUnitXyz still missing with no candidates',
          'NoSuchUnitXyz' in names and not next((m for m in mu if m.get('unit') == 'NoSuchUnitXyz'), {}).get('sourceFolders'), r)

# a successful build carries no missingUnits
s = open(dpr, encoding='utf-8-sig').read().replace('  ' + USADAS + '\n', '')
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
# El temporal del enlazador (A1 de la 1.27): dcclinux64 graba en el ELF la ruta
# de su fichero temporal (.embarcadero.linkinfo), y con el TEMP del servicio el
# binario del agente llevaba el perfil de su usuario (medido el 3-nov-2026). El
# build le da un TEMP suyo, una carpeta __tmp- dentro de la de sus .dcu, y lo
# quita al acabar. (Aqui BASE cuelga del %TEMP% de la bateria: lo que se mira es
# DONDE esta el temporal, no si la ruta nombra al usuario.)
elf = mc.real(out)
datos = open(elf, 'rb').read() if os.path.isfile(elf) else b''
grabado = re.search(rb'[ -~]{0,240}dtf[0-9A-Fa-f]+\.tmp', datos)
ruta = grabado.group().decode('latin-1') if grabado else ''
carpeta = os.path.dirname(ruta)
check('el ELF graba como temporal una carpeta __tmp- del proyecto, no el TEMP del servidor',
      os.path.basename(carpeta).startswith(mc.DESCARGA_PREFIJO)
      and any(carpeta.lower().startswith(b.lower()) for b in (mc.larga(BASE), mc.corta(BASE)) if b), ruta)
quedan = glob.glob(os.path.join(BASE, '**', mc.DESCARGA_PREFIJO + '*'), recursive=True)
check('...y esa carpeta no queda tras el build', not quedan, quedan)

# --- BUILD-042: una unit del PROPIO workspace (3-oct-2026) ---------------------
# solo se buscaba en la zona de biblioteca: una unit de una carpeta vendor del
# proyecto (MCPServer.Types) salia sin ningun candidato. Y la copia de la
# papelera del servidor no es un candidato
VEND = os.path.join(BASE, 'vendor')
os.makedirs(VEND, exist_ok=True)
UNIDAD = 'unit UVendorX;\n\ninterface\n\nfunction Dame: Integer;\n\nimplementation\n\nfunction Dame: Integer;\nbegin\n  Result := 1;\nend;\n\nend.\n'
open(os.path.join(VEND, 'UVendorX.pas'), 'w', encoding='utf-8').write(UNIDAD)
PAPELERA = os.path.join(BASE, mc.PAPELERA, '20261004')
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
      not any(mc.PAPELERA in d for d in uv.get('sourceFolders', [])), json.dumps(uv)[:300])

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
