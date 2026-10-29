# -*- coding: utf-8 -*-
"""El Library Search Path del IDE de una plataforma cuya CLAVE del registro no es su nombre (V198 de la
1.23.1, revisor del paisaje del 29-oct).

El IDE guarda el Library de la plataforma Android (32 bits) bajo la clave Library\\Android32; el .dproj,
msbuild, los .sdk y la carpeta lib\\android la llaman Android. El lector de esa lista
(Lsp.Discovery.IdePlatformLibraryPaths) componia la clave con el nombre que le daban y ponia $(Platform) a
ese nombre: preguntado por Android leia Library\\Android (no existe: 0 carpetas), y preguntado por la
clave expandia $(BDSLIB)\\$(PLATFORM)\\Release a lib\\Android32\\Release, que no existe. delphi_components
platform=Android decia "0 registered folders" y listaba lo de Android32 como "NOT on Android". El juez es
el registro del IDE (sus claves) y la regla, el lector que ya habia (PlataformaDeClaveLibrary) y su inversa.

  L1 platform=Android: tantas carpetas como trozos completos del Search Path de la clave Android32 del
     registro (ROJA contra 283f3f2: 0)
  L2 platform=Android: $(Platform) vale Android: sale lib\\android\\release y no lib\\Android32 (ROJA)
  L3 platform=Android: ninguna carpeta "registered in: Android32" (lo de su propia clave no es de otra
     plataforma; ROJA)
  L4 la vista filter: las plataformas por su NOMBRE (Android), no por la clave (ROJA: Android32)
  L5 (control) platform=Win64: sus carpetas, con lib\\Win64\\Release

Sin la clave Android32 en el registro de esta maquina no se mide (NOTA).

Uso:  python tests/test_library_plataforma_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import re
import sys
import winreg
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None


def search_path(clave):
    """El Search Path de Library\\<clave> del IDE de este servidor ('' sin la clave)."""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'SOFTWARE\Embarcadero\BDS\37.0\Library\%s' % clave) as k:
            return winreg.QueryValueEx(k, 'Search Path')[0]
    except OSError:
        return ''


ANDROID32 = search_path('Android32')
if not ANDROID32:
    print('NOTA: sin Library\\Android32 en el registro de esta maquina: L1-L4 no se miden')
    sys.exit(0)
# los trozos que el lector da: los completos (sin un macro que el no conozca se quedan los demas)
ESPERADAS = len([t for t in ANDROID32.split(';') if t.strip()])

BASE = mc.carpeta('library_plataforma_1231')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='library-plataforma', t=120)
try:
    r = srv.call('delphi_components', {'platform': 'Android'})
    cab = r.splitlines()[0] if r else ''
    n = int(cab.split(':')[-1].split()[0]) if 'registered folders' in cab else -1
    check('L1 platform=Android: las carpetas de la clave Android32 del IDE (%d trozos en el registro)' % ESPERADAS,
          mc.es(r, 'SN_COMPONENTS_PLATFORM_HEAD_FMT') and 0 < n <= ESPERADAS, cab)
    check('L2 platform=Android: $(Platform) vale Android (lib\\android\\release, ningun lib\\Android32)',
          'lib\\android\\release' in r.lower() and '\\lib\\android32' not in r.lower(), r[:600])
    check('L3 platform=Android: nada de su propia clave sale como de otra plataforma (registered in: Android32)',
          not any('Android32' in e for e in re.findall(r'\(registered in: ([^)]*)\)', r)), r[:900])
    r = srv.call('delphi_components', {'filter': 'LockBox'})
    check('L4 filter: las plataformas por su nombre (Android), no por la clave del registro (Android32)',
          'Android64' in r and not any('Android32' in e for e in re.findall(r'\(registered in: ([^)]*)\)', r))
          and 'Android,' in r.replace('Android64', ''), r[-700:])
    r = srv.call('delphi_components', {'platform': 'Win64'})
    check('L5 control: platform=Win64 da sus carpetas, con lib\\Win64\\Release',
          mc.es(r, 'SN_COMPONENTS_PLATFORM_HEAD_FMT') and 'lib\\win64\\release' in r.lower(), r[:400])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('el Library del IDE de una plataforma cuya clave no es su nombre 1231 (V198)')
