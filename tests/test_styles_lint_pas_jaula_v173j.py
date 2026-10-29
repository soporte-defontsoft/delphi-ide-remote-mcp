# -*- coding: utf-8 -*-
"""V173j (1.23.1): delphi_styles lint lee el designer de un .pas por la puerta de leer.

El lint recorre el proyecto y cada .fmx/.pas pasa por la puerta (ReadPathDenied) antes de
leerse: uno que niega se salta. Pero el codigo de una unidad (StyleLookup := '...') pregunta a
SU designer si toma sus estilos de un StyleBook (V153), y ese designer se leia sin preguntar
antes y sin try: un UMain.fmx que es un enlace duro (la puerta lo niega, GUARD-042) hacia saltar
la negativa del lector como excepcion y el lint de TODO el proyecto salia GUARD-042 (medido
contra 9aeba62; sin el StyleLookup en el codigo, el mismo proyecto daba su lint). Oraculo no
habia: el lector pasa por la puerta. Ahora un designer que la puerta niega, o que no se deja
leer, no se lee: su codigo no se juzga y la form va aparte, como una cuyo StyleBook no se lee.

  J0 preparacion: los dos enlaces duros a fuera se pudieron crear
  J3 el lint contesta (no GUARD-042 del proyecto entero) (ROJA contra 9aeba62)
  J1 la respuesta para UMain es la MISMA con el enlace a un form de fuera sin StyleBook que con
     uno con StyleBook (guarda: no depende de lo de fuera)
  J2 ...y es la de un form que no se lee: 'nada' no se da por falta, la form va aparte (ROJA)
  C1 (control) un UMain.fmx de VERDAD (sin enlace) y sin StyleBook: 'nada' sale sin estilo

Uso:  python tests/test_styles_lint_pas_jaula_v173j.py [ruta-a-DelphiLspMcp.exe]
"""
import ctypes, os, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('styles_lint_pas_v173j')
FUERA = mc.carpeta('styles_lint_pas_v173j-fuera')
JAIL = os.path.join(BASE, 'jail')
PROJ = os.path.join(JAIL, 'proj')
STY = os.path.join(PROJ, 'Styles')
os.makedirs(STY)
os.makedirs(FUERA, exist_ok=True)
open(os.path.join(STY, 'Tema.style'), 'w', newline='').write(
    "object TStyleContainer\r\n  object TRectangle\r\n    StyleName = 'cardstyle'\r\n  end\r\nend\r\n")
open(os.path.join(PROJ, 'UMain.pas'), 'w', newline='').write(
    "unit UMain;\r\ninterface\r\nuses FMX.Forms, FMX.StdCtrls;\r\ntype\r\n  TFormMain = class(TForm)\r\n"
    "    Button1: TButton;\r\n    procedure Pon;\r\n  end;\r\nimplementation\r\n{$R *.fmx}\r\n"
    "procedure TFormMain.Pon;\r\nbegin\r\n  Button1.StyleLookup := 'nada';\r\nend;\r\nend.\r\n")
SIN = os.path.join(FUERA, 'sin.fmx')
CON = os.path.join(FUERA, 'con.fmx')
open(SIN, 'w', newline='').write("object FormMain: TFormMain\r\n  Caption = 'x'\r\nend\r\n")
open(CON, 'w', newline='').write("object FormMain: TFormMain\r\n  StyleBook = StyleBook1\r\n"
                                 "  object StyleBook1: TStyleBook\r\n  end\r\nend\r\n")
FMX = os.path.join(PROJ, 'UMain.fmx')


def enlace(nuevo, existente):
    return bool(ctypes.windll.kernel32.CreateHardLinkW(nuevo, existente, None))


srv = mc.Stdio(mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src, con_conversor=True),
               mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='v173j', t=180)


def veredicto():
    """('nada' dado por falta, UMain aparte) de un lint del proyecto"""
    r = srv.call('delphi_styles', {'command': 'lint', 'path': STY}, 180)
    j = mc.como_json(r)
    falta = 'nada' in str(j.get('lookupsWithoutStyle'))
    aparte = 'UMain' in str(j.get('formsWithAStyleBook'))
    return (falta, aparte), r


try:
    ok_sin = enlace(FMX, SIN)
    v_sin, r_sin = veredicto()
    os.remove(FMX)  # quita ESTE nombre (el enlace); el de fuera queda
    ok_con = enlace(FMX, CON)
    v_con, r_con = veredicto()
    os.remove(FMX)
    check('J0 preparacion: los dos enlaces duros a fuera se pudieron crear', ok_sin and ok_con)
    check('J3 el lint del proyecto contesta: un designer que la puerta niega no lo tumba entero',
          not mc.rechazado(r_sin) and not mc.rechazado(r_con) and 'stylesDir' in r_sin, (r_sin[:300], r_con[:300]))
    check('J1 la respuesta para UMain no depende de lo que hay en el form de fuera',
          v_sin == v_con, (v_sin, v_con, r_sin[:400], r_con[:400]))
    check('J2 ...y es la de un form que no se lee: nada no es una falta, la form va aparte',
          v_sin == (False, True) and v_con == (False, True), (v_sin, v_con))
    # C1 control: un UMain.fmx de verdad, sin StyleBook: el codigo se juzga
    open(FMX, 'w', newline='').write("object FormMain: TFormMain\r\n  Caption = 'x'\r\nend\r\n")
    v_real, r_real = veredicto()
    check('C1 (control) un UMain.fmx de verdad sin StyleBook: nada sale sin estilo',
          v_real == (True, False), (v_real, r_real[:400]))
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('V173j styles lint: el designer de un .pas por la puerta')
