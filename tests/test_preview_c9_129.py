# -*- coding: utf-8 -*-
"""C9 de la lista de cierre 1.29: print (WM_PRINT, el de un servicio) contra window (la ventana pintada de verdad,
el juez: lo que ensena el disenador del IDE), pixel a pixel, en los 355 .dfm de los Samples con el renderizador a
pelo (9-nov-2026). 257 iguales, 89 distintos y 9 que no se pintaban en ninguno de los dos. De ahi, dos fallos:

  - un form con FormStyle = fsMDIChild no se pintaba NUNCA, ni por el servidor (DSGN-061 "Cannot hide an MDI Child
    Form", echandole la culpa a un paquete). Esconde hacia AForm.Visible := False con la imagen ya hecha, y la VCL
    niega esconder un hijo MDI sin padre (TCustomForm.VisibleChanging, sin mirar csDesigning: Vcl.Forms 6266). La
    ventana se esconde ahora a mano, como Muestra la ensena.
  - print, en el SERVICIO (sesion 0), no pintaba el texto de ayuda (TextHint) de un edit o un combo vacio: alli
    Windows calla el texto entero de esos controles y DibujaTextoCallado pintaba solo Text (medido el 9-nov por el
    servicio de produccion: el edit y el combo vacios, en blanco). Ahora, vacio, su pista en gris. Eso NO se ve
    desde aqui (una bateria es sesion interactiva, donde Windows pinta el texto y la pista del edit el mismo y
    DibujaTextoCallado no entra): se mide en el servicio tras desplegar. Aqui, el juez (window) y lo que ya
    funcionaba. TMemo no publica TextHint (DSGN-114) y Windows no pone pista a un edit de varias lineas.

  M1 print: el hijo MDI se pinta (su panel azul). ROJO contra 7e01b8d4
  M2 window: lo mismo. ROJO contra 7e01b8d4
  M3 por el servidor: preview y layout del hijo MDI, sin DSGN-061. ROJO contra 7e01b8d4
  H1 window (el juez): el edit vacio con TextHint lleva tinta, gris; el combo vacio, tambien
  H2 print en una sesion interactiva: el edit vacio con su pista, la que pinta Windows (DibujaTextoCallado no la
     pinta encima: con la ventana visible no entra)
  H4 lo que ya funcionaba: el edit con texto, tinta OSCURA en los dos (el texto, no la pista)

Uso:  python tests/test_preview_c9_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('preview_c9_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
RENDER = os.path.join(os.path.dirname(EXE), 'DelphiFormRenderVcl.exe')
F = os.path.join(BASE, 'form')
os.makedirs(F)


def escribe(nombre, texto):
    with open(os.path.join(F, nombre), 'w', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))


escribe('UMdi.pas', 'unit UMdi;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.ExtCtrls, Vcl.Controls, System.Classes;\n\n'
        'type\n  TUMdi = class(TForm)\n    Azul: TPanel;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n')
escribe('UMdi.dfm', 'object UMdi: TUMdi\n  Left = 0\n  Top = 0\n  ClientHeight = 100\n  ClientWidth = 200\n'
        '  Color = clWhite\n  FormStyle = fsMDIChild\n  Visible = True\n  object Azul: TPanel\n    Left = 60\n'
        '    Top = 20\n    Width = 80\n    Height = 50\n    Color = clBlue\n    ParentBackground = False\n'
        '    TabOrder = 0\n  end\nend\n')
# cuatro controles en fila, 160 de ancho y 23 de alto, a 10 de la izquierda y cada 40 hacia abajo
CONTROLES = [('EVacio', 'TEdit', "    TextHint = 'Pista de prueba'\n"),
             ('ELleno', 'TEdit', "    Text = 'Texto real'\n    TextHint = 'Pista de prueba'\n"),
             ('CVacio', 'TComboBox', "    TextHint = 'Pista de prueba'\n")]
dfm = 'object UHint: TUHint\n  Left = 0\n  Top = 0\n  ClientHeight = 180\n  ClientWidth = 200\n  Color = clBtnFace\n'
for n, (nombre, clase, props) in enumerate(CONTROLES):
    dfm += ('  object %s: %s\n    Left = 10\n    Top = %d\n    Width = 160\n    Height = %d\n%s'
            '    TabOrder = %d\n  end\n' % (nombre, clase, 10 + 40 * n, 33 if clase == 'TMemo' else 23, props, n))
escribe('UHint.dfm', dfm + 'end\n')
escribe('UHint.pas', 'unit UHint;\n\ninterface\n\nuses\n  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;\n\n'
        'type\n  TUHint = class(TForm)\n%s  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n'
        % ''.join('    %s: %s;\n' % (c[0], c[1]) for c in CONTROLES))


def pinta(dfm, fidelidad):
    """(pixel, ancho, alto) del PNG, o (None, salida) si no hay imagen."""
    out = os.path.join(F, '%s_%s.png' % (dfm, fidelidad))
    u = subprocess.run([RENDER, '--path', os.path.join(F, dfm + '.dfm'), '--out', out, '--root', 'form',
                        '--fidelity', fidelidad, '--style', 'none', '--timeout', '20000'],
                       capture_output=True, timeout=120, cwd=F)
    if not os.path.exists(out):
        return None, u.stdout.decode('utf-8', 'replace')[-300:]
    ancho, alto, px = mc.png_pixeles(out)
    return px, (ancho, alto)


def tinta(px, n, derecha=4):
    """Los pixeles con tinta (lejos del blanco del control) dentro del control n, sin su borde ni el boton de un
    combo; y su gris medio (0 negro .. 255 blanco)."""
    y0 = 10 + 40 * n
    alto = 33 if CONTROLES[n][1] == 'TMemo' else 23
    cuenta, suma = 0, 0
    for y in range(y0 + 4, y0 + alto - 4):
        for x in range(10 + 4, 10 + 160 - derecha):
            r, g, b = px(x, y)
            if min(r, g, b) < 200:
                cuenta += 1
                suma += (r + g + b) // 3
    return cuenta, (suma // cuenta if cuenta else 255)


try:
    vistos = {}
    for fid in ('print', 'window'):
        px, info = pinta('UMdi', fid)
        vistos[fid] = (px(100, 45) if px else None, info)
    check('M1 print: el hijo MDI se pinta, su panel azul. ROJO contra 7e01b8d4',
          vistos['print'][0] == (0, 0, 255), vistos['print'])
    check('M2 window: lo mismo. ROJO contra 7e01b8d4', vistos['window'][0] == (0, 0, 255), vistos['window'])

    srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': F}), nombre='c9', t=180)
    try:
        r = srv.call('delphi_designer', {'command': 'preview', 'path': os.path.join(F, 'UMdi.dfm'),
                                         'out': os.path.join(F, 'srv.png'), 'inline': False}, t=180)
        r2 = srv.call('delphi_designer', {'command': 'layout', 'path': os.path.join(F, 'UMdi.dfm')}, t=180)
        cajas = {b.get('name') for b in (mc.como_json(r2).get('boxes') or [])}
        check('M3 por el servidor: preview y layout del hijo MDI, sin DSGN-061. ROJO contra 7e01b8d4',
              os.path.exists(os.path.join(F, 'srv.png')) and not mc.es(r + r2, 'SR_DESIGNER_RENDER_FALLO_FMT')
              and 'Azul' in cajas,
              (r[:300], r2[:300]))
    finally:
        srv.cierra()

    hp, hinfo = pinta('UHint', 'print')
    hw, winfo = pinta('UHint', 'window')
    if hp is None or hw is None:
        check('H0 el form de las pistas se pinta en los dos', False, (hinfo, winfo))
    else:
        w0, p0 = tinta(hw, 0), tinta(hp, 0)
        w2 = tinta(hw, 2, derecha=24)
        check('H1 window (el juez): el edit vacio con TextHint lleva tinta, gris; el combo vacio, tambien',
              w0[0] > 30 and w0[1] > 60 and w2[0] > 30, (w0, w2))
        check('H2 print interactivo: el edit vacio con su pista, la de Windows', p0[0] > 30 and p0[1] > 60, (p0, w0))
        w1, p1 = tinta(hw, 1), tinta(hp, 1)
        check('H4 lo que ya funcionaba: el edit con texto, tinta OSCURA en los dos (el texto, no la pista)',
              w1[0] > 30 and p1[0] > 30 and w1[1] < p0[1] and p1[1] < p0[1], (p1, w1, p0))
finally:
    mc.borra(BASE)
mc.fin('C9: print contra window, el hijo MDI y el texto de ayuda (1.29)')
