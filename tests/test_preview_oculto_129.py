# -*- coding: utf-8 -*-
"""1.29 (dirigido de Hermes): el renderizador VCL pinta un control con Visible = False igual en sus dos captores,
como el disenador del IDE. En diseno la VCL MUESTRA los ocultos (Vcl.Controls: UpdateShowing y AlignControls con
csDesigning, salvo csNoDesignVisible), y window los pintaba; print, el de un servicio, recorria las ventanas hijas
por Visible y se los saltaba (medido el 8-nov-2026: el panel oculto rojo en window, blanco en print). Hermes lo vio
en la VM (window) y aqui, en el servicio (print), no salia: el mismo form daba dos imagenes. print pregunta ahora a
Showing, el juez de la VCL. FMX no muestra los ocultos en diseno (TControl.ShowInDesigner) y no cambia.

  V1 print: el panel oculto (rojo) se pinta. ROJO contra 28ddda3f (blanco)
  V2 window: lo mismo (lo que ya hacia; el juez de los dos)
  V3 control: el panel visible (azul) en los dos

Uso:  python tests/test_preview_oculto_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('preview_oculto_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
RENDER = os.path.join(os.path.dirname(EXE), 'DelphiFormRenderVcl.exe')
F = os.path.join(BASE, 'form')
os.makedirs(F)
with open(os.path.join(F, 'UO.pas'), 'w', newline='') as f:
    f.write('unit UO;\r\n\r\ninterface\r\n\r\nuses\r\n  Vcl.Forms, Vcl.ExtCtrls, Vcl.Controls, System.Classes;\r\n\r\n'
            'type\r\n  TUO = class(TForm)\r\n    Rojo: TPanel;\r\n    Azul: TPanel;\r\n  end;\r\n\r\nimplementation\r\n\r\n'
            '{$R *.dfm}\r\n\r\nend.\r\n')
with open(os.path.join(F, 'UO.dfm'), 'w', newline='') as f:
    f.write('object UO: TUO\r\n  Left = 0\r\n  Top = 0\r\n  ClientHeight = 100\r\n  ClientWidth = 200\r\n  Color = clWhite\r\n'
            '  object Rojo: TPanel\r\n    Left = 20\r\n    Top = 20\r\n    Width = 80\r\n    Height = 50\r\n    Color = clRed\r\n'
            '    ParentBackground = False\r\n    TabOrder = 0\r\n    Visible = False\r\n  end\r\n'
            '  object Azul: TPanel\r\n    Left = 120\r\n    Top = 20\r\n    Width = 60\r\n    Height = 50\r\n    Color = clBlue\r\n'
            '    ParentBackground = False\r\n    TabOrder = 1\r\n  end\r\nend\r\n')


def pinta(fidelidad):
    """(oculto, visible): el color en el centro de cada panel, o (None, salida) si no hay imagen."""
    out = os.path.join(F, fidelidad + '.png')
    u = subprocess.run([RENDER, '--path', os.path.join(F, 'UO.dfm'), '--out', out, '--root', 'form',
                        '--fidelity', fidelidad, '--style', 'none', '--timeout', '20000'],
                       capture_output=True, timeout=120, cwd=F)
    if not os.path.exists(out):
        return None, u.stdout.decode('utf-8', 'replace')[-400:]
    _, _, px = mc.png_pixeles(out)
    return px(60, 45), px(150, 45)


try:
    p_oculto, p_visible = pinta('print')
    w_oculto, w_visible = pinta('window')
    check('V1 print: el panel oculto se pinta, como en el disenador (rojo). ROJO contra 28ddda3f',
          p_oculto == (255, 0, 0), (p_oculto, p_visible))
    check('V2 window: lo mismo', w_oculto == (255, 0, 0), (w_oculto, w_visible))
    check('V3 control: el panel visible, azul en los dos', p_visible == (0, 0, 255) and w_visible == (0, 0, 255),
          (p_visible, w_visible))
finally:
    mc.borra(BASE)
mc.fin('el panel oculto, igual en print y en window (1.29)')
