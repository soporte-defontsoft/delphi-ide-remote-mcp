# -*- coding: utf-8 -*-
"""1.23.1 (V114) - a tree of CODE is walked by one walker that does not go
into what is not code below the folder it walks (WalkBajoLaRaiz: WalkFiles
pruned by SkipBajoLaRaiz - build output, the IDE's history, .git, the trash).
Nine readers wrote the walk and then the filter by hand, and two forgot it.
Measured on 28-oct-2026 against the build of V110 (0a35c2a):

  W1 the project of a unit was the day's copy in the trash: a .dpr and its
     .dproj that list U by an ABSOLUTE path, remove-unit (which leaves the
     copy of both, from before the change, in app\\__delphi-patch\\<day>), and
     delphi_diagnostics linted U with app\\__delphi-patch\\<day>\\App.dproj -
     the walk below a level went into the trash and FindDproj did not filter
     it. Control: before the remove-unit, App itself.
  W2 delphi_test discover under an ancestor named Release found no project
     (SkipIdeArtifacts on the ABSOLUTE path); control: the same under Otra
  W3 delphi_package under an ancestor named dcu packed nothing ('\\dcu\\' on the
     absolute path); a dcu\\ BELOW the folder is still left out (control)
  W4 control of the readers that filtered by hand and now walk pruned:
     delphi_symbols of a folder shows its own unit and not the ones in its
     Win64\\ or in its trash

W1-W3 are RED against the build before (pass its exe as argument); W4 is
green with both.

Usage:  python tests/test_paseo_codigo_1231.py [path-to-DelphiLspMcp.exe]
"""
import os, zipfile
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('paseo1231')
EXE = mc.copia_exe(BASE)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA)
ENV = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA})
S = mc.Stdio(EXE, ENV, nombre='paseo1231', t=600)

UNIDAD = 'unit %s;\ninterface\nprocedure P;\nimplementation\nprocedure P; begin end;\nend.\n'


def escribe_unidad(ruta, nombre):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'w', newline='\r\n').write(UNIDAD % nombre)


def reescribe(ruta, viejo, nuevo):
    """Cambia viejo por nuevo UNA vez en un fichero de texto, con su BOM si lo tiene
    (a mano: sin la copia del dia que dejaria una tool)."""
    crudo = open(ruta, 'rb').read()
    bom = crudo.startswith(b'\xef\xbb\xbf')
    t = crudo.decode('utf-8-sig')
    assert viejo in t, (ruta, t[:300])
    t = t.replace(viejo, nuevo, 1)
    open(ruta, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + t.encode('utf-8'))


def diag(ruta):
    r = ''
    for _ in range(8):
        r = S.call('delphi_diagnostics', {'path': ruta}, 300)
        if '"in-progress"' not in r:
            break
    return mc.como_json(r) or {'crudo': r}


def proyecto_de(ruta):
    """El proyecto con el que diagnostics linto esa unidad, en su forma real y
    larga ('' si no linto: su negativa va en el crudo)."""
    d = diag(ruta)
    return os.path.normcase(mc.larga(mc.real(d.get('project', '')))) if d.get('project') else '', d


