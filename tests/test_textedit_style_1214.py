# -*- coding: utf-8 -*-
r"""delphi_textedit sobre un .style pregunta a FMX despues de escribir (1.21.4). Hasta
ahora solo delphi_styles set preguntaba (STYLE-053, antes de escribir); un .style creado o
editado por textedit con un valor que FMX no lee salia OK y solo lint lo veia despues
(Hermes, rondas de la 1.21.0).

  T1  create de un .style con TextSettings.FontColor = $FFFF0000 (FMX no lo carga):
      escrito, y la nota STYLE-055 con el error del lector de FMX
  T2  edit que lo arregla (xFFFF0000): escrito y SIN la nota
  T3  edits (la tanda) que lo vuelve a romper: la nota otra vez
  T4  control: un .txt con lo mismo no pregunta a FMX (sin nota)

T1 y T3 son ROJAS contra 1.21.3. Necesita DelphiStyleConvert.exe junto al exe bajo prueba
(con_conversor).

Uso:  python tests/test_textedit_style_1214.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('textedit-style')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='tes', t=120)
MALO = ("object TStyleContainer\r\n"
        "  object TText\r\n"
        "    StyleName = 'rotulo'\r\n"
        "    TextSettings.FontColor = $FFFF0000\r\n"
        "  end\r\n"
        "end\r\n")

try:
    sty = os.path.join(BASE, 'Roto.style')
    r = srv.call('delphi_textedit', {'path': sty, 'create': True, 'content': MALO})
    check('T1 create de un .style que FMX no carga: escrito y la nota STYLE-055',
          not mc.rechazado(r) and os.path.isfile(sty) and mc.es(r, 'SN_TEXTEDIT_STYLE_FMX_NO_CARGA_FMT'), r[:400])
    r = srv.call('delphi_textedit', {'path': sty, 'old': "    TextSettings.FontColor = $FFFF0000",
                                     'new': "    TextSettings.FontColor = xFFFF0000"})
    check('T2 edit que lo arregla: escrito y sin la nota', not mc.rechazado(r) and 'STYLE-055' not in r, r[:300])
    r = srv.call('delphi_textedit', {'path': sty, 'edits': [{'old': "    TextSettings.FontColor = xFFFF0000",
                                                             'new': "    TextSettings.FontColor = $FFFF0000"}]})
    check('T3 edits (la tanda) que lo rompe otra vez: la nota', not mc.rechazado(r) and 'STYLE-055' in r, r[:300])
    txt = os.path.join(BASE, 'Roto.txt')
    r = srv.call('delphi_textedit', {'path': txt, 'create': True, 'content': MALO})
    check('T4 control: un .txt con lo mismo no pregunta a FMX', not mc.rechazado(r) and 'STYLE-055' not in r, r[:200])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('textedit style 1214')
