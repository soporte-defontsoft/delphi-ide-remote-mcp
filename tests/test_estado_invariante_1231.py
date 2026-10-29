# -*- coding: utf-8 -*-
"""1.23.1 (V121) - the state= of delphi_designer preview reads a number as a
form writes it, whatever the machine's locale. The helper applied it with
SetPropValue, which converts the text through a Variant with the USER's
locale: on a Spanish Windows (decimal comma) Position.X=10.5 was 105, and
100.5 put the control outside the capture (CAPT-007). Measured on 28-oct-2026
against the build of V150 (5931938), es-ES. The reader is
Lsp.DesignerForma.LeeFlotanteDeForm, the inverse of FlotanteDeForm (the RTL's
form parser: decimal point always, the s/c/d suffix, the sign in front).

  E1 state=Rect1.Position.X=100.5 on an FMX form: the rectangle is drawn at
     x=100 (componentRect), not at 1005
  E2 a negative one, Position.Y=-0.5 with the rectangle at y=10: drawn at y 0
     or -1, not at -5
  E3 control: an integer, Position.X=30, at 30
  E4 (V173k) Opacity=0,5 - a number the form parser does not read (a comma):
     refused (RENDER-024), not drawn through the user's locale; designer set
     refuses the same value (DSGN-092). RED against 1d746fd on es-ES

E1 and E2 are RED against the build before ONLY where the decimal separator
is not '.' (this machine: es-ES); E3 is green with both, everywhere.

Usage:  python tests/test_estado_invariante_1231.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('estado1231')
EXE = mc.copia_exe(BASE, con_render=True)  # el renderizador que acompana al exe bajo prueba
S = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='estado1231', t=600)

D = os.path.join(BASE, 'fmx')
r = S.call('delphi_create', {'kind': 'project-fmx', 'name': 'Est', 'dir': D})
check('preparacion: el FMX', not mc.fallo(r), r[:200])
FMX = os.path.join(D, 'UMain.fmx')
r = S.call('delphi_designer', {'command': 'insert', 'path': FMX, 'classname': 'TRectangle', 'component': 'Rect1'})
check('preparacion: un TRectangle en 10,10', not mc.fallo(r), r[:200])


def rect(estado):
    """componentRect del preview de Rect1 con ese state: (x, y) o None (y la respuesta)."""
    j = mc.como_json(S.call('delphi_designer', {'command': 'preview', 'path': FMX, 'component': 'Rect1',
                                                'state': estado, 'inline': False, 'out': os.path.join(BASE, 'cap')
                                                + os.sep}, 300)) or {}
    try:
        x, y = [int(v) for v in j['componentRect'].split(',')[:2]]
        return (x, y), j
    except (KeyError, ValueError):
        return None, j


p, j = rect('Rect1.Position.X=100.5')
check('E1 Position.X=100.5: dibujado en x=100, no en 1005', p is not None and p[0] in (100, 101), (p, str(j)[:300]))
p, j = rect('Rect1.Position.Y=-0.5')
check('E2 Position.Y=-0.5: dibujado en y 0 o -1, no en -5', p is not None and p[1] in (0, -1), (p, str(j)[:300]))
p, j = rect('Rect1.Position.X=30')
check('E3 control: Position.X=30 en x=30', p is not None and p[0] == 30, (p, str(j)[:300]))
r = S.call('delphi_designer', {'command': 'preview', 'path': FMX, 'component': 'Rect1', 'state': 'Rect1.Opacity=0,5',
                               'inline': False, 'out': os.path.join(BASE, 'cap') + os.sep}, 300)
check('E4 (V173k) Opacity=0,5: negado (RENDER-024), no pintado por el locale',
      mc.abre(r, 'SR_RENDER_ESTADO_FLOTANTE_FMT') and 'componentRect' not in r, r[:300])

S.cierra()
mc.borra(BASE)
mc.fin('estado-invariante-1231 battery')