# ---------------------------------------------------------------- W1
P = os.path.join(BASE, 'w1', 'P')
APP = os.path.join(P, 'app')
r = S.call('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': APP})
check('W1 preparacion: la consola App', not mc.fallo(r), r[:200])
DPROJ = os.path.join(APP, 'App.dproj')
U = os.path.join(P, 'shared', 'U.pas')
escribe_unidad(U, 'U')
# el .dpr y el .dproj la nombran por su ruta ABSOLUTA, escritos a mano: la
# primera edicion del dia sera el remove-unit, y su copia aun la listara
reescribe(os.path.join(APP, 'App.dpr'), 'System.SysUtils;', "System.SysUtils,\r\n  U in '%s';" % U)
reescribe(DPROJ, '</DelphiCompile>', '</DelphiCompile>\r\n        <DCCReference Include="%s"/>' % U)
p, d = proyecto_de(U)
check('W1 control: App, que la lista, es su proyecto', p == os.path.normcase(mc.larga(DPROJ)), (p, str(d)[:200]))
r = S.call('delphi_config', {'command': 'remove-unit', 'project': DPROJ, 'path': U})
check('W1 preparacion: remove-unit', mc.abre(r, 'SN_UNIT_REMOVED_FMT') or not mc.fallo(r), r[:200])
copias = [os.path.join(raiz, f) for raiz, _, fs in os.walk(APP) if mc.PAPELERA.lower() in raiz.lower() for f in fs]
nombres = sorted(os.path.basename(c).lower() for c in copias)
check('W1 preparacion: la papelera tiene la copia del dia del .dpr y del .dproj, y la del .dpr aun lista U',
      nombres == ['app.dpr', 'app.dproj'] and
      any(c.lower().endswith('.dpr') and 'U in' in open(c, 'rb').read().decode('utf-8-sig', 'replace')
          for c in copias), nombres)
p, d = proyecto_de(U)
check('W1 tras el remove-unit, su proyecto no es la copia de la papelera: ninguno la sirve (LSP-035)',
      p == '' and mc.abre(d.get('crudo', ''), 'SR_LSP_LINT_SIN_AJUSTES_FMT'), (p, str(d)[:200]))

# ---------------------------------------------------------------- W2
for nombre in ('Release', 'Otra'):
    DT = os.path.join(BASE, 'w2', nombre, 't')
    r = S.call('delphi_create', {'kind': 'project-test', 'name': 'PT', 'dir': DT})
    check('W2 preparacion: un proyecto de test bajo %s' % nombre, not mc.fallo(r), r[:200])
    pr = [x for x in mc.ficheros(S.call('delphi_test', {'command': 'discover', 'path': DT}), 'projects')
          if os.path.basename(mc.real(x.get('path', ''))).lower() == 'pt.dpr']
    check('W2 discover bajo un antepasado llamado %s: encuentra su proyecto%s' % (
        nombre, '' if nombre == 'Release' else ' (control)'), len(pr) == 1, pr)

# ---------------------------------------------------------------- W3
for nombre in ('dcu', 'nodcu'):
    PK = os.path.join(BASE, 'w3', nombre, 'pk')
    os.makedirs(os.path.join(PK, 'dcu'))
    open(os.path.join(PK, 'leeme.txt'), 'w').write('hola\n')
    open(os.path.join(PK, 'App.exe'), 'wb').write(b'MZ' + b'\0' * 64)
    open(os.path.join(PK, 'dcu', 'dentro.txt'), 'w').write('no va\n')
    r = S.call('delphi_package', {'dir': PK})
    z = os.path.join(BASE, 'w3', nombre, 'pk-deploy.zip')
    dentro = sorted(n.replace('\\', '/').lower() for n in zipfile.ZipFile(z).namelist()) if os.path.isfile(z) else None
    check('W3 package bajo un antepasado llamado %s: lo suyo entra y su dcu\\ de debajo no%s' % (
        nombre, '' if nombre == 'dcu' else ' (control)'),
        dentro == ['app.exe', 'leeme.txt'], (dentro, r[:200]))

# ---------------------------------------------------------------- W4
F4 = os.path.join(BASE, 'w4', 'f')
escribe_unidad(os.path.join(F4, 'UPropia.pas'), 'UPropia')
escribe_unidad(os.path.join(F4, 'Win64', 'USalida.pas'), 'USalida')
escribe_unidad(os.path.join(F4, mc.PAPELERA, 'dia', 'UCopia.pas'), 'UCopia')
r = S.call('delphi_symbols', {'path': F4}, 300)
vistas = sorted(os.path.basename(mc.real(u['path'])).lower() for u in mc.ficheros(r, 'units'))
check('W4 control: symbols de una carpeta ensena su unidad y no las de Win64\\ ni las de la papelera',
      vistas == ['upropia.pas'], (vistas, r[:300]))

S.cierra()
mc.borra(BASE)
mc.fin('paseo-codigo-1231 battery')
