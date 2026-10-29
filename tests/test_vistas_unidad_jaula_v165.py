# -*- coding: utf-8 -*-
"""V165 (1.23.1): a unit's "view" (VistasDeUnidad, V122) is a bare name, not a
path.

A {$R *.<X>.fmx} directive declares a companion form. VistasDeUnidad composed
Base + '.' + Resto with Resto taken from the directive text, and a Resto with
path separators ('*.\\..\\..\\fuera\\x.fmx') built a path OUTSIDE the unit's
folder. The consumers (AvisosDelPar on delete/move, InspectUnit, Patch,
DesignerBinding, Config) then TFile.Exists it and name it: an oracle of
existence for a .fmx outside the jail. Now a view is kept only when
ExtractFileName(Resto) = Resto (a bare name, no separators, no '..').

The unit root (X:\\) is OUTSIDE the jail (X:\\proj) and INSIDE the battery
folder: a subst unit over a temp folder, so nothing is written outside it.

  V1 a .pas with {$R *.\\..\\..\\Evil.fmx} and Evil.fmx planted OUTSIDE the
     jail: delete it; the companion note does NOT name the outside .fmx (RED
     against 06f59ce: it names Evil.fmx, the path-traversed view)
  V2 (control) a legit {$R *.Windows.fmx} companion inside the jail is still
     named on delete
  V3 (V165b) the same traversal with '/' ({$R *./../../Evil.fmx}): not named
     either. The first judge, ExtractFileName(Resto) = Resto, only splits on
     '\\' and ':' on Windows, and '/' named Evil.fmx (RED against 13f78f3);
     the judge is Windows now (the composed view resolves in the unit's folder)

Usage:  python tests/test_vistas_unidad_jaula_v165.py [path-to-DelphiLspMcp.exe]
"""
import atexit, os, subprocess, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('vistas_unidad_v165')
UNI = os.path.join(BASE, 'unidad')
os.makedirs(UNI)
L = mc.letras_libres(1)[0]
_r = subprocess.run(['subst', L + ':', UNI], capture_output=True, text=True)
assert _r.returncode == 0 and os.path.isdir(L + ':\\'), _r.stdout + _r.stderr
atexit.register(lambda: subprocess.run(['subst', L + ':', '/d'], capture_output=True))
X = L + ':\\'
J = os.path.join(X, 'proj')          # la jaula; X:\ (la raiz) queda FUERA
os.makedirs(J)
# un .fmx FUERA de la jaula, al que apunta la travesia (X:\proj\UMain + .\..\..\ = X:\)
open(os.path.join(X, 'Evil.fmx'), 'w', newline='\r\n').write('object Evil: TForm\r\nend\r\n')


def unidad(nombre, resto):
    p = os.path.join(J, nombre + '.pas')
    open(p, 'w', newline='\r\n').write(
        'unit %s;\r\ninterface\r\nimplementation\r\n{$R *.%s}\r\nend.\r\n' % (nombre, resto))
    return p


S = mc.Stdio(mc.copia_exe(os.path.join(BASE, 's'), src=exe_src),
             mc.entorno({'DELPHI_MCP_ROOTS': J}), nombre='v165', t=300)
try:
    # V1: la travesia a un .fmx de fuera
    p1 = unidad('UMain', '\\..\\..\\Evil.fmx')
    r = S.call('delphi_delete', {'path': p1})
    check('V1 borrar un .pas con {$R *.\\..\\..\\Evil.fmx}: el aviso de pareja NO nombra el .fmx de fuera',
          'Evil' not in r and 'Evil.fmx' not in r, r[:300])

    # V2 control: una vista legitima dentro de la jaula sigue avisandose
    # V3 (V165b): la misma travesia con '/', que Windows resuelve y ExtractFileName no veia
    p3 = unidad('UBarra', '/../../Evil.fmx')
    r3 = S.call('delphi_delete', {'path': p3})
    check('V3 borrar un .pas con {$R *./../../Evil.fmx}: el aviso de pareja NO nombra el .fmx de fuera',
          'Evil' not in r3 and mc.abre(r3, 'SK_FILE_BORRADO_PAPELERA_FMT'), r3[:300])

    p2 = unidad('UOtra', 'Windows.fmx')
    open(os.path.join(J, 'UOtra.Windows.fmx'), 'w', newline='\r\n').write('object W: TForm\r\nend\r\n')
    r2 = S.call('delphi_delete', {'path': p2})
    check('V2 control: una vista legitima (UOtra.Windows.fmx) dentro de la jaula si se nombra al borrar',
          'UOtra.Windows.fmx' in r2, r2[:300])
finally:
    S.cierra()
    subprocess.run(['subst', L + ':', '/d'], capture_output=True)
    mc.borra(BASE)

mc.fin('V165 vistas de unidad jail battery')
