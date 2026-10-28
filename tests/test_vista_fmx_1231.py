# -*- coding: utf-8 -*-
"""1.23.1 (V122) - an FMX view (<unit>.<View>.fmx) is a form of its MASTER's
unit, as the IDE writes it: the master's .pas declares it with
{$R *.<View>.fmx ...}, and its root is a class the IDE makes up
(inherited FormMain_Windows: TFormMain_Windows, as in the Samples). The
server looked for <unit>.<View>.pas and judged the view against that made-up
class. Measured on 28-oct-2026 against the build of V121 (a9d6e81):

  V1 check-binding of a view: DSGN-023 (no UMain.Windows.pas); now it is
     judged against the master's class, TFormMain, and comes out clean
  V2 insert into a view: DSGN-076 ("has the name of the form file"); now the
     component lands in the view and its field in TFormMain, in UMain.pas
  V3 moving UMain.pas alone warned only about UMain.fmx; now also about the
     view it declares (FILE-051)
  V4 control: a form whose name has a dot but that no unit declares
     (UMain.Copia.fmx) is still a form of its own name: DSGN-023

V1-V3 are RED against the build before (pass its exe as argument); V4 is
green with both. The judge is the directive (Lsp.DesignerForma.VistasDeUnidad,
the same one the renderer reads the view with).

Usage:  python tests/test_vista_fmx_1231.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('vista1231')
EXE = mc.copia_exe(BASE, con_render=True)
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='vista1231', t=600)

D = os.path.join(BASE, 'vis')
r = S.call('delphi_create', {'kind': 'project-fmx', 'name': 'Vis', 'dir': D})
check('preparacion: el FMX', not mc.fallo(r), r[:200])
PAS, VISTA, COPIA = (os.path.join(D, n) for n in ('UMain.pas', 'UMain.Windows.fmx', 'UMain.Copia.fmx'))
# la directiva de la vista en la unidad del maestro y la vista, como las escribe el IDE
t = open(PAS, 'rb').read().decode('utf-8-sig')
check('preparacion: la unidad tiene su {$R *.fmx}', '{$R *.fmx}' in t, t[:300])
t = t.replace('{$R *.fmx}', '{$R *.fmx}\r\n{$R *.Windows.fmx MSWINDOWS}', 1)
open(PAS, 'wb').write(b'\xef\xbb\xbf' + t.encode('utf-8'))
for ruta, raiz in ((VISTA, 'FormMain_Windows: TFormMain_Windows'), (COPIA, 'FormMain_Copia: TFormMain_Copia')):
    open(ruta, 'wb').write(b'\xef\xbb\xbf' + ('inherited %s\r\n  DesignerMasterStyle = 0\r\nend\r\n' % raiz).encode('utf-8'))

# ---------------------------------------------------------------- V1
j = mc.como_json(S.call('delphi_designer', {'command': 'check-binding', 'path': VISTA})) or {}
check('V1 check-binding de la vista: contra la clase del maestro (TFormMain), limpio',
      j.get('class') == 'TFormMain' and j.get('clean') is True, str(j)[:300])

# ---------------------------------------------------------------- V2
r = S.call('delphi_designer', {'command': 'insert', 'path': VISTA, 'classname': 'TRectangle', 'component': 'RectVista'})
vista = open(VISTA, 'rb').read().decode('utf-8-sig')
pas = open(PAS, 'rb').read().decode('utf-8-sig')
clase = pas[pas.find('TFormMain = class'):pas.find('private')]
check('V2 insert en la vista: el bloque en la vista y el campo en TFormMain (UMain.pas)',
      not mc.fallo(r) and 'object RectVista: TRectangle' in vista and 'RectVista: TRectangle;' in clase,
      (r[:200], clase))

# ---------------------------------------------------------------- V4 (antes de mover: el maestro, presente)
r = S.call('delphi_designer', {'command': 'check-binding', 'path': COPIA})
check('V4 control: un form con punto que ninguna unidad declara sigue buscando la suya (DSGN-023)',
      mc.abre(r, 'SR_DESIGNER_NO_UNIT_FMT'), r[:200])

# ---------------------------------------------------------------- V3
OTRA = os.path.join(BASE, 'otra')
r = S.call('delphi_move', {'path': PAS, 'dest': os.path.join(OTRA, 'UMain.pas')})
avisos = [l for l in r.splitlines() if mc.abre(l, 'SN_FILE_PAR_PARTIDO_FMT')]
check('V3 mover UMain.pas solo avisa tambien de la vista que declara (UMain.Windows.fmx)',
      any('UMain.Windows.fmx' in l for l in avisos) and any('UMain.fmx' in l for l in avisos), r[:600])

S.cierra()
mc.borra(BASE)
mc.fin('vista-fmx-1231 battery')
